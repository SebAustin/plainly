import Foundation
import PlainlyCore
import Synchronization
import Testing

@testable import Plainly

/// Every model call the fake received, in order.
private final class CallLog: Sendable {
  private let tasks = Mutex<[InferenceTask]>([])
  func record(_ task: InferenceTask) { tasks.withLock { $0.append(task) } }
  var all: [InferenceTask] { tasks.withLock { $0 } }
}

/// FixtureInference's canned answers, with a call log and a chat that can be
/// held open to test what the app does while a question is pending.
private struct FakeInference: Inference {
  var log: CallLog
  var heldChat: AsyncStream<Void>?

  func generate(_ request: GenerateRequest) async throws -> InferenceResult {
    log.record(request.task)
    return try await FixtureInference().generate(request)
  }

  func chat(_ request: ChatRequest) async throws -> InferenceResult {
    if let heldChat {
      for await _ in heldChat { break }
    }
    return InferenceResult(text: "Call [PHONE_1], [NAME_1].", source: .inCloud)
  }
}

@MainActor
private func model(
  deviceModel: DeviceModelStatus = .available, heldChat: AsyncStream<Void>? = nil,
  log: CallLog = CallLog()
) -> LetterViewModel {
  let model = LetterViewModel(
    inference: FakeInference(log: log, heldChat: heldChat), isDemo: false,
    deviceModel: { deviceModel })
  model.letterText = sampleLetter
  return model
}

/// Receipt lines are recorded on the main actor just after each call returns.
@MainActor
private func receiptSettles(_ model: LetterViewModel, count: Int) async {
  for _ in 0..<100 where model.receipt.count < count { await Task.yield() }
}

@MainActor
@Suite struct LetterViewModelTests {
  @Test func picksUpTheOnDeviceModelOnceItFinishesDownloading() {
    var status = DeviceModelStatus.preparing
    let model = LetterViewModel(
      inference: FakeInference(log: CallLog()), isDemo: false, deviceModel: { status })
    #expect(model.deviceModel == .preparing)

    status = .available
    model.refreshDeviceModel()

    #expect(model.deviceModel == .available)
    #expect(model.redactionLevel == .deviceAssisted)
  }

  @Test func explainsALetterOnTheDeviceWithNothingSentToTheCloud() async {
    let model = model()

    await model.explain()
    await receiptSettles(model, count: 1)

    #expect(model.decoded?.decode.sender == "Northgate Community Health")
    #expect(model.receipt.map(\.task) == [.readLetter])
    #expect(model.receipt.allSatisfy { $0.sentToCloud == nil })
  }

  @Test func asksBeforeSendingWhenNoDeviceModelCanHideNames() async throws {
    let model = model(deviceModel: .unavailable)

    await model.explain()

    #expect(model.pendingConsent == .explain)
    #expect(model.decoded == nil)
    #expect(model.receipt.isEmpty)
  }

  @Test func sendsWithPatternRulesOnlyOnceTheReaderAgrees() async throws {
    let model = model(deviceModel: .unavailable)
    await model.explain()

    await model.grantConsent()?.value
    await receiptSettles(model, count: 1)

    #expect(model.decoded != nil)
    let sent = try #require(model.receipt.first?.sentToCloud)
    #expect(!sent.contains("billing@northgate-health.org"))
    #expect(!sent.contains("4417 1299 8830 2201"))
    #expect(sent.contains("[EMAIL_1]"))
  }

  @Test func decliningSendsNothing() async {
    let model = model(deviceModel: .unavailable)
    await model.explain()

    model.declineConsent()

    #expect(model.pendingConsent == nil)
    #expect(model.decoded == nil)
    #expect(model.receipt.isEmpty)
  }

  @Test func restoresRealDetailsInAFollowUpAnswer() async {
    let model = model()
    await model.explain()

    await model.ask("Who do I call?")

    #expect(model.exchanges.map(\.answer) == ["Call (415) 555-0134, Maria Okafor."])
    #expect(model.question.isEmpty)
  }

  @Test func cannotExplainANewLetterWhileAQuestionIsPending() async {
    let (held, release) = AsyncStream<Void>.makeStream()
    let log = CallLog()
    let model = model(heldChat: held, log: log)
    await model.explain()

    let asking = Task { await model.ask("Who do I call?") }
    for _ in 0..<100 where !model.isAsking { await Task.yield() }
    #expect(model.isAsking)
    #expect(!model.canExplain)

    // Even if called directly, the new letter is not read over the pending answer.
    model.letterText = "A different letter from the tax office."
    await model.explain()
    #expect(log.all.filter { $0 == .readLetter }.count == 1)

    release.yield()
    await asking.value
    #expect(model.exchanges.count == 1)
    #expect(model.canExplain)
  }
}
