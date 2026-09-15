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
#   - Automation → System Events (to flip the appearance between themes)
#
# Usage: ./scripts/capture-screenshots.sh [--both|--dark|--light] [--no-wait] [output-dir]
#   default: --both, into site/assets/screens and site/assets/screens/light
#
# --both takes each shot in both themes before moving on: the view is posed once, captured
# dark, the appearance flipped, and captured light. That is the point of it. Capturing a whole
# set per theme leaves the two five to ten minutes apart, and everything live moves in between
# (chart tails, CPU and memory readings, log content), so toggling the site's theme made the
# numbers jump even though the layout held still. Posing once puts the pair seconds apart.
#
# The menu bar, palette and logs shots pose transient UI (a panel with a popover open, a
# palette with a query typed, a second window). Flipping the appearance while one of those is
# posed risks dismissing it or catching a half-restyled window, so those three re-pose per
# theme instead. Their pairs are a few seconds apart rather than two.
#
# Whichever themes are wanted, the appearance is restored to yours on exit. The site swaps to
# the light set automatically in light mode, falling back to the dark shot for a file that is
# not there yet (see site/theme.js).
#
# Before capturing anything it waits for the charts to have history behind them, so no shot
# goes out with a chart holding three points in the corner of it. Five minutes of the app
# running and on screen is enough (see HISTORY_TARGET below for why), and leaving the demo
# environment up between runs means it usually costs nothing at all. --no-wait skips it, for
# previewing a change to the capture itself without paying for history first: expect sparse
# charts in anything it produces.
#
# The default lands where both consumers can use the files directly:
#   - GH Pages serves them at https://orchard.andon.dev/assets/screens/<tab>.png
#   - the README can embed them as site/assets/screens/<tab>.png
# Re-run and commit to refresh the screenshots everywhere at once.
set -euo pipefail
cd "$(dirname "$0")/.."

# Themes to capture, in the order each pose is shot. Dark first, so the drift inside a pair
# always runs the same direction.
THEMES="dark light"
WAIT_FOR_HISTORY=true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --both)    THEMES="dark light"; shift ;;
    --dark)    THEMES="dark"; shift ;;
    --light)   THEMES="light"; shift ;;
    --no-wait) WAIT_FOR_HISTORY=false; shift ;;
    -*)        echo "unknown option: $1"; exit 1 ;;
    *)         break ;;
  esac
done

ROOT="${1:-site/assets/screens}"
DARK_OUT="$ROOT"
LIGHT_OUT="$ROOT/light"
# `--light` on its own writes where the light set belongs; naming a directory with it means
# "put the light set there", rather than in a light/ below it.
if [[ "$THEMES" == "light" && -n "${1:-}" ]]; then LIGHT_OUT="$ROOT"; fi

AX="scripts/.build/orchard-ax"
APPEARANCE_SETTLE="${APPEARANCE_SETTLE:-2}"   # seconds for the app to re-render after a flip
# The container the menu bar shot hovers (must be running). Named here rather than beside that
# shot because the chart-history wait below measures this container's series too.
MENUBAR_HOVER="${MENUBAR_HOVER:-k8s-dev}"

# The row each tab should open on. Without these a tab shows whatever its list selected first,
# which is not a choice anyone made: it put the Images shot on a digest-pinned node image and
# the Mounts shot on a tmpfs with no source. Everything named here is something
# scripts/demo-env-up.sh creates.
subject_for() {
  case "$1" in
    clusters)  echo "k8s-dev" ;;
    machines)  echo "demo-box" ;;
    sandboxes) echo "agent" ;;
    models)    echo "Ollama" ;;
    images)    echo "orchard-demo" ;;
    builds)    echo "orchard-demo:latest" ;;
    mounts)    echo "/usr/share/nginx/html" ;;
    dns)       echo "demo.test" ;;
    networks)  echo "backend" ;;
    *)         echo "" ;;
  esac
}
MISSED_SUBJECTS=""

# The appearance is flipped many times in a --both run, so it is remembered once here and
# restored unconditionally on exit, including on a failure part-way through a pose.
PREV_DARK=$(osascript -e 'tell application "System Events" to tell appearance preferences to get dark mode')
trap 'osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $PREV_DARK"' EXIT

set_appearance() {
  local want=false
  if [[ "$1" == "dark" ]]; then want=true; fi
  local current
  current=$(osascript -e 'tell application "System Events" to tell appearance preferences to get dark mode')
  if [[ "$current" == "$want" ]]; then return 0; fi
  osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $want"
  sleep "$APPEARANCE_SETTLE"
}

