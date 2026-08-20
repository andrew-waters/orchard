#!/bin/bash
# Tear down everything scripts/demo-env-up.sh created. Leaves traefik, the k8s
# cluster, pulled images, and anything else it didn't create.
set -uo pipefail

for c in web api cache db queue sessions metrics registry objects worker agent; do
  container stop "$c" 2>/dev/null
  container delete "$c" 2>/dev/null && echo "deleted container $c"
done

container machine stop demo-box 2>/dev/null
container machine delete demo-box 2>/dev/null && echo "deleted machine demo-box"

for net in frontend backend; do
  container network delete "$net" 2>/dev/null && echo "deleted network $net"
done

rm -rf "$HOME/.orchard-demo" && echo "removed $HOME/.orchard-demo"
