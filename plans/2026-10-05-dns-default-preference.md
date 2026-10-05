---
issues: [andrew-waters/orchard#116]
summary: Keep the default DNS domain as an Orchard preference instead of calling the removed `container system property set` command.
status: proposed
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

- [ ] `SettingsStore`: add `defaultDNSDomain` (`@Published private(set)`), stored in `UserDefaults`, with
      `setDefaultDNSDomain(_:)`, following the existing settings pattern.
- [ ] `DNSService`: work out the default from the preference, using the `dns.domain` system property when the
      preference is empty. Deleting the default domain clears the preference.
- [ ] `DNSService.setDefault`: save the preference and update the list with `markDefault`. It runs no CLI
      command.
- [ ] Settings > General: point the DNS Domain picker at `dnsService.setDefault`, add a "None" option, and
      update the footer to say the default applies to containers Orchard creates.
- [ ] Remove the dead write path: `SystemService.setSystemProperty`, `setDNSDomainPropertyOptimistically`,
      `revertDNSDomainIfNeeded`, the `markDNSDefault`, `reloadDNS` and `setDefaultDomainProperty` hooks, and
      their wiring in `AppServices.swift`. `dnsService.defaultDomain` stays, but only for reading the fallback.
- [ ] Tests for `DNSService`: `setDefault` runs no command and saves the preference; the preference beats the
      property; the property is used when there's no preference; deleting the default domain clears the
      preference. One test pass at the end, limited to the affected test classes.
- [ ] CHANGELOG entry under Unreleased.
- [ ] Pull request with "Closes andrew-waters/orchard#116".

## Verification

- Unit tests above.
- In the app, against container 1.5.0: Make Default from the DNS list and the detail header, and pick a domain
  in Settings > General. None of these should show an error. A new container's create form should then default
  to that domain, and `container inspect` should show it under `dns.domain`.
