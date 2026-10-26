---
type: plan
status: in-progress
summary: "Choose the platform a container runs as: a Platform picker on Run and Edit that defaults to Automatic (host if the image has it, otherwise what the image offers, like the CLI), amd64 under Rosetta with an install prompt when it is missing, kept on recreate, recovery and compose `platform:`, and shown in the detail view when it is not the host's."
issues: [andrew-waters/orchard#147, andrew-waters/compose#17]
touches: [andrew-waters/orchard, andrew-waters/compose, apple/container]
owner: andrew-waters
agreed_by: [andrew-waters]
agreed_at: 2026-10-26
---

# Choose the platform when creating a container

Orchard creates every container as `Platform.current`, so an image published only for `linux/amd64` cannot run from Orchard even though Apple container runs it under Rosetta, and a multi-platform image cannot be run as anything but the host's variant. The CLI has `--platform`, `--os` and `--arch`, and from 1.6.1 infers the platform from the image.

## What happens today

- `ContainerBackend.createContainer` (`Orchard/Services/ContainerBackend.swift`) fetches the image without a platform, then uses `Platform.current` for `getCreateSnapshot`, `config(for:)` and the kernel. `ContainerConfiguration.platform` and `.rosetta` are left at their defaults (host, false).
- `ContainerRunConfig` and `ContainerCreateSpec` have no platform. Edit, recovery (`recoverContainer`) and the mount-removal recreate all rebuild a `ContainerRunConfig`, so a container's platform would be lost on recreate even once it can be set.
- `mapPlatform` drops the OCI variant (a KNOWN-ISSUE note in `ModelMapping.swift`).
- `ContainerDetail` already shows a Platform row (`os/arch`) for every container.
- Compose: `platform` is a deferred key in andrew-waters/compose, `CreateOperation` has no platform, and `ComposeService.build` passes `arch: "arm64"`.

## How upstream 1.6.1 does it

- `ClientImage.platforms(reference:containerSystemConfig:)` returns an image's runnable platforms: from the local index when the image is here, otherwise over the new `imagePlatforms` route without pulling layers (apple/container#2422).
- `PlatformResolver.resolve`: an explicit platform must be among the candidates; with none asked for, one candidate wins outright, several fall back to the default platform (the host, or `CONTAINER_DEFAULT_PLATFORM`), and an error lists them when the host is not one.
- `fetch(reference:platform:)` pulls the requested variant if the stored image lacks it. Snapshot and image config use the requested platform.
- **The kernel stays the host's** (`SystemPlatform.current`): only userspace is amd64, run by Rosetta. The issue says to use the choice for the kernel lookup too; that would fail, so the kernel stays as it is.
- `config.rosetta = host is arm64 && platform is amd64`, and `runtimeHandler = "container-runtime-<os>"`.

## Approach

### Model

- `ContainerRunConfig.platform: String = ""`. Empty means Automatic; otherwise `os/arch[/variant]`, the form `Platform.description` and `--platform` use.
- `ContainerCreateSpec.platform: String? = nil`, carried by `ContainerListService.runContainer`. Spec stays in app types; the backend parses it with `ContainerizationOCI.Platform(from:)`.
- `mapPlatform` fills `variant`, and `Orchard.Platform` gets a `description` (`os/arch[/variant]`), so a container's platform round-trips through edit exactly.

### Backend

- `ContainerBackend.imagePlatforms(reference:) async throws -> [String]`, through `ClientImage.platforms`. On a runtime older than 1.6.1 the route does not exist, so a remote image yields an error and the form offers Automatic only, with a caption saying to pull the image to choose; a local image still answers from its index on any version.
- A pure, tested `ContainerPlatform.resolve(requested:candidates:host:) throws -> String` mirroring `PlatformResolver` with no flags: requested must be a candidate (when the candidate list is known), one candidate wins, several pick the host, otherwise an error naming them. Unknown candidates (an older runtime and a remote image) fall back to the requested platform or the host, which is today's behaviour.
- `createContainer`: resolve, `fetch(reference:platform:)`, snapshot and config for that platform, kernel unchanged, then set `platform`, `rosetta` and `runtimeHandler` on the configuration as the CLI does.
- Before creating an amd64 container on arm64, check Rosetta and throw `OrchardError.rosettaNotInstalled` ("Rosetta is needed to run linux/amd64 images. Install it from the Run sheet or with `softwareupdate --install-rosetta`."). This covers recovery and compose, which have no sheet to warn from.

### Rosetta

- `RosettaService` (main actor, injected like the others): `availability` from `VZLinuxRosettaDirectoryShare.availability` (`.installed`, `.notInstalled`, `.notSupported`), and `install()` through `VZLinuxRosettaDirectoryShare.installRosetta()`, which shows the system's own licence prompt, then refreshes.
- **Decision:** Rosetta missing and an amd64 platform chosen or resolved? **Block Run with a notice and an Install Rosetta button.** On Intel or `.notSupported`, the notice says the platform cannot run on this Mac and there is no button.

### Form

- A **Platform** picker on the Basic tab, in Run and Edit: "Automatic (linux/arm64)" naming what Automatic resolves to, then each platform the image offers. Loaded with `.task(id: config.image)` so typing a reference in the picker-mode Run sheet refreshes it, debounced.
- A platform that is not the host's shows a caption ("Runs under Rosetta translation") or the Rosetta notice above. Run (and Save & Recreate) is disabled while the notice is up.
- A selected platform the image no longer offers (after the image changes) resets to Automatic.

### Keeping the choice

- Edit prefills `platform` from the container's configuration, so Save & Recreate keeps it; changing it recreates as the new platform.
- `recoverContainer` and the mount-removal recreate in `ContainerListService` carry `config.platform.description`.
- Compose: `ComposeService.createSpec` maps `CreateOperation.platform`; `build` passes the service's architecture instead of `arm64`. Needs the compose change below and a compose release, then the pin moves from 0.5.x to that release.

### Detail view

- The existing Platform row shows the variant too. When the architecture is not the host's, the container header gets a small badge ("amd64 · Rosetta"), and the row's value says "under Rosetta".

### Docs

- README (Orchard Features, and the compose section's supported keys), the site's feature copy in `site/index.html`, and CHANGELOG under Unreleased > Added.

### Tests

- `ContainerPlatform.resolve` cases (requested, single, host among several, no host, unknown candidates), `ContainerRunConfig` to spec carrying the platform, `createSpec` mapping compose's platform, `mapPlatform` keeping the variant, recovery carrying the platform. Mocks and `UITestSupport` get `imagePlatforms`.

## andrew-waters/compose (separate plan in that repo)

- `Service.platform: String?` parsed from `platform:` (interpolated, validated as `os/arch[/variant]`, refused with its line otherwise); `KeySupportTable` marks it supported.
- `canonicalDescription` adds `platform=` only when set, so existing containers keep their hash.
- `CreateOperation.platform`, `BuildOperation.platform` and `PullOperation.platform`, all optional with `nil` defaults so Orchard compiles unchanged until it maps them.
- The plugin's runtime uses it for fetch, snapshot, config, `rosetta` and the build's `--platform`; the kernel stays the host's.
- README Scope and the site's compatibility table. Released as 0.7.0 with the repo's `release` skill once merged.

## Tasks

- [x] [andrew-waters/compose#17](https://github.com/andrew-waters/compose/issues/17) compose: `platform:` parsed, planned and honoured by the plugin; README and site (committed on its branch)
- [ ] compose 0.7.0 released, and Orchard's pin moved to it
- [x] Orchard: model, `imagePlatforms`, `ContainerPlatform.resolve`, platform-aware create with Rosetta check
- [x] Orchard: `RosettaService`, Platform picker and Rosetta notice on Run and Edit
- [x] Orchard: keep the platform on edit, recovery and mount-removal recreate; `mapPlatform` variant
- [x] Orchard: `createSpec` and build map the platform (built and tested against the compose branch through a local workspace override)
- [x] Orchard: detail badge and row
- [x] Orchard: tests, README, site, CHANGELOG

## Open questions

- Does `VZLinuxRosettaDirectoryShare.installRosetta()` work as Orchard is signed and entitled? Orchard is not sandboxed, so it should; if not, the button falls back to `softwareupdate --install-rosetta --agree-to-license` behind an administrator prompt, the way Install container does.

**Decisions:**

- Compose: both repos under this issue, or a follow-up? **Both, with its own issue, andrew-waters/compose#17.**
- Rosetta missing? **Block with a notice and an Install Rosetta button.**
- Kernel for an amd64 container? **The host's, as `container run` does; the issue's "kernel lookup" would fail.**
