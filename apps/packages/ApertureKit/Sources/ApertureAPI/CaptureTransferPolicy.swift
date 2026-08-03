import Foundation

/// Pure policy for deciding whether a queued capture should wait for Wi-Fi.
/// Reachability is only a hint; the durable queue still handles request failures.
public struct CaptureTransferPolicy: Sendable, Equatable {
    public static let defaultLargeUploadThresholdBytes: Int64 = 10 * 1_024 * 1_024

    public let largeUploadThresholdBytes: Int64

    public init(
        largeUploadThresholdBytes: Int64 = Self.defaultLargeUploadThresholdBytes
    ) {
        precondition(largeUploadThresholdBytes >= 0)
        self.largeUploadThresholdBytes = largeUploadThresholdBytes
    }

    public func shouldDefer(
        sizeBytes: Int64,
        waitsForWiFi: Bool,
        networkIsExpensive: Bool,
        networkIsConstrained: Bool
    ) -> Bool {
        waitsForWiFi
            && sizeBytes > largeUploadThresholdBytes
            && (networkIsExpensive || networkIsConstrained)
    }
}
