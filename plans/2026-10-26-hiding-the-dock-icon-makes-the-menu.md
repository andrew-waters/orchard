---
type: plan
status: in-progress
summary: "Replace the Hide Dock icon toggle with a Show Dock Icon choice: Always, While a Window Is Open (regular app while any Orchard window is open, menu-bar accessory once the last closes) or Never (the old accessory behaviour). A toggle left on migrates to While a Window Is Open. Add Settings and Quit to the menu bar panel so they're always reachable."
issues: [andrew-waters/orchard#142]
touches: [andrew-waters/orchard]
owner: andrew-waters
agreed_by: [andrew-waters]
agreed_at: 2026-10-26
---

# Keep the menu bar when the Dock icon is hidden

With "Hide Dock icon" on, `DockIconPolicy` sets the activation policy to `.accessory` for the app's whole run. AppKit gives an accessory app no menu bar of its own (the previous app's menu, often Finder's, stays up), full screen doesn't behave, and the app leaves Cmd-Tab. The menu bar panel only offers "Open Orchard", so with the main menu gone Settings and Quit can't be reached, and the setting can't be turned back off.

## Design

**A choice of three, not a toggle.** Some people want Orchard in the menu bar only and accept losing its main menu and full screen; others want those while they work in a window. macOS can't give a window its app's menu bar without a Dock icon, so this is the user's choice. `DockIconMode` replaces the bool:

- **Always**: `.regular` all the time. The default.
- **While a Window Is Open**: `.regular` while any of Orchard's own windows (main, logs, Settings) is open or minimised, and `.accessory` once the last one closes. The menu bar panel and other panels don't count. `DockIconPolicy` watches `NSWindow.didBecomeKeyNotification` and `NSWindow.willCloseNotification` only in this mode and re-evaluates the policy on each, leaving out the window that is closing.
- **Never**: `.accessory` all the time, the old Hide Dock icon behaviour. The footer says plainly that windows don't get the menu bar or full screen in this mode.

**Migration.** The mode is stored as a string under `OrchardDockIconMode`. With nothing stored, the old `OrchardHideDockIcon` bool decides: on becomes While a Window Is Open, so nobody upgrades into the stuck state from #142, and off becomes Always. Choosing a mode removes the old key.

**Settings and Quit in the menu bar panel.** The "Open Orchard" card gains a Settings button (SwiftUI's `openSettings`, with the app activated first so the window comes forward) and a Quit button. In Never mode they are the only way to reach either without a window.

**Copy.** The toggle becomes a "Show Dock Icon" picker, and its footer describes the chosen mode.

## Tasks

- [x] `DockIconMode` with migration from the old toggle, stored by `SettingsStore`.
- [x] `DockIconPolicy` applies each mode, following Orchard's windows in While a Window Is Open.
- [x] Settings and Quit buttons in the menu bar panel.
- [x] Show Dock Icon picker and per-mode footer.
- [x] `SettingsStore` tests for the mode and the migration.
- [x] CHANGELOG entry under Unreleased > Fixed.
- [x] Debug build and `SettingsStoreTests`.
- [x] Try it by hand: each mode, switching between them, relaunching, and Settings and Quit from the panel.
