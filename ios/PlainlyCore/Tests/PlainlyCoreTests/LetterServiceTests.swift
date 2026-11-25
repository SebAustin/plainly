import Foundation
import Testing

@testable import PlainlyCore

private let letter =
  "Dear Maria Okafor, your balance of $1,284.50 is due 2026-12-14. Questions: billing@northgate.org."

private func decodeAnswer(_ who: String) -> String {
  """
  {"sender":"Northgate Health","category":"medical","summary":"\(who) owes money for a clinic visit.",
  "urgency":"high","actions":[{"what":"Pay the balance, \(who)","deadline":"2026-12-14"}],
  "amountDue":{"value":1284.5,"currency":"USD"},"glossary":[]}
  """
}

private let entitiesAnswer = #"{"entities":[{"type":"NAME","value":"Maria Okafor"}]}"#

/// A fake model that records everything it was sent.
private final class RecordingInference: Inference, @unchecked Sendable {
  private let lock = NSLock()
  private var generatedRequests: [GenerateRequest] = []
  private var chatRequests: [ChatRequest] = []
  private let chatAnswer: String
  private let garbled: Bool
  private let detailsAnswer: String
  private let draftAnswer: String

  init(
    chatAnswer: String = "", garbled: Bool = false, detailsAnswer: String = entitiesAnswer,
    draftAnswer: String = "Dear office,\nPlease help.\n[NAME_1]\n\n"
  ) {
    self.chatAnswer = chatAnswer
    self.garbled = garbled
    self.detailsAnswer = detailsAnswer
    self.draftAnswer = draftAnswer
  }

  var generated: [GenerateRequest] { lock.withLock { generatedRequests } }
  var chats: [ChatRequest] { lock.withLock { chatRequests } }

  /// Everything that left the device, as one string to search for leaks.
  var sentToCloud: String {
    let prompts = generated.filter { $0.mode != .onlyOnDevice }.map { $0.system + $0.prompt }
    let messages = chats.map { $0.system + $0.message + $0.history.map(\.text).joined() }
    return (prompts + messages).joined(separator: "\n")
  }

  func generate(_ request: GenerateRequest) async throws -> InferenceResult {
    lock.withLock { generatedRequests.append(request) }
    let source: InferenceSource = request.mode == .onlyInCloud ? .inCloud : .onDevice
    if garbled { return InferenceResult(text: "I cannot help with that.", source: source) }
    switch request.task {
    case .findPersonalDetails:
      return InferenceResult(text: detailsAnswer, source: source)
    case .draftReply:
      return InferenceResult(text: draftAnswer, source: source)
    default:
      let who = request.mode == .onlyInCloud ? "[NAME_1]" : "Maria Okafor"
      return InferenceResult(text: decodeAnswer(who), source: source)
    }
  }

  func chat(_ request: ChatRequest) async throws -> InferenceResult {
    lock.withLock { chatRequests.append(request) }
    return InferenceResult(text: chatAnswer, source: .inCloud)
  }
}

private let ready = Environment(deviceModel: .available, isOnline: true, deviceTokenBudget: 2500)
private let noModel = Environment(deviceModel: .unavailable, isOnline: true, deviceTokenBudget: 2500)
private let noModelAgreed = Environment(
  deviceModel: .unavailable, isOnline: true, deviceTokenBudget: 2500, hasCloudConsent: true)
private let unreadableDetails = "Here are the names: Maria Okafor"

@Suite struct LetterServiceTests {
  @Test func aShortLetterIsDecodedWithOneOnDeviceCallAndNothingReachesTheCloud() async throws {
    let model = RecordingInference()

    let decoded = try await decodeLetter(letter, environment: ready, inference: model)

    #expect(decoded.source == .onDevice)
    #expect(decoded.decode.sender == "Northgate Health")
    #expect(model.generated.map(\.mode) == [.onlyOnDevice])
    #expect(model.generated.map(\.format) == [.decode])
    #expect(model.sentToCloud.isEmpty)
  }

