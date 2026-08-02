#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
runtime="${APERTURE_STORE_RUNTIME:-com.apple.CoreSimulator.SimRuntime.iOS-26-5}"
minimum_free_gb="${APERTURE_STORE_SCREENSHOT_MIN_FREE_GB:-6}"
capture_kind="${APERTURE_SCREENSHOT_KIND:-internal-review}"
if [[ -n "${APERTURE_STORE_SCREENSHOT_ROOT:-}" ]]; then
  output_root="$APERTURE_STORE_SCREENSHOT_ROOT"
elif [[ "$capture_kind" == "store" ]]; then
  output_root="$repo_root/build/store-screenshots/output"
else
  output_root="$repo_root/build/store-screenshots/internal-review"
fi
derived_data="$repo_root/build/store-screenshots/DerivedData"
app_path="${APERTURE_SCREENSHOT_APP_PATH:-}"
active_device=""

fail() {
  echo "error: $*" >&2
  exit 1
}

cleanup() {
  if [[ -n "$active_device" ]]; then
    DEVELOPER_DIR="$developer_dir" xcrun simctl shutdown "$active_device" >/dev/null 2>&1 || true
    DEVELOPER_DIR="$developer_dir" xcrun simctl delete "$active_device" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

[[ "$minimum_free_gb" =~ ^[0-9]+$ ]] || fail "APERTURE_STORE_SCREENSHOT_MIN_FREE_GB must be an integer"
free_kb="$(df -Pk "$repo_root" | awk 'NR == 2 { print $4 }')"
required_kb=$((minimum_free_gb * 1024 * 1024))
(( free_kb >= required_kb )) || fail "screenshot capture requires at least ${minimum_free_gb} GB free; only $((free_kb / 1024)) MB is available"

[[ -d "$developer_dir" ]] || fail "Xcode developer directory not found: $developer_dir"
runtime_list="$(DEVELOPER_DIR="$developer_dir" xcrun simctl list runtimes)"
grep -Fq "$runtime" <<<"$runtime_list" || fail "requested simulator runtime is not installed: $runtime"

case "$capture_kind" in
  internal-review)
    [[ -z "$app_path" ]] || fail "APERTURE_SCREENSHOT_APP_PATH is only accepted with APERTURE_SCREENSHOT_KIND=store"
    echo "Building an internal-review screenshot app. These images are not App Store upload assets."
    DEVELOPER_DIR="$developer_dir" xcodebuild \
      -project "$repo_root/apps/ios/ApertureApp.xcodeproj" \
      -scheme ApertureApp \
      -configuration Debug \
      -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath "$derived_data" \
      CODE_SIGNING_ALLOWED=NO \
      build
    app_path="$derived_data/Build/Products/Debug-iphonesimulator/ApertureApp.app"
    ;;
  store)
    [[ "${APERTURE_SCREENSHOT_SOURCE:-}" == "production-reviewed" ]] || \
      fail "store capture requires APERTURE_SCREENSHOT_SOURCE=production-reviewed"
    [[ -n "$app_path" && -d "$app_path" ]] || \
      fail "store capture requires APERTURE_SCREENSHOT_APP_PATH pointing to an approved simulator .app"
    ;;
  *) fail "APERTURE_SCREENSHOT_KIND must be internal-review or store" ;;
esac

[[ -d "$app_path" ]] || fail "simulator app not found: $app_path"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Info.plist" 2>/dev/null || true)"
[[ -n "$bundle_id" ]] || fail "could not read CFBundleIdentifier from $app_path"
if [[ "$capture_kind" == "store" ]]; then
  runtime_mode="$(/usr/libexec/PlistBuddy -c 'Print :ApertureRuntimeMode' "$app_path/Info.plist" 2>/dev/null || true)"
  [[ "$runtime_mode" != "internal-demo" && -n "$runtime_mode" ]] || \
    fail "store screenshots cannot use an internal-demo or unspecified runtime mode"
fi

capture_family() {
  local family="$1"
  local device_type="$2"
  local device_name="Aperture Store Capture $family $$"

  active_device="$(DEVELOPER_DIR="$developer_dir" xcrun simctl create "$device_name" "$device_type" "$runtime")"
  DEVELOPER_DIR="$developer_dir" xcrun simctl boot "$active_device"
  DEVELOPER_DIR="$developer_dir" xcrun simctl bootstatus "$active_device" -b
  DEVELOPER_DIR="$developer_dir" xcrun simctl status_bar "$active_device" override \
    --time 9:41 --operatorName '' --wifiBars 3 --cellularBars 4 --batteryState charged --batteryLevel 100
  DEVELOPER_DIR="$developer_dir" xcrun simctl install "$active_device" "$app_path"

  for locale_spec in 'en-US|en|en_US' 'es-MX|es|es_MX'; do
    IFS='|' read -r locale language apple_locale <<<"$locale_spec"
    for state_spec in '01-home|home' '02-capture|capture' '03-missing|missing'; do
      IFS='|' read -r filename tab <<<"$state_spec"
      destination="$output_root/$locale/$family/$filename.png"
      mkdir -p "$(dirname "$destination")"
      DEVELOPER_DIR="$developer_dir" xcrun simctl terminate "$active_device" "$bundle_id" >/dev/null 2>&1 || true
      DEVELOPER_DIR="$developer_dir" xcrun simctl launch "$active_device" "$bundle_id" \
        --ui-testing-reset \
        --ui-testing-authenticated \
        "--ui-testing-start-tab=$tab" \
        -AppleLanguages "($language)" \
        -AppleLocale "$apple_locale" >/dev/null
      sleep 2
      DEVELOPER_DIR="$developer_dir" xcrun simctl io "$active_device" screenshot --type=png "$destination"
    done
  done

  DEVELOPER_DIR="$developer_dir" xcrun simctl shutdown "$active_device"
  DEVELOPER_DIR="$developer_dir" xcrun simctl delete "$active_device"
  active_device=""
}

capture_family iphone-6.9 com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max
capture_family ipad-13 com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB

REQUIRE_SCREENSHOTS=1 \
  APERTURE_STORE_SCREENSHOT_ROOT="$output_root" \
  "$repo_root/tools/validate-ios-store-assets.sh"

echo "Captured $capture_kind screenshots in $output_root. Human visual and privacy approval is still required."
