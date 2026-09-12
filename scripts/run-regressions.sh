#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${LOCALPASTE_TEST_OUTPUT:-$(mktemp -d /tmp/LocalPasteRegression.XXXXXX)}"
mkdir -p "$output_dir"
sdk_dir="$(xcrun --sdk macosx --show-sdk-path)"
sources=()
for source in "$repo_dir"/LocalPaste/*.swift; do
    [[ "$source" == */LocalPasteApp.swift ]] || sources+=("$source")
done
xcrun swiftc -O -module-name LocalPaste -parse-as-library \
    "$repo_dir/Tests/LegacyModels.swift" "$repo_dir/Tests/LegacyFixtureMain.swift" -o "$output_dir/legacy-fixture"
fixture_dir="$output_dir/legacy-fixture-$(uuidgen)"
"$output_dir/legacy-fixture" "$fixture_dir"
xcrun swiftc -O -module-name LocalPaste -parse-as-library -I "$sdk_dir/usr/include/libxml2" \
    "${sources[@]}" "$repo_dir/Tests/BackupRegressions.swift" "$repo_dir/Tests/RegressionMain.swift" -o "$output_dir/regressions"
"$output_dir/regressions" "$fixture_dir"
