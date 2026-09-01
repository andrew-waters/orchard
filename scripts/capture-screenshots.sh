#!/bin/bash
# Capture a retina window screenshot of every Orchard tab (for the site / PRs),
# plus the menu bar panel (with a container's hover popover), the ⌘K command
# palette, and a split-pane logs window.
#
# Drives the running app through the accessibility API: clicks each sidebar row by
# its accessibility identifier, waits for the tab to settle, and captures the main
# window (with shadow) via screencapture.
#
# One-time permissions for your terminal app (System Settings → Privacy & Security):
#   - Accessibility (to click the sidebar)
#   - Screen Recording (to capture the window)
#   - Automation → System Events (only for --light / --dark, to flip the appearance)
#
# Usage: ./scripts/capture-screenshots.sh [--light|--dark] [output-dir]
#   default output: site/assets/screens (site/assets/screens/light with --light)
#
# --light / --dark switch the system appearance for the duration of the run and
# restore your previous setting afterwards, so the app re-renders in that theme
# without a relaunch - the window keeps its geometry, and the captures pair
# pixel-for-pixel with the other theme's set. The site swaps to the light set
# automatically in light mode (see site/theme.js).
#
# The default lands where both consumers can use the files directly:
#   - GH Pages serves them at https://orchard.andon.dev/assets/screens/<tab>.png
#   - the README can embed them as site/assets/screens/<tab>.png
# Re-run and commit to refresh the screenshots everywhere at once.
set -euo pipefail
cd "$(dirname "$0")/.."

APPEARANCE=""
if [[ "${1:-}" == "--light" ]]; then APPEARANCE="light"; shift; fi
if [[ "${1:-}" == "--dark" ]]; then APPEARANCE="dark"; shift; fi

DEFAULT_OUT="site/assets/screens"
[[ "$APPEARANCE" == "light" ]] && DEFAULT_OUT="site/assets/screens/light"
OUT="${1:-$DEFAULT_OUT}"
AX="scripts/.build/orchard-ax"

# Flip the system appearance for the run, restoring the previous setting on exit.
if [[ -n "$APPEARANCE" ]]; then
  WANT_DARK=false
  [[ "$APPEARANCE" == "dark" ]] && WANT_DARK=true
  PREV_DARK=$(osascript -e 'tell application "System Events" to tell appearance preferences to get dark mode')
  if [[ "$PREV_DARK" != "$WANT_DARK" ]]; then
    osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $WANT_DARK"
    trap 'osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $PREV_DARK"' EXIT
    sleep 2   # let the app re-render in the new appearance
  fi
fi

# Compile the AX helper on first run (or when its source changes).
if [[ ! -x "$AX" || scripts/orchard-ax.swift -nt "$AX" ]]; then
  mkdir -p scripts/.build
  echo "Compiling accessibility helper…"
  xcrun swiftc -O -sdk "$(xcrun --show-sdk-path --sdk macosx)" scripts/orchard-ax.swift -o "$AX"
fi

mkdir -p "$OUT"
pgrep -x Orchard >/dev/null || { echo "Start Orchard first"; exit 1; }
osascript -e 'tell application "Orchard" to activate'
sleep 1

TABS="dashboard containers clusters machines sandboxes models images mounts dns networks"
for tab in $TABS; do
  # Fail hard: a missed selection would silently save the wrong view under this name.
  "$AX" press "sidebar-$tab" || { echo "could not select the $tab tab"; exit 1; }
  sleep 1.5   # let the tab load and charts settle
  if [[ "$tab" == "containers" ]]; then
    # The k8s node has the liveliest charts and shows the plugin badge + cluster banner.
    "$AX" press-text "k8s-dev" || { echo "could not select the k8s-dev container"; exit 1; }
    sleep 2
  fi
  WID=$("$AX" window-id)
  if ! screencapture -x -l "$WID" "$OUT/$tab.png" 2>/dev/null || [[ ! -s "$OUT/$tab.png" ]]; then
    echo
    echo "Capture failed ('could not create image from window' means the Screen"
    echo "Recording permission is missing). Grant it to your terminal app under"
    echo "System Settings → Privacy & Security → Screen & System Audio Recording,"
    echo "then QUIT AND REOPEN the terminal app - the grant only applies after a"
    echo "restart - and re-run this script."
    exit 1
  fi
  echo "captured $OUT/$tab.png"
done

# Menu bar panel: toggle it open via the status item, hover a running container so its
# resource-history popover opens to the left, then composite panel + popover into one
# shot. MENUBAR_HOVER picks the container to hover (must be running).
MENUBAR_HOVER="${MENUBAR_HOVER:-k8s-dev}"
"$AX" menubar-click || { echo "could not open the menu bar panel"; exit 1; }
sleep 2.5   # let the rings and container rows settle
"$AX" hover-text "$MENUBAR_HOVER" || { echo "could not hover the $MENUBAR_HOVER row in the panel"; exit 1; }
sleep 2     # popover open + its charts settle
if ! "$AX" capture-panels "$OUT/menubar.png" || [[ ! -s "$OUT/menubar.png" ]]; then
  echo "menu bar panel capture failed"; exit 1
fi
"$AX" menubar-click >/dev/null || true   # close it again
echo "captured $OUT/menubar.png"

# Command palette: over the k8s-dev container detail, open ⌘K and type a query.
# Never click inside the window here: the palette dismisses on any click outside its
# panel, and its search field focuses itself on open - typing lands there directly.
PALETTE_QUERY="${PALETTE_QUERY:-logs api}"
"$AX" press "sidebar-containers" && sleep 1
"$AX" press-text "k8s-dev" || true
sleep 1
"$AX" key escape && sleep 0.5   # ⌘K toggles - make sure no palette is already open
"$AX" key cmd+k && sleep 1
"$AX" type "$PALETTE_QUERY" && sleep 1.5
WID=$("$AX" window-id)
if ! screencapture -x -l "$WID" "$OUT/palette.png" 2>/dev/null || [[ ! -s "$OUT/palette.png" ]]; then
  echo "palette capture failed"; exit 1
fi
"$AX" key escape && sleep 0.5
echo "captured $OUT/palette.png"

# Split logs: open LOGS_TARGET's logs window from its detail-header Logs button,
# add a second pane (it auto-selects the first running container), and capture.
LOGS_TARGET="${LOGS_TARGET:-k8s-dev}"
"$AX" press "sidebar-containers" && sleep 1
"$AX" press-text "$LOGS_TARGET" || { echo "could not select the $LOGS_TARGET container"; exit 1; }
sleep 1
"$AX" press-text "Logs" || { echo "could not find the Logs button in the detail header"; exit 1; }
sleep 3                          # the logs window opens and the first fetch lands
"$AX" press-text "Split" || { echo "could not find the Split button"; exit 1; }
sleep 3                          # second pane loads its logs
WID=$("$AX" window-id)           # frontmost large window - the logs window
if ! screencapture -x -l "$WID" "$OUT/logs.png" 2>/dev/null || [[ ! -s "$OUT/logs.png" ]]; then
  echo "logs capture failed"; exit 1
fi
"$AX" key cmd+w && sleep 0.5     # close the logs window
echo "captured $OUT/logs.png"

echo
echo "Committed with the site, these serve at https://orchard.andon.dev/assets/screens/<tab>.png"
