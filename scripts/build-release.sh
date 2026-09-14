#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${LOCALPASTE_BUILD_OUTPUT:-$(mktemp -d "$HOME/Library/Caches/LocalPasteRelease.XXXXXX")}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
app_path="$output_dir/Clipmori.app"
if [[ -e "$app_path" ]]; then
    echo "Output already contains Clipmori.app; choose a fresh output directory." >&2
    exit 1
fi
revision="$(git -C "$repo_dir" rev-parse --short=12 HEAD)"
if [[ -n "$(git -C "$repo_dir" status --porcelain)" ]]; then revision="${revision}-dirty"; fi
build_number="${LOCALPASTE_BUILD_NUMBER:-$(git -C "$repo_dir" rev-list --count HEAD)}"
if [[ ! "$build_number" =~ ^[1-9][0-9]{0,3}$ ]]; then
    echo "LOCALPASTE_BUILD_NUMBER must be an integer from 1 to 9999." >&2
    exit 1
fi

xcodegen generate --spec "$repo_dir/project.yml" --project "$repo_dir"
if ! xcodebuild -project "$repo_dir/LocalPaste.xcodeproj" -scheme LocalPaste \
    -configuration Release -derivedDataPath "$output_dir/derived" \
    CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO ARCHS="arm64 x86_64" CURRENT_PROJECT_VERSION="$build_number" \
    LOCALPASTE_REVISION="$revision" build > "$output_dir/build.log" 2>&1; then
    tail -n 80 "$output_dir/build.log" >&2
    exit 1
fi

ditto --norsrc "$output_dir/derived/Build/Products/Release/Clipmori.app" "$app_path"
if [[ -n "${LOCALPASTE_SIGNING_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --identifier com.prince.LocalPaste \
        --sign "$LOCALPASTE_SIGNING_IDENTITY" "$app_path"
    codesign --verify --deep --strict "$app_path"
fi

python3 - "$repo_dir" "$output_dir" "$revision" <<'PY'
import hashlib, json, pathlib, plistlib, subprocess, sys
repo, output = map(pathlib.Path, sys.argv[1:3])
app = output / 'Clipmori.app'
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
sources = sorted(p for p in (repo / 'LocalPaste').rglob('*') if p.is_file()) + [repo / 'project.yml']
manifest = {str(p.relative_to(repo)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
report = {
    'product_name': info['CFBundleDisplayName'], 'bundle_identifier': info['CFBundleIdentifier'],
    'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
    'revision': sys.argv[3],
    'commit': subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip(),
    'binary_sha256': hashlib.sha256((app / 'Contents/MacOS/LocalPaste').read_bytes()).hexdigest(),
    'sources': manifest,
}
(output / 'build-info.json').write_text(json.dumps(report, indent=2) + '\n')
PY
ditto -c -k --keepParent "$app_path" "$output_dir/Clipmori.zip"
echo "Release ready: $app_path"
