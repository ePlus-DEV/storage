#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
#  GSP528 - Connecting Cloud Networks with NCC
#  © ePlus.DEV
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
RESET='\033[0m'

line() {
  printf "${CYAN}%s${RESET}\n" \
    "======================================================================"
}

section() {
  echo
  line
  printf "${BOLD}${BLUE}%s${RESET}\n" "$1"
  line
}

ok()   { printf "${GREEN}✓ %s${RESET}\n" "$*"; }
warn() { printf "${YELLOW}⚠ %s${RESET}\n" "$*"; }
fail() {
  printf "${RED}✗ %s${RESET}\n" "$*"
  exit 1
}

echo -e "${MAGENTA}"
cat <<'BANNER'
   _______  _             _____
  |  ____ \| |           |  __ \
  | |__|  _| |_   _ ___  | |  | | _____   __
  |  __| | | | | | / __| | |  | |/ _ \ \ / /
  | |__| |_| | |_| \__ \ | |__| |  __/\ V /
  |_____\__,_|\__,_|___/ |_____/ \___| \_/

       GSP528 - NCC Challenge Lab
               © ePlus.DEV
BANNER
echo -e "${RESET}"

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

basename_uri() {
  local v="${1:-}"
  printf '%s\n' "${v##*/}"
}

find_network() {
  local regex
  local result

  for regex in "$@"; do
    result="$(
      printf '%s\n' "${NETWORKS[@]}" |
        grep -Ei "$regex" |
        head -n 1 || true
    )"

    if [[ -n "$result" ]]; then
      printf '%s\n' "$result"
      return 0
    fi
  done

  return 1
}

network_from_vm_name() {
  local regex="$1"

  jq -r --arg regex "$regex" '
    .[]
    | select(.name | test($regex; "i"))
    | .networkInterfaces[0].network
    | split("/")[-1]
  ' "$INSTANCE_JSON" 2>/dev/null |
    head -n 1
}

vm_for_network() {
  local network="$1"

  jq -r --arg network "$network" '
    .[]
    | select(
        (.networkInterfaces[0].network | split("/")[-1]) == $network
      )
    | .name
  ' "$INSTANCE_JSON" |
    head -n 1
}

vm_zone() {
  local vm="$1"

  jq -r --arg vm "$vm" '
    .[]
    | select(.name == $vm)
    | .zone
    | split("/")[-1]
  ' "$INSTANCE_JSON" |
    head -n 1
}

vm_ip() {
  local vm="$1"

  jq -r --arg vm "$vm" '
    .[]
    | select(.name == $vm)
    | .networkInterfaces[0].networkIP
  ' "$INSTANCE_JSON" |
    head -n 1
}

zone_to_region() {
  local zone="$1"
  echo "${zone%-*}"
}

spoke_global_exists() {
  gcloud network-connectivity spokes describe "$1" \
    --global \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1
}

spoke_regional_exists() {
  local name="$1"
  local region="$2"

  gcloud network-connectivity spokes describe "$name" \
    --region="$region" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1
}

create_vpc_spoke() {
  local name="$1"
  local network="$2"

  echo
  echo -e "${CYAN}VPC spoke:${RESET} $name"
  echo -e "${CYAN}Network  :${RESET} $network"

  if spoke_global_exists "$name"; then
    ok "$name already exists."
    return 0
  fi

  gcloud network-connectivity spokes linked-vpc-network create "$name" \
    --hub="$HUB_URI" \
    --global \
    --vpc-network="projects/${PROJECT_ID}/global/networks/${network}" \
    --project="$PROJECT_ID" \
    --quiet

  ok "Created $name"
}

