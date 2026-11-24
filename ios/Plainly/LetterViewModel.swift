import Foundation
import Observation
import os
import PlainlyCore

/// An action waiting for the reader's agreement to send pattern-redacted text
/// (names and addresses still visible) to the cloud.
enum ConsentRequest: Equatable {
  case explain
  case ask(String)
  case draft
}

/// One question and its answer, as shown to the reader (real details restored).
struct Exchange: Identifiable, Equatable {
  let id = UUID()
  let question: String
  let answer: String
}

@MainActor @Observable
final class LetterViewModel {
  /// Input tokens kept for the letter. Apple's on-device model takes about
  /// 4,096 tokens in total, and the instructions and the answer need room too.
  private static let deviceTokenBudget = 2500
  private static let cloudModelName = "gemini-3.5-flash-lite"

  let isDemo: Bool
  let connectivity = Connectivity()

  var letterText = ""
  var question = ""
  var replyGoal = "Ask for more time and what my options are"

  private(set) var decoded: DecodedLetter?
  private(set) var exchanges: [Exchange] = []
  private(set) var draft: DraftedReply?
  private(set) var receipt: [ReceiptEntry] = []
  private(set) var errorMessage: String?
  private(set) var isReading = false
  private(set) var isAsking = false
  private(set) var isDrafting = false
  private(set) var isRecognizing = false
  private(set) var pendingConsent: ConsentRequest?

  /// The letter the current answers are about. Edits to the text box do not
  /// change it until the letter is explained again.
  private var activeLetter = ""
  private var cloudContext: CloudContext?
  private var cloudHistory: [ChatTurn] = []
  /// The letter text the reader agreed to send with pattern rules only.
  /// Consent covers that letter alone: a different letter asks again.
  private var consentedLetter: String?
  @ObservationIgnored private var inference: (any Inference)!

  init(isFirebaseConfigured: Bool) {
    isDemo = !isFirebaseConfigured
    let base: any Inference =
      isFirebaseConfigured
      ? FirebaseInference(cloudModelName: Self.cloudModelName) : FixtureInference()
    inference = ReceiptInference(base) { [weak self] entry in
      Task { @MainActor in self?.receipt.append(entry) }
    }
  }

  #if DEBUG
    /// Launch with `-simulateNoAppleIntelligence` to try the no-device-model
    /// path (pattern rules only, consent prompt) on a Mac that has Apple Intelligence.
    private static let simulatesNoDeviceModel =
      ProcessInfo.processInfo.arguments.contains("-simulateNoAppleIntelligence")
  #else
    private static let simulatesNoDeviceModel = false
  #endif

  var deviceModel: DeviceModelStatus {
    if Self.simulatesNoDeviceModel { return .unavailable }
    return isDemo ? .available : FirebaseInference.deviceModelStatus
  }

  private func environment(for letter: String) -> Environment {
    Environment(
      deviceModel: deviceModel, isOnline: connectivity.isOnline,
      deviceTokenBudget: Self.deviceTokenBudget, hasCloudConsent: consentedLetter == letter)
  }

  /// How follow-ups will be redacted, so the interface can say so before sending.
  var redactionLevel: RedactionLevel {
    cloudContext?.level ?? (deviceModel == .available ? .deviceAssisted : .rulesOnly)
  }

  var canExplain: Bool {
    !letterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isReading
  }

  func useSampleLetter() {
    letterText = sampleLetter
  }

  func explain() async {
    let text = letterText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    resetResults()
    activeLetter = text
    isReading = true
    defer { isReading = false }
    do {
      let letter = try await decodeLetter(
        text, environment: environment(for: text), inference: inference)
      decoded = letter
      cloudContext = letter.cloudContext
    } catch LetterError.blocked(.needsCloudConsent) {
      pendingConsent = .explain
    } catch {
      errorMessage = message(for: error)
    }
  }

  func ask(_ text: String? = nil) async {
    let asked = (text ?? question).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !asked.isEmpty, !isAsking else { return }
    isAsking = true
    errorMessage = nil
    defer { isAsking = false }
    do {
      let reply = try await askFollowUp(
        context: try await context(), history: cloudHistory, question: asked,
        environment: environment(for: activeLetter), inference: inference)
      cloudContext = reply.context
      cloudHistory += reply.cloudTurns
      exchanges.append(Exchange(question: asked, answer: reply.answer))
      question = ""
    } catch LetterError.blocked(.needsCloudConsent) {
      pendingConsent = .ask(asked)
    } catch {
      errorMessage = message(for: error)
    }
  }

  func writeReply() async {
    let goal = replyGoal.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !goal.isEmpty, !isDrafting else { return }
    isDrafting = true
    errorMessage = nil
    defer { isDrafting = false }
    do {
      draft = try await draftReply(
        context: try await context(), goal: goal, environment: environment(for: activeLetter),
        inference: inference)
    } catch LetterError.blocked(.needsCloudConsent) {
      pendingConsent = .draft
    } catch {
      errorMessage = message(for: error)
    }
  }

  /// The reader agreed: remember it for this letter and run the waiting action.
  func grantConsent() {
    guard let request = pendingConsent else { return }
    pendingConsent = nil
    let letter =
      request == .explain
      ? letterText.trimmingCharacters(in: .whitespacesAndNewlines) : activeLetter
    consentedLetter = letter
    Task {
      switch request {
      case .explain: await explain()
      case .ask(let question): await ask(question)
      case .draft: await writeReply()
      }
    }
  }

  func declineConsent() {
    pendingConsent = nil
  }

  /// Turns a photo into text on the device and puts it in the letter box.
  func readPhoto(_ data: Data) async {
    isRecognizing = true
    errorMessage = nil
    defer { isRecognizing = false }
    do {
      let text = try await TextRecognizer.recognizeText(in: data)
      if text.isEmpty {
        errorMessage = "No text was found in that photo. Try a sharper, well-lit picture."
      } else {
        letterText = text
      }
    } catch {
      errorMessage = "That photo could not be read. Nothing was uploaded."
    }
  }

  private func context() async throws -> CloudContext {
    if let cloudContext { return cloudContext }
    let prepared = try await prepareCloudContext(
      activeLetter, environment: environment(for: activeLetter), inference: inference)
    cloudContext = prepared
    return prepared
  }

  private func resetResults() {
    decoded = nil
    exchanges = []
    draft = nil
    receipt = []
    errorMessage = nil
    cloudContext = nil
    cloudHistory = []
  }

  private static let log = Logger(subsystem: "com.sebaustin.plainly", category: "letters")

  private func message(for error: Error) -> String {
    // The reader gets a plain sentence; the detail goes to the device log.
    Self.log.error("Model call failed: \(String(describing: error), privacy: .public)")
    return switch error {
    case LetterError.blocked(.offline):
      "You are offline and this step needs the cloud. Nothing was sent. Try again when you are connected."
    case LetterError.unreadableAnswer:
      "The model's answer could not be understood, so it is not shown. Please try again."
    default:
      "Something went wrong and the model did not answer. Nothing was saved. Please try again."
    }
  }
}
