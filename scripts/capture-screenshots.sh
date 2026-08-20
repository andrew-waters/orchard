#!/bin/bash
# Capture a retina window screenshot of every Orchard tab (for the site / PRs).
#
# Drives the running app through the accessibility API: clicks each sidebar row by
# its accessibility identifier, waits for the tab to settle, and captures the main
# window (with shadow) via screencapture.
#
# One-time permissions for your terminal app (System Settings → Privacy & Security):
#   - Accessibility (to click the sidebar)
#   - Screen Recording (to capture the window)
#
# Usage: ./scripts/capture-screenshots.sh [output-dir]   (default: site/assets/screens)
#
# The default lands where both consumers can use the files directly:
#   - GH Pages serves them at https://orchard.andon.dev/assets/screens/<tab>.png
#   - the README can embed them as site/assets/screens/<tab>.png
# Re-run and commit to refresh the screenshots everywhere at once.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-site/assets/screens}"
AX="scripts/.build/orchard-ax"

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
echo
echo "Committed with the site, these serve at https://orchard.andon.dev/assets/screens/<tab>.png"
