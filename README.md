# Orchard

Orchard is a native (swift) application to manage containers on macOS using the new [Containerization framework](https://github.com/apple/containerization).

It has been based on years of experience with Docker Desktop, but dedicated to the new containerization option.

The ambition of the project is to allow it easy for developers to switch from Docker Desktop to Containers. Orchard gives you a desktop experience that complements the `container ...` command-line interface.

![container overview screen](assets/overview.png)

## Highlight of Containerization

- Made by Apple: Native support, incredible performance and the engineering resources to make it work.
- Sub second startup times
- Kernel isolation by design
- Easier networking - no more port mapping (every container gets its own IP address), networks out of the box

## Requirements

> `container` relies on the new features and enhancements present in macOS 26. Additionally, you need to install a specific version of container - [follow the instructions here](https://github.com/apple/container?tab=readme-ov-file#install-or-upgrade) if you have not already upgraded.

https://github.com/apple/container?tab=readme-ov-file#requirements

## Installation

You can build from source or download a prebuilt package.

### Prebuilt

1. Download the latest release from [GitHub Releases](https://github.com/container-compose/orchard/releases)
2. Open the `.dmg` file and drag Orchard to your Applications folder
3. Launch Orchard - you may need to go to **System Settings > Privacy & Security** and click "Open Anyway" to allow the app to run

### Build from Source

```bash
git clone https://github.com/container-compose/orchard.git
cd orchard
open Orchard.xcodeproj
```
