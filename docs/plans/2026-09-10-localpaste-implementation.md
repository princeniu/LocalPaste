# LocalPaste Implementation Plan

Historical initial implementation plan. The original Debug/ad-hoc build commands below are not the current day-use installation path. Use the root README and `docs/runbooks/first-run.md` for Release builds and stable local signing; current acceptance status is in `docs/verification/STATUS.md`.

> For Hermes: use subagent-driven-development for the integrated implementation, then one bounded Blocker/High review. Feature-first user rule overrides test-first template: no new tests before user tries the app.

Goal: ship a real native local Mac clipboard app matching the approved design in docs/specs/2026-09-10-localpaste-design.md.
Architecture: SwiftData local history plus AppKit clipboard/panel integration and SwiftUI views. No third-party dependencies, no network feature, no Gateway changes.
Tech Stack: Swift, macOS 14+, Xcode 26.0, XcodeGen.

## 1. Build shell
Create project.yml, .gitignore, LocalPaste/AppDelegate.swift and main entry, Info.plist via XcodeGen. Menu-bar app, own bundle ID, no production service hooks. Generate with `xcodegen generate`; build using `xcodebuild -project LocalPaste.xcodeproj -scheme LocalPaste -configuration Debug -derivedDataPath build CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO build`. Preserve build log as evidence.

## 2. Persistence and capture
Create LocalPaste/ClipboardStore.swift with SwiftData models, encoded multiple pasteboard items/representations, externally stored Data, source/title/date/type and category UUID. Implement filtering, categorization, history cap, explicit errors. Create LocalPaste/ClipboardMonitor.swift: initial change count, pause, exclusions, transient/concealed skip, own-write suppression. No private history extraction; capture only new live events once launched.

## 3. Panel and paste
Create LocalPaste/PanelController.swift and PasteCoordinator.swift. Bottom floating panel on mouse screen, retain target app. Carbon global shortcut registration with collision errors and user-recordable alternative. Restore clipboard then reactivate original app and verify frontmost before CGEvent paste. Permission absence must show copied/manual paste result. Do not bypass permissions.

## 4. Views
Create LocalPaste/HistoryView.swift, PreviewView.swift, SettingsView.swift. Horizontal stable-ID cards with search, selection, keyboard navigation, preview, paste/plain text, create/rename/delete category, clear confirmation preserving favorites. Settings: history cap, pause, exclusions app picker, shortcut recording. Use restrained neutral native materials and cyan accent. Empty state is helpful and real; no fake seeded history.

## 5. Actual run
Generate after every new Swift source batch and build. Launch actual .app only in own scope. Exercise with clearly marked artificial clipboard samples, not user private contents. Observe menu/panel, capture, persistence, categories and cross-app paste where permission permits. Multi-monitor requires actual hardware; mark blocked if not available. No test harness used instead of runtime implementation.

## 6. Delivery
One combined spec/correctness review limited to Blocker/High in this app only, fix concrete findings without recursive hardening. Write docs/runbooks/first-run.md and docs/verification/first-run.md recording exact commands, evidence paths and blockers. Parent verifies actual artifact, then commits own files. Deliver .app path and remaining permission instructions; stop for user experience confirmation.
