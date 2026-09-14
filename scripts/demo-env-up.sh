#!/bin/bash
# Bring up a realistic demo environment for screenshots and manual testing:
# nine distinct lightweight containers across two networks, a compose project, an AI-agent
# sandbox, a container machine, a local Kubernetes cluster, host mounts, a DNS domain, and a stub
# that stands in for local model providers so the AI Models tab is not an empty state. Existing
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
  # --dns-domain is what the DNS tab reads (DetailDNS matches a container's dns.domain against
  # the domain), so attaching here is what puts these containers under demo.test rather than
  # leaving the domain listed with nothing using it. Skipped when no domain could be created.
  local dns=()
  [[ -n "${DEMO_DNS_DOMAIN:-}" ]] && dns=(--dns-domain "$DEMO_DNS_DOMAIN")
  if container run --detach --name "$name" "${dns[@]+"${dns[@]}"}" "$@" >/dev/null; then
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

echo "== DNS domain =="
# The DNS tab has nothing to show without a domain, and the containers below attach to this
# one, so it comes first. Creating a domain edits the resolver configuration, so
# `container system dns create` must run as an administrator: tried with `sudo -n` so a machine
# without cached credentials is told what to run rather than having the script stall behind a
# password prompt with its output swallowed.
#
# Never recorded, so demo-env-down.sh leaves it behind. Removing one needs the same
# administrator rights, and a teardown that cannot finish its own state file is worse than a
# domain left in place: a domain costs nothing, survives anyway, and makes the next `up` cheap.
WANTED_DNS_DOMAIN="${DEMO_DNS_DOMAIN:-demo.test}"
DEMO_DNS_DOMAIN=""      # only set once a domain is known to exist, since `run` attaches to it
if container system dns ls 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$WANTED_DNS_DOMAIN"; then
  DEMO_DNS_DOMAIN="$WANTED_DNS_DOMAIN"
  echo "$WANTED_DNS_DOMAIN exists (left alone)"
elif sudo -n container system dns create "$WANTED_DNS_DOMAIN" >/dev/null 2>&1; then
  DEMO_DNS_DOMAIN="$WANTED_DNS_DOMAIN"
  echo "created DNS domain $WANTED_DNS_DOMAIN"
else
  echo "  (skipped: creating a DNS domain must run as an administrator, so the containers"
  echo "   below are not attached to one)"
  echo "   sudo container system dns create $WANTED_DNS_DOMAIN"
fi

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

# Something running from the built image, so the Builds and Images tabs can show a user for it
# rather than "No containers are currently using this image" in both. The image itself is not
# built here: that lives in the branch that added the build to this script, so this is skipped
# when the image is absent rather than pretending to create it.
if container image ls 2>/dev/null | awk 'NR>1 && $1=="orchard-demo" {f=1} END {exit !f}'; then
  run demo-api --network backend orchard-demo:latest
else
  echo "  (no orchard-demo:latest image, so nothing runs from it)"
fi

# A compose project, so the Compose tab has something to show. The file deliberately asks
# for two things that cannot be honoured, one blocked by the runtime and one not built yet,
# because the Problems tab is half of what the tab is for and an empty one shows nothing.
echo "== Compose project =="
COMPOSE_DIR="$DEMO_DIR/compose"
mkdir -p "$COMPOSE_DIR"
cat > "$COMPOSE_DIR/compose.yaml" <<'YAML'
name: storefront

services:
  web:
    image: docker.io/library/nginx:alpine
    ports:
      - "8090:80"
    depends_on: [inventory]
    # The runtime has no restart policy, so this shows under "Not possible on this runtime".
    restart: always

  inventory:
    image: docker.io/library/alpine:latest
    command: sleep infinity
    # Compose reads a bare port as "publish on any free host port", which nothing here can
    # allocate: it shows under "Not implemented yet".
    ports:
      - "3000"

  cache:
    image: docker.io/library/redis:alpine
YAML

# The CLI will not run this file, and that is the point of it: `container compose` refuses
# anything it cannot honour, because a command in a script has nobody to ask. Orchard is the
# half that can ask, and proceeding there creates exactly these containers. So the demo
# creates them the way a proceed would, and leaves the file saying what it says.
COMPOSE_NETWORK="storefront_default"
if container network create "$COMPOSE_NETWORK" >/dev/null 2>&1; then
  record network "$COMPOSE_NETWORK"
  echo "created network $COMPOSE_NETWORK"
fi

compose_run() {
  local service="$1"; shift
  local name="storefront-$service"
  if container run --detach --name "$name" \
      --network "$COMPOSE_NETWORK" \
      --label com.container-compose.project=storefront \
      --label com.container-compose.service="$service" \
      "$@" >/dev/null; then
    record container "$name"
    echo "created container $name"
  else
    echo "  (skipped: $name failed or already exists)"
  fi
}

# No hash label: only a real `up` can compute one, so Orchard will offer to recreate these.
# That is honest, and invisible in the screenshots this exists for.
compose_run web       -p 8090:80 docker.io/library/nginx:alpine
compose_run inventory docker.io/library/alpine:latest sleep infinity
compose_run cache     docker.io/library/redis:alpine

# Tell Orchard where the file is, the way the file picker would. Without this the project
# still appears (it is found by the labels on its containers) but Orchard cannot show what
# the file asks for, or bring it up again.
if [[ -d "$HOME/Library/Application Support/Orchard" ]] || mkdir -p "$HOME/Library/Application Support/Orchard"; then
  if python3 - "$COMPOSE_DIR/compose.yaml" <<'PY'
import json, os, sys, time

path = sys.argv[1]
store = os.path.expanduser("~/Library/Application Support/Orchard/compose-projects.json")
projects = []
if os.path.exists(store):
    try:
        loaded = json.load(open(store))
        if loaded.get("version") == 1:
            projects = loaded.get("projects", [])
    except ValueError:
        projects = []
if any(p.get("name") == "storefront" for p in projects):
    sys.exit(1)          # already known; leave the user's own record alone
projects.append({
    "name": "storefront",
    "path": path,
    "acknowledgedFindings": [],
    "addedAt": time.time() - 978307200,   # Foundation's reference date
})
json.dump({"version": 1, "projects": projects}, open(store, "w"))
PY
  then
    record composeproject storefront
    echo "registered the storefront project with Orchard"
  else
    echo "  (Orchard already knows a 'storefront' project; left it alone)"
  fi
fi

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
