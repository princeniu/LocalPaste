# Contributing to Clipmori

欢迎使用中文或英文提交 Issue 和 Pull Request。Chinese and English contributions are welcome.

## Report a problem

Include the macOS version, Clipmori version/build, reproducible steps, expected behavior and actual behavior. Use synthetic sample content. Remove private text from screenshots; do not attach clipboard databases, backups, signing material or access tokens.

For a feature request, describe the workflow and the problem it solves. Discuss large changes in an issue before implementation.

## Develop

Requires macOS 14+, full Xcode and XcodeGen. `project.yml` is the source of truth; generated Xcode projects are ignored.

```sh
xcodegen generate
open LocalPaste.xcodeproj
```

The source directory and bundle ID retain LocalPaste for compatibility. Normal app launches can access your daily history and general clipboard; use the isolated regression harness for synthetic testing. Do not run multiple builds with the same bundle ID at once.

## Validate a change

For product code changes, run the existing checks once after the final edit:

```sh
scripts/run-regressions.sh
scripts/build-release.sh
```

The regression harness uses temporary stores and named pasteboards. See [Tests/README.md](Tests/README.md) for GUI fixtures and boundaries. Documentation-only changes need link and diff checks, not extra local app tests. CI runs the required regressions and build on each PR.

Keep PRs focused. Explain the user-visible result and relevant verification; distinguish automated checks from actual UI tests. Never claim a signed or notarized release based on an unsigned CI artifact.

## License

By submitting a contribution, you agree that it may be distributed under this repository's [MIT License](LICENSE).
