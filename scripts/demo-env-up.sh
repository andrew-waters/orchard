#!/bin/bash
# Bring up a realistic demo environment for screenshots and manual testing:
# ten distinct lightweight containers across two networks, an AI-agent sandbox,
# a container machine, and host mounts. Existing resources (traefik, the k8s
# cluster) are left alone. Tear it all down with scripts/demo-env-down.sh.
set -uo pipefail

DEMO_DIR="$HOME/.orchard-demo"
run() { echo "+ container run $*"; container run --detach "$@" >/dev/null || echo "  (skipped: $1 $2 failed)"; }

echo "== Networks =="
for net in frontend backend; do
  container network create "$net" 2>/dev/null && echo "created $net" || echo "$net exists"
done

echo "== Mount sources =="
mkdir -p "$DEMO_DIR"/{web-html,minio-data}
cat > "$DEMO_DIR/web-html/index.html" <<'HTML'
<!doctype html><title>Orchard demo</title><h1>Served from a host mount</h1>
HTML

echo "== Containers =="
run --name web      --network frontend -p 8088:80 -v "$DEMO_DIR/web-html:/usr/share/nginx/html" docker.io/library/nginx:alpine
run --name api      --network frontend -p 8081:80 docker.io/library/caddy:alpine
run --name cache    --network backend  docker.io/library/redis:alpine
run --name db       --network backend  -e POSTGRES_PASSWORD=orchard-demo docker.io/library/postgres:16-alpine
run --name queue    --network backend  docker.io/library/nats:alpine
run --name sessions --network backend  docker.io/library/memcached:alpine
run --name metrics  --network backend  -p 9090:9090 docker.io/prom/prometheus:latest
run --name registry --network backend  -p 5001:5000 docker.io/library/registry:2
run --name objects  --network backend  -p 9000:9000 -v "$DEMO_DIR/minio-data:/data" docker.io/minio/minio:latest server /data
run --name worker   --network backend  docker.io/library/alpine:latest sleep infinity

echo "== AI agent sandbox =="
run --name agent --network backend \
  --label com.orchard.sandbox=true \
  --label com.orchard.model.endpoint=http://192.168.64.1:11434/v1 \
  -e OPENAI_BASE_URL=http://192.168.64.1:11434/v1 \
  docker.io/library/alpine:latest sleep infinity

echo "== Container machine (pulls a large init-enabled image on first run) =="
container machine create --name demo-box --cpus 2 --memory 4G docker.io/geerlingguy/docker-ubuntu2204-ansible:latest 2>/dev/null \
  || echo "demo-box exists or machine create failed"

echo
container ls
