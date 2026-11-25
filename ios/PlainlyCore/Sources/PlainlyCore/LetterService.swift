import Foundation

/// The letter service runs each task where `chooseRoute` says it may run, and
/// guarantees the invariant the product is built on: text only reaches the
/// cloud after it has been through `redact`.

/// Exactly what the cloud is allowed to see of a letter, plus the key to undo it locally.
public struct CloudContext: Sendable, Equatable {
  public let redactedText: String
  public let vault: Vault
  public let level: RedactionLevel
}

public struct DecodedLetter: Sendable, Equatable {
  public let decode: Decode
  public let source: InferenceSource
  public let route: Route
  /// Set when the decode itself went through the cloud.
  public let cloudContext: CloudContext?
}

public enum LetterError: Error, Equatable {
  case blocked(BlockReason)
  /// The model answered twice with something that is not a valid decode.
  case unreadableAnswer
}

public struct FollowUpReply: Sendable, Equatable {
  public let answer: String
  /// This exchange exactly as the cloud saw it; append to the history of the next call.
  public let cloudTurns: [ChatTurn]
  public let context: CloudContext
}

public struct DraftedReply: Sendable, Equatable {
  public let text: String
  public let source: InferenceSource
}

private let maxDecodeAttempts = 2
private let charactersPerToken = 4

