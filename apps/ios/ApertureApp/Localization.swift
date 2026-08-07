import Foundation
import ApertureUI

/// Resolves main-bundle copy against the in-app language preference immediately.
func LaPlumaString(_ key: String.LocalizationValue) -> String {
    let locale = laPlumaPreferredLocale()
    return String(localized: key, bundle: laPlumaLocalizedBundle(for: locale), locale: locale)
}

/// Resolves a named app-bundle format key with the same in-app locale used by
/// `LaPlumaString`. Callers use this for counts and dynamic values so a runtime
/// `String` never bypasses the selected language.
func LaPlumaFormat(_ key: String.LocalizationValue, _ arguments: CVarArg...) -> String {
    let locale = laPlumaPreferredLocale()
    let format = String(localized: key, bundle: laPlumaLocalizedBundle(for: locale), locale: locale)
    return String(format: format, locale: locale, arguments: arguments)
}

func laPlumaPreferredLocale() -> Locale {
    let identifier = UserDefaults.standard.string(forKey: AperturePreferredLocaleKey)
    return identifier.map { Locale(identifier: $0) } ?? .current
}

private func laPlumaLocalizedBundle(for locale: Locale) -> Bundle {
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
    return localizedBundle
}
