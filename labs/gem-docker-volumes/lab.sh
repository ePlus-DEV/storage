#!/usr/bin/env bash
# Copyright (c) 2026 ePlus.DEV | Unlicense
# Google Skills: Docker Essentials: Container Volumes
# https://www.skills.google/focuses/127757
set -Eeuo pipefail

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  CYAN=$'\033[1;36m'; GREEN=$'\033[1;32m'; RED=$'\033[1;31m'; RESET=$'\033[0m'
else
  CYAN=''; GREEN=''; RED=''; RESET=''
fi
log() { printf '%s\n' "${CYAN}== $* ==${RESET}"; }
ok() { printf '%s\n' "${GREEN}$*${RESET}"; }
die() { printf '%s\n' "${RED}ERROR: $*${RESET}" >&2; exit 1; }

printf '%s\n' 'ePlus.DEV – Starting Execution' 'Copyright (c) 2026 ePlus.DEV | Unlicense'
command -v docker >/dev/null 2>&1 || die 'Docker is required.'
docker info >/dev/null 2>&1 || die 'Docker daemon is not available.'
if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  die 'Docker Compose is required for Task 4.'
fi

log 'Task 1: Named volumes, bind mounts, and tmpfs are distinct storage types.'
log 'Task 2: Create and inspect the mydata named volume'
docker volume create mydata >/dev/null
docker volume inspect mydata >/dev/null
docker run --rm --mount type=volume,source=mydata,target=/data alpine:3.20 \
  sh -c 'test -f /data/myfile.txt || printf "%s\n" "Hello from inside the container!" > /data/myfile.txt'
# --rm removes only the container started above; unrelated containers are untouched.
docker run --rm --mount type=volume,source=mydata,target=/data alpine:3.20 \
  sh -c 'test -s /data/myfile.txt && cat /data/myfile.txt'
ok 'Volume data persists across independent containers. Keeping mydata for inspection.'

log 'Task 3: Bind mount a host directory without deleting existing data'
HOST_DATA="${HOST_DATA:-$HOME/host_data}"
mkdir -p "$HOST_DATA"
if [[ ! -e "$HOST_DATA/hostfile.txt" ]]; then
  printf '%s\n' 'Hello from the host!' > "$HOST_DATA/hostfile.txt"
fi
docker run --rm --mount "type=bind,source=$HOST_DATA,target=/data" alpine:3.20 \
  sh -c 'grep -qxF "This line added from container" /data/hostfile.txt || printf "%s\n" "This line added from container" >> /data/hostfile.txt'
grep -qF 'This line added from container' "$HOST_DATA/hostfile.txt" || die 'Bind mount write not visible on host.'
ok "Bind mount verified. Keeping $HOST_DATA and its contents."

log 'Task 4: Docker Compose with a persistent web_data volume'
HOST_PORT="${HOST_PORT:-8080}"
[[ "$HOST_PORT" =~ ^[0-9]+$ ]] || die 'HOST_PORT must be numeric.'
export HOST_PORT
WORK_DIR="$(mktemp -d)"
COMPOSE_PROJECT="eplusvol$RANDOM"
cleanup() {
  "${COMPOSE[@]}" -p "$COMPOSE_PROJECT" -f "$WORK_DIR/compose.yaml" down >/dev/null 2>&1 || true
  rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT
cat > "$WORK_DIR/compose.yaml" <<'YAML'
services:
  init:
    image: alpine:3.20
    command: ["sh", "-c", "printf '%s\n' '<html><body><h1>Hello from Docker Compose!</h1></body></html>' > /data/index.html"]
    volumes:
      - web_data:/data
  web:
    image: nginx:stable-alpine
    ports:
      - "${HOST_PORT}:80"
    volumes:
      - web_data:/usr/share/nginx/html:ro
    depends_on:
      init:
        condition: service_completed_successfully
volumes:
  web_data:
YAML
"${COMPOSE[@]}" -p "$COMPOSE_PROJECT" -f "$WORK_DIR/compose.yaml" up -d
READY=false
for attempt in {1..12}; do
  if curl --fail --silent --show-error "http://127.0.0.1:$HOST_PORT/" 2>/dev/null | grep -q 'Hello from Docker Compose'; then
    READY=true
    break
  fi
  sleep 2
done
[[ "$READY" == true ]] || die 'Docker Compose website did not respond with expected content.'
ok 'Compose website verified; cleanup stops only this project, preserving named volumes.'
ok 'All lab tasks completed; runtime grader is not checked by this script.'
