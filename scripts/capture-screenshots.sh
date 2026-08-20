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
  "$AX" press "sidebar-$tab" || { echo "skip $tab"; continue; }
  sleep 1.5   # let the tab load and charts settle
  WID=$("$AX" window-id)
  screencapture -x -l "$WID" "$OUT/$tab.png"
  echo "captured $OUT/$tab.png"
done
echo
echo "Committed with the site, these serve at https://orchard.andon.dev/assets/screens/<tab>.png"
