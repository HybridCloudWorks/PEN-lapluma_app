#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_dir/.." && pwd)"
archive_path="${1:-$repository_root/build/Aperture-Unsigned.xcarchive}"
project_path="$repository_root/apps/ios/ApertureApp.xcodeproj"
privacy_manifest="$repository_root/apps/ios/ApertureApp/PrivacyInfo.xcprivacy"
export_options="$repository_root/apps/ios/ExportOptions-InternalTestFlight.plist"
build_number_override="${APERTURE_BUILD_NUMBER_OVERRIDE:-}"
build_settings=()

if [[ -n "$build_number_override" ]]; then
    if [[ ! "$build_number_override" =~ ^[1-9][0-9]*$ ]]; then
        echo "APERTURE_BUILD_NUMBER_OVERRIDE must be a positive integer" >&2
        exit 1
    fi
    build_settings+=("CURRENT_PROJECT_VERSION=$build_number_override")
fi

if [[ ! -f "$privacy_manifest" ]]; then
    echo "Missing PrivacyInfo.xcprivacy" >&2
    exit 1
fi

if [[ ! -f "$export_options" ]]; then
    echo "Missing internal TestFlight export options" >&2
    exit 1
fi

plutil -lint "$privacy_manifest" "$export_options" >/dev/null

xcodebuild \
    -quiet \
    -project "$project_path" \
    -scheme ApertureApp \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$archive_path" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    ${build_settings[@]+"${build_settings[@]}"} \
    archive

app_path="$archive_path/Products/Applications/LaPluma.app"
bundled_manifest="$app_path/PrivacyInfo.xcprivacy"
app_info="$app_path/Info.plist"

if [[ ! -d "$app_path" ]]; then
    echo "Archive does not contain LaPluma.app" >&2
    exit 1
fi

if [[ ! -f "$bundled_manifest" ]]; then
    echo "Archive does not contain PrivacyInfo.xcprivacy" >&2
    exit 1
fi

bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_info")"
short_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_info")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_info")"
runtime_mode="$(/usr/libexec/PlistBuddy -c 'Print :ApertureRuntimeMode' "$app_info")"

if [[ "$bundle_identifier" != "app.aperture.mobile" ]]; then
    echo "Unexpected bundle identifier: $bundle_identifier" >&2
    exit 1
fi

if [[ ! "$short_version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    echo "Invalid CFBundleShortVersionString: $short_version" >&2
    exit 1
fi

if [[ ! "$build_number" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    echo "Invalid CFBundleVersion: $build_number" >&2
    exit 1
fi

if [[ "$runtime_mode" != "internal-demo" ]]; then
    echo "Release archive must remain internal-demo while StubAPIClient is compiled in" >&2
    exit 1
fi

echo "Validated unsigned archive: $archive_path"
echo "Bundle: $bundle_identifier  Version: $short_version ($build_number)  Runtime: $runtime_mode"