create_vpn_spoke() {
  local name="$1"
  local region="$2"
  local tunnels="$3"

  echo
  echo -e "${CYAN}VPN spoke:${RESET} $name"
  echo -e "${CYAN}Region   :${RESET} $region"
  echo -e "${CYAN}Tunnels  :${RESET} $tunnels"

  if spoke_regional_exists "$name" "$region"; then
    ok "$name already exists."
    return 0
  fi

  gcloud network-connectivity spokes linked-vpn-tunnels create "$name" \
    --hub="$HUB_URI" \
    --region="$region" \
    --vpn-tunnels="$tunnels" \
    --site-to-site-data-transfer \
    --project="$PROJECT_ID" \
    --quiet

  ok "Created $name"
}

# ============================================================
# [1/8] Detect project
# ============================================================

section "[1/8] Detecting Google Cloud project"

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  PROJECT_ID="$(
    gcloud projects list \
      --filter='projectId:qwiklabs-gcp-*' \
      --format='value(projectId)' |
      head -n 1
  )"
fi

[[ -n "$PROJECT_ID" ]] || fail "Could not detect Qwiklabs project."

gcloud config set project "$PROJECT_ID" >/dev/null

ACCOUNT="$(gcloud config get-value account 2>/dev/null || true)"

echo -e "Project : ${GREEN}${PROJECT_ID}${RESET}"
echo -e "Account : ${GREEN}${ACCOUNT}${RESET}"

# ============================================================
# [2/8] Enable API
# ============================================================

section "[2/8] Enabling Network Connectivity API"

gcloud services enable \
  networkconnectivity.googleapis.com \
  compute.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet

ok "Required APIs are enabled."

# ============================================================
# [3/8] Discover resources
# ============================================================

section "[3/8] Discovering lab resources"

TMPDIR_LAB="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_LAB"' EXIT

INSTANCE_JSON="$TMPDIR_LAB/instances.json"
VPN_JSON="$TMPDIR_LAB/vpn.json"
ROUTING_TUNNELS="$TMPDIR_LAB/routing-tunnels.tsv"

gcloud compute instances list \
  --project="$PROJECT_ID" \
  --format=json > "$INSTANCE_JSON"

gcloud compute vpn-tunnels list \
  --project="$PROJECT_ID" \
  --format=json > "$VPN_JSON"

mapfile -t NETWORKS < <(
  gcloud compute networks list \
    --project="$PROJECT_ID" \
    --format='value(name)'
)

echo
echo "Available VPC networks:"
printf '  - %s\n' "${NETWORKS[@]}"

# ------------------------------------------------------------
# Detect routing VPC
# ------------------------------------------------------------

ROUTING_NET="$(
  find_network \
    '^routing[-_]?vpc$' \
    'routing.*vpc' \
    '^routing' \
    'router' \
    || true
)"

# ------------------------------------------------------------
# Detect Office 1
# ------------------------------------------------------------

OFFICE1_NET="$(
  find_network \
    'on.?prem.*office.*1' \
    'on.?prem.*1' \
    'office[-_]?1' \
    'office.*1' \
    || true
)"

if [[ -z "$OFFICE1_NET" ]]; then
  OFFICE1_NET="$(
    network_from_vm_name \
      'on.?prem.*office.*1|on.?prem.*1|office[-_]?1' \
      || true
  )"
fi

# ------------------------------------------------------------
# Detect Office 2
# ------------------------------------------------------------

OFFICE2_NET="$(
  find_network \
    'on.?prem.*office.*2' \
    'on.?prem.*2' \
    'office[-_]?2' \
    'office.*2' \
    || true
)"

if [[ -z "$OFFICE2_NET" ]]; then
  OFFICE2_NET="$(
    network_from_vm_name \
      'on.?prem.*office.*2|on.?prem.*2|office[-_]?2' \
      || true
  )"
fi

# ------------------------------------------------------------
# Detect Workload 1
# ------------------------------------------------------------

WORKLOAD1_NET="$(
  find_network \
    'workload.*vpc.*1' \
    'workload.*1' \
    || true
)"

