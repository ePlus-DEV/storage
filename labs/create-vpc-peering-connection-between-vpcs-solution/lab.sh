#!/usr/bin/env bash
# Create VPC Peering Connection between VPCs (Arcade lab)
# Copyright (c) 2026 ePlus.DEV | Unlicense
set -euo pipefail
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != dumb ]]; then
  CYAN=$'\033[1;36m'; YELLOW=$'\033[0;33m'; RESET=$'\033[0m'
else
  CYAN=''; YELLOW=''; RESET=''
fi
printf '%s\n' "${CYAN}ePlus.DEV - Starting Execution | VPC Peering${RESET}" \
  "${YELLOW}Copyright (c) 2026 ePlus.DEV | Unlicense${RESET}"
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
step() { printf '\n[TASK %s] %s\n' "$1" "$2"; }
command -v gcloud >/dev/null 2>&1 || die 'gcloud CLI is required.'
PROJECT_ID="${PROJECT_ID:-${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}}"
if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == '(unset)' ]]; then
  [[ -t 0 ]] || die 'Set PROJECT_ID to your temporary lab project.'
  read -r -p 'Lab project ID: ' PROJECT_ID
fi
[[ "$PROJECT_ID" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]] || die 'Invalid project ID.'
WORKSPACE_VPC="${WORKSPACE_VPC:-workspace-vpc}"
PRIVATE_VPC="${PRIVATE_VPC:-private-vpc}"
[[ "$WORKSPACE_VPC" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]] || die 'Invalid workspace VPC name.'
[[ "$PRIVATE_VPC" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]] || die 'Invalid private VPC name.'
[[ "$WORKSPACE_VPC" != "$PRIVATE_VPC" ]] || die 'VPCs must be different.'

ensure_network() {
  local network="$1"
  if gcloud compute networks describe "$network" --project="$PROJECT_ID" >/dev/null 2>&1; then
    printf 'Using existing VPC: %s\n' "$network"
  else
    printf 'Creating missing lab VPC: %s\n' "$network"
    gcloud compute networks create "$network" --subnet-mode=custom --project="$PROJECT_ID"
  fi
}
ensure_peering() {
  local name="$1" network="$2" peer="$3" existing_peer
  existing_peer="$(gcloud compute networks peerings list --project="$PROJECT_ID" \
    --network="$network" --filter="name=$name" --format='value(peerNetwork)')"
  if [[ -n "$existing_peer" ]]; then
    [[ "${existing_peer##*/}" == "$peer" ]] ||
      die "Peering $name already points to ${existing_peer##*/}, not $peer."
    printf 'Using existing peering: %s\n' "$name"
  else
    gcloud compute networks peerings create "$name" --project="$PROJECT_ID" \
      --network="$network" --peer-network="$peer" --auto-create-routes
  fi
}
wait_active() {
  local name="$1" network="$2" state attempt
  for attempt in 1 2 3 4 5 6; do
    state="$(gcloud compute networks peerings list --project="$PROJECT_ID" \
      --network="$network" --filter="name=$name" --format='value(state)')"
    if [[ "$state" == ACTIVE ]]; then
      printf 'Peering %s: ACTIVE\n' "$name"
      return 0
    fi
    if (( attempt < 6 )); then
      printf 'Waiting for %s (state: %s, attempt %s/6)...\n' "$name" "$state" "$attempt"
      sleep 5
    fi
  done
  die "Peering $name is not ACTIVE (last state: $state)."
}
step 1 "Confirm/create the two lab VPC networks in $PROJECT_ID"
ensure_network "$WORKSPACE_VPC"
ensure_network "$PRIVATE_VPC"
step 2 "Create workspace-to-private peering"
ensure_peering workspace-to-private "$WORKSPACE_VPC" "$PRIVATE_VPC"
step 3 "Create private-to-workspace peering"
ensure_peering private-to-workspace "$PRIVATE_VPC" "$WORKSPACE_VPC"
step 4 'Verify both directions are ACTIVE'
wait_active workspace-to-private "$WORKSPACE_VPC"
wait_active private-to-workspace "$PRIVATE_VPC"
printf '\nBoth peerings are ACTIVE. Click Check my progress in Google Skills.\n'
printf 'Optional VM connectivity testing should be performed separately; this script does not open an interactive SSH session.\n'