  @Test func aLongLetterReachesTheCloudWithoutTheNameOrEmailAndComesBackRestored() async throws {
    let model = RecordingInference()
    let tightBudget = Environment(deviceModel: .available, isOnline: true, deviceTokenBudget: 10)

    let decoded = try await decodeLetter(letter, environment: tightBudget, inference: model)

    #expect(!model.sentToCloud.contains("Maria Okafor"))
    #expect(!model.sentToCloud.contains("billing@northgate.org"))
    #expect(model.sentToCloud.contains("[NAME_1]"))
    #expect(decoded.source == .inCloud)
    #expect(decoded.decode.summary == "Maria Okafor owes money for a clinic visit.")
    #expect(decoded.decode.actions.first?.what == "Pay the balance, Maria Okafor")
  }

  @Test func anUnreadableAnswerIsRetriedOnceThenReportedInsteadOfShown() async {
    let model = RecordingInference(garbled: true)

    await #expect(throws: LetterError.unreadableAnswer) {
      try await decodeLetter(letter, environment: ready, inference: model)
    }
    #expect(model.generated.count == 2)
  }

  @Test func offlineWithoutADeviceModelIsBlockedBeforeAnyModelIsCalled() async {
    let model = RecordingInference()
    let stranded = Environment(deviceModel: .unavailable, isOnline: false, deviceTokenBudget: 2500)

    await #expect(throws: LetterError.blocked(.offline)) {
      try await decodeLetter(letter, environment: stranded, inference: model)
    }
    #expect(model.generated.isEmpty)
  }

  @Test func theQuestionAndLetterReachTheCloudRedactedAndTheAnswerIsRestoredOnDevice() async throws {
    let model = RecordingInference(chatAnswer: "Yes [NAME_1], email [EMAIL_1] to ask for a plan.\n")
    let context = try await prepareCloudContext(letter, environment: ready, inference: model)

    let reply = try await askFollowUp(
      context: context, history: [], question: "Can Maria Okafor get a payment plan?",
      environment: ready, inference: model)

    #expect(!model.sentToCloud.contains("Maria Okafor"))
    #expect(!model.sentToCloud.contains("billing@northgate.org"))
    #expect(model.chats.first?.message == "Can [NAME_1] get a payment plan?")
    #expect(reply.answer == "Yes Maria Okafor, email billing@northgate.org to ask for a plan.")
    #expect(reply.cloudTurns.map(\.role) == [.user, .model])
  }

  @Test func withoutADeviceModelOnlyPatternRulesRedactAndTheContextSaysSo() async throws {
    let model = RecordingInference()

    let context = try await prepareCloudContext(letter, environment: noModel, inference: model)

    #expect(context.level == .rulesOnly)
    #expect(context.redactedText.contains("[EMAIL_1]"))
    #expect(context.redactedText.contains("Maria Okafor"))
    #expect(model.generated.isEmpty)
  }

  @Test func aDraftedReplyIsWrittenFromRedactedTextAndSignedWithTheRealName() async throws {
    let model = RecordingInference()
    let context = try await prepareCloudContext(letter, environment: ready, inference: model)

    let draft = try await draftReply(
      context: context, goal: "Ask for more time for Maria Okafor", environment: ready,
      inference: model)

    #expect(!model.sentToCloud.contains("Maria Okafor"))
    #expect(draft.text == "Dear office,\nPlease help.\nMaria Okafor")
  }

  @Test func theReceiptRecordsCloudTextAndNothingForOnDeviceCalls() async throws {
    let entries = Recorder()
    let model = ReceiptInference(RecordingInference(chatAnswer: "ok")) { entries.add($0) }
    let context = try await prepareCloudContext(letter, environment: ready, inference: model)

    _ = try await askFollowUp(
      context: context, history: [], question: "What now?", environment: ready, inference: model)

    #expect(entries.all.map(\.task) == [.findPersonalDetails, .answerQuestion])
    #expect(entries.all.first?.sentToCloud == nil)
    #expect(entries.all.last?.sentToCloud?.contains("[NAME_1]") == true)
    #expect(entries.all.last?.sentToCloud?.contains("Maria Okafor") == false)
  }
}