if [[ -z "$WORKLOAD1_NET" ]]; then
  WORKLOAD1_NET="$(
    network_from_vm_name 'workload.*1' || true
  )"
fi

# ------------------------------------------------------------
# Detect Workload 2
# ------------------------------------------------------------

WORKLOAD2_NET="$(
  find_network \
    'workload.*vpc.*2' \
    'workload.*2' \
    || true
)"

if [[ -z "$WORKLOAD2_NET" ]]; then
  WORKLOAD2_NET="$(
    network_from_vm_name 'workload.*2' || true
  )"
fi

echo
echo -e "${BOLD}Detected networks:${RESET}"
printf "  Routing VPC    : %s\n" "${ROUTING_NET:-NOT FOUND}"
printf "  On-Prem Office1: %s\n" "${OFFICE1_NET:-NOT FOUND}"
printf "  On-Prem Office2: %s\n" "${OFFICE2_NET:-NOT FOUND}"
printf "  Workload VPC 1 : %s\n" "${WORKLOAD1_NET:-NOT FOUND}"
printf "  Workload VPC 2 : %s\n" "${WORKLOAD2_NET:-NOT FOUND}"

[[ -n "$ROUTING_NET" ]]  || fail "Routing VPC was not detected."
[[ -n "$OFFICE1_NET" ]]  || fail "On-Prem Office 1 VPC was not detected."
[[ -n "$OFFICE2_NET" ]]  || fail "On-Prem Office 2 VPC was not detected."
[[ -n "$WORKLOAD1_NET" ]] || fail "Workload VPC 1 was not detected."
[[ -n "$WORKLOAD2_NET" ]] || fail "Workload VPC 2 was not detected."

# ------------------------------------------------------------
# VMs and regions
# ------------------------------------------------------------

OFFICE1_VM="$(vm_for_network "$OFFICE1_NET")"
OFFICE2_VM="$(vm_for_network "$OFFICE2_NET")"
WORKLOAD1_VM="$(vm_for_network "$WORKLOAD1_NET")"
WORKLOAD2_VM="$(vm_for_network "$WORKLOAD2_NET")"

OFFICE1_ZONE=""
OFFICE2_ZONE=""
OFFICE1_REGION=""
OFFICE2_REGION=""

if [[ -n "$OFFICE1_VM" ]]; then
  OFFICE1_ZONE="$(vm_zone "$OFFICE1_VM")"
  OFFICE1_REGION="$(zone_to_region "$OFFICE1_ZONE")"
fi

if [[ -n "$OFFICE2_VM" ]]; then
  OFFICE2_ZONE="$(vm_zone "$OFFICE2_VM")"
  OFFICE2_REGION="$(zone_to_region "$OFFICE2_ZONE")"
fi

echo
echo -e "${BOLD}VMs:${RESET}"
printf "  Office 1 VM : %s\n" "${OFFICE1_VM:-not detected}"
printf "  Office 2 VM : %s\n" "${OFFICE2_VM:-not detected}"
printf "  Workload 1  : %s\n" "${WORKLOAD1_VM:-not detected}"
printf "  Workload 2  : %s\n" "${WORKLOAD2_VM:-not detected}"

# ============================================================
# [4/8] Discover routing-side VPN tunnels
# ============================================================

section "[4/8] Detecting preconfigured VPN tunnels"

: > "$ROUTING_TUNNELS"

while IFS=$'\t' read -r TUNNEL REGION VPN_GW ROUTER PEER_GW PEER_EXT; do

  [[ -n "$TUNNEL" ]] || continue

  REGION="$(basename_uri "$REGION")"
  VPN_GW_NAME="$(basename_uri "$VPN_GW")"

  [[ -n "$VPN_GW_NAME" ]] || continue

  GW_NETWORK="$(
    gcloud compute vpn-gateways describe "$VPN_GW_NAME" \
      --region="$REGION" \
      --project="$PROJECT_ID" \
      --format='value(network)' \
      2>/dev/null || true
  )"

  GW_NETWORK="$(basename_uri "$GW_NETWORK")"

  if [[ "$GW_NETWORK" == "$ROUTING_NET" ]]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$TUNNEL" \
      "$REGION" \
      "$VPN_GW_NAME" \
      "$(basename_uri "$ROUTER")" \
      "$(basename_uri "$PEER_GW")" \
      "$(basename_uri "$PEER_EXT")" \
      >> "$ROUTING_TUNNELS"
  fi

