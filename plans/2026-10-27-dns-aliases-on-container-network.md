---
type: plan
status: done
summary: "DNS aliases on a container's network attachment on container 1.6.0+: an Aliases list in the Run and Edit form, qualified with the container's DNS domain and sent in the XPC create, with the hostname now qualified the same way, as `container run` does. Aliases show in container detail, the Networks and DNS views and Cmd+K. Edit keeps the network, DNS domain and aliases on recreate."
issues: [andrew-waters/orchard#134]
touches: [andrew-waters/orchard]
owner: andrew-waters
agreed_by: [andrew-waters]
agreed_at: 2026-10-27
---

# DNS aliases on container network attachments

apple/container 1.6.0 adds aliases to network attachments (apple/container#2390): `--network default,alias=api,alias=.gateway`. With default domain `test` the container answers to `gateway.test`, `api.test` and every name below `gateway.test`. Orchard builds against 1.6.1, which leaves aliases as 1.6.0 had them.

## What upstream does

- `AttachmentOptions(hostname:macAddress:mtu:aliases:)` takes aliases in their normalised form: lowercase, no trailing dot, a leading dot for a subtree. Storage leaves the key out when there are none, and older configurations decode with none.
- The client qualifies them: `Utility.qualifyAliases` adds the default domain to a name with no dot (for a subtree, to the name after the leading dot). It is internal, so Orchard does the same itself.
- The client also qualifies the first attachment's hostname: `<id>.<domain>.` when the id has no dot, `<id>.` when it has one, and the bare id when there is no domain.
- The server checks the rules (`AliasPolicy`, `AttachmentNameValidator`) at create, at start and in the network helper. A subtree alias must sit below the hostname or an exact alias, so `.gateway.test` needs the hostname `gateway.test`.

## What changes in Orchard

### Hostname follows the CLI

Orchard sent the bare container id as the hostname. It now qualifies it the way `container run` does. The domain is the container's own DNS domain (`spec.dnsDomain`): Orchard keeps the default domain as its own preference (#116), and the form fills that domain in, so it stands where the CLI uses the daemon's `dns.domain`. A container with no DNS domain keeps the bare id, as with the CLI. Compose sends no DNS domain, so compose hostnames do not change.

### Aliases

- `supportsNetworkAliases(containerVersion:)`: 1.6.0 or later.
- `ContainerRunConfig.networkAliases` (rows, like labels) and `ContainerCreateSpec.networkAliases`. The create qualifies them with the DNS domain and puts them on the attachment. The only client-side check is dropping empty or whitespace-only rows; the runtime's errors reach the sheet as they are.
- `ContainerConfiguration.networkAliases`, keyed by network id, read from the stored configuration so it covers stopped containers and CLI containers on several networks.
- Edit fills in the network, DNS domain and aliases, so Save & Recreate keeps them (it dropped the network and domain before). Recovery and the mount-removal recreate carry aliases too. Stored aliases are already qualified, so qualifying them again changes nothing.

### Where aliases show

- The form: an Aliases list under Network on the Basic tab, shown on 1.6.0+, with the names it will produce.
- Container detail: an Aliases row by the hostname, in the overview and in each network's block. A subtree alias reads `*.gateway.test`.
- `ContainerTable`: the aliases under the hostname. The Networks view now shows the attachment for that network rather than the first one.
- DNS domain detail: also lists containers with an alias under the domain.
- Cmd+K: aliases, and the base of each subtree alias, are search keywords for the container.

Display follows the data: a runtime older than 1.6.0 never stores aliases.

## Out of scope (follow-ups to file)

- Compose: honour `networks.<net>.aliases` in the compose package, then bump Orchard.
- Clusters: a one-click gateway container answering for `*.gateway.test` in front of an ingress.

## Tasks

- [x] Alias helpers: version gate, qualification, hostname, display form, keywords
- [x] Create path: qualified hostname and aliases on the attachment
- [x] Model and mapping: `networkAliases` on the configuration
- [x] Form: Aliases list; Edit fills in network, DNS domain and aliases; recovery and mount removal carry aliases
- [x] Display: detail, `ContainerTable`, Networks and DNS views, Cmd+K
- [x] Tests: helpers, spec, mapping, palette, edit prefill
- [x] README, site and CHANGELOG
- [x] One build and unit test pass (543 passed)
- [x] Manual check on 1.6.1 with the domain `stack`: `api.stack` and `x.gateway.stack` resolve from another container, a duplicate alias shows the runtime's error in the sheet, aliases show in detail, Networks, DNS and Cmd+K, and Edit keeps them
- [x] Found while checking: the Run sheet hid a failed create (its alert can't appear over a sheet), so the sheet now shows the error itself; the Containers list's context menu offered Remove for running containers, so it now offers it only for stopped ones
