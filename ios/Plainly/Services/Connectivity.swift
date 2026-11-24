import Network
import Observation

/// Tracks whether the device has a network path, so routing can block cloud
/// tasks up front instead of letting them fail.
@MainActor @Observable
final class Connectivity {
  private(set) var isOnline = true
  private let monitor = NWPathMonitor()

  init() {
    monitor.pathUpdateHandler = { [weak self] path in
      let online = path.status == .satisfied
      Task { @MainActor in self?.isOnline = online }
    }
    monitor.start(queue: DispatchQueue(label: "plainly.connectivity"))
  }

  deinit { monitor.cancel() }
}
