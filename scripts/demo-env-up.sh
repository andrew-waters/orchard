#!/bin/bash
# Bring up a realistic demo environment for screenshots and manual testing:
# nine distinct lightweight containers across two networks, an AI-agent sandbox,
# a container machine, a local Kubernetes cluster, host mounts, and a stub that stands in
# for local model providers so the AI Models tab is not an empty state. Existing
# resources (traefik, a cluster you already have, anything with a clashing name)
# are left alone; everything this script actually creates is recorded in a state
# file so demo-env-down.sh removes exactly that and nothing else.
set -uo pipefail

DEMO_DIR="$HOME/.orchard-demo"
STATE="$DEMO_DIR/state"

if [[ -d "$DEMO_DIR" ]]; then
  DIR_CREATED=0
else
  mkdir -p "$DEMO_DIR"
  DIR_CREATED=1
fi
touch "$STATE"
[[ "$DIR_CREATED" == 1 ]] && echo "dir $DEMO_DIR" >> "$STATE"

record() { echo "$1 $2" >> "$STATE"; }

run() {
  local name="$1"; shift
  if container run --detach --name "$name" "$@" >/dev/null; then
    record container "$name"
    echo "created container $name"
  else
    echo "  (skipped: container $name failed or already exists)"
  fi
}

echo "== Networks =="
for net in frontend backend; do
  if container network create "$net" >/dev/null 2>&1; then
    record network "$net"
    echo "created network $net"
  else
    echo "$net exists (left alone)"
  fi
done

echo "== Mount sources =="
mkdir -p "$DEMO_DIR/web-html"
cat > "$DEMO_DIR/web-html/index.html" <<'HTML'
<!doctype html><title>Orchard demo</title><h1>Served from a host mount</h1>
HTML

echo "== Containers =="
run web      --network frontend -p 8088:80 -v "$DEMO_DIR/web-html:/usr/share/nginx/html" docker.io/library/nginx:alpine
run api      --network frontend -p 8081:80 docker.io/library/caddy:alpine
run cache    --network backend  docker.io/library/redis:alpine
run db       --network backend  -e POSTGRES_PASSWORD=orchard-demo docker.io/library/postgres:16-alpine
run queue    --network backend  docker.io/library/nats:alpine
run sessions --network backend  docker.io/library/memcached:alpine
run metrics  --network backend  -p 9090:9090 docker.io/prom/prometheus:latest
run registry --network backend  -p 5001:5000 docker.io/library/registry:2
run worker   --network backend  docker.io/library/alpine:latest sleep infinity

echo "== AI agent sandbox =="
# The endpoint has to name the gateway of the network the sandbox is on: that is the address
# the host answers on from inside a container (see ModelBridge), and the runtime assigns it at
# network-create time, so it cannot be hardcoded. Derived from the subnet, whose .1 is the
# gateway. A hardcoded address here named the wrong network's gateway, so the sandbox advertised
# an endpoint nothing was listening on.
BACKEND_SUBNET=$(container network ls 2>/dev/null | awk '$1=="backend" {print $2; exit}')
MODEL_GATEWAY=$(echo "$BACKEND_SUBNET" | sed -E 's#^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+/[0-9]+$#\1.1#')
if [[ -z "$MODEL_GATEWAY" || "$MODEL_GATEWAY" == "$BACKEND_SUBNET" ]]; then
  echo "  (could not read the backend gateway; the sandbox endpoint may not resolve)"
  MODEL_GATEWAY="192.168.64.1"
fi
MODEL_ENDPOINT="http://$MODEL_GATEWAY:11434/v1"
run agent --network backend \
  --label com.orchard.sandbox=true \
  --label com.orchard.model.endpoint=$MODEL_ENDPOINT \
  -e OPENAI_BASE_URL=$MODEL_ENDPOINT \
  docker.io/library/alpine:latest sleep infinity

echo "== Container machine (pulls a large init-enabled image on first run) =="
if container machine create --name demo-box --cpus 2 --memory 4G docker.io/geerlingguy/docker-ubuntu2204-ansible:latest >/dev/null 2>&1; then
  record machine demo-box
  echo "created machine demo-box"
