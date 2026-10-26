---
type: plan
status: in-progress
summary: "Treat a sandbox as an isolated workload rather than a container wired to a model: the `com.orchard.sandbox` label alone makes one, with an optional model endpoint, an owner (`com.orchard.sandbox.owner`) and a network mode (`com.orchard.sandbox.network`). The Sandbox tab shows how each one is contained (network, mounts, CPU and memory, owner), groups them by owner, and a sandbox another app owns, such as a Gannin session, is badged and warns before it is stopped or removed from anywhere in Orchard."
issues: [andrew-waters/orchard#122]
touches: [andrew-waters/orchard]
owner: andrew-waters
agreed_by: [andrew-waters]
agreed_at: 2026-10-26
---

# A sandbox is an isolated workload, with or without a model

`SandboxMarker` and the views around it describe a sandbox as "a workload wired to a local model". Detection already accepts the label alone (`hasLabel || endpoint != nil` in `Sandbox.from`), but everything a sandbox shows is about its model: the list's sections read "Wired by Orchard", the detail shows an endpoint and a host-only line, and the badges say "wired to a local model". Gannin is about to run sessions in containers labelled `com.orchard.sandbox=true` with no model, owned by Gannin, and Orchard would let anyone stop or remove one mid-session without a word.

## Approach

### Label contract

| Label | Meaning |
|---|---|
| `com.orchard.sandbox=true` | A sandbox. The label alone is enough. |
| `com.orchard.sandbox.owner` | The app that manages it, such as `dev.andon.gannin`. Orchard stamps `dev.andon.orchard`; absent also means Orchard's own. |
| `com.orchard.sandbox.network` | `nat`, `host-only` or `allowlist`. |
| `com.orchard.model.endpoint` | Optional, as today. |

### `SandboxMarker`

- New keys `ownerLabelKey` and `networkLabelKey`.
- `orchardOwner = "dev.andon.orchard"`, the identifier Orchard already uses for its log subsystem, URL scheme and keychain service. The app's bundle ID is left as it is.
- `owner(labels:) -> String?`: the owner label, nil when absent, empty or `dev.andon.orchard`, so Orchard's own sandboxes, old (absent) and new (stamped), read the same.
- `SandboxNetworkMode` (`nat`, `hostOnly`, `allowlist`) with `init?(label:)` for `nat` / `host-only` / `allowlist`.
- `networkMode(labels:observed:)`, where what Orchard sees of the network is host-only, egress or unknown (not named, or not in the list yet). Host-only observed is `hostOnly` whatever the label says; on a network with egress a `host-only` label is not believed (`nat`), while `allowlist` stands since an allow list can't be seen from the network; only when the network is unknown does the label decide alone. `nat` with no label.
- `labels(endpoint:networkMode:)` stamps the marker, the owner `dev.andon.orchard`, the endpoint and the network mode. The New Sandbox sheet passes `hostOnly` when the chosen network is host-only, else `nat`.
- `chatAPIStyle` and `modelEndpoint` unchanged: the env heuristic still finds sandboxes made elsewhere.

### `Sandbox`

- `Source` becomes `orchard`, `owned(by: SandboxOwner)` and `detected` (env heuristic only, no label).
- `SandboxOwner`: the raw ID plus a display name and a badge, from a small table of known owners (`dev.andon.gannin` is "Gannin", badged "Gannin session"); an unknown owner shows its ID for both.
- New fields: `networkMode`, `mounts` (destination, source, read-only from the `ro` option, tmpfs as a mask), `cpus`, `memoryBytes`. `isIsolated` becomes `networkMode == .hostOnly`.
- The network a stopped container belongs to comes from `configuration.networkName` when `networks` is empty (it is while stopped), so a stopped host-only sandbox no longer reads "Egress open".
- `Container.sandboxOwner` alongside `isSandbox`, for the container views.

### Sandbox tab

- List sections: "Orchard", one per other owner (by display name, such as "Gannin"), then "Detected". Rows say the network mode ("Host-only", "Allow list", "Egress open") and the owner badge for an owned sandbox.
- Detail: header badges for network mode and owner; rows for owner, network mode and network, CPU and memory, and model endpoint only when there is one; a Mounts section listing each mount as read-only, read-write or masked (tmpfs). Chat appears only when there is an endpoint the tester speaks, as today.
- Detail actions: Stop while running, and Delete when stopped (new here, to match the container header), both through the owner confirmation.
- Empty state and the network caption reworded so a model is one thing a sandbox may have, not the definition.

### Warning before acting on another app's sandbox

- A shared `OwnedSandboxConfirmation` (pure): given the action and the target containers, nil when none is a sandbox another app manages, else a title and message naming them and their owner(s), such as "Stop a sandbox Gannin manages?" / "Gannin manages this sandbox. Stopping it here can interrupt work in progress, and Gannin may not expect it."
- `ownedSandboxConfirmation(_:)`, a view modifier that presents that confirmation and runs the action only on confirm; with no owned sandbox among the targets the action runs straight away, so nothing changes for ordinary containers.
- Applied at every stop, force stop and remove entry point: container detail header (Stop, Delete, and Edit Configuration, which recreates the container), list context menu (single and multi-select), the group "Stop All" menu, multi-select cards, the Cmd+K palette's stop action, the menu bar dashboard (Stop, Remove, asked inline in the panel rather than in an alert) and the Sandbox detail (Stop, Delete). A bulk action warns once for the whole set.
- Compose's own teardown and Orchard-internal recreate paths are not user requests on a sandbox and are left alone.

### Container views

- The "sandbox" badge, its popover and the membership banner say "isolated workload" rather than "wired to a local model", name the owner when there is one, and show the endpoint only when there is one.

### Docs

- README "Local AI & Sandboxes": a sandbox is any container labelled `com.orchard.sandbox=true`; the label contract table; owned sandboxes and the warning.
- CHANGELOG under Unreleased > Added / Changed.

### Tests

- `SandboxMarker`: label alone; label with endpoint; environment only; owner present, absent, empty and `dev.andon.orchard`; network mode from label, unknown label value, and the host-only observation overriding the label; stamped labels round-trip with the network mode.
- `Sandbox.from`: a labelled container with no endpoint and no model env is a sandbox with no chat API; owned source and known/unknown owner names; mounts (read-only, read-write, tmpfs), CPU and memory carried over; stopped container's network from `networkName`.
- `OwnedSandboxConfirmation`: no owned targets means no prompt; one owned; a mixed bulk set; two different owners.

## Tasks

- [x] `SandboxMarker`: owner, network mode, stamped labels
- [x] `Sandbox`: sources, owner, network mode, mounts, resources, stopped network
- [x] Sandbox tab list and detail, including Delete
- [x] `OwnedSandboxConfirmation` and its confirmation at every stop and remove entry point
- [x] Container badge, popover and banner wording
- [x] Tests
- [x] README and CHANGELOG

## Open questions

None.

**Decisions:**

- Where does the warning apply? **Every user entry point that stops, force stops or removes a container, bulk and menu bar included.**
- Does Orchard stamp an owner on its own sandboxes? **Yes, `dev.andon.orchard`; absent still counts as Orchard's for sandboxes made before this. The bundle ID is not renamed.**
- Label and observed network disagree? **What Orchard sees wins: host-only observed is host-only, and a host-only claim on a network with egress is NAT. The label decides alone only when the network is unknown.**
- Edit Configuration recreates the container. **It warns like a remove for another app's sandbox.**
