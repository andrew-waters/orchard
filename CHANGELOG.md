# Changelog

All notable changes to Orchard are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.1.2] - 2026-07-07

### Added
- **Container machines**: create, configure, run and monitor Apple container machines (persistent Linux VMs) directly in Orchard, over the native XPC API rather than shelling out to the CLI. A new **Machines** section in the sidebar lists your machines with state, IP address and a default badge, and the detail view shows the full configuration plus live CPU, memory, network and disk usage.
- Create machines from an image with configurable CPUs, memory (defaulting to about half your host RAM), home-directory mount mode (read/write, read-only, or none), nested virtualization, and an optional custom kernel.
- Machine lifecycle controls - start, stop, set-default, and delete - each with clear in-progress feedback.
- Edit a machine's configuration with a one-click stop, apply and restart, since Apple's runtime only applies CPU/memory/home-mount/kernel changes on the next boot.
- Machine output and boot logs stream in the same multi-pane log viewer as containers, and running machines appear in a **Machine Utilisation** table on the Dashboard.
- Init-system guardrails for the most common machine pitfall: a warning before creating from an image that has no init system, and a clear "the image has no init system" explanation when a machine boots and immediately stops because it lacks `/sbin/init`.

### Changed
- Reorganised the sidebar into **Compute** (Containers, Machines), **Resources** (Images, Mounts) and **Networking** (DNS, Networks), with Machines a first-class peer of Containers.

### Fixed
- Container machines' backing containers no longer appear as unexplained entries in the container list - they're now filtered out, matching the `container` CLI.

## [2.1.1] - 2026-07-07

### Changed
- Updated for Apple's `container` 1.1.0. Orchard now builds against the 1.1.0 client libraries (previously 0.12.3), which had many breaking API changes across the 1.0 release; container 1.0.0 or later is now required.

