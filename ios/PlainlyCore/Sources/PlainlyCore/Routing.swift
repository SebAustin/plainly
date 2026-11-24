import Foundation

/// Routing decides where each task runs. It is the product's privacy policy,
/// written as a pure function:
///
///  - Raw letters are only ever read on the device.
///  - The cloud only sees text that was redacted first.
///
/// On iOS the on-device model (Apple Foundation Models) is text-only, so a
/// photographed letter is turned into text on the device with Vision before
/// it gets here. Every input this function sees is therefore text.

public enum DeviceModelStatus: Sendable, Equatable {
  case available
  /// Apple Intelligence is on but the model is still downloading.
  case preparing
  case unavailable
}

public struct Environment: Sendable, Equatable {
  public var deviceModel: DeviceModelStatus
  public var isOnline: Bool
  /// Input tokens the on-device model can take.
  public var deviceTokenBudget: Int
  /// The reader agreed to send this letter to the cloud even though only
  /// pattern rules could hide details (names and addresses stay visible).
  public var hasCloudConsent: Bool

  public init(
    deviceModel: DeviceModelStatus, isOnline: Bool, deviceTokenBudget: Int,
    hasCloudConsent: Bool = false
  ) {
    self.deviceModel = deviceModel
    self.isOnline = isOnline
    self.deviceTokenBudget = deviceTokenBudget
    self.hasCloudConsent = hasCloudConsent
  }
}

public enum RouteTask: Sendable, Equatable {
  case decode(characters: Int)
  case findPersonalDetails
  case followUp
  case draftReply
}

/// How text is redacted before the cloud sees it.
public enum RedactionLevel: Sendable, Equatable {
  /// Pattern rules plus names and addresses found by the on-device model.
  case deviceAssisted
  /// Pattern rules only: no on-device model was available to find names.
  case rulesOnly
}

public enum InferenceMode: Sendable, Equatable {
  case onlyOnDevice
  case onlyInCloud
  case preferOnDevice
}

public enum BlockReason: Sendable, Equatable {
  case offline
  /// Only pattern rules hid details, so names and addresses would be sent.
  /// The reader has to agree first.
  case needsCloudConsent
}

public enum Route: Sendable, Equatable {
  case device
  case cloud(redaction: RedactionLevel)
  case either(redaction: RedactionLevel)
  case blocked(BlockReason)

  /// The inference mode the Firebase AI Logic adapter must use, if the task may run.
  public var mode: InferenceMode? {
    switch self {
    case .device: .onlyOnDevice
    case .cloud: .onlyInCloud
    case .either: .preferOnDevice
    case .blocked: nil
    }
  }
}

private let charactersPerToken = 4

public func estimateTokens(characters: Int) -> Int {
  Int((Double(characters) / Double(charactersPerToken)).rounded(.up))
}

/// A model that is still preparing does not count on iOS: unlike Chrome, the
/// app cannot trigger or wait on the download, so the request would just fail.
private func hasDeviceModel(_ environment: Environment) -> Bool {
  environment.deviceModel == .available
}

private func redactionLevel(_ environment: Environment) -> RedactionLevel {
  hasDeviceModel(environment) ? .deviceAssisted : .rulesOnly
}

private func cloudWithRedactedText(_ environment: Environment) -> Route {
  environment.isOnline ? .cloud(redaction: redactionLevel(environment)) : .blocked(.offline)
}

public func chooseRoute(_ task: RouteTask, _ environment: Environment) -> Route {
  switch task {
  case .decode(let characters):
    let fits = hasDeviceModel(environment)
      && estimateTokens(characters: characters) <= environment.deviceTokenBudget
    return fits ? .device : cloudWithRedactedText(environment)
  case .findPersonalDetails:
    return .device
  case .followUp:
    return cloudWithRedactedText(environment)
  case .draftReply:
    if !environment.isOnline {
      return hasDeviceModel(environment) ? .device : .blocked(.offline)
    }
    // Without a device model a "prefer" mode is just the cloud; say so plainly.
    return hasDeviceModel(environment)
      ? .either(redaction: .deviceAssisted) : .cloud(redaction: .rulesOnly)
  }
}
