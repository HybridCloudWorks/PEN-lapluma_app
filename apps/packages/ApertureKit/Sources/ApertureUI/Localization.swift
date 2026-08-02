import Foundation
import SwiftUI

/// Resolves a key against **ApertureKit's** bundle.
///
/// `Bundle.module` is synthesised only for SwiftPM targets, so an Xcode app target
/// cannot use it. Shared copy therefore has to be reached through this helper rather
/// than through `String(localized:bundle:.module)` at the call site.
public func ApertureString(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}

/// Resolves a shared format string first, then applies its arguments. Interpolating
/// values into `String.LocalizationValue` changes the lookup key and leaks keys such
/// as `catalog.editionDate Jul 30, 2025` into the UI.
public func ApertureFormat(
    _ key: String.LocalizationValue,
    _ arguments: CVarArg...
) -> String {
    String(format: ApertureString(key), locale: .current, arguments: arguments)
}

public extension Text {
    /// `Text(aperture: "common.continue")` — shared copy from ApertureKit.
    init(aperture key: String.LocalizationValue) {
        self.init(ApertureString(key))
    }
}
