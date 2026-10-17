"""
Pastel Visual System & Accessibility Automated Verification Suite (APP-10, APP-11, APP-12).

Validates:
1. Pure white (#FFFFFF) canvas token and native pastel fills.
2. Saturated action tokens meeting WCAG AA contrast (>= 4.5:1) against pastel fills and white.
3. Dark ink typography (#202124) meeting WCAG AAA (>= 7:1) on white.
4. Modular 4px rhythm spacing and exact component radii (12px card, 8px chip, 32px control, 40px pill).
5. Non-color state encoding (NFR-A11Y-004): mandatory paired icon and text label.
6. 100% Spanish/English localization key parity across all resource bundles.
7. Workforce workstation (APP-11) pastel system styling and split-view stage pills.
"""
import pathlib
import re
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
DESIGN_TOKENS_SWIFT = REPO_ROOT / "apps" / "packages" / "ApertureKit" / "Sources" / "ApertureUI" / "DesignTokens.swift"
WORKFORCE_APP_SWIFT = REPO_ROOT / "apps" / "packages" / "ApertureKit" / "Sources" / "LaPlumaWorkforce" / "LaPlumaWorkforceApp.swift"
APERTURE_UI_EN = REPO_ROOT / "apps" / "packages" / "ApertureKit" / "Sources" / "ApertureUI" / "Resources" / "en.lproj" / "Localizable.strings"
APERTURE_UI_ES = REPO_ROOT / "apps" / "packages" / "ApertureKit" / "Sources" / "ApertureUI" / "Resources" / "es.lproj" / "Localizable.strings"
APERTURE_APP_EN = REPO_ROOT / "apps" / "ios" / "ApertureApp" / "en.lproj" / "Localizable.strings"
APERTURE_APP_ES = REPO_ROOT / "apps" / "ios" / "ApertureApp" / "es.lproj" / "Localizable.strings"
FEATURES_DIR = REPO_ROOT / "apps" / "ios" / "ApertureApp" / "Features"


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def relative_luminance(r: float, g: float, b: float) -> float:
    r_lin = srgb_to_linear(r)
    g_lin = srgb_to_linear(g)
    b_lin = srgb_to_linear(b)
    return 0.2126 * r_lin + 0.7152 * g_lin + 0.0722 * b_lin


def contrast_ratio(rgb1: tuple[float, float, float], rgb2: tuple[float, float, float]) -> float:
    l1 = relative_luminance(*rgb1)
    l2 = relative_luminance(*rgb2)
    lighter = max(l1, l2)
    darker = min(l1, l2)
    return (lighter + 0.05) / (darker + 0.05)


def extract_strings_keys(path: pathlib.Path) -> set[str]:
    return set(re.findall(r'^"((?:\\.|[^"\\])+)"\s*=', path.read_text(encoding="utf-8"), re.M))


