import Foundation
import Network
import Observation

/// App-wide reachability signal. It is advisory only: network requests can still fail,
/// so the durable queue remains the source of truth for whether a capture is pending.
@Observable
@MainActor
final class ConnectivityMonitor {
    private(set) var isOnline: Bool
    private(set) var isExpensive: Bool
    private(set) var isConstrained: Bool

    @ObservationIgnored private let monitor: NWPathMonitor?
    @ObservationIgnored private let queue = DispatchQueue(label: "app.aperture.connectivity")

    init(forceOffline: Bool = false, forceExpensive: Bool = false) {
        if forceOffline {
            isOnline = false
            isExpensive = forceExpensive
            isConstrained = false
            monitor = nil
            return
        }

        let pathMonitor = NWPathMonitor()
        isOnline = true
        isExpensive = forceExpensive
        isConstrained = false
        monitor = pathMonitor
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isOnline = path.status == .satisfied
                self.isExpensive = forceExpensive || path.isExpensive
                self.isConstrained = path.isConstrained
            }
        }
        pathMonitor.start(queue: queue)
    }

    deinit { monitor?.cancel() }
}
