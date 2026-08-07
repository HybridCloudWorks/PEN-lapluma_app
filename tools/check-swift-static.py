#!/usr/bin/env python3
"""
Static source-policy checks for the Swift mobile app.

This does not replace compiling or runtime tests. It enforces project rules that are
reliably expressible as text.

Usage:  python3 tools/check-swift-static.py [root]
"""
import re
import sys
import pathlib
import plistlib

ROOT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "apps")

BANNED_APIS = [
    (r"NavigationLink\(\s*isActive:", "deprecated NavigationLink(isActive:) — use navigationDestination(isPresented:)"),
    (r"\.accessibilityRepresentation\s*\{", "accessibilityRepresentation replaces the whole subtree — usually a bug"),
]

# ADR-012: no third-party SDKs in the client.
BANNED_IMPORTS = ["Firebase", "Sentry", "Amplitude", "Mixpanel", "Bugsnag", "GoogleAnalytics", "FBSDK", "AppsFlyer"]

SWIFT_STRING = r'"((?:\\.|[^"\\])*)"'
APP_LOCALIZED_LITERAL_PATTERNS = [
    rf'\b(?:Text|Label|Button|NavigationLink|Section|TextField|LabeledContent|Toggle|Picker|Link|ProgressView|DisclosureGroup)\(\s*{SWIFT_STRING}',
    rf'\.(?:navigationTitle|accessibilityLabel|accessibilityHint|accessibilityValue|alert)\(\s*{SWIFT_STRING}',
]


def strings_keys(path: pathlib.Path) -> set[str]:
    return set(re.findall(r'^"((?:\\.|[^"\\])+)"\s*=\s*', path.read_text(encoding="utf-8"), re.M))


def strings_values(path: pathlib.Path) -> dict[str, str]:
    return dict(re.findall(
        r'^"((?:\\.|[^"\\])+)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;',
        path.read_text(encoding="utf-8"),
        re.M,
    ))


def stringsdict_keys(path: pathlib.Path, issues: list[str]) -> set[str]:
    if not path.exists():
        issues.append(f"required plural localisation resource is missing: {path}")
        return set()
    try:
        with path.open("rb") as stream:
            value = plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException) as error:
        issues.append(f"invalid stringsdict resource {path}: {error}")
        return set()
    if not isinstance(value, dict):
        issues.append(f"invalid stringsdict root in {path}: expected dictionary")
        return set()
    for key, definition in value.items():
        if not isinstance(definition, dict) or not isinstance(
            definition.get("NSStringLocalizedFormatKey"), str
        ):
            issues.append(f"invalid plural entry '{key}' in {path}: missing format key")
            continue
        plural_rules = [
            rule for rule in definition.values()
            if isinstance(rule, dict)
            and rule.get("NSStringFormatSpecTypeKey") == "NSStringPluralRuleType"
        ]
        if not plural_rules:
            issues.append(f"invalid plural entry '{key}' in {path}: no plural rule")
        for rule in plural_rules:
            if "one" not in rule or "other" not in rule:
                issues.append(
                    f"invalid plural entry '{key}' in {path}: one/other forms are required"
                )
    return set(value)


