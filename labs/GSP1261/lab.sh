#!/usr/bin/env bash
# Copyright (c) 2026 ePlus.DEV | Unlicense
# GSP1261 — Getting Started with Google Cloud NetApp Volumes
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  bash "${BASH_SOURCE[0]}" "$@"
  return $?
fi
set -Eeuo pipefail
if [[ -z "${NO_COLOR:-}" && ( -t 1 || "${FORCE_COLOR:-0}" == "1" ) ]]; then
  BLUE=$'\033[1;34m'; GREEN=$'\033[1;32m'; RED=$'\033[1;31m'; RESET=$'\033[0m'
else
  BLUE=''; GREEN=''; RED=''; RESET=''
fi
printf '%s\n' "${BLUE}ePlus.DEV – Starting Execution${RESET}" 'Copyright (c) 2026 ePlus.DEV | Unlicense'
fail() { printf '%sERROR: %s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }
step() { printf '\n%s== %s ==%s\n' "$BLUE" "$1" "$RESET"; }
need() { command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1"; }
trap 'printf "%sError at line %s%s\n" "$RED" "$LINENO" "$RESET" >&2' ERR
need gcloud
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ "$PROJECT_ID" =~ ^[a-z][a-z0-9-]{4,61}[a-z0-9]$ ]] || fail 'Select the temporary lab project first'
VM_NAME=vm1
POOL=pool1
VOLUME=volume1
SHARE=share1
NETWORK=default
VM_ZONE="$(gcloud compute instances list --project="$PROJECT_ID" --filter="name=$VM_NAME" --format='value(zone)' | awk -F/ 'NF {print $NF}' | sort -u)"
[[ -n "$VM_ZONE" && "$VM_ZONE" != *$'\n'* && "$VM_ZONE" =~ ^[a-z]+(-[a-z0-9]+)+[0-9]+-[a-z]$ ]] || fail 'Expected exactly one provisioned vm1 with a valid zone'
REGION="${REGION:-${VM_ZONE%-*}}"
[[ "$REGION" =~ ^[a-z]+(-[a-z0-9]+)+[0-9]+$ ]] || fail 'Invalid region'
VM_NETWORK="$(gcloud compute instances describe "$VM_NAME" --project="$PROJECT_ID" --zone="$VM_ZONE" --format='value(networkInterfaces[0].network)')"
[[ "$VM_NETWORK" == */networks/default ]] || fail 'vm1 is not attached to the default VPC; refusing to mount an unrelated export'
printf 'Project: %s | Region: %s | VM zone: %s\n' "$PROJECT_ID" "$REGION" "$VM_ZONE"

wait_ready() {
  local kind="$1" name="$2" state attempt
  for ((attempt=1; attempt<=40; attempt++)); do
    state="$(gcloud netapp "$kind" describe "$name" --project="$PROJECT_ID" --location="$REGION" --format='value(state)' 2>/dev/null || true)"
    [[ "$state" == READY ]] && return 0
    [[ "$state" == ERROR || "$state" == DELETING ]] && fail "$kind/$name entered $state"
    printf '%s/%s: %s (attempt %d/40)\n' "$kind" "$name" "${state:-not-yet-visible}" "$attempt"
    sleep 15
  done
  fail "Timed out waiting for $kind/$name to become READY"
}

step 'Task 1 — Configure private services access and create pool1'
gcloud services enable netapp.googleapis.com servicenetworking.googleapis.com --project="$PROJECT_ID" --quiet
if [[ -z "$(gcloud services vpc-peerings list --project="$PROJECT_ID" --network="$NETWORK" --service=servicenetworking.googleapis.com --format='value(peering)' 2>/dev/null)" ]]; then
  RANGE_NAME="eplus-gsp1261-netapp"
  if ! gcloud compute addresses describe "$RANGE_NAME" --project="$PROJECT_ID" --global >/dev/null 2>&1; then
    gcloud compute addresses create "$RANGE_NAME" --project="$PROJECT_ID" --global \
      --purpose=VPC_PEERING --prefix-length=24 --network="$NETWORK" --quiet
  fi
  gcloud services vpc-peerings connect --project="$PROJECT_ID" --network="$NETWORK" \
    --service=servicenetworking.googleapis.com --ranges="$RANGE_NAME" --quiet
fi
if ! gcloud netapp storage-pools describe "$POOL" --project="$PROJECT_ID" --location="$REGION" >/dev/null 2>&1; then
  gcloud netapp storage-pools create "$POOL" --project="$PROJECT_ID" --location="$REGION" \
    --capacity=2048 --service-level=premium --network=name="$NETWORK" --quiet
fi
wait_ready storage-pools "$POOL"
POOL_LEVEL="$(gcloud netapp storage-pools describe "$POOL" --project="$PROJECT_ID" --location="$REGION" --format='value(serviceLevel)')"
[[ "$POOL_LEVEL" == PREMIUM ]] || fail "Existing pool service level is $POOL_LEVEL, not PREMIUM"

step 'Task 2 — Create NFSv3 volume1 (share1, 100 GiB)'
if ! gcloud netapp volumes describe "$VOLUME" --project="$PROJECT_ID" --location="$REGION" >/dev/null 2>&1; then
  gcloud netapp volumes create "$VOLUME" --project="$PROJECT_ID" --location="$REGION" \
    --storage-pool="$POOL" --capacity=100 --protocols=nfsv3 --share-name="$SHARE" \
    --export-policy=access-type=READ_WRITE,allowed-clients=10.128.0.0/9,has-root-access=true,nfsv3=true \
    --quiet
fi
wait_ready volumes "$VOLUME"
VOLUME_SHARE="$(gcloud netapp volumes describe "$VOLUME" --project="$PROJECT_ID" --location="$REGION" --format='value(shareName)')"
[[ "$VOLUME_SHARE" == "$SHARE" ]] || fail "Existing volume share is $VOLUME_SHARE, not $SHARE"
SERVER_IP="$(gcloud netapp volumes describe "$VOLUME" --project="$PROJECT_ID" --location="$REGION" --format='value(mountOptions[0].ipAddress)')"
[[ "$SERVER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || fail 'Volume mount IP not available; inspect mount instructions in console'

step 'Task 3 — Mount volume on vm1 and verify'
REMOTE_CMD="set -e; sudo apt-get update -qq; sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nfs-common; sudo mkdir -p /share1; if ! mountpoint -q /share1; then sudo mount -t nfs -o rw,hard,rsize=65536,wsize=65536,vers=3,tcp ${SERVER_IP}:/share1 /share1; fi; findmnt -n -o SOURCE,FSTYPE,TARGET /share1"
gcloud compute ssh "$VM_NAME" --project="$PROJECT_ID" --zone="$VM_ZONE" --quiet --command="$REMOTE_CMD"
printf '\n%sAll three tasks configured. Click Check my progress for each checkpoint.%s\n' "$GREEN" "$RESET"
printf '%s\n' 'static validated only; runtime/grader unverified'
