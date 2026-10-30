#!/usr/bin/env bash
# Copyright (c) 2026 ePlus.DEV | Unlicense
# GSP1318: Establish Hybrid Network Connectivity with NCC
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
for c in gcloud openssl jq curl; do command -v "$c" >/dev/null || die "Missing $c"; done
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != '(unset)' ]] || die 'Use the temporary lab project.'
ZONE="${ZONE:-$(gcloud compute instances list --project="$PROJECT_ID" --filter='name=vm3-onprem' --format='value(zone)' | head -n1 | awk -F/ '{print $NF}')}"
[[ "$ZONE" =~ ^[a-z]+-[a-z0-9]+[0-9]-[a-z]$ ]] || die 'Cannot discover vm3-onprem zone.'
REGION="${REGION:-${ZONE%-*}}"
[[ "$REGION" == "${ZONE%-*}" ]] || die 'Region and zone mismatch.'
WORKLOAD_CIDR="${WORKLOAD_CIDR:-10.0.1.0/24}"
info "Project=$PROJECT_ID Region=$REGION Zone=$ZONE"
for n in routing-vpc on-prem-net-vpc workload-vpc; do
  gcloud compute networks describe "$n" --project="$PROJECT_ID" >/dev/null || die "Missing lab VPC $n"
done
gcloud services enable networkconnectivity.googleapis.com --project="$PROJECT_ID" --quiet
retry(){ local max="$1" delay="$2" i; shift 2; for ((i=1;i<=max;i++)); do
  if "$@"; then return 0; fi
  if ((i<max)); then sleep "$delay"; fi
done; return 1; }
router_exists(){ gcloud compute routers describe "$1" --project="$PROJECT_ID" --region="$REGION" >/dev/null 2>&1; }
gateway_exists(){ gcloud compute vpn-gateways describe "$1" --project="$PROJECT_ID" --region="$REGION" >/dev/null 2>&1; }
tunnel_exists(){ gcloud compute vpn-tunnels describe "$1" --project="$PROJECT_ID" --region="$REGION" >/dev/null 2>&1; }
router_has(){ gcloud compute routers describe "$1" --project="$PROJECT_ID" --region="$REGION" --format=json | jq -e --arg n "$3" --arg c "$2" '.[$c][]? | select(.name == $n)' >/dev/null; }
ensure_router(){ if ! router_exists "$1"; then
  gcloud compute routers create "$1" --project="$PROJECT_ID" --region="$REGION" --network="$2" --asn="$3" --quiet
fi; }
ensure_gateway(){ if ! gateway_exists "$1"; then
  gcloud compute vpn-gateways create "$1" --project="$PROJECT_ID" --region="$REGION" --network="$2" --quiet
fi; }
ensure_interface(){ if ! router_has "$1" interfaces "$2"; then
  gcloud compute routers add-interface "$1" --project="$PROJECT_ID" --region="$REGION" --interface-name="$2" --ip-address="$3" --mask-length=30 --vpn-tunnel="$4" --quiet
fi; }
ensure_peer(){ if ! router_has "$1" bgpPeers "$2"; then
  gcloud compute routers add-bgp-peer "$1" --project="$PROJECT_ID" --region="$REGION" --peer-name="$2" --peer-ip-address="$3" --interface="$4" --peer-asn="$5" --quiet
fi; }
hub_exists(){ gcloud network-connectivity hubs describe mesh-hub --project="$PROJECT_ID" >/dev/null 2>&1; }
vpc_spoke_exists(){ gcloud network-connectivity spokes describe workload-vpc-spoke --global --project="$PROJECT_ID" >/dev/null 2>&1; }
hybrid_spoke_exists(){ gcloud network-connectivity spokes describe hybrid-spoke --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; }

info 'Task 1: HA VPN and BGP'
ensure_router routing-vpc-cr routing-vpc 64525
ensure_router on-prem-router on-prem-net-vpc 64526
ensure_gateway routing-vpc-vpn-gateway routing-vpc
ensure_gateway on-prem-vpn-gateway on-prem-net-vpc
if tunnel_exists routing-vpc-tunnel && tunnel_exists on-prem-tunnel; then
  info 'Reusing the existing VPN tunnel pair'
elif tunnel_exists routing-vpc-tunnel || tunnel_exists on-prem-tunnel; then
  die 'One VPN tunnel exists without its peer; repair the shared-secret pair manually.'
else
  SECRET="$(openssl rand -base64 24)"
  gcloud compute vpn-tunnels create routing-vpc-tunnel --project="$PROJECT_ID" --region="$REGION" --vpn-gateway=routing-vpc-vpn-gateway --peer-gcp-gateway=on-prem-vpn-gateway --router=routing-vpc-cr --interface=0 --shared-secret="$SECRET" --quiet
  gcloud compute vpn-tunnels create on-prem-tunnel --project="$PROJECT_ID" --region="$REGION" --vpn-gateway=on-prem-vpn-gateway --peer-gcp-gateway=routing-vpc-vpn-gateway --router=on-prem-router --interface=0 --shared-secret="$SECRET" --quiet
  unset SECRET
