#!/usr/bin/env bash
# ============================================================
#  ePlus.DEV - Google Cloud AD Lab FULL Provisioning Script
#  Purpose : Auto REGION_1/ZONE_1, force input REGION_2/ZONE_2,
#            then create VPC + 2 subnets + firewall + 2 Windows VMs
#  Author  : ePlus.DEV
#  License : Internal training use only
# ============================================================

set -euo pipefail

# ----------------------------- Colors -----------------------------
if command -v tput >/dev/null 2>&1; then
  RED="$(tput setaf 1)"; GREEN="$(tput setaf 2)"; YELLOW="$(tput setaf 3)"
  BLUE="$(tput setaf 4)"; MAGENTA="$(tput setaf 5)"; CYAN="$(tput setaf 6)"
  BOLD="$(tput bold)"; RESET="$(tput sgr0)"
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""; CYAN=""; BOLD=""; RESET=""
fi

banner () {
  echo "${MAGENTA}${BOLD}"
  echo "============================================================"
  echo "  ePlus.DEV | GCP AD Lab - FULL Provisioning Script"
  echo "============================================================"
  echo "${RESET}"
}

ok()   { echo "${GREEN}${BOLD}✔${RESET} $*"; }
warn() { echo "${YELLOW}${BOLD}⚠${RESET} $*"; }
err()  { echo "${RED}${BOLD}✖${RESET} $*"; }
info() { echo "${CYAN}${BOLD}➜${RESET} $*"; }
step() { echo "${BLUE}${BOLD}==>${RESET} $*"; }

need() {
  command -v "$1" >/dev/null 2>&1 || { err "Missing command: $1"; exit 1; }
}

exists_network() { gcloud compute networks describe "$1" --project "$project_id" >/dev/null 2>&1; }
exists_subnet()  { gcloud compute networks subnets describe "$1" --region "$2" --project "$project_id" >/dev/null 2>&1; }
exists_fw()      { gcloud compute firewall-rules describe "$1" --project "$project_id" >/dev/null 2>&1; }
exists_vm()      { gcloud compute instances describe "$1" --zone "$2" --project "$project_id" >/dev/null 2>&1; }

# ----------------------------- Start -----------------------------
banner
need gcloud

project_id="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "${project_id}" ]]; then
  err "Cannot detect project. Run: gcloud config set project <PROJECT_ID>"
  exit 1
fi
ok "Project: ${BOLD}${project_id}${RESET}"

# ----------------------------- Variables (Lab defaults) -----------------------------
# You can override before running:
#   export vpc_name=webappnet
: "${vpc_name:=webappnet}"

subnet1_name="private-ad-zone-1"
subnet2_name="private-ad-zone-2"
subnet1_range="10.1.0.0/24"
subnet2_range="10.2.0.0/24"

dc1_name="ad-dc1"
dc2_name="ad-dc2"
dc1_ip="10.1.0.100"
dc2_ip="10.2.0.100"

machine_type="e2-standard-2"
disk_type="pd-ssd"
disk_size="50GB"
win_family="windows-2016"
win_project="windows-cloud"

# ----------------------------- REGION_1 / ZONE_1 auto -----------------------------
step "Auto-detect REGION_1 / ZONE_1 from project metadata"
REGION_1="$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])" || true)"
ZONE_1="$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])" || true)"

if [[ -z "$REGION_1" || -z "$ZONE_1" ]]; then
  err "Cannot auto-detect default region/zone."
  err "Fix by setting defaults:"
  err "  gcloud config set compute/region <region>"
  err "  gcloud config set compute/zone <zone>"
  exit 1
fi

ok "REGION_1 (auto): ${BOLD}$REGION_1${RESET}"
ok "ZONE_1   (auto): ${BOLD}$ZONE_1${RESET}"

# ----------------------------- REGION_2 / ZONE_2 required -----------------------------
echo
warn "Enter REGION_2 and ZONE_2 (required; should be different from REGION_1)"
read -rp "$(echo "${BOLD}REGION_2:${RESET} ")" REGION_2
read -rp "$(echo "${BOLD}ZONE_2:${RESET}   ")" ZONE_2

if [[ -z "$REGION_2" || -z "$ZONE_2" ]]; then
  err "REGION_2 and ZONE_2 are REQUIRED. Exiting."
  exit 1
fi

if [[ "$REGION_2" == "$REGION_1" ]]; then
  warn "REGION_2 equals REGION_1 ($REGION_1). Lab usually expects different regions."
fi

ok "REGION_2 (input): ${BOLD}$REGION_2${RESET}"
ok "ZONE_2   (input): ${BOLD}$ZONE_2${RESET}"

# Export for later commands if user sources this script
export REGION_1 ZONE_1 REGION_2 ZONE_2 vpc_name project_id

