#!/usr/bin/env bash
# Copyright (c) 2026 ePlus.DEV | Unlicense
set -Eeuo pipefail
if [[ -v NO_COLOR ]]; then CYAN='' GREEN='' YELLOW='' RESET=''
elif [[ -t 1 || "${FORCE_COLOR:-0}" == 1 ]]; then
  CYAN=$'\033[1;36m'; GREEN=$'\033[1;32m'; YELLOW=$'\033[1;33m'; RESET=$'\033[0m'
else CYAN='' GREEN='' YELLOW='' RESET=''; fi
log() { printf '%s%s%s\n' "$CYAN" "$*" "$RESET"; }
ok() { printf '%s%s%s\n' "$GREEN" "$*" "$RESET"; }
warn() { printf '%s%s%s\n' "$YELLOW" "$*" "$RESET"; }
trap 'warn "Failed at line $LINENO (exit $?)."' ERR
printf '%s\n' "${CYAN}ePlus.DEV – Starting Execution${RESET}" 'GSP1312 — NetApp snapshots (static validated only; runtime/grader unverified)'
for cmd in gcloud curl grep head; do command -v "$cmd" >/dev/null || { warn "Missing $cmd"; exit 1; }; done
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != '(unset)' ]] || { warn 'Choose an authorized lab project'; exit 1; }
VM=vm1
VOLUME=volume1
SNAPSHOT=snapshot1
ZONE="${ZONE:-$(gcloud compute instances list --project="$PROJECT_ID" --filter="name=$VM" --format='value(zone.basename())' | head -n 1)}"
[[ -n "$ZONE" ]] || { warn 'Preprovisioned vm1 not found'; exit 1; }
VOLUME_PATH="$(gcloud netapp volumes list --project="$PROJECT_ID" --format='value(name)' | grep '/volumes/volume1$' | head -n 1 || true)"
[[ "$VOLUME_PATH" =~ /locations/([^/]+)/volumes/volume1$ ]] || { warn 'Preprovisioned volume1 not found'; exit 1; }
LOCATION="${BASH_REMATCH[1]}"
NFS_EXPORT="${NFS_EXPORT:-$(gcloud netapp volumes describe "$VOLUME" --project="$PROJECT_ID" --location="$LOCATION" --format='value(mountOptions[0].exportFull)' 2>/dev/null || true)}"
if [[ -z "$NFS_EXPORT" && -t 0 ]]; then read -r -p 'NFS export from volume1 Mount instructions (IP:/share): ' NFS_EXPORT; fi
[[ "$NFS_EXPORT" =~ ^[0-9.]+:/[^[:space:]]+$ ]] || { warn 'Set NFS_EXPORT to the verified lab volume export'; exit 1; }
remote() {
  local script="$1" attempt
  for attempt in 1 2 3; do
    if gcloud compute ssh "$VM" --project="$PROJECT_ID" --zone="$ZONE" --quiet --command="bash -lc $(printf '%q' "$script")"; then return 0; fi
    warn "SSH retry $attempt/3"; sleep 8
  done
  return 1
}
wait_snapshot() {
  local attempt state
  for attempt in {1..24}; do
    state="$(gcloud netapp volumes snapshots describe "$SNAPSHOT" --volume="$VOLUME" --location="$LOCATION" --project="$PROJECT_ID" --format='value(state)' 2>/dev/null || true)"
    [[ "$state" == READY ]] && return 0
    sleep 10
  done
  warn "Snapshot not READY (last: $state)"; return 1
}
log '== Task 1/5 — Mount volume1 on preprovisioned vm1 =='
remote "set -e; command -v mount.nfs >/dev/null || { sudo apt-get update -qq; sudo apt-get install -y -qq nfs-common; }; sudo mkdir -p /share1; if ! mountpoint -q /share1; then sudo mount -t nfs -o rw,hard,rsize=65536,wsize=65536,vers=3,tcp '$NFS_EXPORT' /share1; fi; df -h /share1"
ok 'NFS mount verified'
log '== Task 2/5 — Create files and manual snapshot1 =='
remote "set -e; sudo mkdir -p /share1/folder1 /share1/folder2; printf 'important\\n' | sudo tee /share1/file1.txt >/dev/null; printf 'top secret\\n' | sudo tee /share1/file2.txt >/dev/null; sudo ls -la /share1"
if ! gcloud netapp volumes snapshots describe "$SNAPSHOT" --volume="$VOLUME" --location="$LOCATION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud netapp volumes snapshots create "$SNAPSHOT" --volume="$VOLUME" --location="$LOCATION" --project="$PROJECT_ID" --quiet
fi
wait_snapshot
ok 'snapshot1 READY'
log '== Task 3/5 — Restore file1.txt from snapshot directory =='
gcloud netapp volumes update "$VOLUME" --project="$PROJECT_ID" --location="$LOCATION" --snapshot-directory=true --quiet
remote "set -e; sudo rm -f /share1/file1.txt; sudo test -f /share1/.snapshot/snapshot1/file1.txt; sudo cp /share1/.snapshot/snapshot1/file1.txt /share1/file1.txt; sudo test -f /share1/file1.txt; sudo ls -la /share1"
ok 'file1.txt restored'
log '== Task 4/5 — Configure hourly/daily/weekly/monthly snapshots =='
# The gcloud update command does not expose snapshotPolicy.enabled; patch only that policy.
POLICY_JSON='{"snapshotPolicy":{"enabled":true,"hourlySchedule":{"snapshotsToKeep":24,"minute":0},"dailySchedule":{"snapshotsToKeep":7,"hour":0,"minute":0},"weeklySchedule":{"snapshotsToKeep":8,"day":"Sunday","hour":0,"minute":0},"monthlySchedule":{"snapshotsToKeep":3,"daysOfMonth":"1","hour":0,"minute":0}}}'
TOKEN="$(gcloud auth print-access-token)"
[[ -n "$TOKEN" ]] || { warn 'No authorized lab access token'; exit 1; }
curl -fsS --retry 3 -X PATCH \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  "https://netapp.googleapis.com/v1/$VOLUME_PATH?updateMask=snapshotPolicy" \
  -d "$POLICY_JSON" >/dev/null
unset TOKEN
for attempt in {1..24}; do
  enabled="$(gcloud netapp volumes describe "$VOLUME" --project="$PROJECT_ID" --location="$LOCATION" --format='value(snapshotPolicy.enabled)' 2>/dev/null || true)"
  [[ "$enabled" == 'True' || "$enabled" == 'true' ]] && break
  sleep 10
done
[[ "$enabled" == 'True' || "$enabled" == 'true' ]] || { warn 'Snapshot policy not confirmed enabled'; exit 1; }
ok 'Scheduled snapshots enabled'
log '== Task 5/5 — Revert volume1 to snapshot1 =='
warn 'Revert is destructive to changes made after snapshot1, as required by this temporary lab.'
remote 'sudo rm -f /share1/file1.txt /share1/file2.txt; sudo rm -rf /share1/folder1 /share1/folder2; sudo ls -la /share1'
gcloud netapp volumes revert "$VOLUME" --location="$LOCATION" --project="$PROJECT_ID" --snapshot="$SNAPSHOT" --quiet
remote 'set -e; for i in $(seq 1 24); do if sudo test -f /share1/file1.txt && sudo test -f /share1/file2.txt; then sudo ls -la /share1; exit 0; fi; sleep 10; done; exit 1'
ok 'Reverted files confirmed. Use all four official Check my progress buttons.'
warn 'static validated only; runtime/grader unverified'