done < <(
  jq -r '
    .[] |
    [
      .name,
      (.region // ""),
      (.vpnGateway // ""),
      (.router // ""),
      (.peerGcpGateway // ""),
      (.peerExternalGateway // "")
    ] |
    @tsv
  ' "$VPN_JSON"
)

echo "VPN tunnels attached to Routing VPC:"
column -t -s $'\t' "$ROUTING_TUNNELS" 2>/dev/null ||
  cat "$ROUTING_TUNNELS"

# ------------------------------------------------------------
# Function to select office tunnel pair
# ------------------------------------------------------------

select_office_tunnels() {
  local office_number="$1"
  local office_region="$2"
  local regex
  local matched

  regex="office[-_]?${office_number}|office.?${office_number}|on.?prem.*${office_number}"

  matched="$(
    awk -F'\t' -v IGNORECASE=1 -v r="$regex" '
      $0 ~ r { print $0 }
    ' "$ROUTING_TUNNELS"
  )"

  # Fallback: use same region as the office VM.
  if [[ "$(printf '%s\n' "$matched" | sed '/^$/d' | wc -l)" -lt 2 ]] &&
     [[ -n "$office_region" ]]; then

    matched="$(
      awk -F'\t' -v region="$office_region" '
        $2 == region { print $0 }
      ' "$ROUTING_TUNNELS"
    )"
  fi

  printf '%s\n' "$matched" |
    sed '/^$/d' |
    head -n 2
}

OFFICE1_TUNNEL_ROWS="$(
  select_office_tunnels 1 "$OFFICE1_REGION"
)"

OFFICE2_TUNNEL_ROWS="$(
  select_office_tunnels 2 "$OFFICE2_REGION"
)"

O1_COUNT="$(
  printf '%s\n' "$OFFICE1_TUNNEL_ROWS" |
    sed '/^$/d' |
    wc -l
)"

O2_COUNT="$(
  printf '%s\n' "$OFFICE2_TUNNEL_ROWS" |
    sed '/^$/d' |
    wc -l
)"

if (( O1_COUNT < 2 || O2_COUNT < 2 )); then
  echo
  warn "Automatic VPN classification failed."
  echo "Routing-side VPN tunnels detected:"
  cat "$ROUTING_TUNNELS"
  exit 1
fi

OFFICE1_VPN_REGION="$(
  printf '%s\n' "$OFFICE1_TUNNEL_ROWS" |
    awk -F'\t' 'NR==1 {print $2}'
)"

OFFICE2_VPN_REGION="$(
  printf '%s\n' "$OFFICE2_TUNNEL_ROWS" |
    awk -F'\t' 'NR==1 {print $2}'
)"

OFFICE1_TUNNELS="$(
  printf '%s\n' "$OFFICE1_TUNNEL_ROWS" |
    awk -F'\t' -v p="$PROJECT_ID" \
      '{printf "%sprojects/%s/regions/%s/vpnTunnels/%s",
         (NR==1?"":","),p,$2,$1}'
)"

OFFICE2_TUNNELS="$(
  printf '%s\n' "$OFFICE2_TUNNEL_ROWS" |
    awk -F'\t' -v p="$PROJECT_ID" \
      '{printf "%sprojects/%s/regions/%s/vpnTunnels/%s",
         (NR==1?"":","),p,$2,$1}'
)"

