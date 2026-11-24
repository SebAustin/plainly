import FirebaseAILogic
import Foundation
import PlainlyCore

/// The Firebase AI Logic adapter. Each `InferenceMode` chosen by `chooseRoute`
/// becomes one kind of model on the hybrid session:
///
///  - only on device  → Apple's on-device system model alone
///  - only in cloud   → a Gemini model alone
///  - prefer on device → a hybrid model, system model first, Gemini as fallback
struct FirebaseInference: Inference {
  /// `modelVersion` the SDK reports when Apple Foundation Models answered.
  private static let onDeviceModelPrefix = "apple-foundation-models"

  private let ai: FirebaseAI
  private let cloudModelName: String

  init(cloudModelName: String) {
    ai = FirebaseAI.firebaseAI(backend: .googleAI())
    self.cloudModelName = cloudModelName
  }

  /// Maps Apple Intelligence availability onto what routing needs to know.
  static var deviceModelStatus: DeviceModelStatus {
    switch FirebaseAI.SystemLanguageModel.default.availability {
    case .available: .available
    case .unavailable(.modelNotReady): .preparing
    case .unavailable: .unavailable
    }
  }

  func generate(_ request: GenerateRequest) async throws -> InferenceResult {
    // The session keeps chat history, so every single-turn task gets a new one.
    if request.mode == .onlyInCloud {
      return try await generateWithSchema(request)
    }
    let session = ai.generativeModelSession(
      model: provider(for: request.mode),
      instructions: [request.system, template(for: request.format)].compactMap { $0 }
        .joined(separator: " "))
    let response = try await session.respond(to: request.prompt)
    return result(response.content, from: response.rawResponse)
  }

  /// Cloud calls constrain the answer to a schema. See GeneratedShapes for why
  /// on-device calls use a template instead.
  private func generateWithSchema(_ request: GenerateRequest) async throws -> InferenceResult {
    let session = ai.generativeModelSession(
      model: provider(for: request.mode), instructions: request.system)
    switch request.format {
    case .text:
      let response = try await session.respond(to: request.prompt)
      return result(response.content, from: response.rawResponse)
    case .decode:
      let response = try await session.respond(to: request.prompt, generating: GeneratedDecode.self)
      return result(try jsonText(response.content), from: response.rawResponse)
    case .personalDetails:
      let response = try await session.respond(
        to: request.prompt, generating: GeneratedPersonalDetails.self)
      return result(try jsonText(response.content), from: response.rawResponse)
    }
  }

  private func template(for format: ResponseFormat) -> String? {
    switch format {
    case .text: nil
    case .decode: JSONTemplate.decode
    case .personalDetails: JSONTemplate.personalDetails
    }
  }

  /// Reports where the call really ran, from what the SDK says answered it.
  private func result(_ text: String, from response: GenerateContentResponse) -> InferenceResult {
    let ranOnDevice = response.modelVersion.hasPrefix(Self.onDeviceModelPrefix)
    return InferenceResult(text: text, source: ranOnDevice ? .onDevice : .inCloud)
  }

  func chat(_ request: ChatRequest) async throws -> InferenceResult {
    // Follow-ups are cloud-only, so they use the standard chat API, which
    // takes the exact (already redacted) history on every call.
    let model = ai.generativeModel(
      modelName: cloudModelName,
      systemInstruction: ModelContent(role: "system", parts: request.system))
    let history = request.history.map { turn in
      ModelContent(role: turn.role == .user ? "user" : "model", parts: turn.text)
    }
    let response = try await model.startChat(history: history).sendMessage(request.message)
    return InferenceResult(text: response.text ?? "", source: .inCloud)
  }

  private func provider(for mode: InferenceMode) -> any LanguageModelProvider {
    // Official letters are full of medical, legal and money terms. The reader
    // supplied the text and only asks to have it explained, which is the case
    // Apple's permissive guardrail setting for content transformations is for.
    let system: FirebaseAI.SystemLanguageModel = .systemModel(
      guardrails: .permissiveContentTransformations)
    let cloud: GeminiModelProvider = .geminiModel(name: cloudModelName)
    switch mode {
    case .onlyOnDevice: return system
    case .onlyInCloud: return cloud
    case .preferOnDevice: return HybridModelProvider.hybridModel(primary: system, secondary: cloud)
    }
  }
}