def main() -> int:
    issues: list[str] = []
    files = sorted(ROOT.rglob("*.swift"))
    if not files:
        issues.append(f"{ROOT}: no Swift files found; refusing to pass an empty scan")

    for path in files:
        src = path.read_text(encoding="utf-8")

        for open_c, close_c in [("{", "}"), ("(", ")"), ("[", "]")]:
            if src.count(open_c) != src.count(close_c):
                issues.append(f"{path}: unbalanced {open_c}{close_c}")

        # Bundle.module is synthesised only for SwiftPM targets.
        if "bundle: .module" in src and "/ios/" in str(path):
            issues.append(f"{path}: Bundle.module is unavailable in an Xcode app target")

        for pattern, why in BANNED_APIS:
            for match in re.finditer(pattern, src):
                line = src[: match.start()].count("\n") + 1
                issues.append(f"{path}:{line}: {why}")

        for banned in BANNED_IMPORTS:
            if re.search(rf"^import\s+{banned}", src, re.M):
                issues.append(f"{path}: third-party SDK '{banned}' is forbidden (ADR-012)")

        # C-12: app-authored motion must honor Reduce Motion through the shared
        # modifier. System navigation and presentation animations already do so.
        if path.name != "DesignTokens.swift":
            for pattern in (r"\.animation\s*\(", r"\bwithAnimation\s*\("):
                for match in re.finditer(pattern, src):
                    line = src[: match.start()].count("\n") + 1
                    issues.append(
                        f"{path}:{line}: raw animation bypasses Reduce Motion — "
                        "use respectfulAnimation(value:)"
                    )

    # Localisation parity for both resource-bundle boundaries.
    ui = ROOT / "packages/ApertureKit/Sources/ApertureUI/Resources"
    en_path, es_path = ui / "en.lproj/Localizable.strings", ui / "es.lproj/Localizable.strings"
    for resource in (en_path, es_path):
        if not resource.is_file():
            issues.append(f"required localisation resource is missing: {resource}")
    if en_path.exists() and es_path.exists():
        keys = {lang: strings_keys(p) for lang, p in (("en", en_path), ("es", es_path))}
        if keys["en"] != keys["es"]:
            issues.append(f"locale drift: en-only={sorted(keys['en'] - keys['es'])} es-only={sorted(keys['es'] - keys['en'])}")

        used: set[str] = set()
        for path in files:
            src = path.read_text(encoding="utf-8")
            used |= set(re.findall(rf'ApertureString\(\s*{SWIFT_STRING}', src))
            used |= set(re.findall(rf'ApertureFormat\(\s*{SWIFT_STRING}', src))
            used |= set(re.findall(rf'Text\(aperture:\s*{SWIFT_STRING}', src))
        for missing in sorted(used - keys["en"]):
            issues.append(f"localisation key used in code but not defined: {missing}")

    app = ROOT / "ios/ApertureApp"
    app_en, app_es = app / "en.lproj/Localizable.strings", app / "es.lproj/Localizable.strings"
    for resource in (app_en, app_es):
        if not resource.is_file():
            issues.append(f"required localisation resource is missing: {resource}")
    if app_en.exists() and app_es.exists():
        app_plural_paths = {
            "en": app / "en.lproj/Localizable.stringsdict",
            "es": app / "es.lproj/Localizable.stringsdict",
        }
        app_keys = {lang: strings_keys(p) for lang, p in (("en", app_en), ("es", app_es))}
        app_plural_keys = {
            lang: stringsdict_keys(path, issues)
            for lang, path in app_plural_paths.items()
        }
        if app_keys["en"] != app_keys["es"]:
            issues.append(
                "app locale drift: "
                f"en-only={sorted(app_keys['en'] - app_keys['es'])} "
                f"es-only={sorted(app_keys['es'] - app_keys['en'])}"
            )
        if app_plural_keys["en"] != app_plural_keys["es"]:
            issues.append(
                "app plural locale drift: "
                f"en-only={sorted(app_plural_keys['en'] - app_plural_keys['es'])} "
                f"es-only={sorted(app_plural_keys['es'] - app_plural_keys['en'])}"
            )

        all_app_keys = app_keys["en"] | app_plural_keys["en"]
        used_app_keys: set[str] = set()
        for path in sorted(app.rglob("*.swift")):
            src = path.read_text(encoding="utf-8")
            used_app_keys |= set(re.findall(rf'LaPlumaString\(\s*{SWIFT_STRING}', src))
            used_app_keys |= set(re.findall(rf'LaPlumaFormat\(\s*{SWIFT_STRING}', src))
            for pattern in APP_LOCALIZED_LITERAL_PATTERNS:
                for match in re.finditer(pattern, src):
                    key = match.group(1)
                    literal_copy = re.sub(r"\\\([^)]*\)", "", key)
                    if not key or not re.search(r"[A-Za-z]", literal_copy):
                        continue
                    line = src[: match.start()].count("\n") + 1
                    if "\\(" in key:
                        issues.append(
                            f"{path}:{line}: interpolated applicant-facing copy bypasses "
                            "plural/format localization — use LaPlumaFormat"
                        )
                    else:
                        used_app_keys.add(key)

            for match in re.finditer(r'count\s*==\s*1\s*\?\s*""\s*:\s*"s"', src):
                line = src[: match.start()].count("\n") + 1
                issues.append(
                    f"{path}:{line}: hand-written English plural suffix — use a stringsdict key"
                )

        for missing in sorted(used_app_keys - all_app_keys):
            issues.append(f"app localisation key used in code but not defined: {missing}")

        package_values = strings_values(en_path)
        for path in sorted(app.rglob("*.swift")):
            src = path.read_text(encoding="utf-8")
            for key in re.findall(r'messageKey:\s*"([a-zA-Z0-9._]+)"', src):
                if "%" in package_values.get(key, ""):
                    issues.append(
                        f"{path}: formatted package key '{key}' is rendered without arguments"
                    )

    for issue in issues:
        print(f"FAIL {issue}")
    print(f"{len(files)} Swift files checked, {len(issues)} problems")
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())