class VisualSystemAndAccessibilityTests(unittest.TestCase):

    def setUp(self):
        self.assertTrue(DESIGN_TOKENS_SWIFT.exists(), f"Missing {DESIGN_TOKENS_SWIFT}")
        self.tokens_code = DESIGN_TOKENS_SWIFT.read_text(encoding="utf-8")
        self.workforce_code = WORKFORCE_APP_SWIFT.read_text(encoding="utf-8")

    def test_white_canvas_and_pastel_palette_tokens(self):
        """Palette must define pure white canvas, dark ink, and the pastel fills."""
        self.assertIn("whiteSurface", self.tokens_code)
        self.assertIn("darkInk", self.tokens_code)
        self.assertIn("inkSecondary", self.tokens_code)
        self.assertIn("pastelRed", self.tokens_code)
        self.assertIn("pastelYellow", self.tokens_code)
        self.assertIn("pastelGreen", self.tokens_code)
        self.assertIn("pastelBlue", self.tokens_code)
        self.assertIn("actionRed", self.tokens_code)
        self.assertIn("actionYellow", self.tokens_code)
        self.assertIn("actionGreen", self.tokens_code)
        self.assertIn("actionBlue", self.tokens_code)

    def test_contrast_ratios_meet_wcag_aa(self):
        """Action variants must achieve >= 4.5:1 contrast against respective pastel fills and white."""
        white = (1.0, 1.0, 1.0)
        dark_ink = (32 / 255.0, 33 / 255.0, 36 / 255.0)

        pastel_red = (252 / 255.0, 228 / 255.0, 228 / 255.0)
        action_red = (179 / 255.0, 38 / 255.0, 30 / 255.0)

        pastel_yellow = (255 / 255.0, 244 / 255.0, 204 / 255.0)
        action_yellow = (125 / 255.0, 87 / 255.0, 0 / 255.0)

        pastel_green = (227 / 255.0, 243 / 255.0, 232 / 255.0)
        action_green = (27 / 255.0, 110 / 255.0, 50 / 255.0)

        pastel_blue = (227 / 255.0, 238 / 255.0, 252 / 255.0)
        action_blue = (24 / 255.0, 90 / 255.0, 188 / 255.0)

        self.assertGreaterEqual(contrast_ratio(action_red, pastel_red), 4.5)
        self.assertGreaterEqual(contrast_ratio(action_red, white), 4.5)

        self.assertGreaterEqual(contrast_ratio(action_yellow, pastel_yellow), 4.5)
        self.assertGreaterEqual(contrast_ratio(action_yellow, white), 4.5)

        self.assertGreaterEqual(contrast_ratio(action_green, pastel_green), 4.5)
        self.assertGreaterEqual(contrast_ratio(action_green, white), 4.5)

        self.assertGreaterEqual(contrast_ratio(action_blue, pastel_blue), 4.5)
        self.assertGreaterEqual(contrast_ratio(action_blue, white), 4.5)

        self.assertGreaterEqual(contrast_ratio(dark_ink, white), 7.0)

    def test_geometry_and_component_radii(self):
        """Radii must match: card 12, chip 8, control 32, pill 40."""
        self.assertIn("card: CGFloat = 12", self.tokens_code)
        self.assertIn("chip: CGFloat = 8", self.tokens_code)
        self.assertIn("control: CGFloat = 32", self.tokens_code)
        self.assertIn("pill: CGFloat = 40", self.tokens_code)

    def test_card_and_pill_modifiers_available(self):
        """Modifiers for flat pastel cards and pills must be exposed in View extension."""
        self.assertIn("func aperturePastelCard(", self.tokens_code)
        self.assertIn("func aperturePastelPill(", self.tokens_code)

    def test_aperture_canvas_mercury_dark_and_pure_white_support(self):
        """ApertureCanvas must default to the adaptive canvas (Mercury Onyx in dark) while supporting pure white."""
        self.assertIn("public init(pureWhite: Bool = false", self.tokens_code)
        self.assertIn("Aperture.Palette.canvas", self.tokens_code)
        self.assertRegex(self.tokens_code, r"static let canvas = adaptive\(\s*light:[^)]*\),\s*dark: onyxCanvas")
        self.assertIn("Aperture.Palette.whiteSurface", self.tokens_code)

    def test_semantic_tokens_resolve_per_appearance(self):
        """APP-25: semantic text and surface tokens must resolve per appearance, never to a dark-only swatch."""
        for token, dark in [
            ("surface", "graphiteCard"),
            ("surfaceSecondary", "obsidianButton"),
            ("onSurface", "ivoryText"),
            ("onSurfaceSecondary", "ashText"),
        ]:
            self.assertRegex(
                self.tokens_code,
                rf"public static let {token} = adaptive\([\s\S]*?dark: {dark}\b",
                f"{token} must be adaptive with {dark} as its dark value",
            )
        for token in ["warning", "critical", "information", "positive", "accent"]:
            self.assertRegex(self.tokens_code, rf"public static let {token} = adaptive\(")
        self.assertIn("traits.userInterfaceStyle == .dark", self.tokens_code)
        # Neutral pairs with the adaptive secondary surface, so its foreground must adapt too.
        self.assertIn("case .neutral: Palette.onSurface", self.tokens_code)

    def test_light_appearance_counterparts_meet_wcag_aa(self):
        """APP-25: the light counterparts must clear WCAG AA on every light surface they sit on."""
        light_surfaces = {
            "white": (1.0, 1.0, 1.0),
            "canvas #F2F2F7": (242 / 255.0, 242 / 255.0, 247 / 255.0),
            "surfaceSecondary #E9E9F0": (233 / 255.0, 233 / 255.0, 240 / 255.0),
        }
        light_foregrounds = {
            "onSurface #1c1c24": (28 / 255.0, 28 / 255.0, 36 / 255.0),
            "onSurfaceSecondary #4a4a57": (74 / 255.0, 74 / 255.0, 87 / 255.0),
            "accent #3d4fd6": (61 / 255.0, 79 / 255.0, 214 / 255.0),
            "warning #7d4000": (125 / 255.0, 64 / 255.0, 0 / 255.0),
            "critical #b80005": (184 / 255.0, 0 / 255.0, 5 / 255.0),
            "information #005785": (0 / 255.0, 87 / 255.0, 133 / 255.0),
            "positive #00612e": (0 / 255.0, 97 / 255.0, 46 / 255.0),
        }
        for fg_name, fg in light_foregrounds.items():
            for bg_name, bg in light_surfaces.items():
                ratio = contrast_ratio(fg, bg)
                self.assertGreaterEqual(ratio, 4.5, f"{fg_name} on {bg_name} ({ratio:.2f}) < 4.5")

    def test_dark_appearance_accent_meets_wcag_aa(self):
        """APP-25: the dark foreground accent must clear AA on Onyx, Graphite and Obsidian (Cobalt does not)."""
        accent_dark = (154 / 255.0, 166 / 255.0, 255 / 255.0)  # #9aa6ff
        cobalt = (82 / 255.0, 102 / 255.0, 235 / 255.0)
        onyx = (23 / 255.0, 23 / 255.0, 33 / 255.0)
        for bg in [onyx, (30 / 255.0, 30 / 255.0, 42 / 255.0), (39 / 255.0, 39 / 255.0, 53 / 255.0)]:
            self.assertGreaterEqual(contrast_ratio(accent_dark, bg), 4.5)
        self.assertLess(contrast_ratio(cobalt, onyx), 4.5, "Cobalt as dark-mode text is why accent adapts")

    def test_mercury_alpine_tokens_and_wcag_contrast(self):
        """Mercury Alpine tokens must be defined and exceed WCAG AA/AAA contrast ratios."""
        self.assertIn("onyxCanvas", self.tokens_code)
        self.assertIn("graphiteCard", self.tokens_code)
        self.assertIn("obsidianButton", self.tokens_code)
        self.assertIn("slateBorder", self.tokens_code)
        self.assertIn("mistBorder", self.tokens_code)
        self.assertIn("ivoryText", self.tokens_code)
        self.assertIn("ashText", self.tokens_code)
        self.assertIn("cobalt", self.tokens_code)

        onyx_canvas = (23 / 255.0, 23 / 255.0, 33 / 255.0)      # #171721
        graphite_card = (30 / 255.0, 30 / 255.0, 42 / 255.0)    # #1e1e2a
        ivory_text = (237 / 255.0, 237 / 255.0, 243 / 255.0)    # #ededf3
        ash_text = (195 / 255.0, 195 / 255.0, 204 / 255.0)      # #c3c3cc
        cobalt = (82 / 255.0, 102 / 255.0, 235 / 255.0)         # #5266eb
        white = (1.0, 1.0, 1.0)

        # Ivory on Onyx Canvas (exceeds AAA >= 7:1)
        cr_ivory_onyx = contrast_ratio(ivory_text, onyx_canvas)
        self.assertGreaterEqual(cr_ivory_onyx, 7.0, f"Ivory on Onyx ({cr_ivory_onyx:.2f}) < 7.0")

        # Ivory on Graphite Card (exceeds AAA >= 7:1)
        cr_ivory_graphite = contrast_ratio(ivory_text, graphite_card)
        self.assertGreaterEqual(cr_ivory_graphite, 7.0, f"Ivory on Graphite ({cr_ivory_graphite:.2f}) < 7.0")

        # Ash on Graphite Card (exceeds AAA >= 7:1)
        cr_ash_graphite = contrast_ratio(ash_text, graphite_card)
        self.assertGreaterEqual(cr_ash_graphite, 7.0, f"Ash on Graphite ({cr_ash_graphite:.2f}) < 7.0")

        # White on Cobalt (exceeds AA >= 4.5:1)
        cr_white_cobalt = contrast_ratio(white, cobalt)
        self.assertGreaterEqual(cr_white_cobalt, 4.5, f"White on Cobalt ({cr_white_cobalt:.2f}) < 4.5")

    def test_sensory_haptics_utility_present(self):
        """ApertureHaptics must expose cross-platform feedback and impact methods."""
        self.assertIn("public enum ApertureHaptics", self.tokens_code)
        self.assertIn("public static func feedback(", self.tokens_code)
        self.assertIn("public static func impact(", self.tokens_code)

    def test_non_color_state_encoding(self):
        """All StatusTone values must provide an SF Symbol icon for accessibility (NFR-A11Y-004)."""
        self.assertIn("var iconName: String", self.tokens_code)
        for tone_icon in ["info.circle.fill", "exclamationmark.circle.fill", "exclamationmark.triangle.fill", "checkmark.circle.fill", "circle.fill"]:
            self.assertIn(tone_icon, self.tokens_code)

    def test_workforce_workstation_pastel_adoption(self):
        """Workforce workbench must use ApertureCanvas, stage pills, and non-color icons (APP-11)."""
        self.assertIn("ApertureCanvas {", self.workforce_code)
        self.assertIn("stagePill(", self.workforce_code)
        self.assertIn("aperturePastelPill(", self.workforce_code)
        self.assertIn("accessibilityLabel(", self.workforce_code)

    def test_localization_key_symmetry_aperture_ui(self):
        """ApertureUI English and Spanish Localizable.strings must have 100% key parity."""
        en_keys = extract_strings_keys(APERTURE_UI_EN)
        es_keys = extract_strings_keys(APERTURE_UI_ES)
        self.assertEqual(en_keys, es_keys, f"ApertureUI localization drift: en-es={en_keys - es_keys}, es-en={es_keys - en_keys}")

    def test_localization_key_symmetry_aperture_app(self):
        """ApertureApp English and Spanish Localizable.strings must have 100% key parity."""
        en_keys = extract_strings_keys(APERTURE_APP_EN)
        es_keys = extract_strings_keys(APERTURE_APP_ES)
        self.assertEqual(en_keys, es_keys, f"ApertureApp localization drift: en-es={en_keys - es_keys}, es-en={es_keys - en_keys}")

    def test_touch_target_accessibility_standards(self):
        """Touch targets must enforce minimum 44pt and accessible 48pt targets (APP-12)."""
        self.assertIn("minimumTarget: CGFloat = 44", self.tokens_code)
        self.assertIn("accessibleTarget: CGFloat = 48", self.tokens_code)

    def test_dynamic_type_typography_standards(self):
        """Typography must use scalable semantic font tokens (APP-12)."""
        self.assertIn("screenTitle = Font.largeTitle.weight(.bold)", self.tokens_code)
        self.assertIn("sectionTitle = Font.title3.weight(.semibold)", self.tokens_code)
        self.assertIn("body = Font.body", self.tokens_code)
        self.assertIn("caption = Font.footnote", self.tokens_code)

    def test_applicant_screens_route_inventory_and_pastel_adoption(self):
        """Applicant functional routes must adopt ApertureUI, pastel tokens, and 12px cards (APP-10)."""
        self.assertTrue(FEATURES_DIR.exists(), f"Missing {FEATURES_DIR}")
        required_routes = [
            FEATURES_DIR / "Home" / "HomeView.swift",
            FEATURES_DIR / "Catalog" / "CatalogView.swift",
            FEATURES_DIR / "Workflow" / "BlueprintFormEntryView.swift",
            FEATURES_DIR / "Workflow" / "WorkflowViews.swift",
        ]
        for route in required_routes:
            self.assertTrue(route.exists(), f"Missing route {route}")
            content = route.read_text(encoding="utf-8")
            self.assertIn("import ApertureUI", content, f"{route.name} must import ApertureUI")
            has_pastel_surface = (
                "ApertureCanvas" in content
                or "aperturePastelCard" in content
                or "aperturePastelPill" in content
                or "Aperture.Palette" in content
            )
            self.assertTrue(has_pastel_surface, f"{route.name} must use pastel tokens or canvas")


if __name__ == "__main__":
    unittest.main()