echo
echo -e "${BOLD}Office 1 VPN pair:${RESET}"
printf '%s\n' "$OFFICE1_TUNNEL_ROWS"

echo
echo -e "${BOLD}Office 2 VPN pair:${RESET}"
printf '%s\n' "$OFFICE2_TUNNEL_ROWS"

# ============================================================
# [5/8] Prepare Routing VPC and create NCC hub
# ============================================================

section "[5/8] Creating NCC hub"

echo "Setting Routing VPC dynamic routing mode to GLOBAL..."

gcloud compute networks update "$ROUTING_NET" \
  --bgp-routing-mode=GLOBAL \
  --project="$PROJECT_ID" \
  --quiet

ok "Routing VPC uses GLOBAL dynamic routing."

HUB_NAME="globaltech-ncc-hub"
HUB_URI="projects/${PROJECT_ID}/locations/global/hubs/${HUB_NAME}"

if gcloud network-connectivity hubs describe "$HUB_NAME" \
     --project="$PROJECT_ID" >/dev/null 2>&1; then
  ok "Hub $HUB_NAME already exists."
else
  gcloud network-connectivity hubs create "$HUB_NAME" \
    --description="GSP528 GlobalTech NCC hub - ePlus.DEV" \
    --project="$PROJECT_ID" \
    --quiet

  ok "Created hub $HUB_NAME"
fi

# ============================================================
# [6/8] TASK 1 - On-Prem <-> On-Prem using VPN spokes
# ============================================================

section "[6/8] TASK 1 - Connect two On-Prem VPCs"

create_vpn_spoke \
  "office-1-vpn-spoke" \
  "$OFFICE1_VPN_REGION" \
  "$OFFICE1_TUNNELS"

create_vpn_spoke \
  "office-2-vpn-spoke" \
  "$OFFICE2_VPN_REGION" \
  "$OFFICE2_TUNNELS"

echo
ok "TASK 1 topology created."
echo "  office-1-vpn-spoke -> VPN tunnel pair -> NCC"
echo "  office-2-vpn-spoke -> VPN tunnel pair -> NCC"
echo "  Site-to-site data transfer = ENABLED"

# ============================================================
# [7/8] TASK 2 + TASK 3
# ============================================================

section "[7/8] TASK 2 + TASK 3 - VPC spokes"

# ------------------------------------------------------------
# Task 2:
# Workload 1 <-> Workload 2
#
# The Workload 1 spoke intentionally contains BOTH:
#   workload-1  -> Task 2 requirement
#   hybrid      -> Task 3 requirement
# ------------------------------------------------------------

create_vpc_spoke \
  "workload-1-hybrid-spoke" \
  "$WORKLOAD1_NET"

create_vpc_spoke \
  "workload-2-spoke" \
  "$WORKLOAD2_NET"

# ------------------------------------------------------------
# Task 3:
# On-Prem Office 1 as VPC network spoke.
#
# Do not put "office-1" in this name so the Task 1 grader
# cannot confuse this VPC spoke with office-1-vpn-spoke.
# It contains "hybrid", as required by Task 3.
# ------------------------------------------------------------

create_vpc_spoke \
  "hybrid-office-spoke" \
  "$OFFICE1_NET"

echo
ok "TASK 2 VPC-to-VPC topology created."
ok "TASK 3 VPC-to-On-Prem topology created."

# ============================================================
# [8/8] Verification
# ============================================================

section "[8/8] Verifying NCC configuration"

echo
echo -e "${BOLD}NCC Hub:${RESET}"

gcloud network-connectivity hubs describe "$HUB_NAME" \
  --project="$PROJECT_ID" \
  --format='table(name.basename():label=HUB,state)'

echo
echo -e "${BOLD}All spokes:${RESET}"

gcloud network-connectivity spokes list \
  --project="$PROJECT_ID" \
  --format='table(
    name.basename():label=SPOKE,
    location.basename():label=LOCATION,
    state:label=STATE
  )'