@Suite struct CloudConsentTests {
  @Test func withoutADeviceModelTheLetterIsNotSentUntilTheReaderAgrees() async {
    let model = RecordingInference()

    await #expect(throws: LetterError.blocked(.needsCloudConsent)) {
      try await decodeLetter(letter, environment: noModel, inference: model)
    }
    #expect(model.generated.isEmpty)
  }

  @Test func onceTheReaderAgreesTheLetterGoesWithPatternRulesOnly() async throws {
    let model = RecordingInference()

    let decoded = try await decodeLetter(letter, environment: noModelAgreed, inference: model)

    #expect(decoded.cloudContext?.level == .rulesOnly)
    #expect(!model.sentToCloud.contains("billing@northgate.org"))
  }

  @Test func questionsAndDraftsWithPatternRulesOnlyAlsoNeedConsent() async throws {
    let model = RecordingInference(chatAnswer: "ok")
    let context = try await prepareCloudContext(letter, environment: noModel, inference: model)

    await #expect(throws: LetterError.blocked(.needsCloudConsent)) {
      try await askFollowUp(
        context: context, history: [], question: "Why?", environment: noModel, inference: model)
    }
    await #expect(throws: LetterError.blocked(.needsCloudConsent)) {
      try await draftReply(context: context, goal: "More time", environment: noModel, inference: model)
    }
    #expect(model.sentToCloud.isEmpty)
  }
}

@Suite struct UnreadablePersonalDetailsTests {
  @Test func anUnreadableListIsRetriedOnceThenTheContextIsMarkedPatternRulesOnly() async throws {
    let model = RecordingInference(detailsAnswer: unreadableDetails)

    let context = try await prepareCloudContext(letter, environment: ready, inference: model)

    #expect(model.generated.filter { $0.task == .findPersonalDetails }.count == 2)
    #expect(context.level == .rulesOnly)
  }

  @Test func aQuestionIsNotSentWhenNamesCouldNotBeFound() async throws {
    let model = RecordingInference(chatAnswer: "ok", detailsAnswer: unreadableDetails)
    let context = try await prepareCloudContext(letter, environment: ready, inference: model)

    await #expect(throws: LetterError.blocked(.needsCloudConsent)) {
      try await askFollowUp(
        context: context, history: [], question: "Why?", environment: ready, inference: model)
    }
    #expect(!model.sentToCloud.contains("Maria Okafor"))
  }

  @Test func aLongLetterIsNotSentWhenNamesCouldNotBeFound() async {
    let model = RecordingInference(detailsAnswer: unreadableDetails)
    let tightBudget = Environment(deviceModel: .available, isOnline: true, deviceTokenBudget: 10)

    await #expect(throws: LetterError.blocked(.needsCloudConsent)) {
      try await decodeLetter(letter, environment: tightBudget, inference: model)
    }
    #expect(model.sentToCloud.isEmpty)
  }

  @Test func anEmptyListIsAValidAnswerAndKeepsDeviceAssistedRedaction() async throws {
    let model = RecordingInference(detailsAnswer: #"{"entities":[]}"#)

    let context = try await prepareCloudContext(letter, environment: ready, inference: model)

    #expect(context.level == .deviceAssisted)
    #expect(model.generated.filter { $0.task == .findPersonalDetails }.count == 1)
  }
}

@Suite struct EmptyAnswerTests {
  @Test func anEmptyFollowUpAnswerIsAnErrorNotABlankReply() async throws {
    let model = RecordingInference(chatAnswer: " \n ")
    let context = try await prepareCloudContext(letter, environment: ready, inference: model)

    await #expect(throws: LetterError.unreadableAnswer) {
      try await askFollowUp(
        context: context, history: [], question: "Why?", environment: ready, inference: model)
    }
  }

  @Test func anEmptyDraftIsAnErrorNotABlankReply() async throws {
    let model = RecordingInference(draftAnswer: "\n\n")
    let context = try await prepareCloudContext(letter, environment: ready, inference: model)

    await #expect(throws: LetterError.unreadableAnswer) {
      try await draftReply(context: context, goal: "More time", environment: ready, inference: model)
    }
  }
}

private final class Recorder: @unchecked Sendable {
  private let lock = NSLock()
  private var entries: [ReceiptEntry] = []
  var all: [ReceiptEntry] { lock.withLock { entries } }
  func add(_ entry: ReceiptEntry) { lock.withLock { entries.append(entry) } }
}
