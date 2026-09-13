<p align="center">
  <img src="LocalPaste/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="112" alt="Clipmori icon">
</p>
<h1 align="center">拾贴 · Clipmori</h1>
<p align="center"><strong>Copy now. Find it when you need it.</strong><br>A native macOS clipboard history app with a horizontal card shelf.</p>
<p align="center">
  <a href="https://github.com/princeniu/LocalPaste/actions/workflows/ci.yml"><img src="https://github.com/princeniu/LocalPaste/actions/workflows/ci.yml/badge.svg" alt="macOS checks"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="macOS 14 or later">
  <img src="https://img.shields.io/badge/Swift-SwiftUI%20%2B%20AppKit-F05138" alt="Swift, SwiftUI and AppKit">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT license"></a>
</p>
<p align="center"><a href="README.md">简体中文</a> · <a href="README.en.md">English</a></p>

[Features](#features) · [Build](#build) · [Usage](#usage) · [Privacy](#privacy) · [FAQ](#faq) · [Contributing](#contributing)

Clipmori keeps copied text, images and file references in a horizontal card shelf at the bottom of your Mac screen. Search your history, preview an item and paste it back into the app you were using.

No account required. History stays on your Mac. **Version 1.2.0 is an early release**, with a primarily Simplified Chinese interface. Source code is available; notarized downloads, Homebrew distribution and automatic updates are not available yet.

## Features

| Workflow | What Clipmori offers |
| --- | --- |
| Keep copied content | Text, links, images, rich text and Finder file references |
| Browse naturally | Horizontal cards with vertical mouse-wheel support |
| Find and preview | Search content or source apps; press Space to preview |
| Paste again | Original-format and plain-text paste, with keyboard and mouse support |
| Stay organized | Favorites, categories and a configurable ordinary-history limit |
| Control capture | Pause recording, exclude apps and skip concealed/transient content |
| Back up history | Export history, favorites and categories; preview a merge before importing |
| Feel at home | Native SwiftUI/AppKit UI, menu bar, custom shortcut and launch at login |

## Build

Requires **macOS 14+, full Xcode and XcodeGen**. Local builds have been verified with Xcode 26; CI runs regressions and Release builds on macOS 15.

With Homebrew already installed:

```sh
brew install xcodegen
git clone https://github.com/princeniu/LocalPaste.git
cd LocalPaste
scripts/build-release.sh
```

The script prints the path to `Clipmori.app`, alongside a ZIP and build manifest. Builds are unsigned by default. For a daily-use build, use your own stable signing identity:

```sh
LOCALPASTE_SIGNING_IDENTITY="Your valid signing identity" scripts/build-release.sh
```

Move the built app into Applications and open it. Clipmori lives in the menu bar, not the Dock. Allow it under **System Settings → Privacy & Security → Accessibility** for automatic paste. Without permission, restore an item and press `⌘V` manually in the target app.

Signing does not imply notarization. See the [first-run guide (Chinese)](docs/runbooks/first-run.md) for signing and upgrade details. The repository and bundle identifier retain the original LocalPaste name for data compatibility.

## Usage

1. Copy something as usual.
2. Press `⌘⇧V` or open history from the menu bar.
3. Search or scroll to an item and click it to attempt paste into the previous app.

| Action | Control |
| --- | --- |
| Open history | `⌘⇧V`, configurable in settings |
| Select a card | `←` / `→` |
| Browse horizontally | Vertical mouse wheel or horizontal trackpad gesture |
| Paste selection | `Return` or click |
| Preview | `Space` |
| Close the panel | `Esc` |
| More actions | Right-click a card |

Arrow keys and Space retain normal text-editing behavior while editing search. Reopen the usage guide from Settings → About.

### Backup and restore

Open Settings → Data to export a `.clipmori` file or import a backup. The preview shows new records, favorites and categories. Same-name categories merge; existing records keep their local version. Any required increase to the history limit is shown before importing.

Backups exclude preferences, system permissions and original files. Maximum backup size: **256 MB**. Maximum merged non-favorite history: **5,000 items**.

## Privacy

- The app has no accounts, cloud sync, telemetry or networking features.
- History and backup files are **not encrypted**. Store backups carefully and pause recording before copying sensitive content.
- App exclusions and confidential-type filtering are best-effort protections; macOS source identification cannot guarantee that every sensitive copy is excluded.
- File history stores references only. Moving or deleting the original file can make a record unusable.
- History is stored under `~/Library/Application Support/com.prince.LocalPaste/` by default.

## FAQ

**Why does clicking an item not paste automatically?** Check Accessibility permission for the installed build. Without it, the item is still restored to the clipboard; switch to your target app and press `⌘V`.

**Will paused content be captured later?** No. Resuming starts with new copy operations.

**Does a backup transfer my files to another Mac?** No. File entries retain their original path references; transfer the files separately.

**Is this a finished public distribution?** This is an early daily-use project. Isolated regressions and selected real-app workflows have been verified, but notarized packaging, automatic updates and all hardware scenarios have not. See [verification status (Chinese)](docs/verification/STATUS.md).

See the [distribution guide (Chinese)](docs/runbooks/distribution.md) for DMG packaging and notarization.

## Contributing

[Issues](https://github.com/princeniu/LocalPaste/issues) and pull requests are welcome. Include your macOS version, app version, steps to reproduce and expected behavior. Never attach real clipboard content, backups, databases or credentials.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development and checks, and the [roadmap (Chinese)](docs/plans/next-phase.md) for priorities.

## License

[MIT License](LICENSE) · Copyright © 2026 princeniu
