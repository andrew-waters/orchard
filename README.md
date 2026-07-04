![Banner - Orchard](assets/banner.png)

[![GitHub stars](https://img.shields.io/github/stars/andrew-waters/orchard?color=e8590c&label=stars)](https://github.com/andrew-waters/orchard/stargazers)
[![Homebrew installs](https://img.shields.io/homebrew/cask/installs/dm/orchard?color=e8590c&label=homebrew%20installs)](https://formulae.brew.sh/cask/orchard)
[![Homebrew cask version](https://img.shields.io/homebrew/cask/v/orchard?color=e8590c&label=homebrew)](https://formulae.brew.sh/cask/orchard)
[![License: MIT](https://img.shields.io/github/license/andrew-waters/orchard?color=e8590c)](LICENSE)
[![CI](https://github.com/andrew-waters/orchard/actions/workflows/ci.yml/badge.svg)](https://github.com/andrew-waters/orchard/actions/workflows/ci.yml)
[![Services coverage](https://img.shields.io/endpoint?url=https%3A%2F%2Forchard.andon.dev%2Fcoverage-badge.json)](https://github.com/andrew-waters/orchard/actions/workflows/ci.yml)

```bash
brew install orchard
```

[See all install options](#installation)

---

Orchard is a native (Swift) macOS application for managing containers using Apple's [container](https://github.com/apple/container) tooling.

It gives you a desktop experience that complements the `container` command-line interface.

Hundreds of installations and starred by engineers from Apple, Microsoft, Red Hat, GitHub & more - [see who's adopting Orchard](#adoption)  

---

- [Benefits of Apple Containers](#benefits-of-apple-containers)
- [Orchard Features](#orchard-features)
- [How Orchard compares](#how-orchard-compares)
- [Requirements](#requirements)
- [Architecture](#architecture)
- [Installation](#installation)
  - [Homebrew](#homebrew)
  - [Release download](#release-download)
  - [Build from Source](#build-from-source)
- [Adoption](#adoption)
- [Star History](#star-history)
- [License](#license)

![container overview screen](assets/overview.png)

## Benefits of Apple Containers

- Native support, incredible performance and the engineering resources to make it work.
- Sub second startup times
- Kernel isolation by design
- Easier networking - no more port mapping (every container gets its own IP address), networks out of the box

## Orchard Features

- Container management: create, start, stop, force stop, delete
- Image management: pull, delete, search Docker Hub
- Network and DNS domain management
- Real-time container stats with sortable columns
- Sortable container and image lists with persistent preferences
- Multi-container log viewer with split panes, filtering, and per-container colour coding
- Container log viewer with search highlighting
- Builder, kernel and system property management
- Menu bar integration

![image management](assets/images.png)

Browse, pull, and delete container images. Search Docker Hub directly from the app and inspect image metadata without dropping to the CLI.

![container logs](assets/logs.png)

Stream logs from multiple containers side by side. Split panes, filter by text, and use per-container colour coding to keep output readable when debugging across services.

![container runtime stats](assets/runtime.png)

Monitor live CPU, memory, and network usage for running containers. Sortable columns and persistent preferences make it easy to spot resource hotspots at a glance.

## How Orchard compares

Orchard isn't the only way to work with Apple's `container` runtime:

| | Orchard | Podman Desktop | The `container` CLI |
| --- | :---: | :---: | :---: |
| Purpose-built for `apple/container` | ✅ | ➖ via an extension | ✅ |
| Native macOS app | ✅ Swift / SwiftUI | ❌ Electron | - |
| Native XPC integration (no CLI shelling) | ✅ | ❌ Docker-API shim | ✅ |
| Signed & notarized | ✅ | ✅ | ✅ |
| Multi-pane log viewer | ✅ | ➖ | ➖ terminal only |
| Live container stats (CPU/mem/net/disk) | ✅ | ✅ | ➖ |
| Network, DNS & builder management | ✅ | ➖ | ✅ |
| Focused, lightweight footprint | ✅ | ❌ general-purpose | ✅ |
| Open source (MIT) | ✅ | ✅ (Apache-2.0) | ✅ (Apache-2.0) |

Orchard is the **native, purpose-built** choice: a lightweight Swift app focused solely on giving Apple's `container` a first-class desktop experience, rather than a heavyweight cross-platform tool that supports it as one runtime among many. (Note: Docker Desktop is a separate container runtime and doesn't manage `apple/container`.)

Being native goes beyond the UI: Orchard talks to the container daemon over the same typed XPC API the `container` CLI uses internally, rather than spawning the CLI and parsing its output. That means structured data instead of screen-scraping (no breakage when CLI wording changes), no child processes on every refresh, real log streams feeding the multi-pane viewer, and typed errors instead of exit codes.

## Requirements

- macOS 26 (Tahoe)
- Xcode 26 / Swift 6.2 (for building from source)
- [Apple Container](https://github.com/apple/container) installed - [follow the instructions here](https://github.com/apple/container?tab=readme-ov-file#install-or-upgrade)

## Architecture

Orchard communicates with the container daemon primarily through the `ContainerAPIClient` Swift library (from [apple/container](https://github.com/apple/container)) over XPC — typed Swift APIs for containers, images, networks, stats, logs, and system health, with no CLI process spawning or output parsing on this path. Every operation the API exposes goes over XPC; the remaining CLI-backed operations are the exceptions noted below.

A small number of operations still use the `container` CLI via `Foundation.Process`, each for a structural reason rather than convenience: system start/stop/restart (the daemon is registered with launchd — there is nothing to XPC to until it's running), builder lifecycle (the API exposes no builder surface; the CLI orchestrates it client-side), system properties (a local defaults store, not an API), and DNS domain create/delete (requires root, so it runs the CLI under administrator privileges).

## Installation

You can install Orchard via homebrew or via a prebuilt release package. You can also download the source and build it yourself!

> Every release is **code-signed with a registered Apple Developer ID and notarized by Apple**, so it installs and launches cleanly with no Gatekeeper "unidentified developer" warning.

### Homebrew

```bash
brew install orchard
```

### Release download

1. Download the latest release from [GitHub Releases](https://github.com/andrew-waters/orchard/releases)
2. Open the `.dmg` file and drag Orchard to your Applications folder
3. Launch Orchard from the Apps directory

### Build from Source

```bash
git clone https://github.com/andrew-waters/orchard.git
cd orchard
open Orchard.xcodeproj
```

The project uses Swift Package Manager for dependencies. Xcode will resolve the `apple/container` package automatically on first build.

## Adoption

Orchard is installed hundreds of times a month via Homebrew - see the live [install stats](https://formulae.brew.sh/cask/orchard) - and has been starred by engineers from Apple, Microsoft, GitHub, Red Hat, Amazon, MongoDB, Tencent and across the wider cloud-native community.

Using Orchard at your company or in your day-to-day workflow? We'd love to hear about it - add yourself to [`ADOPTERS.md`](ADOPTERS.md) with a quick pull request.

## Star History

<a href="https://www.star-history.com/?repos=andrew-waters%2Forchard&type=date&legend=bottom-right">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=andrew-waters/orchard&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=andrew-waters/orchard&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=andrew-waters/orchard&type=date&legend=top-left" />
 </picture>
</a>

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