out_dir_for() {
  if [[ "$1" == "dark" ]]; then echo "$DARK_OUT"; else echo "$LIGHT_OUT"; fi
}

capture_failed() {
  echo
  echo "Capture failed ('could not create image from window' means the Screen"
  echo "Recording permission is missing). Grant it to your terminal app under"
  echo "System Settings → Privacy & Security → Screen & System Audio Recording,"
  echo "then QUIT AND REOPEN the terminal app - the grant only applies after a"
  echo "restart - and re-run this script."
  exit 1
}

# Shoot the pose that is already on screen, once per theme. Only the appearance changes between
# the frames, so the pair differs by a flip and the couple of seconds it takes.
capture_pose() {
  local name="$1" theme dir wid
  for theme in $THEMES; do
    set_appearance "$theme"
    dir="$(out_dir_for "$theme")"
    wid=$("$AX" window-id)
    if ! screencapture -x -l "$wid" "$dir/$name.png" 2>/dev/null || [[ ! -s "$dir/$name.png" ]]; then
      capture_failed
    fi
    echo "captured $dir/$name.png"
  done
}

# Compile the AX helper on first run (or when its source changes).
if [[ ! -x "$AX" || scripts/orchard-ax.swift -nt "$AX" ]]; then
  mkdir -p scripts/.build
  echo "Compiling accessibility helper…"
  xcrun swiftc -O -sdk "$(xcrun --show-sdk-path --sdk macosx)" scripts/orchard-ax.swift -o "$AX"
fi

for theme in $THEMES; do mkdir -p "$(out_dir_for "$theme")"; done
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

# Prints "<covered-seconds> <staleness-seconds> <newest-sample-stamp>". Never fails the script:
# an unreadable or not-yet-written file reads as no coverage, which the loop reports and keeps
# waiting on.
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
    print("0 0 0")
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
print(f"{int(covered)} {int(stale)} {int(newest or 0)}")
PY
}

if [[ "$WAIT_FOR_HISTORY" != true ]]; then
  echo "chart history: skipped (--no-wait), so charts show only what has accumulated so far"
elif [[ "$HISTORY_TARGET" != "0" ]] && command -v python3 >/dev/null 2>&1; then
  # Park on the Dashboard: a visible stats consumer samples every 2s instead of every 10s, so
  # the wait spends its time producing a dense chart rather than a sparse one.
  "$AX" press sidebar-dashboard || true
  last_newest=0
  stalls=0
  while :; do
    read -r covered stale newest < <(history_coverage "$MENUBAR_HOVER")
    if [[ "$covered" -ge "$HISTORY_TARGET" ]]; then
      echo "chart history: ${covered}s covered, enough for the ${HISTORY_TARGET}s window"
      break
    fi
    # Progress is samples arriving, not coverage growing. Coverage legitimately falls after a
    # pause: sampling resumes, the pause is a gap, and the unbroken window restarts from the
    # resumption. Treating that as a stall counted a recovery as a failure.
    if [[ "$newest" -gt "$last_newest" ]]; then
      stalls=0
    else
      # Nothing new since the last poll, so sampling is paused: every Orchard window is
      # covered or minimized. Acted on immediately rather than after a staleness threshold,
      # because a poll that saw no new samples is already the signal, and the old 180s wait
      # spent three polls of the stall budget before trying anything.
      stalls=$((stalls + 1))
      echo "chart history: no new samples for ${stale}s, bringing Orchard forward"
      osascript -e 'tell application "Orchard" to activate'
      if [[ "$stalls" -ge "$HISTORY_STALL_LIMIT" ]]; then
        echo
        echo "Chart history stopped growing at ${covered}s of ${HISTORY_TARGET}s: no new"
        echo "samples for ${stale}s, over $HISTORY_STALL_LIMIT polls, even after raising Orchard."
        echo "It samples only while one of its windows is on screen, so check it is not covered"
        echo "or minimized and that the demo containers are running. Re-run with"
        echo "HISTORY_TARGET=0 to capture anyway."
        exit 1
      fi
    fi
    last_newest="$newest"
    echo "chart history: ${covered}s of ${HISTORY_TARGET}s (leave Orchard on screen)"
    sleep "$HISTORY_POLL"
  done
fi

