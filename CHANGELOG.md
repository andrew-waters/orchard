# Changelog

All notable changes to Orchard are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- Running a locally built image no longer fails with a 401 from Docker Hub. The Run Container sheet canonicalised every image reference before running, so a local tag like `mono2` was rewritten to `docker.io/library/mono2` and the backend tried to pull a repository that doesn't exist on the registry (Hub answers 401 for unknown repositories). The reference now resolves against the local image store first - a match runs under the exact reference the store knows (including the implied `:latest`), and only unmatched references canonicalise into pullable registry form. The "Local image available" hint and the actual run decision now agree.

### Added
- A Builds sidebar tab (Resources section, `orchard://builds`) tracks every image build Orchard has started, and the records survive relaunches (stored as versioned JSON in Application Support, with each log's last 1000 lines). The list shows status, start time, and duration per build, searchable by image name; the detail pane shows the build's request (Dockerfile, platform) and its full log, live while building and reviewable after, with Cancel Build for in-flight builds and a context-menu Remove Record for finished ones. Once a build's image exists, the detail also mirrors the image view's affordances: a "Launch image" button opening the run-container sheet pre-filled with the built reference, a "Containers using this image" list that jumps to each container, and a confirmed Delete that removes both the build record and the built image (disabled while containers use the image; if the image delete fails, the record is kept). Builds and images cross-reference: the build detail's "View Image" jumps to the built image, and an image produced by an Orchard build gains a "View Build" button jumping to the newest successful build of that reference. Builds run concurrently and survive closing the Build Image sheet; a build still running when the app quits is marked "interrupted" on the next launch, since the CLI process was orphaned and its outcome never observed (the image may still have been built). The registry only lists builds Orchard itself started: apple/container's builder shim exposes just info() and a build stream over its gRPC surface, so BuildKit's own history is not reachable from the host.
- Deep links: Orchard registers the `orchard://` URL scheme. `orchard://<tab>` opens any sidebar tab (e.g. `orchard://dashboard`), and `orchard://container/<id>`, `orchard://image/<reference>`, `orchard://mount/<id>`, `orchard://machine/<id>`, `orchard://dns/<domain>`, and `orchard://network/<id>` jump straight to a resource, reusing the same navigation path as the command palette and menu bar (so a target in a still-loading list is selected once it appears). A resource noun without an identifier falls back to its tab, and image references keep their interior slashes.
- Containers can be grouped by label: the containers sort menu gains a "Group by Label" submenu listing every label key present on current containers (internal `com.apple.container.*` bookkeeping labels excluded). With a key selected, the list renders one collapsible section per label value - click a header to fold it - with a count badge, a "No label" bucket for containers missing the key, and a per-group actions menu to start or stop everything in the group. The choice persists, and search/running filters apply within the groups.
- Containers can be exported as tar archives (container 1.2+ API). An "Export…" button in the container detail header and an "Export Filesystem…" context-menu item in the containers list prompt for a destination, stream the filesystem through the API client (written to a scratch directory first, so a failed export never leaves a partial file at the chosen path), show an "Exporting…" state while in flight, and reveal the archive in Finder when done.
- Image pulls now show real progress: a determinate bar with downloaded/total bytes and blob counts (e.g. "256 MB / 512 MB · 3/8 blobs") instead of an indeterminate spinner, updating live from the registry client's progress events (throttled to ~10 Hz so per-chunk byte updates don't churn the UI). The bar stays indeterminate until the total size is known, and the phase label ("Fetching image") replaces the static "Pulling image..." message.
- Build images from a Dockerfile. The Images tab gains a hammer button (and the command palette a "Build an Image..." action) opening a Build Image sheet: pick the Dockerfile through a file panel so non-default names like `Dockerfile.dev` are discoverable (the build context auto-fills to the Dockerfile's folder), name the image, choose the target platform (Apple silicon linux/arm64 or Intel linux/amd64, defaulting to the host), and optionally build without cache. The build shells out to `container build`, which starts the BuildKit builder on demand, and the build log streams live into the sheet through the ANSI console; closing the sheet leaves the build running, and a Cancel Build button terminates it. Successful builds refresh the image list automatically.
- Log views now render ANSI colours and support selection across lines. Container and machine logs were previously drawn as one SwiftUI `Text` per line, which printed colour escape codes as literal garbage and scoped text selection to a single line. Both the detail Logs tab and the log viewer window now share a single `NSTextView`-backed console: SGR styles (16-colour, bright, 256-colour, truecolour, bold/italic/underline) are rendered, other escape sequences are stripped, carriage-return progress lines show their final state, and click-drag or Cmd+A/Cmd+C works across the whole log. Filtering now matches the escape-stripped text, so a filter term can no longer hit or miss because of bytes inside a colour code, and the console follows the tail only while scrolled to the bottom (scrolling up to read no longer fights the 2s refresh, which previously only auto-scrolled on first load).

## [2.3.2] - 2026-08-30

### Fixed
- The GUI now tracks the container system when it is stopped and started from the CLI (#100). The 5-second status poll was torn down by the main interface's `onDisappear`, which also fires when the system stops and the "not running" screen swaps in. After that, nothing polled, so a `container system start` run in a terminal was never noticed and Orchard stayed on "Container is not currently running" until the power button was clicked. The same dead end was reachable by launching Orchard while the system was stopped. The poll's lifetime now matches the window rather than one branch of the state view, so external stops appear within a poll tick (a stop can still lag while `container system stop` drains running containers, since the API server answers until it deregisters) and an external start restores the full interface automatically.

## [2.3.1] - 2026-08-30

### Fixed
- Image sizes now match `container image ls -v` (#98). Orchard was showing the size of each variant's manifest *descriptor* — a couple of kilobytes of JSON — instead of the image content, so every image listed as "1 KB"–"3 KB". Variant sizes are now computed the same way the CLI computes FULL SIZE: manifest descriptor plus config blob plus the sum of the compressed layers. The container detail's Image section and the multi-select image cards previously showed the raw index descriptor size as "Size"; both now use the same resolved size as the images list, and the image Technical Details row is relabeled "Index Size (bytes)" since that value genuinely is the index descriptor size.

## [2.3.0] - 2026-08-29

### Changed
- Orchard now links the Apple container 1.3.1 client libraries (previously 1.2.2), restoring compatibility with current container installs. 1.3.1 also patches six security advisories in the containerization package that Orchard's image operations link directly, including path traversal in the local content store and a `RegistryClient` that followed `WWW-Authenticate` realms without validating the host.
- Image pulls now default to `https` for all registries, matching container 1.3.0's removal of the `auto` registry scheme. Pulls from localhost or private-IP registries no longer silently downgrade to plain http; a local http registry needs `registry.scheme = "http"` in the container configuration, same as the `container` CLI.

### Fixed
- Local-model detection no longer follows HTTP redirects when probing for providers. The probe targets conventional ports (11434, 1234, 8080, 8000), which are often owned by something else entirely; a dev server on 8080 that redirects to its TLS port would take the probe with it, so Orchard opened a connection to an unrelated endpoint every five seconds and abandoned it when the 1.5s probe deadline expired. Against a Rails app running with `force_ssl` this leaked a socket per probe until the server's accept loop stopped and it served nothing at all. A real provider answers 200 directly, so a redirect is now simply classified as "not a provider" - which also stops a redirecting server from being misreported as a model server.

## [2.2.2] - 2026-08-25

### Added
- The menu bar popup now exposes a Stop control for the container system alongside the existing Start control, so the system can be shut down without opening the main window or going through the command palette. The button is gated on a running system and disabled while a transition is in flight; calling `stopSystem()` while a transition is already in flight is a no-op at the service layer.

### Fixed
- Menu-bar System analytics no longer stays stuck on "Collecting…" when container stats fail. The menu-bar hover popover now distinguishes four explicit states: collecting during the initial two-tick baseline, available with real CPU/memory history, "No running containers" when the system has none to sample, and "Stats unavailable" with a short reason when the XPC service is unreachable or every stats call failed. Per-container stats failures are now logged via `Log.xpc` so diagnostics aren't blind, and the existing dashboard, container, and machine stats paths are unchanged. No new macOS permission is required.
- Container service-unavailable failures in the menu-bar sampling tick are now logged only once per tick via `Log.xpc`; subsequent outcomes in the same tick fold in silently while the first error is retained, so a single tick with several unreachable containers no longer produces one log line per outcome.

## [2.2.1] - 2026-08-20

### Added
- Command palette: press Cmd+K (or View > Command Palette...) to fuzzy-search everything Orchard manages - containers, images, mounts, machines, k8s clusters, AI models, sandboxes, DNS domains and networks - and jump straight to any of them, or run actions from the keyboard: run a container, pull an image, create networks/machines/clusters, start/stop/restart the container system, and per-resource verbs like "stop db", "logs api" or "console web". Results rank with real fuzzy matching (exact prefix beats word-boundary beats scattered match); destructive operations are deliberately not palette-reachable.
- The Dock icon can now be hidden (Settings > General > "Hide Dock icon"): Orchard switches to a menu-bar accessory, staying reachable from the menu bar, and the preference applies immediately and persists across launches. Note that macOS also removes accessory apps from the Cmd-Tab switcher.

### Fixed
- The AI Models and Sandboxes middle columns no longer render lighter than every other list: they used the sidebar list style, which paints its own source-list background, instead of the plain style the rest of the middle columns use.
- Searching in the DNS and Networks tabs now actually filters the list; previously the search field rendered, but typing did nothing.
- The search query is cleared when switching tabs, so a query typed in one tab no longer silently filters the next.
- The containers list now supports Command+A select-all like the other multi-select lists.

### Removed
- Dead internal code: the never-shipped item navigator popover, its orphaned header component and an unused detail column wrapper.

## [2.2.0] - 2026-08-20

### Added
- Containers owned by a container plugin (such as k8s cluster nodes) are badged in the containers list and detail header with the owning plugin and their role, e.g. "k8s · control-plane", so kindest/node containers aren't mystery rows.
- Clusters: a new sidebar section for local Kubernetes clusters created with the `container k8s` plugin (container 1.2.2+). Node containers are grouped into clusters with per-node role, status, IP, CPUs, memory, and published ports; clusters can be created, started, and deleted from the UI, local images can be loaded into a cluster's containerd, and the kubeconfig can be written or its path copied, with a one-click terminal preconfigured for kubectl. Installs without the plugin get an explanatory state with upgrade guidance.

### Fixed
- With the sidebar hidden, the Dashboard (and other full-width pages) no longer render underneath the macOS window controls ([#88](https://github.com/andrew-waters/orchard/issues/88)).

## [2.1.7] - 2026-08-20

### Changed
- Orchard now links the Apple container 1.2.2 client libraries (previously 1.1.0), restoring compatibility with current container installs ([#54](https://github.com/andrew-waters/orchard/issues/54)).
- When the installed container release doesn't match the client Orchard links, the app now shows the version-incompatibility screen with upgrade guidance instead of reporting the system as stopped with a raw health-check decode error ([#37](https://github.com/andrew-waters/orchard/issues/37), [#39](https://github.com/andrew-waters/orchard/issues/39)).

## [2.1.6] - 2026-08-20

### Added
- Pull images by reference from non-Docker-Hub registries: the image search gains a pull-by-reference input, and references are canonicalized so by-reference and search-result pulls share progress tracking.
- Docker Hub search now searches as you type (300ms debounce, Enter bypasses it) and paginates as you scroll.

### Changed
- Image sizes display consistently and pull progress is clearer, with failed pulls dismissible and retryable.
- Multi-selection across containers, images, mounts, DNS domains, and networks: shift-click range selection, Command+A select-all, batch deletion, and a summary detail view for the selection ([#53](https://github.com/andrew-waters/orchard/pull/53)).

### Fixed
- The Run Container sheet now stays open when the run fails, so the configuration can be adjusted and retried; previously it dismissed regardless, leaving only the error alert.
- When the container system is stopped or XPC is unreachable, Orchard no longer storms error dialogs from background refresh. Failed XPC connections surface as a clear "container service is unavailable" message, and after starting the system Orchard waits until the service is actually reachable before loading data.
- Running containers' stop buttons in the menu-bar panel now respond on first click.

## [2.1.5] - 2026-08-20

### Added
- Containers can now be created with a chosen CPU and memory allocation, and both can be changed later from Edit Configuration (via the usual stop/recreate flow). Previously every container silently got the runtime defaults of 4 CPUs and 1 GB with no way to change them in the GUI ([#73](https://github.com/andrew-waters/orchard/issues/73)).
- The AI Models section now recognises [oMLX](https://github.com/jundot/omlx) servers. oMLX serves the same OpenAI-style API on the same conventional port (8000) as `mlx_lm.server`, so it previously appeared as a generic "MLX Server"; it's now identified by the `owned_by: omlx` stamp in its models listing ([#72](https://github.com/andrew-waters/orchard/issues/72)).
- Local model servers that require an API key (oMLX generates one at setup) are no longer invisible: they appear as a locked provider with a field to paste the key, which is then used for detection, model listing, the chat tester, and the container bridge (`OPENAI_API_KEY`).

### Fixed
- Edit Configuration no longer drops the executable from the Command Override field: the form now shows the full command (`sleep 3600`, not just `3600`), so saving doesn't corrupt the container's process configuration. Quoted arguments (`sh -c "echo hi"`) now also survive the round-trip ([#42](https://github.com/andrew-waters/orchard/issues/42)).
- Unchecking "Run in detached mode (background)" now does what it says: after the container starts, Orchard opens your preferred terminal attached to it. The toggle no longer appears in the Edit Configuration sheet, where recreation always happens in the background ([#43](https://github.com/andrew-waters/orchard/issues/43)).
- Opening a container terminal in Terminal.app or iTerm2 no longer fails with "Not authorized to send Apple events" on notarized builds: the app now carries the `com.apple.security.automation.apple-events` entitlement and a usage description, so macOS shows the Automation consent prompt. If permission is denied, the error now points to System Settings → Privacy & Security → Automation instead of dumping the raw AppleScript error ([#64](https://github.com/andrew-waters/orchard/issues/64)).

## [2.1.4] - 2026-07-23

### Added
- Error message displayed when trying to start `container` now includes a download link if the binary could not be found.

## [2.1.3] - 2026-07-08

### Added
- **Local AI models (MLX)**: a new **AI Models** section discovers model servers running on your Mac (Ollama, LM Studio, and MLX servers), and can start and stop your own `mlx_lm.server` instances - pick a model and port, choose whether to bind `0.0.0.0` so containers can reach it, with child-process supervision, crash surfacing and log access.
- **The container↔model bridge**: wire a container to a host model in one step. Orchard computes the container-reachable endpoint from the network gateway and injects `OPENAI_BASE_URL` at create time - so a containerised app or agent talks to a local model with no hand-configured host networking. Inference runs on the Apple GPU on the host (Virtualization.framework guests have no GPU access).
- **Sandboxes**: a first-class view of containers wired to a local model, recognised by a label Orchard stamps or by a model-endpoint environment variable. Each sandbox shows its model endpoint, an isolation badge (host-only/no-egress vs internet-open), and agent-runner controls - chat, terminal, and a stop kill-switch. Create one from the **New Sandbox** button or from a model's detail.
- **In-app chat tester**: hold a short conversation with any model server from the AI Models view - no terminal or container needed - to check it's working.
- Sandbox containers are flagged with a shield badge (and an explanatory popover) in the Containers list and detail, since a sandbox appears in both places.
- A new [Local AI guide](https://orchard.andon.dev/ai.html) on the site covering MLX, the bridge, isolation, and a runnable quick start.

### Changed
- Reorganised the sidebar so **Sandboxes** joins Containers and Machines under **Compute**, and **AI Models** sits under **Resources** alongside Images and Mounts.

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
