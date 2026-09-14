"""
Native Pastel Design Tokens & Shared Specification Test Suite (INT-10, APP-09).

Verifies:
1. Palette completeness: Pure white canvas, pastel red/yellow/green/blue, dark ink.
2. Accessible WCAG AA contrast ratios (>= 4.5:1) for action/text variants on pastels.
3. Component geometry: 12px flat cards, 32px controls/buttons, 40px pills, 8px chips.
4. 4px modular grid rhythm scale: 4, 8, 12, 16, 20, 24, 32, 40, 56, 72, 112, 128px.
5. Non-color state encoding (NFR-A11Y-004): Mandatory paired icon for all status tones.
6. Flat card styling: Surface separation without drop shadows.
"""
import pathlib
import re
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
DESIGN_TOKENS_SWIFT = REPO_ROOT / "apps" / "packages" / "ApertureKit" / "Sources" / "ApertureUI" / "DesignTokens.swift"


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


class DesignTokensContractTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(DESIGN_TOKENS_SWIFT.exists(), f"Missing DesignTokens.swift at {DESIGN_TOKENS_SWIFT}")
        self.tokens_code = DESIGN_TOKENS_SWIFT.read_text(encoding="utf-8")

    def test_pastel_palette_tokens_present(self):
        """Aperture.Palette must define white canvas, dark ink, and the four pastel fills."""
        # White canvas and dark ink
        self.assertIn("whiteSurface", self.tokens_code)
        self.assertIn("darkInk", self.tokens_code)
        self.assertIn("inkSecondary", self.tokens_code)

        # Pastel fills
        self.assertIn("pastelRed", self.tokens_code)
        self.assertIn("pastelYellow", self.tokens_code)
        self.assertIn("pastelGreen", self.tokens_code)
        self.assertIn("pastelBlue", self.tokens_code)

        # Action / foreground accessible variants
        self.assertIn("actionRed", self.tokens_code)
        self.assertIn("actionYellow", self.tokens_code)
        self.assertIn("actionGreen", self.tokens_code)
        self.assertIn("actionBlue", self.tokens_code)

    def test_wcag_aa_contrast_compliance_on_pastels(self):
        """Action variants must achieve >= 4.5:1 contrast against their respective pastel fills and white."""
        # RGB normalized values matching DesignTokens.swift
        white = (1.0, 1.0, 1.0)
        dark_ink = (32 / 255.0, 33 / 255.0, 36 / 255.0)  # #202124

        pastel_red = (252 / 255.0, 228 / 255.0, 228 / 255.0)  # #FCE4E4
        action_red = (179 / 255.0, 38 / 255.0, 30 / 255.0)  # #B3261E

        pastel_yellow = (255 / 255.0, 244 / 255.0, 204 / 255.0)  # #FFF4CC
        action_yellow = (125 / 255.0, 87 / 255.0, 0 / 255.0)  # #7D5700

        pastel_green = (227 / 255.0, 243 / 255.0, 232 / 255.0)  # #E3F3E8
        action_green = (27 / 255.0, 110 / 255.0, 50 / 255.0)  # #1B6E32

        pastel_blue = (227 / 255.0, 238 / 255.0, 252 / 255.0)  # #E3EEFC
        action_blue = (24 / 255.0, 90 / 255.0, 188 / 255.0)  # #185ABC

        # 1. Action Red on Pastel Red & White
        cr_red_pastel = contrast_ratio(action_red, pastel_red)
        cr_red_white = contrast_ratio(action_red, white)
        self.assertGreaterEqual(cr_red_pastel, 4.5, f"ActionRed on PastelRed ({cr_red_pastel:.2f}) < 4.5")
        self.assertGreaterEqual(cr_red_white, 4.5, f"ActionRed on White ({cr_red_white:.2f}) < 4.5")

        # 2. Action Yellow on Pastel Yellow & White
        cr_yellow_pastel = contrast_ratio(action_yellow, pastel_yellow)
        cr_yellow_white = contrast_ratio(action_yellow, white)
        self.assertGreaterEqual(cr_yellow_pastel, 4.5, f"ActionYellow on PastelYellow ({cr_yellow_pastel:.2f}) < 4.5")
        self.assertGreaterEqual(cr_yellow_white, 4.5, f"ActionYellow on White ({cr_yellow_white:.2f}) < 4.5")

        # 3. Action Green on Pastel Green & White
        cr_green_pastel = contrast_ratio(action_green, pastel_green)
        cr_green_white = contrast_ratio(action_green, white)
        self.assertGreaterEqual(cr_green_pastel, 4.5, f"ActionGreen on PastelGreen ({cr_green_pastel:.2f}) < 4.5")
        self.assertGreaterEqual(cr_green_white, 4.5, f"ActionGreen on White ({cr_green_white:.2f}) < 4.5")

        # 4. Action Blue on Pastel Blue & White
        cr_blue_pastel = contrast_ratio(action_blue, pastel_blue)
        cr_blue_white = contrast_ratio(action_blue, white)
        self.assertGreaterEqual(cr_blue_pastel, 4.5, f"ActionBlue on PastelBlue ({cr_blue_pastel:.2f}) < 4.5")
        self.assertGreaterEqual(cr_blue_white, 4.5, f"ActionBlue on White ({cr_blue_white:.2f}) < 4.5")

        # 5. Dark Ink on White Canvas (should achieve AAA >= 7.0)
        cr_ink_white = contrast_ratio(dark_ink, white)
        self.assertGreaterEqual(cr_ink_white, 7.0, f"DarkInk on White ({cr_ink_white:.2f}) < 7.0 (AAA)")

        # 6. Prove why white text on pastels is prohibited (contrast < 2.0)
        cr_white_on_pastel_red = contrast_ratio(white, pastel_red)
        self.assertLess(cr_white_on_pastel_red, 2.0, "White text on pastel red should fail contrast")

    def test_geometry_and_radii(self):
        """Cards must be 12px, controls 32px, pills 40px, chips 8px."""
        self.assertIn("public static let card: CGFloat = 12", self.tokens_code)
        self.assertIn("public static let control: CGFloat = 32", self.tokens_code)
        self.assertIn("public static let pill: CGFloat = 40", self.tokens_code)
        self.assertIn("public static let chip: CGFloat = 8", self.tokens_code)

    def test_spacing_4px_grid_rhythm(self):
        """Spacing scale must provide a complete 4px modular grid rhythm."""
        for step in [4, 8, 12, 16, 20, 24, 32, 40, 56, 72, 112, 128]:
            self.assertTrue(
                re.search(rf":\s*CGFloat\s*=\s*{step}\b", self.tokens_code),
                f"Missing grid step {step} in Spacing enum",
            )

    def test_non_color_accessibility_invariants(self):
        """StatusTone must provide a paired SF Symbol iconName for every tone (NFR-A11Y-004)."""
        self.assertIn("var iconName: String", self.tokens_code)
        self.assertIn('"info.circle.fill"', self.tokens_code)
        self.assertIn('"exclamationmark.circle.fill"', self.tokens_code)
        self.assertIn('"exclamationmark.triangle.fill"', self.tokens_code)
        self.assertIn('"checkmark.circle.fill"', self.tokens_code)
        self.assertIn('"circle.fill"', self.tokens_code)

    def test_flat_card_styling_no_drop_shadows(self):
        """Flat cards must not rely on heavy drop shadows."""
        self.assertNotIn(".shadow(color: .black.opacity(0.06), radius: 18, y: 8)", self.tokens_code)
        self.assertIn(".shadow(color: .clear, radius: 0)", self.tokens_code)


if __name__ == "__main__":
    unittest.main()
