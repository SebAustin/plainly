import Foundation
import PlainlyCore

/// Canned answers for running the app before it is connected to a Firebase
/// project. The interface labels this mode "Demo" wherever results are shown.
struct FixtureInference: Inference {
  private static let delay: Duration = .milliseconds(600)

  private static let decode = """
    {"sender":"Northgate Community Health","category":"medical",
    "summary":"This is a bill for a clinic visit on October 3. Your insurance paid part of it. You still owe the rest.",
    "urgency":"high",
    "actions":[{"what":"Pay $1,284.50, or call to set up a monthly payment plan","deadline":"2026-12-14"},
    {"what":"Ask for financial assistance if you cannot pay. The letter says you may qualify","deadline":null}],
    "amountDue":{"value":1284.5,"currency":"USD"},
    "glossary":[{"term":"Patient responsibility","plain":"The part of the bill you pay yourself"},
    {"term":"Collections","plain":"A company that chases unpaid bills. It can hurt your credit"}]}
    """

  private static let entities = """
    {"entities":[{"type":"NAME","value":"Maria Okafor"},
    {"type":"ADDRESS","value":"88 Linden Avenue, Apt 4, Oakland, CA 94607"}]}
    """

  func generate(_ request: GenerateRequest) async throws -> InferenceResult {
    try await Task.sleep(for: Self.delay)
    let text =
      switch request.task {
      case .readLetter: Self.decode
      case .findPersonalDetails: Self.entities
      default: "Dear Billing Office,\n\nI am writing about my account. [YOUR REQUEST]\n\nThank you,\n[NAME_1]"
      }
    return InferenceResult(text: text, source: request.mode == .onlyInCloud ? .inCloud : .onDevice)
  }

  func chat(_ request: ChatRequest) async throws -> InferenceResult {
    try await Task.sleep(for: Self.delay)
    return InferenceResult(
      text: "Yes, [NAME_1]. The letter says you can call [PHONE_1] to ask for a payment plan before the due date.",
      source: .inCloud)
  }
}
