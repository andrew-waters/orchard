#!/bin/bash
# Tear down exactly what scripts/demo-env-up.sh recorded creating - nothing else.
# Pre-existing resources that happened to share a name were never recorded, so
# they survive.
set -uo pipefail

DEMO_DIR="$HOME/.orchard-demo"
STATE="$DEMO_DIR/state"

[[ -f "$STATE" ]] || { echo "No state file at $STATE - nothing recorded to tear down."; exit 0; }

REMOVE_DIR=0
# Containers first, then the machine, then networks (they must be unused).
while read -r kind name; do
  [[ "$kind" == "container" ]] || continue
  container stop "$name" 2>/dev/null
  container delete "$name" 2>/dev/null && echo "deleted container $name"
done < "$STATE"

while read -r kind name; do
  case "$kind" in
    machine)
      container machine stop "$name" 2>/dev/null
      container machine delete "$name" 2>/dev/null && echo "deleted machine $name" ;;
    network)
      container network delete "$name" 2>/dev/null && echo "deleted network $name" ;;
    dir)
      REMOVE_DIR=1 ;;
  esac
done < "$STATE"

if [[ "$REMOVE_DIR" == 1 ]]; then
  rm -rf "$DEMO_DIR" && echo "removed $DEMO_DIR"
else
  rm -f "$STATE"
  echo "kept pre-existing $DEMO_DIR (removed the state file)"
fi
