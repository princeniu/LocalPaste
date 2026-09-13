#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 /path/Clipmori.app /new/output-directory" >&2
    exit 1
fi
app_path="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
output_dir="$2"
: "${LOCALPASTE_SIGNING_IDENTITY:?Set your Developer ID Application signing identity}"
[[ -d "$app_path" && ! -e "$output_dir" ]] || { echo "App must exist and output directory must be new." >&2; exit 1; }
codesign --verify --deep --strict "$app_path"
signature="$(LC_ALL=C codesign -d --verbose=4 "$app_path" 2>&1)"
if [[ "$signature" != *"Authority=Developer ID Application:"* || "$signature" != *"Timestamp="* || "$signature" != *"runtime"* ]]; then
    echo "App requires Developer ID signing, a secure timestamp and hardened runtime." >&2
    exit 1
fi
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_path/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app_path/Contents/Info.plist")
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$build" =~ ^[0-9]+$ ]] || { echo "Invalid version/build." >&2; exit 1; }
lipo -verify_arch arm64 x86_64 "$app_path/Contents/MacOS/LocalPaste"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
stage="$(mktemp -d "$output_dir/.dmg-stage.XXXXXX")"
trap 'rm -rf "$stage"' EXIT

ditto --norsrc "$app_path" "$stage/Clipmori.app"
ln -s /Applications "$stage/Applications"
cat > "$stage/安装说明 - Read Me.txt" <<'TEXT'
拾贴 · Clipmori

将 Clipmori.app 拖入 Applications，然后从“应用程序”打开。
拾贴常驻菜单栏，不显示 Dock 图标。默认按 ⌘⇧V 打开历史。
自动粘贴需要在“系统设置 → 隐私与安全性 → 辅助功能”中授权。

已有 LocalPaste 用户：先从“设置 → 数据”导出备份，然后退出旧版。
不要同时运行新旧版本。保留原安装位置升级可避免影响已有系统授权；
如改用 Clipmori.app，请重新确认辅助功能权限与登录启动设置。
历史和备份未加密；文件类记录仅保存引用，不包含原文件。

Drag Clipmori.app into Applications, then open it from Applications.
Clipmori lives in the menu bar, not the Dock. Press ⌘⇧V to open history.
Allow Accessibility access in System Settings for automatic paste.

Existing LocalPaste users: export a backup from Settings → Data and quit
before upgrading. Do not run both versions at once. Keeping your existing
installation path helps preserve system integration. If you change to
Clipmori.app, check Accessibility and launch-at-login settings again.
History and backups are not encrypted. File records contain references only.

macOS 14+ · Apple Silicon & Intel
https://github.com/princeniu/LocalPaste
TEXT
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cp "$repo_dir/LICENSE" "$stage/LICENSE.txt"
dmg="$output_dir/Clipmori-$version-$build-universal.dmg"
hdiutil create -volname "Clipmori $version" -srcfolder "$stage" -format UDZO -ov "$dmg"
codesign --force --timestamp --sign "$LOCALPASTE_SIGNING_IDENTITY" --identifier com.prince.LocalPaste.dmg "$dmg"
codesign --verify --strict "$dmg"
hdiutil verify "$dmg"
(cd "$output_dir" && shasum -a 256 "$(basename "$dmg")" > SHA256SUMS)
echo "Signed DMG ready (not yet notarized): $dmg"
