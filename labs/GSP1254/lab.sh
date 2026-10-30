#!/usr/bin/env bash
# Copyright (c) 2026 ePlus.DEV | Unlicense
# GSP1254 — Exploring Memorystore for Redis Cluster
# Static validated only; runtime/grader unverified.
set -Eeuo pipefail
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then CYAN=$'\033[1;36m'; RESET=$'\033[0m'; else CYAN=''; RESET=''; fi
log() { printf '%s%s%s\n' "$CYAN" "$*" "$RESET"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
command -v gcloud >/dev/null || die 'gcloud CLI required'
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != '(unset)' ]] || die 'Set PROJECT_ID'
CLUSTER="${CLUSTER:-redis-cluster}"
VM="${VM:-redis-client}"
log 'ePlus.DEV – Starting Execution'
log '[1/4] Discover location and validate resources'
if [[ -z "${REGION:-}" ]]; then
  mapfile -t regions < <(gcloud redis clusters list --project="$PROJECT_ID" --format='value(name)' | sed -n "s@.*/locations/\\([^/]*\\)/clusters/${CLUSTER}$@\\1@p")
  (("${#regions[@]}" == 1)) || die 'Set REGION: unique cluster location not detected'
  REGION="${regions[0]}"
fi
if [[ -z "${ZONE:-}" ]]; then
  mapfile -t zones < <(gcloud compute instances list --project="$PROJECT_ID" --filter="name=$VM" --format='value(zone.basename())')
  (("${#zones[@]}" == 1)) || die 'Set ZONE: unique redis-client VM not detected'
  ZONE="${zones[0]}"
fi
gcloud redis clusters describe "$CLUSTER" --region="$REGION" --project="$PROJECT_ID" >/dev/null
log '[2/4] Task 1: inspect Redis client VM'
# Host/port and RedisSim command vary by lab image. Do not fabricate these values.
gcloud compute ssh "$VM" --zone="$ZONE" --project="$PROJECT_ID" --command='command -v redis-cli && (command -v RedisSim || true)'
log 'ACTION REQUIRED: run official RedisSim workload and Redis commands on redis-client.'
log '[3/4] Task 2: enable AOF persistence (everysec)'
gcloud redis clusters update "$CLUSTER" --project="$PROJECT_ID" --region="$REGION" --persistence-mode=aof --aof-append-fsync=everysec --quiet
log '[4/4] Task 3: scale cluster to 10 shards'
gcloud redis clusters update "$CLUSTER" --project="$PROJECT_ID" --region="$REGION" --shard-count=10 --quiet
gcloud redis clusters describe "$CLUSTER" --project="$PROJECT_ID" --region="$REGION" --format='yaml(shardCount,persistenceConfig)'
log 'Partial CLI implementation. Task 1 and workload concurrency require manual verification; grader unverified.'
