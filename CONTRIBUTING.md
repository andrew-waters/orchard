# Contributing to Orchard

Thanks for your interest in improving Orchard! Contributions of all kinds are
welcome — bug reports, feature ideas, documentation, and code.

## Ways to contribute

- **Report a bug** — open a [bug report](https://github.com/andrew-waters/orchard/issues/new?template=bug_report.md).
- **Request a feature** — open a [feature request](https://github.com/andrew-waters/orchard/issues/new?template=feature_request.md).
- **Improve the docs** — even small README/typo fixes are appreciated.
- **Submit code** — see below.

## Requirements

- macOS 26 (Tahoe)
- Xcode 26 / Swift 6.2
- [Apple Container](https://github.com/apple/container) installed

## Getting started

```bash
git clone https://github.com/andrew-waters/orchard.git
cd orchard
open Orchard.xcodeproj
```

Xcode will resolve the `apple/container` Swift Package dependency on first build.
Build and run the `Orchard` scheme, and run the tests with **Product ▸ Test**
(`⌘U`), or from the command line:

```bash
xcodebuild test -project Orchard.xcodeproj -scheme Orchard -destination 'platform=macOS'
```

## Pull requests

1. Fork the repo and create a branch from `main` (e.g. `fix/logs-scroll` or
   `feat/volume-picker`).
2. Keep changes focused — one logical change per PR is easiest to review.
3. Match the existing code style; keep views small and composable.
4. Make sure the project builds and the tests pass.
5. Add a note to [`CHANGELOG.md`](CHANGELOG.md) under an `Added` / `Changed` /
   `Fixed` heading describing your change.
6. Open the PR with a clear description of **what** changed and **why**. Include
   screenshots or a short clip for any UI change.

## Reporting security issues

Please don't file public issues for security vulnerabilities — see
[`SECURITY.md`](SECURITY.md) for how to report them privately.

## Code of conduct

Be respectful and constructive. Harassment or abuse of any kind isn't welcome
in this project's spaces.
