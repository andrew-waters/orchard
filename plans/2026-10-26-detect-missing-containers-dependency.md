---
type: plan
status: in-progress
summary: "Notice when Apple container is not installed, say so on a screen of its own instead of 'not running', and offer to install the pinned signed pkg behind one admin prompt, then start the system with the default kernel. Declining or a failed install leaves manual instructions on screen."
issues: [andrew-waters/orchard#145]
touches: [andrew-waters/orchard]
owner: andrew-waters
agreed_by: [andrew-waters]
agreed_at: 2026-10-26
---

# Detect a missing container install and offer to install it

Orchard drives Apple container. Without it installed there is nothing to talk to, but today Orchard cannot tell "not installed" from "not running".

## What happens today

- `SettingsStore.defaultBinaryPath` stats four candidate paths and falls back to `/usr/local/bin/container` whether or not it exists.
- `SystemService.checkSystemStatus` only pings the daemon over XPC. With nothing installed the ping fails, the status is `.stopped`, and the window shows `NotRunningView`: "Container is not currently running" with a Start button.
- Pressing Start runs the missing binary, `NSFileNoSuchFileError` is caught, and an alert says "Make sure Apple Container is installed" with a link to the upstream README. The menu-bar panel offers the same Start button.

So the user is told to start something they do not have, and only finds out what is wrong after pressing the button.

## Decisions

- **Detection.** Installed means the resolved `container` binary (custom path, else the first candidate path) exists and is executable. Checked before the ping, so a missing install never reaches XPC. No version check here: a version mismatch is already handled by the ping (`.unsupportedVersion`).
- **Install source.** The signed pkg from the apple/container release that matches `supportedContainerVersion` (`container-1.6.0-installer-signed.pkg`), downloaded directly from the release URL. Pinned rather than latest so the installed version is the one this build of Orchard speaks.
- **Trust.** Before anything runs as root, `pkgutil --check-signature` must report a signature through a chain Apple issued, with a leaf of "Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)". The team ID is what is pinned. A pkg that fails the check is deleted and reported, never installed.
- **Privileges.** `installer -pkg <path> -target /` through `CommandRunner.runWithSudo`: one macOS administrator prompt, the same mechanism as DNS domains and the compose plugin. Dismissing the prompt is not a failure: the sheet returns to the not-installed screen.
- **Consent.** Nothing downloads until the user presses Install. The issue's `--yes` and non-interactive concerns do not apply: Orchard is a GUI app with no headless mode.
- **After install.** Clear the cached binary path, then run `container system start --enable-kernel-install` so a fresh machine gets the default kernel without the CLI's stdin prompt (which Orchard cannot answer), and poll to `.running` as `startSystem` already does. If the start fails, the install still stands: the user lands on the existing Start screen with the error in Diagnostics.
- **"Non-zero exit".** The app does not quit. Declining or a failed install keeps the user on the not-installed screen, which always shows the manual route (upstream install link and the `installer` command), so there is a way forward without Orchard's help.
- **Platforms.** Apple silicon on macOS 26, which is what container 1.6.0 supports and what Orchard already requires.

## Design

**Status.** `SystemStatus` gains `.notInstalled` (grey, "not installed"). `checkSystemStatus` returns it, without pinging, when the binary is missing. Detection is injected into `SystemService` as a closure (defaulting to `SettingsStore.isContainerInstalled`) so tests do not depend on what the test machine has installed.

**Service.** `ContainerInstallService`, shaped like `ComposePluginService`: a `State` of `idle`, `working(Step)` and `failed(String)`, with steps Downloading, Verifying, Installing (notes "Authorisation required") and Starting. Holds its task so the download and check can be cancelled (not `installer` once it runs as root); cleans up its scratch directory on every path; user-facing failure messages only, never raw URL or osascript errors. The download is injected for tests. Wired in `AppServices` with the shared runner and an `onInstalled` hook to `SystemService.startSystem(installKernel: true)`.

**Screens.**
- `NotInstalledView` (Views/States): what container is and why Orchard needs it, an **Install container 1.6.0** button, **Check Again**, and an **Install it yourself** disclosure with the package link, the commands and the upstream instructions. Routed from `Content.swift` like the other states.
- The install runs inline on that screen rather than in a sheet: the step list replaces the buttons and is ticked off as it goes, and on failure the message shows with **Try Again** and the manual disclosure opens. Inline because the screen itself is replaced once the system starts, which would tear a sheet down mid-step.
- Menu-bar panel: a "Container is not installed" card with an **Install** button that brings the window forward.

**Start path.** `startSystem` gains `installKernel: Bool = false` to add `--enable-kernel-install`. Its `NSFileNoSuchFileError` alert goes, since re-deriving status now lands on `.notInstalled`.

## Tasks

- [x] `SettingsStore.isContainerInstalled`; `SystemStatus.notInstalled`; injected detection in `SystemService.checkSystemStatus`
- [x] `startSystem(installKernel:)`; drop the no-such-file alert in favour of the new state
- [x] `ContainerInstallService`: download, signature check, admin install, start; cancel and cleanup
- [x] `NotInstalledView` with the install inline, routing in `Content.swift`, menu-bar card
- [x] Unit tests: detection gates the ping; install happy path (runner sees `pkgutil`, `installer` via sudo, `system start --enable-kernel-install`); bad signature never reaches `installer`; dismissed prompt returns to idle; a failed installer is reported; no network is reported and cleans up
- [x] Build; OrchardTests pass (479 tests)
- [ ] Smoke test: with the binary path pointed somewhere empty, the window and menu bar show the not-installed state; a real install on a machine without container (or a VM) ends on the running screen
- [x] README requirements, CHANGELOG

## Out of scope

- Upgrading an existing install of the wrong version (the version screens keep their upgrade link).
- Homebrew installs, and choosing a version other than the pinned one.
- Passing `--enable-kernel-install` on ordinary Start presses.
