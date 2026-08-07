import Foundation
import SwiftUI

/// The app-owned preference key used to select ApertureKit copy immediately.
///
/// Keeping the key here lets package localization resolve the same choice as the
/// app without coupling this reusable target to `AppSession`.
public let AperturePreferredLocaleKey = "preferences.locale"

private func aperturePreferredLocale() -> Locale {
    guard let identifier = UserDefaults.standard.string(forKey: AperturePreferredLocaleKey),
          !identifier.isEmpty else {
        return .current
    }
    return Locale(identifier: identifier)
}

private func apertureLocalizedBundle(for locale: Locale) -> Bundle {
    let preferences = [
        locale.identifier,
        locale.language.languageCode?.identifier
    ].compactMap { $0 }
    guard let localization = Bundle.preferredLocalizations(
        from: Bundle.module.localizations,
        forPreferences: preferences
    ).first,
    let path = Bundle.module.path(forResource: localization, ofType: "lproj"),
    let bundle = Bundle(path: path) else {
        return .module
    }
    return bundle
}

/// Resolves a key against **ApertureKit's** bundle.
///
/// `Bundle.module` is synthesised only for SwiftPM targets, so an Xcode app target
/// cannot use it. Shared copy therefore has to be reached through this helper rather
/// than through `String(localized:bundle:.module)` at the call site.
public func ApertureString(
    _ key: String.LocalizationValue,
    locale: Locale? = nil
) -> String {
    let selectedLocale = locale ?? aperturePreferredLocale()
    return String(
        localized: key,
        bundle: apertureLocalizedBundle(for: selectedLocale),
        locale: selectedLocale
    )
}

/// Resolves a shared format string first, then applies its arguments. Interpolating
/// values into `String.LocalizationValue` changes the lookup key and leaks keys such
/// as `catalog.editionDate Jul 30, 2025` into the UI.
public func ApertureFormat(
    _ key: String.LocalizationValue,
    _ arguments: CVarArg...
) -> String {
    let locale = aperturePreferredLocale()
    return String(format: ApertureString(key, locale: locale), locale: locale, arguments: arguments)
}

public extension Text {
    /// `Text(aperture: "common.continue")` — shared copy from ApertureKit.
    init(aperture key: String.LocalizationValue) {
        self.init(ApertureString(key))
    }
}
