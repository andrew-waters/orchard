---
type: plan
status: in-progress
summary: "Let Create Machine set the machine's account (user, UID, GID and Linux home) on container 1.6.0+, sent through Flags.MachineUser only for the fields the user changed; show the account and its home in the machine detail. Create-only, since the runtime has no way to change it later."
issues: [andrew-waters/orchard#136]
touches: [andrew-waters/orchard]
owner: andrew-waters
agreed_by: [andrew-waters]
agreed_at: 2026-10-20
---

# Set the user account when creating a machine

Apple container 1.6.0 (apple/container#2322) lets `container machine create` choose the machine's account with `--user`, `--uid`, `--gid` and `--home`. Orchard builds against 1.6.0 since #132 but always passes `Flags.MachineUser.parse([])`, so every machine gets the host user.

## What upstream does

- `MachineClient.machineConfigFromFlags(user: Flags.MachineUser, ...)` resolves the account with `Parser.userAccount`: `--user` is `name|uid[:gid]`, `--uid`/`--gid` fill what `--user` left unset, and anything left unset falls back to the host user (`NSUserName()`, `getuid()`, `getgid()`). `--home` defaults to `/home/<user>`.
- The result is stored as `UserSetup { username, uid, gid, home }` on `MachineConfiguration`, which is sent once, on create. Provisioning reapplies it on every boot.
- `setConfig` takes only the boot config (`MachineConfig`: CPUs, memory, home-mount, virtualization, kernel). There is no route that updates `MachineConfiguration`, and the docs say to override the account "at creation time". **So the account is create-only**; Edit Machine shows nothing new.
- The docs now spell out the home mount: macOS `$HOME` is mounted read-write **at the same path** (`/Users/<you>`), and root in the machine (passwordless sudo) can write anywhere in it with your macOS permissions. The Linux account's home (`/home/<user>`) is a separate directory inside the machine.

## Design

**Create Machine.** A collapsed **Account** disclosure group after Home Directory Mount, shown only when `systemService.containerVersion` is 1.6.0 or later. Four fields, all empty by default with the host's values as placeholders:

- **User**: a name only. Upstream's `name|uid[:gid]` packing duplicates the UID and GID fields and makes their precedence surprising, so the field takes a name and the numbers have fields of their own. Rejected if it is all digits (upstream would read it as a UID), contains `:`, whitespace or `/`, or is longer than 32 characters.
- **UID** and **GID**: digits only, within `UInt32`.
- **Home Directory**: an absolute path. Its placeholder follows the typed user (`/home/<user>`).

Only non-empty fields are sent, so a form left alone creates exactly what it does today. Validation errors use the existing red caption under the form.

**Boundary.** `MachineCreateSpec` gains `account: MachineAccountSpec` (`user`, `uid`, `gid`, `home`, all optional, app-owned). `LiveMachineBackend` turns it into CLI-style arguments and parses them with `Flags.MachineUser.parse(_:)`, so upstream's own parsing and defaults apply. That translation is a free function so it can be unit-tested without XPC.

**Detail.** `MachineUserSetup` gains `home`. The existing "User" row moves up next to Home Mount as **Account** (`devuser (uid 1500, gid 1600)`), with a **Linux Home** row under it.

**Version gating.** `ClusterService.isContainerVersion(_:atLeast:)` moves to a shared free function beside `supportedContainerVersion`, and `MachineService.supportsUserAccount(containerVersion:)` uses it. On 1.5.x the group is hidden and creation is unchanged.

**Copy.** `homeMountCaption` names the mount path and the sudo consequence, for example: read/write "Your Mac home folder is mounted at the same path. Anything in the machine, including root via sudo, can change your files." The site's pitfall and the README get the same correction, and the site's "mapped in automatically" sentence says the account can now be chosen.

## Tasks

- [ ] Shared `isContainerVersion(_:atLeast:)`; `MachineService.supportsUserAccount(containerVersion:)`
- [ ] `MachineAccountSpec` on `MachineCreateSpec`; argument building and `Flags.MachineUser.parse` in `LiveMachineBackend.createMachine`
- [ ] `MachineUserSetup.home`, mapped from `UserSetup.home`; mocks and UI-test fixture updated
- [ ] Create Machine: Account group, placeholders, validation (pure function), gated on 1.6.0
- [ ] Detail: Account and Linux Home rows beside Home Mount
- [ ] `homeMountCaption` rewritten against upstream's wording
- [ ] Unit tests: argument building (empty, each field, all fields), validation, version gate, mapping of `home`
- [ ] Build; OrchardTests pass
- [ ] Smoke test on 1.6.0: a machine created with user, UID, GID and home reports them from `id` and `echo $HOME`; one created with defaults matches the host user; the detail view shows the account
- [ ] README Container Machines section, site machines guide, CHANGELOG

## Out of scope

- Changing a machine's account after creation: the runtime has no way to do it.
- Accepting upstream's packed `name|uid[:gid]` form in the User field.
