---
type: plan
status: in-progress
summary: "In full screen the main window's toolbar strip is drawn over the top of the content, hiding the list and detail headers (search, filters, sort and the add buttons) that sit in the title bar row. Track whether the window is full screen and, while it is, lay the columns out below the toolbar instead of under it, dropping the traffic-light inset that full screen doesn't need."
issues: [andrew-waters/orchard#167]
touches: [andrew-waters/orchard]
owner: andrew-waters
agreed_by: [andrew-waters]
agreed_at: 2026-11-06
---

# Keep the header buttons visible in full screen

The main window uses a unified toolbar with no title and a hidden toolbar background, and every column in `ThreeColumnLayout` ignores the top safe area so its header (search field, filter and sort menus, the add buttons; the detail headers at `.padding(.top, 20)`) shares the title bar row. In a window that works, because the title bar is transparent. In full screen AppKit moves the title bar and toolbar into their own strip at the top of the screen, which covers that row, so the headers vanish behind an empty bar.

## Design

**Know when the window is full screen.** A `tracksWindowFullScreen()` view modifier on `ContentView` follows its host window (resolved with `WindowAccessor`) and puts the state in the environment as `isWindowFullScreen`. It switches on `NSWindow.willEnterFullScreenNotification` and `willExitFullScreenNotification`, so the layout changes with the transition rather than after it, and reads the window's `styleMask` back on `didFailToEnterFullScreenNotification` and `didFailToExitFullScreenNotification` so a failed transition doesn't leave it wrong. A window restored straight into full screen is read from its `styleMask` when it resolves.

**Respect the safe area in full screen.** In `ThreeColumnLayout`, each column's `.ignoresSafeArea(.container, edges: .top)` becomes `edges: isWindowFullScreen ? [] : .top`, so in full screen the headers sit just below the toolbar strip. The windowed layout is unchanged.

**No traffic-light inset in full screen.** The `sidebarCollapsed ? 52 : 20` (and `52 : 0`) top padding keeps headers clear of the traffic lights when the sidebar is hidden (#88). Full screen has no traffic lights in that row, so it uses the normal padding there.

The logs window lays its header out inside the safe area already, so it needs nothing.

## Tasks

- [x] `isWindowFullScreen` environment value and the observer that sets it from the host window.
- [x] `ThreeColumnLayout` keeps clear of the toolbar in full screen, in both the three- and two-column arms.
- [x] Traffic-light inset only outside full screen.
- [x] CHANGELOG entry under Unreleased > Fixed.
- [x] Debug build.
- [ ] Try it by hand: enter and leave full screen on a three-column tab and a two-column tab, with the sidebar shown and hidden, and check the windowed layout is unchanged.
