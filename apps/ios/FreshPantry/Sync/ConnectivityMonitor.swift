import Foundation
import Network

/// Reactive network-reachability flag for the offline / 待同步 banner.
///
/// Wraps `NWPathMonitor`: path updates arrive on a background queue and are
/// hopped onto the main actor to publish `isOnline`, so SwiftUI re-renders the
/// `SyncStatusBanner` the moment connectivity changes. Ports the Flutter
/// `connectivityOnlineProvider`. Optimistically starts `true` (assume online
/// until the first path update says otherwise) to avoid a launch flash.
@Observable
@MainActor
final class ConnectivityMonitor {
    /// Whether the device currently has a usable network path.
    private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "fresh_pantry.connectivity")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            // `path.status` is read on the monitor's background queue; publish the
            // resolved Bool back on the main actor where `isOnline` is isolated.
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: queue)
    }

    deinit {
        // `cancel()` is thread-safe and the handler holds only a weak self, so
        // tearing down from a nonisolated deinit is safe.
        monitor.cancel()
    }
}
