import Foundation

/// The inference port. The app talks to models only through this protocol;
/// the real adapter is Firebase AI Logic (FirebaseInference in the app target).

public enum InferenceSource: Sendable, Equatable {
  case onDevice
  case inCloud
}

/// What a model call is for. Shown to the user in the privacy receipt.
public enum InferenceTask: String, Sendable, Equatable {
  case readLetter = "Read the letter"
  case findPersonalDetails = "Find personal details"
  case answerQuestion = "Answer a question"
  case draftReply = "Draft a reply"
}

/// What shape the answer must have. For the structured formats the adapter
/// constrains the model to a schema and returns the result as JSON text,
/// which the core then validates again before anything is shown.
public enum ResponseFormat: Sendable, Equatable {
  case text
  case decode
  case personalDetails
}

public struct GenerateRequest: Sendable, Equatable {
  public var task: InferenceTask
  public var mode: InferenceMode
  public var system: String
  public var prompt: String
  public var format: ResponseFormat

  public init(
    task: InferenceTask, mode: InferenceMode, system: String, prompt: String,
    format: ResponseFormat = .text
  ) {
    self.task = task
    self.mode = mode
    self.system = system
    self.prompt = prompt
    self.format = format
  }
}

public struct ChatTurn: Sendable, Equatable {
  public enum Role: Sendable, Equatable { case user, model }
  public var role: Role
  public var text: String

  public init(role: Role, text: String) {
    self.role = role
    self.text = text
  }
}

public struct ChatRequest: Sendable, Equatable {
  public var task: InferenceTask
  public var system: String
  public var history: [ChatTurn]
  public var message: String

  public init(task: InferenceTask, system: String, history: [ChatTurn], message: String) {
    self.task = task
    self.system = system
    self.history = history
    self.message = message
  }
}

public struct InferenceResult: Sendable, Equatable {
  public var text: String
  /// Where the answer was actually produced, as reported by the SDK.
  public var source: InferenceSource

  public init(text: String, source: InferenceSource) {
    self.text = text
    self.source = source
  }
}

public protocol Inference: Sendable {
  func generate(_ request: GenerateRequest) async throws -> InferenceResult
  /// Multi-turn chat. Always the cloud: follow-ups only ever see redacted text.
  func chat(_ request: ChatRequest) async throws -> InferenceResult
}

// MARK: - Privacy receipt

/// One line of the privacy receipt: a model call, where it ran and, for cloud
/// calls, the exact text that left the device.
public struct ReceiptEntry: Sendable, Equatable, Identifiable {
  public let id: UUID
  public let task: InferenceTask
  public let source: InferenceSource
  /// Text sent to the cloud. Nil for on-device calls: nothing left.
  public let sentToCloud: String?
}

/// Wraps an Inference so every call is reported to `record`.
public struct ReceiptInference: Inference {
  private let inner: any Inference
  private let record: @Sendable (ReceiptEntry) -> Void

  public init(_ inner: any Inference, record: @escaping @Sendable (ReceiptEntry) -> Void) {
    self.inner = inner
    self.record = record
  }

  public func generate(_ request: GenerateRequest) async throws -> InferenceResult {
    let result = try await inner.generate(request)
    report(request.task, system: request.system, text: request.prompt, result: result)
    return result
  }

  public func chat(_ request: ChatRequest) async throws -> InferenceResult {
    let result = try await inner.chat(request)
    report(request.task, system: request.system, text: request.message, result: result)
    return result
  }

  private func report(_ task: InferenceTask, system: String, text: String, result: InferenceResult) {
    // The system instruction travels too (for follow-ups it carries the
    // redacted letter), so the receipt shows it along with the message.
    let sent = result.source == .inCloud ? "\(system)\n\n\(text)" : nil
    record(ReceiptEntry(id: UUID(), task: task, source: result.source, sentToCloud: sent))
  }
}