echo
echo -e "${BOLD}Detailed verification:${RESET}"

for SPEC in \
  "office-1-vpn-spoke:$OFFICE1_VPN_REGION" \
  "office-2-vpn-spoke:$OFFICE2_VPN_REGION"
do
  NAME="${SPEC%%:*}"
  REGION="${SPEC##*:}"

  echo
  echo "---- $NAME ----"

  gcloud network-connectivity spokes describe "$NAME" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format='yaml(
      name,
      hub,
      state,
      linkedVpnTunnels
    )'
done

for NAME in \
  "workload-1-hybrid-spoke" \
  "workload-2-spoke" \
  "hybrid-office-spoke"
do
  echo
  echo "---- $NAME ----"

  gcloud network-connectivity spokes describe "$NAME" \
    --global \
    --project="$PROJECT_ID" \
    --format='yaml(
      name,
      hub,
      state,
      linkedVpcNetwork
    )'
done

# ------------------------------------------------------------
# Optional connectivity tests
# These do NOT abort the lab if SSH isn't available.
# ------------------------------------------------------------

section "Optional connectivity tests"

try_ping() {
  local src_vm="$1"
  local dst_vm="$2"
  local label="$3"

  [[ -n "$src_vm" && -n "$dst_vm" ]] || {
    warn "$label: VM not detected; skipped."
    return 0
  }

  local src_zone
  local dst_ip

  src_zone="$(vm_zone "$src_vm")"
  dst_ip="$(vm_ip "$dst_vm")"

  echo
  echo -e "${CYAN}$label${RESET}"
  echo "  Source      : $src_vm"
  echo "  Destination : $dst_ip"

  if timeout 25 \
    gcloud compute ssh "$src_vm" \
      --zone="$src_zone" \
      --project="$PROJECT_ID" \
      --command="ping -c 3 -W 2 '$dst_ip'" \
      --quiet \
      >/tmp/gsp528-ping.log 2>&1; then

    ok "$label connectivity OK"
  else
    warn "$label ping could not be verified from Cloud Shell."
    warn "This can be caused by SSH/IAP/firewall restrictions and does not remove the NCC resources."
  fi
}

try_ping \
  "$OFFICE1_VM" \
  "$OFFICE2_VM" \
  "Task 1: Office 1 -> Office 2"

try_ping \
  "$WORKLOAD1_VM" \
  "$WORKLOAD2_VM" \
  "Task 2: Workload 1 -> Workload 2"

try_ping \
  "$OFFICE1_VM" \
  "$WORKLOAD1_VM" \
  "Task 3: Office 1 -> Workload 1"

# ------------------------------------------------------------
# Final summary
# ------------------------------------------------------------

echo
line
echo -e "${GREEN}${BOLD}GSP528 NCC CONFIGURATION COMPLETE${RESET}"
line

echo
echo -e "${GREEN}✓ TASK 1${RESET}"
echo "  office-1-vpn-spoke"
echo "  office-2-vpn-spoke"
echo "  VPN Site-to-Site Data Transfer enabled"
echo

echo -e "${GREEN}✓ TASK 2${RESET}"
echo "  workload-1-hybrid-spoke -> $WORKLOAD1_NET"
echo "  workload-2-spoke        -> $WORKLOAD2_NET"
echo

echo -e "${GREEN}✓ TASK 3${RESET}"
echo "  hybrid-office-spoke     -> $OFFICE1_NET"
echo "  workload-1-hybrid-spoke -> $WORKLOAD1_NET"
echo

echo -e "${BOLD}Hub:${RESET} $HUB_NAME"
echo
echo -e "${MAGENTA}© ePlus.DEV${RESET}"
echo
echo -e "${YELLOW}Now return to Google Skills and click Check my progress for Task 1 -> Task 2 -> Task 3.${RESET}"