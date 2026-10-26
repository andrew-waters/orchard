---
type: plan
status: done
summary: "Tell someone on an older `container compose` plugin that a newer one exists: compare the installed version with the latest release (fetched once per visit to the Compose tab, a failed lookup meaning unknown) and with the compose package Orchard links, show the installed version in a quiet footer, and offer **Update** through the existing install flow when it is behind."
issues: [andrew-waters/orchard#155]
touches: [andrew-waters/orchard]
owner: andrew-waters
agreed_by: [andrew-waters]
agreed_at: 2026-10-26
---

# Offer to update the compose plugin when it is behind

`ComposePluginService` reads the installed plugin's version (`container compose --version`) and fetches the latest release for **Install**, but never compares the two. Since Orchard links compose 0.7.0 (#147) the window honours a service's `platform:`, while a 0.6.0 plugin ignores it, so `container compose up` and the Compose tab can bring the same file up as different architectures and nothing says why.

## Approach

### Versions

- A small `ComposePluginVersion` value: parsed from `x.y.z` (any number of numeric components, an optional leading `v`), compared numerically component by component with missing components as zero, so `0.10.0 > 0.9.0` and `0.7 == 0.7.0`.
- Anything else does not parse and is left alone: `0.0.0-dev` (a working-copy build of compose), a pre-release suffix, or text the plugin did not mean as a version. An unparseable installed or latest version never produces an offer.

### The linked package

- `ComposePluginService.linkedVersion = "0.7.0"`, the compose package Orchard is built against, since the package does not report its own version at runtime.
- A test reads `Package.resolved` through `#filePath` and fails when the pin and the constant disagree, so moving the pin cannot leave this behind.

### Service

- `@Published private(set) var latestVersion: String?`, filled by `checkForUpdate()`, which fetches the latest release through the existing `latestRelease()` and records only its tag. Any failure (offline, rate limited, bad response, no asset) leaves it nil: unknown, never "out of date", and never an error shown.
- `checkForUpdate()` runs once per visit to the tab: the view calls it after `refresh()` in the same `.task`, and only when the plugin is installed with a version that parses. `refresh()` itself never touches the network, so an install finishing (which calls `refresh()`) does not fetch again.
- `var update: Update?` derived from the installed version, `latestVersion` and `linkedVersion`, through a pure static `updateOffer(installed:latest:linked:)`:
  - `.newerRelease(latest)` when the latest release is newer than the installed plugin.
  - `.olderThanOrchard(linked)` when the installed plugin is older than the linked package and no newer release is known (offline, or the lookup failed). This is offered with no network.
  - nil otherwise, including any version that does not parse.
- `install()` is unchanged apart from being reachable from an installed state: the sheet starts it for an update as it does for a missing plugin. It still fetches the latest release itself, so an update offered offline fails in the sheet with "No network connection." as an install does.

### Compose tab

- **Footer:** when the plugin is installed, a one-line caption at the bottom of the tab, "container compose 0.7.0" (or "container compose" when the version could not be read). Nothing while unknown or missing, since the missing banner covers that.
- **Update banner:** the same blue banner as the missing one, shown when `update` is set, with an **Update** button opening the install sheet.
  - Newer release: "container compose 0.7.0 is available" / "0.6.0 is installed. The terminal may not handle a file the way this window does."
  - Older than Orchard (offline): "container compose 0.6.0 is older than Orchard's" / "The terminal may not handle a file the way this window does."
- **Sheet:** `InstallComposePluginSheet` starts the work when the plugin is missing or an update is offered, and its title and caption say "Update" when it is replacing an installed plugin. The finished line reads "Installed 0.7.0." as now.

### Docs

- README, "The compose plugin": the tab shows the installed version and offers an update when a newer release exists or the plugin is older than the package Orchard links.
- CHANGELOG under Unreleased > Added.

### Tests

- `ComposePluginVersion`: parsing (`v` prefix, two and four components, `0.0.0-dev` and junk rejected) and ordering (`0.10.0 > 0.9.0`, `0.7 == 0.7.0`).
- `updateOffer`: newer release; latest installed offers nothing; installed newer than latest offers nothing; older than linked with no latest; unparseable installed, latest or both.
- `linkedVersion` matches `Package.resolved`.
- `checkForUpdate` through a stubbed session: a 200 records the tag, a failure leaves `latestVersion` nil.

## Tasks

- [x] `ComposePluginVersion`, `linkedVersion` and its `Package.resolved` test
- [x] Service: `latestVersion`, `checkForUpdate()`, `updateOffer` and `update`
- [x] Compose tab: footer, update banner, sheet wording and starting an update
- [x] Tests
- [x] README and CHANGELOG

## Open questions

None.

**Decisions:**

- How does the installed version appear? **A quiet footer line whenever the plugin is installed; the banner only when behind.**
- Does a plugin older than the linked package count as behind when the release lookup fails? **Yes, it is offered offline too.**
