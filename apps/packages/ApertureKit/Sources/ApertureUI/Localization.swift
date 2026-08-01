import Foundation

/// Resolves a key against **ApertureKit's** bundle.
///
/// `Bundle.module` is synthesised only for SwiftPM targets, so an Xcode app target
/// cannot use it. Shared copy therefore has to be reached through this helper rather
/// than through `String(localized:bundle:.module)` at the call site.
public func ApertureString(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}

public extension Text {
    /// `Text(aperture: "common.continue")` — shared copy from ApertureKit.
    init(aperture key: String.LocalizationValue) {
        self.init(ApertureString(key))
    }
}
