#!/bin/bash
# =============================================================
# 🚀 AlloyDB - Create ONLY required resources (NO SSH / NO DB)
# ✅ Covers checkpoints:
#   1) Create a cluster and instance (lab-cluster / lab-instance)
#   3) Create a cluster and instance with CLI (gcloud-lab-cluster / gcloud-lab-instance)
# =============================================================
# © 2025 ePlus.DEV
# =============================================================

set -euo pipefail

GREEN="\033[1;32m"; CYAN="\033[1;36m"; YELLOW="\033[1;33m"; RED="\033[1;31m"; BOLD="\033[1m"; RESET="\033[0m"
log(){ echo -e "${CYAN}▶${RESET} $*"; }
ok(){ echo -e "${GREEN}✔${RESET} $*"; }
warn(){ echo -e "${YELLOW}⚠${RESET} $*"; }
die(){ echo -e "${RED}✘${RESET} $*"; exit 1; }

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
NETWORK="peering-network"
DB_PASSWORD="Change3Me"

CLUSTER_UI="lab-cluster"
INSTANCE_UI="lab-instance"
CLUSTER_CLI="gcloud-lab-cluster"
INSTANCE_CLI="gcloud-lab-instance"

[[ -n "${PROJECT_ID}" ]] || die "Cannot detect PROJECT_ID. Use Cloud Shell of the LAB."

create_cluster_if_missing() {
  local cluster="$1"
  if gcloud alloydb clusters describe "${cluster}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    ok "Cluster '${cluster}' exists (skip)."
    return 0
  fi
  log "Creating cluster '${cluster}'..."
  gcloud alloydb clusters create "${cluster}" \
    --password="${DB_PASSWORD}" \
    --network="${NETWORK}" \
    --region="${REGION}" \
    --project="${PROJECT_ID}"
  ok "Cluster '${cluster}' created."
}

create_instance_if_missing() {
  local cluster="$1"
  local instance="$2"
  if gcloud alloydb instances describe "${instance}" --cluster="${cluster}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    ok "Instance '${instance}' exists (skip)."
    return 0
  fi
  log "Creating PRIMARY instance '${instance}' (REGIONAL/HA)..."
  gcloud alloydb instances create "${instance}" \
    --instance-type=PRIMARY \
    --cpu-count=2 \
    --availability-type=REGIONAL \
    --cluster="${cluster}" \
    --region="${REGION}" \
    --project="${PROJECT_ID}"
  ok "Instance '${instance}' created."
}

echo -e "${CYAN}=============================================================${RESET}"
echo -e "${CYAN}🚀 AlloyDB - Create required resources only${RESET}"
echo -e "${CYAN}© 2026 ePlus.DEV${RESET}"
echo -e "${CYAN}=============================================================${RESET}"
log "Project: ${BOLD}${PROJECT_ID}${RESET}"
log "Region : ${BOLD}${REGION}${RESET}"
echo

echo -e "${BOLD}${CYAN}== Checkpoint 1: lab-cluster / lab-instance ==${RESET}"
create_cluster_if_missing "${CLUSTER_UI}"
create_instance_if_missing "${CLUSTER_UI}" "${INSTANCE_UI}"
echo

echo -e "${BOLD}${CYAN}== Checkpoint 3: gcloud-lab-cluster / gcloud-lab-instance ==${RESET}"
create_cluster_if_missing "${CLUSTER_CLI}"
create_instance_if_missing "${CLUSTER_CLI}" "${INSTANCE_CLI}"
echo

ok "Done creating required resources."
warn "Next: run SSH + SQL commands for Task 2."