# ----------------------------- Set compute/region to REGION_1 -----------------------------
step "Set gcloud compute/region => $REGION_1"
gcloud config set compute/region "$REGION_1" >/dev/null
ok "Region set: $REGION_1"

# ----------------------------- 1) Create VPC -----------------------------
step "Create VPC network: ${vpc_name} (custom mode)"
if exists_network "$vpc_name"; then
  warn "VPC ${vpc_name} already exists. Skipping."
else
  gcloud compute networks create "$vpc_name" \
    --description "VPC network to deploy Active Directory" \
    --subnet-mode custom
  ok "VPC created: $vpc_name"
fi

# ----------------------------- 2) Create Subnets -----------------------------
step "Create subnet: ${subnet1_name} (${subnet1_range}) in ${REGION_1}"
if exists_subnet "$subnet1_name" "$REGION_1"; then
  warn "Subnet ${subnet1_name} already exists in ${REGION_1}. Skipping."
else
  gcloud compute networks subnets create "$subnet1_name" \
    --network "$vpc_name" \
    --range "$subnet1_range" \
    --region "$REGION_1"
  ok "Subnet created: $subnet1_name"
fi

step "Create subnet: ${subnet2_name} (${subnet2_range}) in ${REGION_2}"
if exists_subnet "$subnet2_name" "$REGION_2"; then
  warn "Subnet ${subnet2_name} already exists in ${REGION_2}. Skipping."
else
  gcloud compute networks subnets create "$subnet2_name" \
    --network "$vpc_name" \
    --range "$subnet2_range" \
    --region "$REGION_2"
  ok "Subnet created: $subnet2_name"
fi

# ----------------------------- 3) Firewall Rules -----------------------------
step "Create firewall rule: allow-internal-ports-private-ad"
if exists_fw "allow-internal-ports-private-ad"; then
  warn "Firewall rule allow-internal-ports-private-ad exists. Skipping."
else
  gcloud compute firewall-rules create allow-internal-ports-private-ad \
    --network "$vpc_name" \
    --allow tcp:1-65535,udp:1-65535,icmp \
    --source-ranges "${subnet1_range},${subnet2_range}"
  ok "Firewall rule created: allow-internal-ports-private-ad"
fi

step "Create firewall rule: allow-rdp (tcp:3389 from 0.0.0.0/0)"
if exists_fw "allow-rdp"; then
  warn "Firewall rule allow-rdp exists. Skipping."
else
  gcloud compute firewall-rules create allow-rdp \
    --network "$vpc_name" \
    --allow tcp:3389 \
    --source-ranges 0.0.0.0/0
  ok "Firewall rule created: allow-rdp"
fi

# ----------------------------- 4) Create DC1 VM -----------------------------
step "Create VM: ${dc1_name} in ${ZONE_1} (private IP ${dc1_ip})"
if exists_vm "$dc1_name" "$ZONE_1"; then
  warn "VM ${dc1_name} already exists in ${ZONE_1}. Skipping."
else
  gcloud compute instances create "$dc1_name" \
    --machine-type "$machine_type" \
    --boot-disk-type "$disk_type" \
    --boot-disk-size "$disk_size" \
    --image-family "$win_family" --image-project "$win_project" \
    --network "$vpc_name" \
    --zone "$ZONE_1" --subnet "$subnet1_name" \
    --private-network-ip="$dc1_ip"
  ok "VM created: $dc1_name"
fi

# ----------------------------- 5) Create DC2 VM -----------------------------
step "Create VM: ${dc2_name} in ${ZONE_2} (private IP ${dc2_ip})"
if exists_vm "$dc2_name" "$ZONE_2"; then
  warn "VM ${dc2_name} already exists in ${ZONE_2}. Skipping."
else
  gcloud compute instances create "$dc2_name" \
    --machine-type "$machine_type" \
    --boot-disk-type "$disk_type" \
    --boot-disk-size "$disk_size" \
    --image-family "$win_family" --image-project "$win_project" \
    --can-ip-forward \
    --network "$vpc_name" \
    --zone "$ZONE_2" --subnet "$subnet2_name" \
    --private-network-ip="$dc2_ip"
  ok "VM created: $dc2_name"
fi

# ----------------------------- 6) Next Commands -----------------------------
echo
step "NEXT: Reset Windows passwords (run when VM is ready; retry if 'instance not ready')"
echo "${BOLD}DC1:${RESET} gcloud compute reset-windows-password ${dc1_name} --zone ${ZONE_1} --quiet --user=admin"
echo "${BOLD}DC2:${RESET} gcloud compute reset-windows-password ${dc2_name} --zone ${ZONE_2} --quiet --user=admin"
echo
step "RDP in Console: Compute Engine -> VM instances -> RDP"
echo "  - Before AD: login user from reset command (usually 'admin')"
echo "  - After AD forest: login as  EXAMPLE-GCP\\Administrator"
echo
ok "Done. ePlus.DEV"