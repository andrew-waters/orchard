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
