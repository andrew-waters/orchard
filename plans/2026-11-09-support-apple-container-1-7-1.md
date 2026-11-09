---
type: plan
status: done
summary: "Build Orchard against apple/container 1.7.1 (containerization 0.54.0), replace Load Image with --shared-image-store on 1.7+, stop Orchard acting on cluster nodes on their own, and apply config.toml's [container.dns] defaults to containers Orchard creates."
issues: [andrew-waters/orchard#173]
touches: [andrew-waters/orchard]
owner: andrew-waters
agreed_by: [andrew-waters]
agreed_at: 2026-11-09
---

# Support Apple container 1.7.1

Orchard pins apple/container 1.6.1 and containerization 0.53.0. 1.7.1 removes `cluster load-image`, hides cluster nodes from the CLI's per-container commands, and adds `[container.dns]` defaults that only the CLI applies. Orchard talks XPC, so it needs its own version of each guard. The follow-on improvements (worker sizing, the clusters service, kernel reporting) are #174; the version range is #172.

## What changes between 1.6.1 and 1.7.1 for Orchard

From a diff of the two tags:

- **Client API.** Nothing Orchard calls changes shape. `ContainerListFilters.withoutMachines()` is gone (replaced by `withoutPlugins(_:)`), but Orchard doesn't use it. `ContainerConfig` gains `dns: ContainerDNSConfig?`, decoded from `[container.dns]`. `ResourcePluginValues` names the `machine` and `cluster` plugin labels. A new `ContainerClusterService` product exists; Orchard doesn't need it here (#174).
- **Over XPC with a 1.6.x runtime.** `SystemHealth`, `ContainerConfiguration` and the routes Orchard uses are unchanged, so the 1.7.1 client should still ping and drive a 1.6.x daemon. To confirm in the smoke test.
- **New client-side guards Orchard skips.** Cluster nodes are filtered out of `start`, `stop`, `kill`, `delete`, `prune` and `ls` (apple/container#2462); handled in part 3. `--cpus` above the host's core count is refused by the CLI's parser but not the daemon; out of scope, noted for #174.
- **Cluster plugin.** `load-image` is removed (apple/container#2437). `cluster create --shared-image-store` mounts `cluster-hoststore.sock` into each node at `/opt/cluster-shim/hoststore.sock` and runs cluster-shim as the kubelet's image service. The flag needs the `cluster-hoststore` plugin, which the signed installer ships and loads at boot. `cluster list` now prints one row per cluster; Orchard only uses its exit status for the plugin probe, so that keeps working.

## 1. Build against 1.7.1

- Pin `container` at 1.7.1 in `project.pbxproj`; resolve `Package.resolved` to container 1.7.1 and containerization 0.54.0, moving no other pins unless the resolver must.
- `supportedContainerVersion = "1.7.1"`: the install button, the not-installed and incompatibility screens, the installer URL (`container-1.7.1-installer-signed.pkg`) and release.yml all follow it.
- Version gates are unchanged in meaning: `supportsWorkerNodes`, `supportsNoCNI`, `supportsCommit`, aliases and the machine account stay `>= 1.6`, `pluginCommand` stays `cluster` from 1.6.1. Each gets a 1.7.1 case in its existing test.

## 2. Load Image becomes "Use local images"

- `ClusterService.supportsSharedImageStore(containerVersion:)`: `>= 1.7`. Load Image is offered only when it is false.
- `ClusterService.loadImage` refuses on 1.7+ (backstop, never runs `load-image`); the Load Image button and sheet in `ClusterDetail` hide on 1.7+.
- Create Cluster gets a **Use local images** toggle on 1.7+, on by default, which adds `--shared-image-store`. Never sent below 1.7.
- `RememberedOptions` gains `sharedImageStore: Bool?` (nil in options saved before it existed), `ClusterRecreateSettings` gains `sharedImageStore`, and Recreate passes it back.
- A cluster's detail says whether it can see local images. This is read off the control-plane node's mounts (a mount whose destination is `/opt/cluster-shim/hoststore.sock`), so it is right for a cluster made outside Orchard too; the remembered option is the fallback. A cluster without it gets a note pointing at Recreate, with the toggle on in the Recreate sheet.
- Tests: create arguments with the option, without it, and on 1.6.1 where it is never passed; recreate settings from a node with and without the mount; the remembered option round-trip.
- CHANGELOG, README and `site/clusters.html`.

## 3. Cluster nodes are managed by their cluster

Applies on every version, not just 1.7.1 (agreed 2026-11-09): stopping, killing or deleting one node breaks the cluster's kubeadm state whichever runtime does it, and Orchard already blocks Start on a node everywhere.

- `ContainerListService.stopContainer`, `forceStopContainer` and `removeContainer` refuse a node the way `startContainer` does, with an alert saying to use the cluster. `removeContainers` skips nodes.
- One shared help string for disabled actions ("Managed by cluster <name>. Stop or delete the cluster from Clusters.").
- Disabled or hidden for a node: `ContainerDetailHeader` (Stop, Force Stop, Delete), the list context menu in `ListContainers`, `UIComponents`' row actions, `MultiContainerCards` (per-card and bulk stop and delete), `MenuBarDashboard` (stop and remove), and `CommandPaletteCatalog` (no stop action for a node, as it already has no start).
- Bulk counts exclude nodes: Stop All, Start All (already), multi-select stop and delete. The filtering lives in small pure helpers so it can be tested.
- Deep links only navigate, so nothing to block there.
- Unaffected: logs, exec and terminal, stats and export on a node; the stranded legacy (`k8s`) cluster delete in `ClusterService`, which runs `container delete --force` on the CLI and so is not behind the service backstop (and upstream filters only the `cluster` label); Free Up Space, which already excludes plugin-owned containers.
- Tests: the bulk filters and counts, and the service backstop for stop, kill and delete.

## 4. `[container.dns]` defaults

- A pure `ContainerDNSDefaults` (domain, nameservers, search domains, options) and `resolveContainerDNS(spec:defaults:hostDomain:)` mirroring `Utility.dnsConfiguration`: each field set in Orchard wins, then `[container.dns]`, then `[dns].domain` for the domain. The existing rules stay: a resolver configuration is always sent, and the default nameservers are added when Orchard set a domain and neither Orchard nor `[container.dns]` gives nameservers.
- `LiveContainerBackend.createContainer` already loads the system config; it resolves DNS from it. Every create path (the form, recreate, compose, sandboxes and model servers) goes through it, so all of them follow the same precedence.
- Domain order with Orchard's own default-domain preference (agreed 2026-11-09: `config.toml` first): the container's own domain, then `[container.dns].domain`, then Orchard's chosen default, then `[dns].domain`. In the backend that is `spec.dnsDomain`, then `[container.dns].domain`, then `spec.fallbackDNSDomain`, then `[dns].domain`.
  - Compose needs no change: its fallback stays Orchard's choice, else `[dns].domain`, and the backend puts `[container.dns].domain` ahead of it, which gives the order above.
  - `DNSService.defaultDomain` becomes `[container.dns].domain`, then Orchard's choice, then `[dns].domain`, so the run form prefills the domain a container would get anyway, and the domain marked default in the DNS list matches. The defaults are read through a new `ContainerBackend.containerDNSDefaults()` on each DNS load; `daemonDNSDomain()` is unchanged.
  - A container with no domain of its own now gets `[dns].domain` as `container run` gives it, where before the Run form's "None" gave it no domain.
  - When `[container.dns].domain` is set, Settings says it takes precedence over the DNS Domain picker for new containers, rather than letting the picker look like it does nothing.
- A backend call `containerDNSDefaults()` feeds Settings: read-only rows for the `[container.dns]` nameservers, search domains, options and domain next to the DNS Domain picker, with a line saying they live in `~/.config/container/config.toml`. Hidden when none are set.
- The container form has only the DNS Domain picker: its empty choice reads "container default (<domain>)" (`[container.dns].domain`, else `[dns].domain`) when one applies. There are no nameserver, search or option fields in the form to put placeholders in; the container's detail shows what it resolved to.
- Tests: no defaults, defaults only, an Orchard field overriding a default, the domain fallback order, and the default-nameservers rule.

## Out of scope

- Worker sizing, `cluster ls --format json` and the recommended kernel: #174.
- A version range instead of one supported version: #172.
- The 1.7.1 CPU upper bound the CLI's parser now applies.

## Tasks

- [x] Pin container 1.7.1 / containerization 0.54.0 (no other pins moved); `supportedContainerVersion` 1.7.1; gate tests get 1.7.1 cases
- [x] Shared image store: gate, create flag and toggle, remembered option, recreate, detail status, Load Image hidden and refused on 1.7+
- [x] Cluster node actions: service backstop, views, bulk filters
- [x] `[container.dns]` resolution in the backend, `DNSService` defaults, Settings rows, form label
- [x] Unit tests for each part
- [x] App builds and OrchardTests pass (628 tests after the review fixes)
- [x] Smoke test on 1.7.1 (Andrew, 2026-11-09): system reports running, every tab loads, a cluster created with local images runs a pod from a locally built image, node actions are blocked, a container from the Run form picks up `[container.dns]` nameservers (after `container system stop && start`, which 1.7.1 needs to reread `config.toml`)
- [ ] Smoke test on 1.6.1: Load Image still works, gates unchanged. Not run: it needs a downgrade; the 1.6.x paths are covered by unit tests only
- [x] CHANGELOG, README (requirements, clusters, DNS) and `site/clusters.html`
