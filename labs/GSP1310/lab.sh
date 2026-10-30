#!/usr/bin/env bash
# Copyright (c) 2026 ePlus.DEV | Unlicense
set -Eeuo pipefail
if [[ -v NO_COLOR ]]; then BLUE='' GREEN='' YELLOW='' RESET=''
elif [[ -t 1 || "${FORCE_COLOR:-0}" == 1 ]]; then
  BLUE=$'\033[1;36m'; GREEN=$'\033[1;32m'; YELLOW=$'\033[1;33m'; RESET=$'\033[0m'
else BLUE='' GREEN='' YELLOW='' RESET=''; fi
info() { printf '%s%s%s\n' "$BLUE" "$*" "$RESET"; }
ok() { printf '%s%s%s\n' "$GREEN" "$*" "$RESET"; }
warn() { printf '%s%s%s\n' "$YELLOW" "$*" "$RESET"; }
trap 'warn "Failed at line $LINENO (exit $?)."' ERR
printf '%s\n' "${BLUE}ePlus.DEV – Starting Execution${RESET}" 'GSP1310 — NetApp Volumes resizing (static validated only; runtime/grader unverified)'
for cmd in gcloud grep sed head; do command -v "$cmd" >/dev/null || { warn "Missing $cmd"; exit 1; }; done
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != '(unset)' ]] || { warn 'Choose an authorized lab project'; exit 1; }
VM_NAME=vm1
VOLUME_NAME=volume1
ZONE="${ZONE:-$(gcloud compute instances list --project="$PROJECT_ID" --filter="name=$VM_NAME" --format='value(zone.basename())' | head -n 1)}"
[[ -n "$ZONE" ]] || { warn 'Preprovisioned vm1 not found'; exit 1; }
VOLUME_PATH="$(gcloud netapp volumes list --project="$PROJECT_ID" --format='value(name)' | grep '/volumes/volume1$' | head -n 1 || true)"
[[ "$VOLUME_PATH" =~ /locations/([^/]+)/volumes/volume1$ ]] || { warn 'Preprovisioned volume1 not found'; exit 1; }
LOCATION="${BASH_REMATCH[1]}"
NFS_EXPORT="${NFS_EXPORT:-$(gcloud netapp volumes describe "$VOLUME_NAME" --project="$PROJECT_ID" --location="$LOCATION" --format='value(mountOptions[0].exportFull)' 2>/dev/null || true)}"
if [[ -z "$NFS_EXPORT" ]]; then
  if [[ -t 0 ]]; then read -r -p 'NFS export from volume1 Mount instructions (IP:/share): ' NFS_EXPORT; fi
fi
[[ "$NFS_EXPORT" =~ ^[0-9.]+:/[^[:space:]]+$ ]] || { warn 'Missing/invalid NFS export. Set NFS_EXPORT=IP:/share'; exit 1; }
remote() {
  local script="$1" attempt
  for attempt in 1 2 3; do
    if gcloud compute ssh "$VM_NAME" --project="$PROJECT_ID" --zone="$ZONE" --quiet --command="bash -lc $(printf '%q' "$script")"; then return 0; fi
    warn "SSH retry $attempt/3"; sleep 8
  done
  return 1
}
wait_capacity() {
  local wanted="$1" actual attempt
  for attempt in {1..24}; do
    actual="$(gcloud netapp volumes describe "$VOLUME_NAME" --project="$PROJECT_ID" --location="$LOCATION" --format='value(capacityGib)' 2>/dev/null || true)"
    [[ "$actual" == "$wanted" ]] && return 0
    sleep 10
  done
  warn "Volume did not reach $wanted GiB (last: $actual)"; return 1
}
benchmark() {
  local label="$1"
  info "Performance sample: $label (10 seconds, bounded; not a full 9000-second test)"
  remote "set -e; if ! command -v fio >/dev/null; then sudo apt-get update -qq; sudo apt-get install -y -qq fio; fi; timeout 25s sudo fio --directory=/share1 --ioengine=libaio --rw=write --bs=64k --iodepth=24 --size=1g --fallocate=none --direct=1 --runtime=10 --time_based --ramp_time=2 --numjobs=2 --name=netappvolumes || test \"\$?\" -eq 124"
}
info '== Task 1/4 — Mount preprovisioned NetApp volume on vm1 =='
remote "set -e; command -v mount.nfs >/dev/null || { sudo apt-get update -qq; sudo apt-get install -y -qq nfs-common; }; sudo mkdir -p /share1; if ! mountpoint -q /share1; then sudo mount -t nfs -o rw,hard,rsize=65536,wsize=65536,vers=3,tcp '$NFS_EXPORT' /share1; fi; df -h /share1"
ok 'Volume mounted or already mounted'
info '== Task 2/4 — Baseline fio performance =='
benchmark 'initial capacity'
info '== Task 3/4 — Grow volume1 to 2048 GiB and verify =='
gcloud netapp volumes update "$VOLUME_NAME" --project="$PROJECT_ID" --location="$LOCATION" --capacity=2048 --quiet
wait_capacity 2048
remote 'df -h /share1'
benchmark '2048 GiB'
ok 'Volume capacity 2048 GiB verified'
info '== Task 4/4 — Shrink volume1 to 512 GiB and verify =='
gcloud netapp volumes update "$VOLUME_NAME" --project="$PROJECT_ID" --location="$LOCATION" --capacity=512 --quiet
wait_capacity 512
remote 'df -h /share1'
benchmark '512 GiB'
ok 'Volume capacity 512 GiB verified'
warn 'static validated only; runtime/grader unverified. Use Check my progress for the 3 official checkpoints.'
