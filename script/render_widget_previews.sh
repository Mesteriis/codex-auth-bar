#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project="$root_dir/CodexAuthBar.xcodeproj"
result_bundle="$root_dir/build/widget-previews.xcresult"
attachments_dir="$root_dir/build/widget-preview-attachments"
output_dir="$root_dir/docs/qa"

rm -rf "$result_bundle" "$attachments_dir"
mkdir -p "$output_dir"

xcodebuild test \
  -project "$project" \
  -scheme CodexAuthWidget \
  -destination "platform=macOS,arch=$(uname -m)" \
  -resultBundlePath "$result_bundle" \
  -only-testing:CodexAuthWidgetTests/CodexAuthWidgetTests/testRenderSmallPrecisionLedger \
  -only-testing:CodexAuthWidgetTests/CodexAuthWidgetTests/testRenderMediumPrecisionLedger \
  -only-testing:CodexAuthWidgetTests/CodexAuthWidgetTests/testRenderLargePrecisionLedger \
  CODE_SIGNING_ALLOWED=NO

xcrun xcresulttool export attachments \
  --path "$result_bundle" \
  --output-path "$attachments_dir"

for family in small medium large; do
  exported_file="$(awk -v family="$family" '
    /"exportedFileName"/ {
      file = $0
      sub(/^.*"exportedFileName" : "/, "", file)
      sub(/".*$/, "", file)
    }
    /"suggestedHumanReadableName"/ && $0 ~ ("widget-" family "-dark") {
      print file
      exit
    }
  ' "$attachments_dir/manifest.json")"
  source="$attachments_dir/$exported_file"
  if [[ -z "$exported_file" || ! -f "$source" ]]; then
    echo "missing widget-$family attachment PNG" >&2
    exit 1
  fi
  cp "$source" "$output_dir/widget-$family.png"
done