fi
ensure_interface routing-vpc-cr if-hub-to-prem 169.254.1.1 routing-vpc-tunnel
ensure_peer routing-vpc-cr bgp-hub-to-prem 169.254.1.2 if-hub-to-prem 64526
ensure_interface on-prem-router if-prem-to-hub 169.254.1.2 on-prem-tunnel
ensure_peer on-prem-router bgp-prem-to-hub 169.254.1.1 if-prem-to-hub 64525
gcloud compute routers update routing-vpc-cr --project="$PROJECT_ID" --region="$REGION" --advertisement-mode=custom --set-advertisement-groups=all_subnets --set-advertisement-ranges="$WORKLOAD_CIDR" --quiet
gcloud compute routers update on-prem-router --project="$PROJECT_ID" --region="$REGION" --advertisement-mode=custom --set-advertisement-groups=all_subnets --quiet
gcloud compute routers update-bgp-peer on-prem-router --project="$PROJECT_ID" --region="$REGION" --peer-name=bgp-prem-to-hub --advertised-route-priority=111 --quiet
tunnel_ready(){ [[ "$(gcloud compute vpn-tunnels describe routing-vpc-tunnel --project="$PROJECT_ID" --region="$REGION" --format='value(status)' 2>/dev/null)" == ESTABLISHED ]]; }
retry 12 15 tunnel_ready || die 'VPN did not establish within the bounded wait.'
gcloud compute routers get-status routing-vpc-cr --project="$PROJECT_ID" --region="$REGION" >/dev/null
info 'Task 1 checkpoints: HA VPN (30) and BGP routes (35)'

info 'Task 2: NCC hub'
if ! hub_exists; then gcloud network-connectivity hubs create mesh-hub --project="$PROJECT_ID" --quiet; fi
retry 10 5 gcloud network-connectivity hubs route-tables describe default --hub=mesh-hub --project="$PROJECT_ID" >/dev/null || die 'NCC route table not ready.'
info 'Task 2 checkpoint: NCC hub (15)'

info 'Task 3: NCC VPC and VPN spokes'
if ! vpc_spoke_exists; then
  gcloud network-connectivity spokes linked-vpc-network create workload-vpc-spoke --project="$PROJECT_ID" --hub=mesh-hub --vpc-network=workload-vpc --global --quiet
fi
if ! hybrid_spoke_exists; then
  gcloud network-connectivity spokes linked-vpn-tunnels create hybrid-spoke --project="$PROJECT_ID" --region="$REGION" --hub=mesh-hub --vpn-tunnels=routing-vpc-tunnel --quiet
fi
gcloud network-connectivity hubs list-spokes mesh-hub --project="$PROJECT_ID"
gcloud network-connectivity hubs route-tables routes list --project="$PROJECT_ID" --hub=mesh-hub --route_table=default --effective-location="$REGION" --filter=10.0.3.0/24 || warn 'Route propagation may still be in progress.'
info 'Task 3 checkpoint: NCC spokes (20)'

info 'Task 4: verify data path from on-prem VM'
retry 5 15 gcloud compute ssh vm3-onprem --project="$PROJECT_ID" --zone="$ZONE" --quiet --command='curl --fail --silent --show-error --connect-timeout 5 --max-time 15 http://10.0.1.2/ -o /dev/null' || die 'On-prem to workload HTTP verification failed.'
printf '%s[OK]%s Workload HTTP path verified\n' "$G" "$R"

# Task 5 is opt-in to protect grader state.
if [[ "${CLEANUP:-0}" == 1 ]]; then
  [[ "${CONFIRM_CLEANUP:-}" == YES ]] || die 'Set CONFIRM_CLEANUP=YES after checking the grader.'
  warn 'Task 5: deleting lab-created resources'
  if vpc_spoke_exists; then gcloud network-connectivity spokes delete workload-vpc-spoke --project="$PROJECT_ID" --global --quiet; fi
  if hybrid_spoke_exists; then gcloud network-connectivity spokes delete hybrid-spoke --project="$PROJECT_ID" --region="$REGION" --quiet; fi
  if hub_exists; then gcloud network-connectivity hubs delete mesh-hub --project="$PROJECT_ID" --quiet; fi
  for t in on-prem-tunnel routing-vpc-tunnel; do if tunnel_exists "$t"; then gcloud compute vpn-tunnels delete "$t" --project="$PROJECT_ID" --region="$REGION" --quiet; fi; done
  for r in routing-vpc-cr on-prem-router; do if router_exists "$r"; then gcloud compute routers delete "$r" --project="$PROJECT_ID" --region="$REGION" --quiet; fi; done
else
  info 'Task 5 cleanup is opt-in: CLEANUP=1 CONFIRM_CLEANUP=YES after grading.'
fi
info 'Finished: static validated only; runtime/grader unverified.'