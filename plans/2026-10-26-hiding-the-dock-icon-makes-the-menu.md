---
type: plan
status: in-progress
summary: "With Hide Dock icon on, run Orchard as a regular app while any of its windows is open (menu bar, full screen, Cmd-Tab) and as a menu-bar accessory only once the last window closes. Add Settings and Quit to the menu bar panel so they're always reachable."
issues: [andrew-waters/orchard#142]
touches: [andrew-waters/orchard]
owner: andrew-waters
agreed_by: [andrew-waters]
agreed_at: 2026-10-26
---

# Keep the menu bar when the Dock icon is hidden

With "Hide Dock icon" on, `DockIconPolicy` sets the activation policy to `.accessory` for the app's whole run. AppKit gives an accessory app no menu bar of its own (the previous app's menu, often Finder's, stays up), full screen doesn't behave, and the app leaves Cmd-Tab. The menu bar panel only offers "Open Orchard", so with the main menu gone Settings and Quit can't be reached, and the setting can't be turned back off.

## Design

**Dock icon only while windows are open.** With the setting on, Orchard is `.regular` while any of its own windows (main, logs, Settings) is open or minimised, and `.accessory` once the last one closes. The menu bar panel and other panels don't count. `DockIconPolicy` watches `NSWindow.didBecomeKeyNotification` and `NSWindow.willCloseNotification` while the setting is on and re-evaluates the policy on each, leaving out the window that is closing. Turning the setting off stops observing and goes back to `.regular`, as before. At launch the policy starts as `.accessory` and the main window, if one opens, switches it to `.regular`.

**Settings and Quit in the menu bar panel.** The "Open Orchard" card gains a Settings button (SwiftUI's `openSettings`, with the app activated first so the window comes forward) and a Quit button, so both are reachable whatever the Dock setting is.

**Copy.** The toggle reads "Hide Dock icon when no windows are open", and its footer explains that Orchard shows its Dock icon and menu bar while a window is open.

## Tasks

- [x] `DockIconPolicy` switches between `.regular` and `.accessory` as Orchard's windows open and close.
- [x] Settings and Quit buttons in the menu bar panel.
- [x] Toggle label and footer copy.
- [x] CHANGELOG entry under Unreleased > Fixed.
- [x] Debug build.
- [ ] Try it by hand: menu bar and full screen with a window open, Dock icon gone once it closes, Settings and Quit from the panel.