else
  echo "demo-box exists or machine create failed (left alone)"
fi

echo "== Kubernetes cluster =="
# The Containers, Clusters, menu bar, palette and logs shots all use a k8s node: it has the
# liveliest charts, and it is the only container carrying a plugin badge and cluster banner.
# Node containers are ordinary containers, so the plain lists answer both questions about one.
K8S_CLUSTER="${K8S_CLUSTER:-k8s-dev}"
cluster_exists() { container ls -a 2>/dev/null | awk -v n="$1" 'NR>1 && $1==n {f=1} END {exit !f}'; }
cluster_running() { container ls 2>/dev/null | awk -v n="$1" 'NR>1 && $1==n {f=1} END {exit !f}'; }

if cluster_exists "$K8S_CLUSTER"; then
  echo "$K8S_CLUSTER exists (left alone)"
elif container k8s create --name "$K8S_CLUSTER" >/dev/null 2>&1; then
  record k8scluster "$K8S_CLUSTER"
  echo "created cluster $K8S_CLUSTER"
else
  # Reported rather than fatal: every other resource above is still usable without a cluster.
  # A guest kernel from before container 1.3.0 was built without nftables and cannot finish
  # node preparation (apple/container#2120), and upgrading the CLI never replaces an existing
  # kernel (apple/container#905), so this is what an install carried forward looks like.
  echo "  (skipped: container k8s create failed)"
  echo "   If it aborted in node prep, the guest kernel predates nftables:"
  echo "   container system kernel set --recommended --force"
fi

# Whether it was just created or was already there, the screenshots need it up.
if cluster_running "$K8S_CLUSTER"; then
  echo "cluster $K8S_CLUSTER is running"
elif cluster_exists "$K8S_CLUSTER"; then
  if container k8s start --name "$K8S_CLUSTER" >/dev/null 2>&1; then
    echo "started cluster $K8S_CLUSTER"
  else
    echo "  (cluster $K8S_CLUSTER exists but is not running, and would not start)"
  fi
fi

echo "== Local model providers (stub) =="
# The AI Models tab lists providers Orchard finds by probing conventional loopback ports, so
# with nothing installed it shows an empty state. scripts/demo-model-server.py answers those
# probes from canned JSON, which fills the tab without anyone installing Ollama or LM Studio.
# Ports already in use are left alone, so a real provider still wins.
MODEL_STUB="$(dirname "$0")/demo-model-server.py"
MODEL_STUB_LOG="$DEMO_DIR/model-stub.log"
if pgrep -f "demo-model-server.py" >/dev/null 2>&1; then
  echo "model stub already running (left alone)"
elif [[ ! -f "$MODEL_STUB" ]]; then
  echo "  (skipped: $MODEL_STUB not found)"
else
  nohup python3 "$MODEL_STUB" > "$MODEL_STUB_LOG" 2>&1 &
  MODEL_STUB_PID=$!
  sleep 1.5
  # Alive *and* actually serving something. Liveness alone is not enough: if every port was
  # already taken the stub binds nothing and exits, and claiming success there would leave the
  # tab empty with nothing said about why. The log names each port it bound.
  if kill -0 "$MODEL_STUB_PID" 2>/dev/null && grep -q '^serving ' "$MODEL_STUB_LOG"; then
    record modelstub "$MODEL_STUB_PID"
    sed -n 's/^/  /p' "$MODEL_STUB_LOG"
    echo "model stub running (pid $MODEL_STUB_PID, log in $MODEL_STUB_LOG)"
  else
    echo "  (model stub did not start; see $MODEL_STUB_LOG)"
  fi
fi

echo
container ls
echo
echo "State recorded in $STATE - tear down with scripts/demo-env-down.sh"
echo
echo "Charts fill in only as Orchard samples, and it samples only while one of its windows is"
echo "on screen. Give this environment and the app five minutes before capturing screenshots;"
echo "scripts/capture-screenshots.sh waits for that history before it shoots."
