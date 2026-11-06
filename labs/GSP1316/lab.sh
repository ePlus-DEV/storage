#!/usr/bin/env bash
# Copyright (c) 2026 ePlus.DEV | Unlicense
# GSP1316 — Establish Site to Site Connectivity with HA-VPN using NCC
# static validated only; runtime/grader unverified
set -Eeuo pipefail
if [[ -n "${NO_COLOR:-}" ]]; then C='' G='' Y='' R='';
elif [[ -t 1 || "${FORCE_COLOR:-0}" == 1 ]]; then
  C=$'\033[36m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[0m'
else C='' G='' Y='' R=''; fi
info(){ printf '%s[INFO]%s %s\n' "$C" "$R" "$*"; }
warn(){ printf '%s[WARN]%s %s\n' "$Y" "$R" "$*" >&2; }
die(){ printf '[ERROR] %s\n' "$*" >&2; exit 1; }
printf '%sePlus.DEV – Starting Execution%s\n' "$C" "$R"
printf 'Copyright (c) 2026 ePlus.DEV | Unlicense\n'
for c in gcloud jq; do command -v "$c" >/dev/null || die "Missing $c"; done
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != '(unset)' ]] || die 'Use the temporary lab project.'
HUB_NAME="${HUB_NAME:-site-to-site-hub}"
[[ "$HUB_NAME" =~ ^[a-z][a-z0-9-]{1,61}[a-z0-9]$ ]] || die 'Invalid NCC hub name.'
zone_of(){ gcloud compute instances list --project="$PROJECT_ID" --filter="name=$1" --format='value(zone)' | head -n1 | awk -F/ '{print $NF}'; }
ZONE1="${ZONE1:-$(zone_of onprem-office1-vm)}"
ZONE2="${ZONE2:-$(zone_of onprem-office2-vm)}"
[[ "$ZONE1" =~ ^[a-z]+-[a-z0-9]+[0-9]-[a-z]$ && "$ZONE2" =~ ^[a-z]+-[a-z0-9]+[0-9]-[a-z]$ ]] || die 'Missing office VM zones.'
REGION1="${REGION1:-${ZONE1%-*}}"; REGION2="${REGION2:-${ZONE2%-*}}"
[[ "$REGION1" == "${ZONE1%-*}" && "$REGION2" == "${ZONE2%-*}" ]] || die 'Office VM zone/region mismatch.'
[[ "$REGION1" != "$REGION2" ]] || die 'Expected two different office regions; inspect lab resources.'
info "Project=$PROJECT_ID Office1=$REGION1 Office2=$REGION2"
gcloud compute networks describe routing-vpc --project="$PROJECT_ID" >/dev/null || die 'Missing pre-provisioned routing-vpc.'
gcloud services enable networkconnectivity.googleapis.com --project="$PROJECT_ID" --quiet

