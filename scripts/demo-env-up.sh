#!/bin/bash
# Bring up a realistic demo environment for screenshots and manual testing:
# ten distinct lightweight containers across two networks, an AI-agent sandbox,
# a container machine, and host mounts. Existing resources (traefik, the k8s
# cluster, anything with a clashing name) are left alone; everything this
# script actually creates is recorded in a state file so demo-env-down.sh
# removes exactly that and nothing else.
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
mkdir -p "$DEMO_DIR"/{web-html,minio-data}
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
run objects  --network backend  -p 9000:9000 -v "$DEMO_DIR/minio-data:/data" docker.io/minio/minio:latest server /data
run worker   --network backend  docker.io/library/alpine:latest sleep infinity

echo "== AI agent sandbox =="
run agent --network backend \
  --label com.orchard.sandbox=true \
  --label com.orchard.model.endpoint=http://192.168.64.1:11434/v1 \
  -e OPENAI_BASE_URL=http://192.168.64.1:11434/v1 \
  docker.io/library/alpine:latest sleep infinity

echo "== Container machine (pulls a large init-enabled image on first run) =="
if container machine create --name demo-box --cpus 2 --memory 4G docker.io/geerlingguy/docker-ubuntu2204-ansible:latest >/dev/null 2>&1; then
  record machine demo-box
  echo "created machine demo-box"
else
  echo "demo-box exists or machine create failed (left alone)"
fi

echo
container ls
echo
echo "State recorded in $STATE - tear down with scripts/demo-env-down.sh"