TABS="dashboard containers clusters machines sandboxes models images builds mounts dns networks"
for tab in $TABS; do
  # Fail hard: a missed selection would silently save the wrong view under this name.
  "$AX" press "sidebar-$tab" || { echo "could not select the $tab tab"; exit 1; }
  sleep 1.5   # let the tab load and charts settle
  # A missing subject is reported rather than fatal: the tab is still the right tab, and
  # aborting a run that has already waited out the chart history, to save one duller shot, is
  # the worse trade. The summary at the end names any that missed.
  subject="$(subject_for "$tab")"
  if [[ -n "$subject" ]]; then
    if "$AX" press-text "$subject" >/dev/null 2>&1; then
      sleep 1.5   # the detail pane loads and its own charts settle
    else
      echo "  (no '$subject' on the $tab tab: keeping whatever the list selected)"
      MISSED_SUBJECTS="$MISSED_SUBJECTS $tab:$subject"
    fi
  fi
  if [[ "$tab" == "containers" ]]; then
    # The k8s node has the liveliest charts and shows the plugin badge + cluster banner.
    "$AX" press-text "k8s-dev" || { echo "could not select the k8s-dev container"; exit 1; }
    sleep 2
  fi
  capture_pose "$tab"
done

# Menu bar panel: toggle it open via the status item, hover a running container so its
# resource-history popover opens to the left, then composite panel + popover into one shot.
# Re-posed per theme rather than flipped mid-pose: the panel and its popover are transient, and
# an appearance change under them is the kind of thing that dismisses one.
for theme in $THEMES; do
  set_appearance "$theme"
  dir="$(out_dir_for "$theme")"
  "$AX" menubar-click || { echo "could not open the menu bar panel"; exit 1; }
  sleep 2.5   # let the rings and container rows settle
  "$AX" hover-text "$MENUBAR_HOVER" || { echo "could not hover the $MENUBAR_HOVER row in the panel"; exit 1; }
  sleep 2     # popover open + its charts settle
  if ! "$AX" capture-panels "$dir/menubar.png" || [[ ! -s "$dir/menubar.png" ]]; then
    echo "menu bar panel capture failed"; exit 1
  fi
  "$AX" menubar-click >/dev/null || true   # close it again
  echo "captured $dir/menubar.png"
done

# Command palette: over the k8s-dev container detail, open ⌘K and type a query.
# Never click inside the window here: the palette dismisses on any click outside its
# panel, and its search field focuses itself on open - typing lands there directly.
PALETTE_QUERY="${PALETTE_QUERY:-logs api}"
for theme in $THEMES; do
  set_appearance "$theme"
  dir="$(out_dir_for "$theme")"
  "$AX" press "sidebar-containers" && sleep 1
  "$AX" press-text "k8s-dev" || true
  sleep 1
  "$AX" key escape && sleep 0.5   # ⌘K toggles - make sure no palette is already open
  "$AX" key cmd+k && sleep 1
  "$AX" type "$PALETTE_QUERY" && sleep 1.5
  wid=$("$AX" window-id)
  if ! screencapture -x -l "$wid" "$dir/palette.png" 2>/dev/null || [[ ! -s "$dir/palette.png" ]]; then
    echo "palette capture failed"; exit 1
  fi
  "$AX" key escape && sleep 0.5
  echo "captured $dir/palette.png"
done

# Split logs: open LOGS_TARGET's logs window from its detail-header Logs button,
# add a second pane (it auto-selects the first running container), and capture.
LOGS_TARGET="${LOGS_TARGET:-k8s-dev}"
for theme in $THEMES; do
  set_appearance "$theme"
  dir="$(out_dir_for "$theme")"
  "$AX" press "sidebar-containers" && sleep 1
  "$AX" press-text "$LOGS_TARGET" || { echo "could not select the $LOGS_TARGET container"; exit 1; }
  sleep 1
  "$AX" press-text "Logs" || { echo "could not find the Logs button in the detail header"; exit 1; }
  sleep 3                          # the logs window opens and the first fetch lands
  "$AX" press-text "Split" || { echo "could not find the Split button"; exit 1; }
  sleep 3                          # second pane loads its logs
  wid=$("$AX" window-id)           # frontmost large window - the logs window
  if ! screencapture -x -l "$wid" "$dir/logs.png" 2>/dev/null || [[ ! -s "$dir/logs.png" ]]; then
    echo "logs capture failed"; exit 1
  fi
  "$AX" key cmd+w && sleep 0.5     # close the logs window
  echo "captured $dir/logs.png"
done

if [[ -n "$MISSED_SUBJECTS" ]]; then
  echo
  echo "These tabs did not find their intended subject, so they show whatever their list"
  echo "selected instead:$MISSED_SUBJECTS"
  echo "Check the resource exists (scripts/demo-env-up.sh) before shipping those shots."
fi

echo
echo "Committed with the site, these serve at https://orchard.andon.dev/assets/screens/<tab>.png"
