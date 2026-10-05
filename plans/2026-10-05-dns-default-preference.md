---
issues: [andrew-waters/orchard#116]
summary: Keep the default DNS domain as an Orchard preference instead of calling the removed `container system property set` command.
status: done
pr: andrew-waters/orchard#117
---

# Default DNS domain as an Orchard preference

## Problem

Making a DNS domain the default fails with `Error: 3 unexpected arguments: 'set', 'dns.domain', '<domain>'`.

Since container 1.0, `container system property` only has `list`. The default DNS domain is now `[dns] domain`
in `~/.config/container/config.toml`, and the `container` service reads that file only at startup. Orchard
still runs `container system property set dns.domain <domain>` from two places:

- `DNSService.setDefault` (`Orchard/Services/DNSService.swift`): **Make Default** in the DNS list and the
  detail header.
- `SystemService.setSystemProperty` (`Orchard/Services/SystemService.swift`): the **DNS Domain** picker in
  Settings > General.

Both fail on container 1.4.1 and 1.5.0.

## Approach

Store the default domain as an Orchard preference. Orchard creates containers through the API backend and
already passes `spec.dnsDomain` (`ContainerBackend.swift`). The create form fills that from the domain marked
`isDefault` (`ContainerConfigForm.swift`), so a preference already reaches every container Orchard creates.

When no preference is set, Orchard shows the `dns.domain` system property as the default, so a value set in
`config.toml` still appears.

### Considered and set aside

Writing `[dns] domain` into `~/.config/container/config.toml` would make the default apply to the `container`
CLI too. It only takes effect after `container system stop` and `start`, which stops every running container,
and Orchard would have to edit the user's TOML file without a TOML library. We can add it later as an opt-in
("also write to config.toml, restart required") if people ask for it.

## Tasks

- [x] `SettingsStore`: add `defaultDNSDomain` (`@Published private(set)`), stored in `UserDefaults`, with
      `setDefaultDNSDomain(_:)`, following the existing settings pattern.
- [x] `DNSService`: work out the default from the preference, using the `dns.domain` system property when the
      preference is empty. A chosen domain that a successful list no longer returns (deleted in bulk or outside
      Orchard) is cleared on load. Deleting the default from Orchard is still refused, as before.
- [x] `DNSService.setDefault`: save the preference and re-mark the list. It runs no CLI
      command.
- [x] Settings > General: point the DNS Domain picker at `dnsService.setDefault`, add a "None" option, and
      update the footer to say the default applies to containers Orchard creates.
- [x] Remove the dead write path: `SystemService.setSystemProperty`, `setDNSDomainPropertyOptimistically`,
      `revertDNSDomainIfNeeded`, the `markDNSDefault`, `reloadDNS` and `setDefaultDomainProperty` hooks, and
      their wiring in `AppServices.swift`. `dnsService.defaultDomain` becomes `daemonDefaultDomain`, kept only for reading the fallback.
- [x] Tests for `DNSService` and `SettingsStore`: `setDefault` runs no command and saves the preference; the
      preference beats the property; the property is used when there's no preference; a chosen domain that's
      gone is cleared on load, but not when the list fails; the preference persists. One pass
      of the unit test target at the end (415 passed).
- [x] CHANGELOG entry under Unreleased.
- [x] Pull request with "Closes andrew-waters/orchard#116":
      [andrew-waters/orchard#117](https://github.com/andrew-waters/orchard/pull/117).

## Verification

- Unit tests above.
- Driven in a debug build through Accessibility against container 1.5.0 on 2026-10-05; all passed with no
  error alerts:
  - [x] Make Default from the DNS list's context menu and from the detail header: the DEFAULT marker moves,
        the header button disables, and the preference is saved.
  - [x] Settings > General picker: choosing a domain moves the DEFAULT marker, and None clears it and the
        preference.
  - [x] Run Container's DNS Domain starts on the default, and `container inspect` shows it in `dns.domain`.
  - [x] The default survives a relaunch.
  - [x] A default domain deleted with the CLI is dropped from the list and the preference is cleared.
  - [x] With `[dns] domain` in `config.toml` and no preference, the picker offers "container default
        (<domain>)" and that domain is DEFAULT; picking another domain overrides it, and picking the
        container default goes back to it.

## Notes

- The `container` service copies `config.toml` into
  `~/Library/Application Support/com.apple.container/config/config.toml` when it starts, and keeps using that
  copy after the original is deleted. Removing `[dns] domain` therefore means editing the file (or deleting
  both copies) and restarting the service. Orchard only reads the merged value through
  `container system property list`, so this doesn't affect the fix.

## Progress

- 2026-10-05: Plan written and agreed.
- 2026-10-05: Preference, `DNSService` changes, Settings picker, removal of the old write path, tests and
  CHANGELOG entry landed; the `OrchardTests` target passed (415 tests).
- 2026-10-05: Manual testing in a debug build against container 1.5.0, all steps passed (see Verification).
- 2026-10-05: Opened [andrew-waters/orchard#117](https://github.com/andrew-waters/orchard/pull/117).
