#!/bin/bash
# =============================================================
# 🚀 AlloyDB for PostgreSQL - Task 1
# ✅ Create cluster & instance
# ✅ PRINT connection info for Task 2 (manual SSH + psql)
# =============================================================
# © 2026 ePlus.DEV
# =============================================================

set -euo pipefail

# =======================
# 🌈 Colors
# =======================
GREEN="\033[1;32m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
BOLD="\033[1m"
RESET="\033[0m"

log(){ echo -e "${CYAN}▶${RESET} $*"; }
ok(){ echo -e "${GREEN}✔${RESET} $*"; }
die(){ echo -e "${RED}✘${RESET} $*"; exit 1; }

# =======================
# 🔧 Config (LAB fixed)
# =======================
PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
NETWORK="peering-network"
DB_PASSWORD="Change3Me"

CLUSTER_NAME="lab-cluster"
INSTANCE_NAME="lab-instance"
CLIENT_VM="alloydb-client"

[[ -n "${PROJECT_ID}" ]] || die "Cannot detect PROJECT_ID. Use LAB Cloud Shell."

echo -e "${CYAN}=============================================================${RESET}"
echo -e "${CYAN}🚀 AlloyDB Task 1 - Create & Print Connection Info${RESET}"
echo -e "${CYAN}© 2025 ePlus.DEV${RESET}"
echo -e "${CYAN}=============================================================${RESET}"
log "Project: ${BOLD}${PROJECT_ID}${RESET}"
log "Region : ${BOLD}${REGION}${RESET}"
echo

# =======================
# Create cluster if missing
# =======================
if gcloud alloydb clusters describe "${CLUSTER_NAME}" \
  --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  ok "Cluster '${CLUSTER_NAME}' already exists (skip)."
else
  log "Creating cluster '${CLUSTER_NAME}'..."
  gcloud alloydb clusters create "${CLUSTER_NAME}" \
    --password="${DB_PASSWORD}" \
    --network="${NETWORK}" \
    --region="${REGION}" \
    --project="${PROJECT_ID}"
  ok "Cluster created."
fi

# =======================
# Create instance if missing
# =======================
if gcloud alloydb instances describe "${INSTANCE_NAME}" \
  --cluster="${CLUSTER_NAME}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" >/dev/null 2>&1; then
  ok "Instance '${INSTANCE_NAME}' already exists (skip)."
else
  log "Creating PRIMARY instance '${INSTANCE_NAME}' (HA)..."
  gcloud alloydb instances create "${INSTANCE_NAME}" \
    --instance-type=PRIMARY \
    --cpu-count=2 \
    --availability-type=REGIONAL \
    --cluster="${CLUSTER_NAME}" \
    --region="${REGION}" \
    --project="${PROJECT_ID}"
  ok "Instance created."
fi

# =======================
# Fetch connection info
# =======================
log "Fetching AlloyDB private IP..."
ALLOYDB_IP="$(gcloud alloydb instances describe "${INSTANCE_NAME}" \
  --cluster="${CLUSTER_NAME}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="value(ipAddress)" 2>/dev/null || true)"

[[ -n "${ALLOYDB_IP}" ]] || die "Cannot fetch AlloyDB private IP."

log "Detecting zone of '${CLIENT_VM}' VM..."
CLIENT_ZONE="$(gcloud compute instances describe "${CLIENT_VM}" \
  --project="${PROJECT_ID}" \
  --format="value(zone)" | awk -F/ '{print $NF}')"

[[ -n "${CLIENT_ZONE}" ]] || die "Cannot detect zone for ${CLIENT_VM}."

# =======================
# PRINT INFO FOR TASK 2
# =======================
echo
echo -e "${BOLD}${GREEN}=================================================${RESET}"
echo -e "${BOLD}${GREEN}TASK 2 – CONNECTION INFORMATION${RESET}"
echo -e "${BOLD}${GREEN}=================================================${RESET}"
echo
echo -e "AlloyDB Private IP : ${BOLD}${ALLOYDB_IP}${RESET}"
echo -e "Postgres user      : ${BOLD}postgres${RESET}"
echo -e "Postgres password  : ${BOLD}${DB_PASSWORD}${RESET}"
echo
echo -e "${BOLD}SSH to client VM:${RESET}"
echo -e "gcloud compute ssh ${CLIENT_VM} --zone=${CLIENT_ZONE}"
echo
echo -e "${BOLD}Inside VM:${RESET}"
echo -e "export ALLOYDB=${ALLOYDB_IP}"
echo -e "echo \$ALLOYDB > alloydbip.txt"
echo -e "psql -h \$ALLOYDB -U postgres"
echo
echo -e "${BOLD}${GREEN}=================================================${RESET}"
echo
ok "Task 1 completed. Use the above info to perform Task 2 manually."