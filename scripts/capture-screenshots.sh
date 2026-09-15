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
# Before capturing anything it waits for the charts to have history behind them, so no shot
# goes out with a chart holding three points in the corner of it. Five minutes of the app
# running and on screen is enough (see HISTORY_TARGET below for why), and leaving the demo
# environment up between runs means it usually costs nothing at all.
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
# The container the menu bar shot hovers (must be running). Named here rather than beside that
# shot because the chart-history wait below measures this container's series too.
MENUBAR_HOVER="${MENUBAR_HOVER:-k8s-dev}"

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

# Chart history. An environment that has only just come up draws a few points in the corner of
# every chart. Orchard samples every 2s while a stats view is on screen (10s otherwise) and
# writes stats-history.json about once a minute, so this waits on that file rather than on a
# blind sleep: samples are wall-clock stamped and survive relaunches, so an environment that has
# already been up long enough passes straight through.
#
# Coverage is unbroken time back from the newest sample, not newest minus oldest. A stopped and
# restarted environment leaves a gap, the charts draw gaps as gaps instead of joining across
# them, and a window spanning one is not full. Measured on MENUBAR_HOVER's series when it has
# one, since that container is the subject of the shot with the widest window, otherwise on
# whichever series has the most coverage.
HISTORY_FILE="$HOME/Library/Application Support/Orchard/stats-history.json"
# 5m is the window the main-window panels open on (ResourceStatsPanel, SystemStatsDashboard),
# and those are the charts with a real time axis to fill. The menu bar popover names a 1h window
# but does not plot one: HistoryBars stretches however many values it has across the full width,
# thinned to 120 bars, so it fills on sample count rather than elapsed time, and 5m at the 2s
# cadence is already ~150 samples. Raise this only to make that hour's worth of bars genuinely
# span an hour.
HISTORY_TARGET="${HISTORY_TARGET:-300}"
HISTORY_MAX_GAP="${HISTORY_MAX_GAP:-60}"   # a sampling pause longer than this breaks the line
HISTORY_POLL="${HISTORY_POLL:-60}"         # matches how often Orchard writes the file
HISTORY_STALL_LIMIT="${HISTORY_STALL_LIMIT:-5}"   # polls without progress before giving up

# Prints "<covered-seconds> <staleness-seconds>". Never fails the script: an unreadable or
# not-yet-written file reads as no coverage, which the loop reports and keeps waiting on.
history_coverage() {
  python3 - "$HISTORY_FILE" "$HISTORY_MAX_GAP" "$1" <<'PY'
import json, sys, time

path, max_gap, preferred = sys.argv[1], float(sys.argv[2]), sys.argv[3]

def coverage(samples):
    """Unbroken seconds back from the newest sample, stopping at the first real pause."""
    stamps = sorted(s["timestamp"] for s in samples)
    covered = 0.0
    for i in range(len(stamps) - 1, 0, -1):
        gap = stamps[i] - stamps[i - 1]
        if gap > max_gap:
            break
        covered += gap
    return covered, (stamps[-1] if stamps else None)

try:
    series = json.load(open(path)).get("series", [])
except Exception:
    print("0 0")
    raise SystemExit

best = (0.0, None)
for entry in series:
    samples = entry.get("samples") or []
    if not samples:
        continue
    result = coverage(samples)
    if entry.get("id") == preferred:
        best = result
        break
    if result[0] > best[0]:
        best = result

covered, newest = best
# Foundation stamps dates from 2001-01-01, which is what the JSON carries.
stale = 0.0 if newest is None else max(0.0, (time.time() - 978307200.0) - newest)
print(f"{int(covered)} {int(stale)}")
PY
}

if [[ "$HISTORY_TARGET" != "0" ]] && command -v python3 >/dev/null 2>&1; then
  # Park on the Dashboard: a visible stats consumer samples every 2s instead of every 10s, so
  # the wait spends its time producing a dense chart rather than a sparse one.
  "$AX" press sidebar-dashboard || true
  last_covered=-1
  stalls=0
  while :; do
    read -r covered stale < <(history_coverage "$MENUBAR_HOVER")
    if [[ "$covered" -ge "$HISTORY_TARGET" ]]; then
      echo "chart history: ${covered}s covered, enough for the ${HISTORY_TARGET}s window"
      break
    fi
    # Sampling stops outright while every Orchard window is covered or minimized, which shows
    # up as a file that stops advancing. Bring the app forward rather than wait on nothing.
    if [[ "$stale" -gt $((HISTORY_MAX_GAP * 3)) ]]; then
      echo "chart history: no new samples for ${stale}s, bringing Orchard forward"
      osascript -e 'tell application "Orchard" to activate'
    fi
    if [[ "$covered" -gt "$last_covered" ]]; then
      stalls=0
    else
      stalls=$((stalls + 1))
      if [[ "$stalls" -ge "$HISTORY_STALL_LIMIT" ]]; then
        echo
        echo "Chart history stopped growing at ${covered}s of ${HISTORY_TARGET}s."
        echo "Orchard samples only while one of its windows is on screen, so check that it is"
        echo "not covered or minimized and that the demo containers are running. Re-run with"
        echo "HISTORY_TARGET=0 to capture anyway."
        exit 1
      fi
    fi
    last_covered="$covered"
    echo "chart history: ${covered}s of ${HISTORY_TARGET}s (leave Orchard on screen)"
    sleep "$HISTORY_POLL"
  done
fi

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
# resource-history popover opens to the left, then composite panel + popover into one shot.
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
