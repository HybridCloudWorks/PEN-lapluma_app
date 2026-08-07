import Foundation
import ApertureUI

/// Resolves main-bundle copy against the in-app language preference immediately.
func LaPlumaString(_ key: String.LocalizationValue) -> String {
    let identifier = UserDefaults.standard.string(forKey: AperturePreferredLocaleKey)
    let locale = identifier.map { Locale(identifier: $0) } ?? .current
    let preferences = [
        locale.identifier,
        locale.language.languageCode?.identifier
    ].compactMap { $0 }
    let localization = Bundle.preferredLocalizations(
        from: Bundle.main.localizations,
        forPreferences: preferences
    ).first
    let localizedBundle = localization
        .flatMap { Bundle.main.path(forResource: $0, ofType: "lproj") }
        .flatMap(Bundle.init(path:)) ?? .main
    return String(localized: key, bundle: localizedBundle, locale: locale)
}