# Discover only routing-vpc-side tunnels, not the on-premises-side peers.
# Require exactly two HA VPN tunnels per office; refuse ambiguous selections.
discover_tunnels(){
  local region="$1" name router network
  local -a found=()
  while IFS=$'\t' read -r name router; do
    [[ -n "$name" && -n "$router" ]] || continue
    network="$(gcloud compute routers describe "${router##*/}" --project="$PROJECT_ID" --region="$region" --format='value(network)' 2>/dev/null || true)"
    if [[ "${network##*/}" == routing-vpc ]]; then found+=("$name"); fi
  done < <(gcloud compute vpn-tunnels list --project="$PROJECT_ID" --format=json |
    jq -r --arg region "$region" '.[] | select((.region | split("/")[-1]) == $region) | [.name, (.router // "")] | @tsv')
  (( ${#found[@]} == 2 )) || die "Expected exactly two routing-vpc HA VPN tunnels in $region; found ${#found[@]}. Set OFFICE1_TUNNELS/OFFICE2_TUNNELS only after manual verification."
  printf '%s,%s\n' "${found[0]}" "${found[1]}"
}
TUNNELS1="${OFFICE1_TUNNELS:-$(discover_tunnels "$REGION1")}"
TUNNELS2="${OFFICE2_TUNNELS:-$(discover_tunnels "$REGION2")}"
validate_tunnels(){
  local region="$1" csv="$2" t
  local -a items=()
  IFS=',' read -r -a items <<< "$csv"
  (( ${#items[@]} == 2 )) || die "Expected two comma-separated tunnel names in $region."
  [[ "${items[0]}" != "${items[1]}" ]] || die 'Tunnel names must differ.'
  for t in "${items[@]}"; do
    gcloud compute vpn-tunnels describe "$t" --project="$PROJECT_ID" --region="$region" >/dev/null || die "Missing tunnel $t in $region"
  done
}
validate_tunnels "$REGION1" "$TUNNELS1"
validate_tunnels "$REGION2" "$TUNNELS2"
info "Office 1 routing-side tunnels: $TUNNELS1"
info "Office 2 routing-side tunnels: $TUNNELS2"
hub_exists(){ gcloud network-connectivity hubs describe "$HUB_NAME" --project="$PROJECT_ID" >/dev/null 2>&1; }
spoke_exists(){ gcloud network-connectivity spokes describe "$1" --project="$PROJECT_ID" --region="$2" >/dev/null 2>&1; }
retry(){ local max="$1" delay="$2" i; shift 2; for ((i=1;i<=max;i++)); do
  if "$@"; then return 0; fi
  if ((i<max)); then warn "Retry $i/$max"; sleep "$delay"; fi
done; return 1; }

info 'Task 1: create NCC hub'
if ! hub_exists; then gcloud network-connectivity hubs create "$HUB_NAME" --project="$PROJECT_ID" --quiet; fi
retry 10 5 gcloud network-connectivity hubs describe "$HUB_NAME" --project="$PROJECT_ID" >/dev/null || die 'NCC hub not ready.'
info 'Task 2: attach two HA VPN tunnel spokes'
if ! spoke_exists office-1-spoke "$REGION1"; then
  gcloud network-connectivity spokes linked-vpn-tunnels create office-1-spoke --project="$PROJECT_ID" --hub="$HUB_NAME" --region="$REGION1" --vpn-tunnels="$TUNNELS1" --site-to-site-data-transfer --quiet
fi
if ! spoke_exists office-2-spoke "$REGION2"; then
  gcloud network-connectivity spokes linked-vpn-tunnels create office-2-spoke --project="$PROJECT_ID" --hub="$HUB_NAME" --region="$REGION2" --vpn-tunnels="$TUNNELS2" --site-to-site-data-transfer --quiet
fi
gcloud network-connectivity hubs list-spokes "$HUB_NAME" --project="$PROJECT_ID"
info 'Task 1-2 checkpoint: Create a Hub and Spokes (100 points)'

info 'Task 3: verify connectivity between office VMs'
ip_of(){ gcloud compute instances describe "$1" --project="$PROJECT_ID" --zone="$2" --format='value(networkInterfaces[0].networkIP)'; }
IP1="$(ip_of onprem-office1-vm "$ZONE1")"; IP2="$(ip_of onprem-office2-vm "$ZONE2")"
[[ "$IP1" =~ ^[0-9.]+$ && "$IP2" =~ ^[0-9.]+$ ]] || die 'Unable to discover both office VM internal IPs.'
retry 5 15 gcloud compute ssh onprem-office1-vm --project="$PROJECT_ID" --zone="$ZONE1" --quiet --command="ping -c 5 -W 3 $IP2" || die 'Office 1 -> Office 2 ping failed.'
retry 5 15 gcloud compute ssh onprem-office2-vm --project="$PROJECT_ID" --zone="$ZONE2" --quiet --command="ping -c 5 -W 3 $IP1" || die 'Office 2 -> Office 1 ping failed.'
printf '%s[OK]%s Both office-to-office paths responded\n' "$G" "$R"

# Task 4: cleanup is opt-in to preserve grader state.
if [[ "${CLEANUP:-0}" == 1 ]]; then
  [[ "${CONFIRM_CLEANUP:-}" == YES ]] || die 'Set CONFIRM_CLEANUP=YES only after checking the grader.'
  for entry in "office-1-spoke:$REGION1" "office-2-spoke:$REGION2"; do
    name="${entry%%:*}"; region="${entry#*:}"
    if spoke_exists "$name" "$region"; then
      gcloud network-connectivity spokes delete "$name" --project="$PROJECT_ID" --region="$region" --quiet
    fi
  done
  if hub_exists; then gcloud network-connectivity hubs delete "$HUB_NAME" --project="$PROJECT_ID" --quiet; fi
else
  info 'Task 4 cleanup skipped. Use CLEANUP=1 CONFIRM_CLEANUP=YES after grading.'
fi
info 'Finished: static validated only; runtime/grader unverified.'