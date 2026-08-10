#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
metadata_root="${APERTURE_STORE_METADATA_ROOT:-$repo_root/apps/ios/AppStore/metadata}"
screenshot_root="${APERTURE_STORE_SCREENSHOT_ROOT:-$repo_root/build/store-screenshots/output}"
require_screenshots="${REQUIRE_SCREENSHOTS:-0}"
require_store_review_ready="${REQUIRE_STORE_REVIEW_READY:-0}"
review_root="$repo_root/apps/ios/AppStore/review"

fail() {
  echo "error: $*" >&2
  exit 1
}

# Checked before first use: character counts and the manifest check both shell
# out to ruby, and "ruby: command not found" inside a command substitution is a
# far worse diagnostic than this one.
command -v ruby >/dev/null 2>&1 || fail "ruby is required for metadata validation"

character_count() {
  ruby -e 'print File.read(ARGV.fetch(0), encoding: "UTF-8").strip.length' "$1"
}

validate_text_field() {
  local path="$1"
  local maximum="$2"
  [[ -s "$path" ]] || fail "missing or empty metadata file: ${path#$repo_root/}"
  local count
  count="$(character_count "$path")"
  (( count <= maximum )) || fail "${path#$repo_root/} has $count characters; maximum is $maximum"
  if grep -Eiq '(^|[^[:alpha:]])(tbd|todo|placeholder)([^[:alpha:]]|$)' "$path"; then
    fail "placeholder text remains in ${path#$repo_root/}"
  fi
}

for locale in en-US es-MX; do
  locale_root="$metadata_root/$locale"
  validate_text_field "$locale_root/name.txt" 30
  validate_text_field "$locale_root/subtitle.txt" 30
  validate_text_field "$locale_root/keywords.txt" 100
  validate_text_field "$locale_root/promotional_text.txt" 170
  validate_text_field "$locale_root/description.txt" 4000
  validate_text_field "$locale_root/release_notes.txt" 4000
done
validate_text_field "$repo_root/apps/ios/AppStore/testflight/what_to_test.en-US.txt" 4000
validate_text_field "$repo_root/apps/ios/AppStore/testflight/what_to_test.es-MX.txt" 4000
validate_text_field "$review_root/reviewer-notes.en-US.txt" 4000

for review_file in \
  submission-manifest.json \
  age-rating.md \
  review-account.md \
  app-privacy-answers.md \
  accessibility-support.md \
  localization-approval.md \
  content-rights.md \
  submission-checklist.md; do
  [[ -s "$review_root/$review_file" ]] || fail "missing review artifact: apps/ios/AppStore/review/$review_file"
done

# Debug and Release each declare MARKETING_VERSION. Reading only the first would
# let a Release-only drift ship while the manifest check compared the Debug value,
# so require every declaration to agree before comparing against the manifest.
project_versions="$(awk -F'= ' '/MARKETING_VERSION =/ { gsub(/;/, "", $2); gsub(/[ \t]/, "", $2); print $2 }' \
  "$repo_root/apps/ios/ApertureApp.xcodeproj/project.pbxproj" | sort -u)"
[[ -n "$project_versions" ]] || fail "no MARKETING_VERSION found in project.pbxproj"
if [[ "$(printf '%s\n' "$project_versions" | wc -l)" -ne 1 ]]; then
  fail "MARKETING_VERSION differs between build configurations: $(printf '%s ' $project_versions)"
fi
project_version="$project_versions"
ruby -rjson -e '
  manifest = JSON.parse(File.read(ARGV.fetch(0), encoding: "UTF-8"))
  expected_version = ARGV.fetch(1)
  abort "manifest releaseLabel must be Alpha 0.2" unless manifest["releaseLabel"] == "Alpha 0.2"
  abort "manifest marketingVersion does not match the project" unless manifest["marketingVersion"] == expected_version
  abort "Alpha distribution must remain internal-testflight" unless manifest["distribution"] == "internal-testflight"
  abort "Alpha runtime must remain internal-demo" unless manifest["runtimeMode"] == "internal-demo"
  abort "Alpha must not claim public submission eligibility" unless manifest["publicSubmissionEligible"] == false
' "$review_root/submission-manifest.json" "$project_version" || fail "submission manifest validation failed"

if [[ "$require_store_review_ready" == "1" ]]; then
  fail "Alpha 0.2 is intentionally non-deploying and internal-only; public store readiness requires a production manifest"
fi

validate_screenshot_family() {
  local family="$1"
  local locale="$2"
  local directory="$screenshot_root/$locale/$family"
  local count=0

  if [[ -d "$directory" ]]; then
    while IFS= read -r image_path; do
      [[ -n "$image_path" ]] || continue
      count=$((count + 1))
      local properties width height alpha dimensions
      properties="$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$image_path")"
      width="$(awk '/pixelWidth:/ { print $2 }' <<<"$properties")"
      height="$(awk '/pixelHeight:/ { print $2 }' <<<"$properties")"
      alpha="$(awk '/hasAlpha:/ { print $2 }' <<<"$properties")"
      dimensions="${width}x${height}"

      case "$family:$dimensions" in
        iphone-6.9:1260x2736|iphone-6.9:1290x2796|iphone-6.9:1320x2868) ;;
        ipad-13:2048x2732|ipad-13:2064x2752) ;;
        *) fail "unsupported $family screenshot dimensions $dimensions: $image_path" ;;
      esac
      [[ "$alpha" != "yes" ]] || fail "screenshot contains an alpha channel: $image_path"
    done < <(find "$directory" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) | sort)
  fi

  (( count <= 10 )) || fail "$locale/$family has $count screenshots; App Store maximum is 10"
  if [[ "$require_screenshots" == "1" ]]; then
    (( count >= 1 )) || fail "$locale/$family requires at least one screenshot"
  fi
  if (( count > 0 )); then
    echo "Validated $count screenshot(s) for $locale/$family"
  fi
}

if [[ "$require_screenshots" == "1" || -d "$screenshot_root" ]]; then
  command -v sips >/dev/null || fail "sips is required for screenshot validation"
  for locale in en-US es-MX; do
    validate_screenshot_family iphone-6.9 "$locale"
    validate_screenshot_family ipad-13 "$locale"
  done
fi

echo "App Store metadata validation passed."