### Fixed
- Stop, force-stop, and remove container actions work again on container 1.0.0 and later. Orchard was still linking the pre-1.0 client, so these commands silently failed against a 1.x daemon and the container never stopped ([#54](https://github.com/andrew-waters/orchard/issues/54)).
- The System pane in Settings no longer stays stuck on "Loading…". container 1.0 changed `system property list --format=json` from a flat array to a nested object keyed by category, which the parser didn't recognise, so every daemon property read as missing.

## [1.12.7] - 2026-07-05

### Added
- App preferences now live in a native Settings window (⌘,), split into a **General** pane (terminal application, container-binary path, default DNS domain, and software updates) and a **System** pane showing the read-only `container` daemon properties (Rosetta, image builder/init, kernel, registry).

### Changed
- Configuration moved out of the sidebar into the Settings window (⌘,); the sidebar no longer has a Configuration tab.

### Fixed
- Daemon system properties no longer stay stuck on "Loading…" and the default DNS domain shows its current value again - `container system property list` now returns a JSON array, which the parser didn't recognise, so it read no values at all.
- The sidebar no longer stays greyed-out after you open and dismiss a right-click menu on a container.

## [1.12.6] - 2026-07-05

### Added
- Live resource charts for every container - CPU, memory, network, and disk over time - on the container Overview, plus a system-wide dashboard in the Dashboard view that sums usage across all containers. Charts have selectable time windows (5m / 15m / 1h / 24h) and hover tooltips, and the container list gains a per-row CPU sparkline.
- Real CPU usage percentage (previously a placeholder that always read 0%). Stats are sampled continuously in the background and the history is saved between launches, so the longer time windows have data to show. Sampling pauses while the app is hidden to save resources.
- A redesigned menu-bar panel: CPU and memory usage rings across all running containers, a per-container list with start/stop controls, and hover-to-reveal history panels (per container, and system-wide) showing the last hour of CPU and memory.

### Changed
- Redesigned the container detail view into a single scrolling page (no more Overview/Environment/Mounts/Logs tabs): the resource metrics show as CPU, Memory, Network, and Disk panels pairing current values with their graph (network/disk graphs plot inbound above the axis and outbound below), and the remaining configuration sits in boxed sections below. Environment values are hidden until you click Show, and the image reference now appears under the container name in the header. Logs and Edit Configuration moved into the header, and the Logs button opens on the container you're viewing.
- Reworked the Stats tab into a **Dashboard** - now the default view when the app opens - with disk-usage headline tiles, per-metric panels (CPU / Memory / Network / Disk) each pairing current values with a graph, and per-metric sparklines in the container table.
- Copy controls across the app now read "Copy" and confirm with "Copied" instead of an icon.
- Ongoing performance and maintainability improvements to the app's internals - views now refresh only when the data they display actually changes.
- Refactored the internals: the monolithic container service was split into focused per-domain services with each view observing only what it needs, the Run and Edit container forms now share one implementation, and a UI smoke-test harness was added. No user-facing behaviour change.

### Fixed
- Network subnet validation now rejects out-of-range addresses (e.g. `999.999.999.999/24`); each octet must be 0–255.

## [1.12.5] - 2026-07-04

### Changed
- Expanded automated test coverage across the service layer (image, network, builder, container lifecycle/recovery, model mapping, and settings), and hardened the test suite for reliability. No user-facing behaviour change.

## [1.12.4] - 2026-07-03

### Added
- Sidebar badges showing counts at a glance: running containers, and the number of images, mounts, DNS domains, and networks.
- Diagnostic logging via Apple's unified logging system - filter by subsystem `dev.andon.orchard` in Console.app when troubleshooting.
- Continuous integration: the unit test suite runs on every pull request and must pass before a release can ship.

### Fixed
- Failed actions no longer fail silently. Many operations that failed wrote an error message that most views never displayed, so buttons could appear to do nothing ([#54](https://github.com/andrew-waters/orchard/issues/54)). Errors now appear in a standard alert.
- Fixed potential crashes when adding or editing a container's port mappings, volume mounts, or environment variables, and when validating a container name.
- Builder status and container stats failures are no longer silently ignored.
- CLI commands (builder, DNS, kernel, and system-property operations, including the admin-password prompt for DNS changes) now run off the main thread, so the UI no longer freezes while they execute.

## [1.12.3] - 2026-07-03

### Added
- Automatic in-app updates via [Sparkle](https://sparkle-project.org). Orchard now checks for updates in the background (after asking on first launch) and can install them in place; "Check for Updates…" is also available from the menu. Updates are delivered through an EdDSA-signed appcast.

### Changed
- The previous manual "check GitHub releases for a newer version" prompt has been replaced by Sparkle.

## [1.12.2] - 2026-06-16

### Fixed
- System properties no longer get stuck on "Loading…" (wrong JSON format).
- Tab controls are now clickable across their entire area.

### Changed
- Use relative shell paths instead of absolute paths.

## [1.12.1] - 2026-05-14

### Added
- Bulk actions for containers.

## [1.12.0] - 2026-05-06

### Added
- Support for Apple `container` 0.12.x.

## [1.11.7] - 2026-04-26

### Added
- Diagnostics view to help troubleshoot setup issues.

## [1.11.6] - 2026-04-26

### Added
- Automatic detection of common `container` binary locations, with a setting to override the path.

## [1.11.5] - 2026-04-26

### Changed
- Larger hit areas for controls for easier clicking.

## [1.11.4] - 2026-04-17

### Added
- Application icon.
- Homebrew installation instructions.

## [1.11.3] - 2026-04-13

### Added
- User-selectable terminal application for attaching a container shell.

## [1.11.2] - 2026-04-08

### Added
- Additional image information in the image detail view.

### Removed
- System logs and registries views.

## [1.11.1] - 2026-04-08

### Added
- Release builds are now code-signed with a Developer ID certificate and notarized by Apple.

## [1.11.0] - 2026-04-08

### Added
- Migrated to the Apple `container` XPC API for most operations (no longer shells out to the CLI).
- Multi-pane log viewer with split panes (one container's logs per pane).
- Force stop action in the container list.
- Sortable stats table, and sortable container and image lists.
- MIT license.

### Changed
- Improved log viewer performance.

## [1.7.3] - 2026-03-15

### Fixed
- Include stopped and pending containers in the container list (`container ls -a`).

## [1.7.2] - 2026-03-09

### Fixed
- Running containers not appearing in the container view.

## [1.7.1] - 2025-12-18

### Added
- Option to keep using the app when a newer version of `container` is available.

### Changed
- Updated the supported `container` version.

## [1.7.0] - 2025-12-03

### Added
- DNS domain management.
- Container resource stats - CPU, memory, disk, and network - with a sortable stats table.
- Name-uniqueness check when launching containers.

### Changed
- Renamed "Settings" to "Configuration".
- Unified content into a single detail view, removed tabs, and made numerous list/table UI improvements.

## [1.6.0] - 2025-11-30

### Added
- Network management views.
- System properties and system settings.
- Published ports and hostname opening.
- Choose a DNS domain when launching a container.

## [1.1.8] - 2025-11-29

### Added
- **Image Search and Download**: New feature to search Docker Hub for container images and download them directly from the UI
  - Search interface with Docker Hub integration
  - Pull progress tracking with visual feedback
  - Quick search suggestions for popular images (nginx, postgres, redis, alpine)
  - Displays official images with badges and star counts
  - Shows which images are already downloaded
  - Automatic image list refresh after successful pulls
- **Run Container from Image**: New feature to run containers directly from images with comprehensive configuration options
  - "Run Container" button in image detail view and search results
  - Configuration dialog with tabbed interface for easy navigation
  - Basic settings: container name, detached mode, auto-remove options
  - Port mappings: map container ports to host ports with TCP/UDP protocol selection
  - Volume mounts: bind mount host directories into containers with read-only option
  - Environment variables: set custom environment variables
  - Advanced options: working directory and command override
- **Delete Images**: Added ability to delete downloaded images
  - "Delete" button in image detail view (only shown if image is not in use)
  - Context menu delete option in image list
  - Safety check: prevents deletion if image is in use by any container
  - Confirmation dialog before deletion
- **Edit Container Configuration**: Added ability to edit stopped containers
  - "Edit Configuration" button appears for stopped containers
  - Pre-filled configuration dialog with all current settings
  - Edit ports, volumes, environment variables, working directory, and commands
  - Container is automatically deleted and recreated with new settings
  - Warning banner explains the recreation process
- **Terminal Attachment**: Added ability to attach terminal to running containers
  - "Terminal" button with dropdown menu in toolbar for running containers
  - Choose between sh (default shell) or bash
  - Opens in Terminal.app with interactive session
  - Context menu option to open terminal from container list

### Changed
- **Settings page deprecated**: You can no longer access them in the main window
  - Loading state now displays to prevent jarring view changes
  - Now requires `0.6.0` and checks the CLI version for compatibility

### Fixed
- Fixed image commands to use correct CLI syntax for container 0.6.0 (`container image pull` and `container image list` instead of plural `images`)

## [0.1.7] - 2025-11-08

> Note: this release was also tagged `v1.1.7` by mistake.

### Added
- Split settings into separate views.

### Changed
- Improved DNS domain loading and validity handling.

### Removed
- Registry management.

## [0.1.6] - 2025-06-20

### Changed
- Removed a conflicting keyboard shortcut.

## [0.1.5] - 2025-06-19

### Added
- Labels tab in the container view.

### Changed
- Lowered the minimum macOS requirement to 15.0+.

## [0.1.4] - 2025-06-18

### Fixed
- Release pipeline fixes.

## [0.1.3] - 2025-06-18

### Changed
- Release process tweaks.

## [0.1.2] - 2025-06-18

### Fixed
- Corrected permissions in the release workflow.

## [0.1.1] - 2025-06-18

### Changed
- Updated the release GitHub Action.

## [0.1.0] - 2025-06-18

### Added
- Initial release - a native macOS GUI for Apple's `container` tooling, including:
  - Container management (start, stop, view, mounts, logs)
  - Image management and image views, with filtering
  - Multi-container logs viewer
  - Builders / BuildKit and kernel support
  - DNS controls and registry management
  - System status and menu bar integration
