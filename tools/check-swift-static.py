#!/usr/bin/env python3
"""
Static checks for the Swift scaffold.

This does NOT replace compiling — nothing here can. It catches the specific classes of
mistake that are easy to make when writing Swift without a toolchain, and it enforces
the project rules that are expressible as text.

Usage:  python3 tools/check-swift-static.py [root]
"""
import re
import sys
import pathlib

ROOT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "apps")

BANNED_APIS = [
    (r"NavigationLink\(\s*isActive:", "deprecated NavigationLink(isActive:) — use navigationDestination(isPresented:)"),
    (r"\.accessibilityRepresentation\s*\{", "accessibilityRepresentation replaces the whole subtree — usually a bug"),
]

# ADR-012: no third-party SDKs in the client.
BANNED_IMPORTS = ["Firebase", "Sentry", "Amplitude", "Mixpanel", "Bugsnag", "GoogleAnalytics", "FBSDK", "AppsFlyer"]


def main() -> int:
    issues: list[str] = []
    files = sorted(ROOT.rglob("*.swift"))

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

    # Localisation parity and completeness.
    ui = ROOT / "packages/ApertureKit/Sources/ApertureUI/Resources"
    en_path, es_path = ui / "en.lproj/Localizable.strings", ui / "es.lproj/Localizable.strings"
    if en_path.exists() and es_path.exists():
        keys = {
            lang: set(re.findall(r'^"([^"]+)" = ', p.read_text(encoding="utf-8"), re.M))
            for lang, p in (("en", en_path), ("es", es_path))
        }
        if keys["en"] != keys["es"]:
            issues.append(f"locale drift: en-only={sorted(keys['en'] - keys['es'])} es-only={sorted(keys['es'] - keys['en'])}")

        used: set[str] = set()
        for path in files:
            src = path.read_text(encoding="utf-8")
            used |= set(re.findall(r'ApertureString\("([a-zA-Z0-9._]+)"\)', src))
            used |= set(re.findall(r'Text\(aperture:\s*"([a-zA-Z0-9._]+)"\)', src))
        for missing in sorted(used - keys["en"]):
            issues.append(f"localisation key used in code but not defined: {missing}")

    for issue in issues:
        print(f"FAIL {issue}")
    print(f"{len(files)} Swift files checked, {len(issues)} problems")
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())
