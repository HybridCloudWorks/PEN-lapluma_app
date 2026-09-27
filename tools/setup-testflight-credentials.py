#!/usr/bin/env python3
"""
TestFlight Credentials & Signing Setup Helper.

Helps configure GitHub repository or environment variables and secrets
for automated TestFlight builds in PEN-lapluma_app:

1. APPLE_DEVELOPMENT_TEAM (10-character team ID from developer.apple.com/account)
2. PRODUCT_BUNDLE_IDENTIFIER (default: app.aperture.mobile)
3. APP_STORE_CONNECT_API_KEY_ID (10-character key ID from App Store Connect)
4. APP_STORE_CONNECT_API_ISSUER_ID (UUID from App Store Connect Keys page)
5. APP_STORE_CONNECT_API_PRIVATE_KEY_BASE64 (Base64-encoded contents of AuthKey_*.p8)

Usage:
    python tools/setup-testflight-credentials.py --status
    python tools/setup-testflight-credentials.py --team-id=<TEAM> --key-id=<KEY_ID> --issuer-id=<UUID> --key-file=<PATH_TO_P8>
"""

import argparse
import base64
import os
import pathlib
import subprocess
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ENVIRONMENT_NAME = "internal-testflight"
DEFAULT_BUNDLE_ID = "app.aperture.mobile"


def run_gh(cmd: list[str], input_str: str | None = None) -> tuple[int, str, str]:
    try:
        res = subprocess.run(
            ["gh"] + cmd,
            input=input_str,
            capture_output=True,
            text=True,
            check=False
        )
        return res.returncode, res.stdout.strip(), res.stderr.strip()
    except FileNotFoundError:
        return 1, "", "gh CLI not installed or not in PATH"


def check_status():
    print("=" * 70)
    print("TESTFLIGHT PREFLIGHT CREDENTIALS AUDIT")
    print(f"Target Environment: {ENVIRONMENT_NAME}")
    print("=" * 70)

    # 1. Variables
    code, stdout, stderr = run_gh(["variable", "list", "--env", ENVIRONMENT_NAME])
    existing_vars = {}
    if code == 0 and stdout:
        for line in stdout.splitlines():
            parts = line.split(maxsplit=1)
            if parts:
                existing_vars[parts[0]] = parts[1] if len(parts) > 1 else ""

    # 2. Secrets
    code, stdout, stderr = run_gh(["secret", "list", "--env", ENVIRONMENT_NAME])
    existing_secrets = set()
    if code == 0 and stdout:
        for line in stdout.splitlines():
            parts = line.split(maxsplit=1)
            if parts:
                existing_secrets.add(parts[0])

    items = [
        ("APPLE_DEVELOPMENT_TEAM", "variable", existing_vars.get("APPLE_DEVELOPMENT_TEAM")),
        ("PRODUCT_BUNDLE_IDENTIFIER", "variable", existing_vars.get("PRODUCT_BUNDLE_IDENTIFIER", DEFAULT_BUNDLE_ID)),
        ("APP_STORE_CONNECT_API_KEY_ID", "variable", existing_vars.get("APP_STORE_CONNECT_API_KEY_ID")),
        ("APP_STORE_CONNECT_API_ISSUER_ID", "variable", existing_vars.get("APP_STORE_CONNECT_API_ISSUER_ID")),
        ("APP_STORE_CONNECT_API_PRIVATE_KEY_BASE64", "secret", "Configured" if "APP_STORE_CONNECT_API_PRIVATE_KEY_BASE64" in existing_secrets else None),
    ]

    all_ready = True
    for name, kind, val in items:
        status_str = f"[SET] {val}" if val else "[MISSING]"
        if not val:
            all_ready = False
        print(f"  {name:42s} ({kind:8s}) : {status_str}")

    print("-" * 70)
    if all_ready:
        print("ALL TESTFLIGHT CREDENTIALS CONFIGURED! Ready to trigger signed upload.")
    else:
        print("PREFLIGHT STATUS: Ready for credentials entry.")
        print("\nWhere to find these in Apple Developer & App Store Connect:")
        print("  1. Apple Team ID: https://developer.apple.com/account (top-right under your name)")
        print("  2. App Store Connect API Key & Issuer ID: https://appstoreconnect.apple.com/access/integrations/api")
        print("     - Generate an API Key with 'App Manager' or 'Developer' access.")
        print("     - Download the AuthKey_<KeyID>.p8 file (note: Apple only lets you download it once).")
    print("=" * 70)
    return all_ready


def configure_credentials(team_id: str, key_id: str, issuer_id: str, key_file: str, bundle_id: str = DEFAULT_BUNDLE_ID):
    p8_path = pathlib.Path(key_file)
    if not p8_path.exists():
        print(f"Error: Key file '{key_file}' does not exist.")
        return 1

    p8_bytes = p8_path.read_bytes()
    b64_key = base64.b64encode(p8_bytes).decode("ascii")

    print(f"Configuring environment '{ENVIRONMENT_NAME}' in GitHub...")
    # Ensure environment exists
    run_gh(["api", "-X", "PUT", f"repos/:owner/:repo/environments/{ENVIRONMENT_NAME}"])

    # Set variables
    for var_name, var_val in [
        ("APPLE_DEVELOPMENT_TEAM", team_id),
        ("PRODUCT_BUNDLE_IDENTIFIER", bundle_id),
        ("APP_STORE_CONNECT_API_KEY_ID", key_id),
        ("APP_STORE_CONNECT_API_ISSUER_ID", issuer_id),
    ]:
        code, out, err = run_gh(["variable", "set", var_name, "--body", var_val, "--env", ENVIRONMENT_NAME])
        if code == 0:
            print(f"  [OK] Set variable {var_name}")
        else:
            print(f"  [FAIL] Failed to set variable {var_name}: {err}")

    # Set secret
    code, out, err = run_gh(["secret", "set", "APP_STORE_CONNECT_API_PRIVATE_KEY_BASE64", "--body", b64_key, "--env", ENVIRONMENT_NAME])
    if code == 0:
        print(f"  [OK] Set secret APP_STORE_CONNECT_API_PRIVATE_KEY_BASE64")
    else:
        print(f"  [FAIL] Failed to set secret: {err}")

    print("\nConfiguration complete! Re-verifying status:")
    check_status()
    return 0


def main():
    parser = argparse.ArgumentParser(description="TestFlight Credentials Setup Helper")
    parser.add_argument("--status", action="store_true", help="Audit current TestFlight credentials status")
    parser.add_argument("--team-id", help="10-character Apple Development Team ID")
    parser.add_argument("--key-id", help="10-character App Store Connect API Key ID")
    parser.add_argument("--issuer-id", help="UUID App Store Connect API Issuer ID")
    parser.add_argument("--key-file", help="Path to AuthKey_*.p8 private key file")
    parser.add_argument("--bundle-id", default=DEFAULT_BUNDLE_ID, help=f"Bundle ID (default: {DEFAULT_BUNDLE_ID})")

    args = parser.parse_args()

    if args.team_id and args.key_id and args.issuer_id and args.key_file:
        return configure_credentials(
            team_id=args.team_id.strip(),
            key_id=args.key_id.strip(),
            issuer_id=args.issuer_id.strip(),
            key_file=args.key_file.strip(),
            bundle_id=args.bundle_id.strip()
        )

    check_status()
    return 0


if __name__ == "__main__":
    sys.exit(main())