private func chunks(of text: String, size: Int) -> [String] {
  guard size > 0 else { return [text] }
  var result: [String] = []
  var start = text.startIndex
  while start < text.endIndex {
    let end = text.index(start, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
    result.append(String(text[start..<end]))
    start = end
  }
  return result
}

private let maxPersonalDetailsAttempts = 2

/// Asks the on-device model for one chunk's names and addresses. Returns nil
/// if no attempt produced a readable answer.
private func personalDetails(
  in chunk: String, inference: any Inference
) async throws -> [DetectedEntity]? {
  for _ in 0..<maxPersonalDetailsAttempts {
    let result = try await inference.generate(
      GenerateRequest(
        task: .findPersonalDetails, mode: .onlyOnDevice,
        system: Prompts.personalDetailsSystem, prompt: Prompts.personalDetails(text: chunk),
        format: .personalDetails))
    if let found = parsePersonalDetails(result.text) { return found }
  }
  return nil
}

/// Asks the on-device model for names and addresses, one budget-sized chunk at
/// a time. Returns nil if any chunk could not be read.
private func findPersonalDetails(
  in text: String, environment: Environment, inference: any Inference
) async throws -> [DetectedEntity]? {
  var found: [DetectedEntity] = []
  for chunk in chunks(of: text, size: environment.deviceTokenBudget * charactersPerToken) {
    guard let entities = try await personalDetails(in: chunk, inference: inference) else {
      return nil
    }
    found += entities
  }
  return found
}

/// Redacts text for the cloud. If the on-device model was meant to find names
/// but its answer could not be read, the context says so honestly: it is
/// marked pattern-rules only, which then needs the reader's consent to send.
private func redactForCloud(
  _ text: String, level: RedactionLevel, environment: Environment, inference: any Inference
) async throws -> CloudContext {
  var entities: [DetectedEntity] = []
  var actualLevel = level
  if level == .deviceAssisted {
    if let found = try await findPersonalDetails(
      in: text, environment: environment, inference: inference)
    {
      entities = found
    } else {
      actualLevel = .rulesOnly
    }
  }
  let redaction = redact(text, entities: entities)
  return CloudContext(redactedText: redaction.redacted, vault: redaction.vault, level: actualLevel)
}

/// Text redacted by pattern rules alone still shows names and addresses, so it
/// only leaves the device once the reader has agreed.
private func requireConsent(for context: CloudContext, _ environment: Environment) throws {
  if context.level == .rulesOnly && !environment.hasCloudConsent {
    throw LetterError.blocked(.needsCloudConsent)
  }
}

private func restoreDecode(_ decode: Decode, vault: Vault) -> Decode {
  var restored = decode
  restored.sender = restore(decode.sender, vault: vault)
  restored.summary = restore(decode.summary, vault: vault)
  restored.actions = decode.actions.map {
    Decode.Action(what: restore($0.what, vault: vault), deadline: $0.deadline)
  }
  restored.glossary = decode.glossary.map {
    Decode.GlossaryEntry(term: restore($0.term, vault: vault), plain: restore($0.plain, vault: vault))
  }
  return restored
}

private func generateDecode(
  letter: String, mode: InferenceMode, inference: any Inference
) async throws -> (decode: Decode, source: InferenceSource) {
  for _ in 0..<maxDecodeAttempts {
    let result = try await inference.generate(
      GenerateRequest(
        task: .readLetter, mode: mode, system: Prompts.decoderSystem,
        prompt: Prompts.decode(letter: letter), format: .decode))
    if case .success(let decode) = parseDecode(result.text) {
      return (decode, result.source)
    }
  }
  throw LetterError.unreadableAnswer
}

/// Reads a letter. On the device when the model is there and the letter fits;
/// otherwise in the cloud, after redaction.
public func decodeLetter(
  _ text: String, environment: Environment, inference: any Inference
) async throws -> DecodedLetter {
  let route = chooseRoute(.decode(characters: text.count), environment)
  switch route {
  case .blocked(let reason):
    throw LetterError.blocked(reason)
  case .either:
    preconditionFailure("Decoding never uses a prefer mode.")
  case .device:
    let result = try await generateDecode(letter: text, mode: .onlyOnDevice, inference: inference)
    return DecodedLetter(decode: result.decode, source: result.source, route: route, cloudContext: nil)
  case .cloud(let level):
    if level == .rulesOnly && !environment.hasCloudConsent {
      // Nothing has been sent or even looked at yet: ask before any work.
      throw LetterError.blocked(.needsCloudConsent)
    }
    let context = try await redactForCloud(
      text, level: level, environment: environment, inference: inference)
    try requireConsent(for: context, environment)
    let result = try await generateDecode(
      letter: context.redactedText, mode: .onlyInCloud, inference: inference)
    return DecodedLetter(
      decode: restoreDecode(result.decode, vault: context.vault), source: result.source,
      route: route, cloudContext: context)
  }
}

/// Builds the redacted view of a letter that follow-ups and reply drafting send to the cloud.
public func prepareCloudContext(
  _ text: String, environment: Environment, inference: any Inference
) async throws -> CloudContext {
  let level: RedactionLevel = environment.deviceModel == .available ? .deviceAssisted : .rulesOnly
  return try await redactForCloud(text, level: level, environment: environment, inference: inference)
}

/// Answers a question about the letter in the cloud. The question is redacted
/// with the letter's vault, and the answer is rehydrated on the device.
public func askFollowUp(
  context: CloudContext, history: [ChatTurn], question: String,
  environment: Environment, inference: any Inference
) async throws -> FollowUpReply {
  if case .blocked(let reason) = chooseRoute(.followUp, environment) {
    throw LetterError.blocked(reason)
  }
  try requireConsent(for: context, environment)
  let redactedQuestion = redact(question, existingVault: context.vault)
  let result = try await inference.chat(
    ChatRequest(
      task: .answerQuestion,
      system: Prompts.followUpSystem(redactedLetter: context.redactedText),
      history: history, message: redactedQuestion.redacted))
  let updated = CloudContext(
    redactedText: context.redactedText, vault: redactedQuestion.vault, level: context.level)
  return FollowUpReply(
    answer: try nonEmpty(restore(result.text, vault: redactedQuestion.vault)),
    cloudTurns: [
      ChatTurn(role: .user, text: redactedQuestion.redacted),
      ChatTurn(role: .model, text: result.text),
    ],
    context: updated)
}

/// Drafts a reply from the redacted letter, then puts the real details back locally.
public func draftReply(
  context: CloudContext, goal: String, environment: Environment, inference: any Inference
) async throws -> DraftedReply {
  let route = chooseRoute(.draftReply, environment)
  guard let mode = route.mode else {
    if case .blocked(let reason) = route { throw LetterError.blocked(reason) }
    preconditionFailure("A route without a mode is always blocked.")
  }
  // A prefer-on-device draft may still fall back to the cloud.
  try requireConsent(for: context, environment)
  let redactedGoal = redact(goal, existingVault: context.vault)
  let result = try await inference.generate(
    GenerateRequest(
      task: .draftReply, mode: mode, system: Prompts.draftReplySystem,
      prompt: Prompts.draftReply(redactedLetter: context.redactedText, goal: redactedGoal.redacted)))
  return DraftedReply(
    text: try nonEmpty(restore(result.text, vault: redactedGoal.vault)), source: result.source)
}

/// A model can return an empty answer (a safety filter, a cut-off stream). The
/// reader should be told it failed, not shown a blank reply.
private func nonEmpty(_ answer: String) throws -> String {
  let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { throw LetterError.unreadableAnswer }
  return trimmed
}
