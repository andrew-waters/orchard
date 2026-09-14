#!/bin/bash
# Tear down exactly what scripts/demo-env-up.sh recorded creating - nothing else.
# Pre-existing resources that happened to share a name were never recorded, so
# they survive.
set -uo pipefail

DEMO_DIR="$HOME/.orchard-demo"
STATE="$DEMO_DIR/state"

[[ -f "$STATE" ]] || { echo "No state file at $STATE - nothing recorded to tear down."; exit 0; }

REMOVE_DIR=0
# The model-provider stub first: it owns no container resources, so nothing waits on it.
# Checked against the recorded pid's own command line before signalling, because a pid from a
# previous boot may well belong to something else entirely by now.
while read -r kind pid; do
  [[ "$kind" == "modelstub" ]] || continue
  if ps -p "$pid" -o command= 2>/dev/null | grep -q "demo-model-server.py"; then
    kill "$pid" 2>/dev/null && echo "stopped model stub (pid $pid)"
  fi
done < "$STATE"

# The compose project next: its own `down` removes the containers and the network it
# created, which the loops below know nothing about.
while read -r kind name; do
  [[ "$kind" == "compose" ]] || continue
  if [[ -d "$name" ]] && container compose --help >/dev/null 2>&1; then
    (cd "$name" && container compose down) && echo "took down the compose project in $name"
  fi
done < "$STATE"

# And the record that told Orchard where its file was, leaving any other project alone.
while read -r kind name; do
  [[ "$kind" == "composeproject" ]] || continue
  python3 - "$name" <<'PY'
import json, os, sys
store = os.path.expanduser("~/Library/Application Support/Orchard/compose-projects.json")
if not os.path.exists(store):
    sys.exit(0)
try:
    loaded = json.load(open(store))
except ValueError:
    sys.exit(0)
projects = [p for p in loaded.get("projects", []) if p.get("name") != sys.argv[1]]
json.dump({"version": 1, "projects": projects}, open(store, "w"))
PY
  echo "removed the $name project from Orchard's list"
done < "$STATE"

# The DNS domain is deliberately not torn down. Deleting one needs administrator rights, the
# same as creating it, and this script must be able to finish unattended. It is also the one
# piece of the demo that is harmless to keep: nothing resolves under it once the containers are
# gone, and leaving it means the next `up` needs no password. Remove it by hand if you want it
# gone, naming the domain demo-env-up.sh was told to create:
#   sudo container system dns delete ${DEMO_DNS_DOMAIN:-demo.test}

# Clusters first: their node containers are ordinary containers, so removing the cluster
# through the plugin takes them with it, and deleting a node from under it would not.
while read -r kind name; do
  [[ "$kind" == "k8scluster" ]] || continue
  container k8s delete --name "$name" 2>/dev/null && echo "deleted cluster $name"
done < "$STATE"

# Then containers, then the machine, then networks (they must be unused).
while read -r kind name; do
  [[ "$kind" == "container" ]] || continue
  container stop "$name" 2>/dev/null
  container delete "$name" 2>/dev/null && echo "deleted container $name"
done < "$STATE"

# The build: its registry backup, its record in Orchard's list, and the image itself.
while read -r kind name; do
  case "$kind" in
    buildsbackup)
      # Put the registry back exactly as it was found, rather than trusting a surgical edit.
      if [[ -f "$name" ]]; then
        cp "$name" "$HOME/Library/Application Support/Orchard/builds.json"
        echo "restored the build registry from $name"
      fi ;;
    buildrecord)
      python3 - "$name" <<'PY'
import json, os, sys
store = os.path.expanduser("~/Library/Application Support/Orchard/builds.json")
if not os.path.exists(store):
    sys.exit(0)
try:
    loaded = json.load(open(store))
except ValueError:
    sys.exit(0)
builds = [b for b in loaded.get("builds", []) if b.get("request", {}).get("tag") != sys.argv[1]]
json.dump({"version": 1, "builds": builds}, open(store, "w"))
PY
      echo "removed the $name build from Orchard's list" ;;
    image)
      container image delete "$name" >/dev/null 2>&1 && echo "deleted image $name" ;;
  esac
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
