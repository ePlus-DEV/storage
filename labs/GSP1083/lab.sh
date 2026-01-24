#!/bin/bash
# =============================================================
# 🚀 AlloyDB for PostgreSQL - Lab Script (Controlled Flow)
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
warn(){ echo -e "${YELLOW}⚠${RESET} $*"; }
die(){ echo -e "${RED}✘${RESET} $*"; exit 1; }

# =======================
# 🔧 Lab fixed config
# =======================
PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
export REGION="$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")"
NETWORK="peering-network"
DB_PASSWORD="Change3Me"

# Task 1 resources
CLUSTER_TASK1="lab-cluster"
INSTANCE_TASK1="lab-instance"

# Task 3 resources
CLUSTER_TASK3="gcloud-lab-cluster"
INSTANCE_TASK3="gcloud-lab-instance"

CLIENT_VM="alloydb-client"

[[ -n "${PROJECT_ID}" ]] || die "Cannot detect PROJECT_ID. Use LAB Cloud Shell."
[[ -n "${REGION}" ]] || die "Cannot detect REGION from project metadata."

echo -e "${CYAN}=============================================================${RESET}"
echo -e "${CYAN}🚀 AlloyDB Lab${RESET}"
echo -e "${CYAN}© 2026 - ePlus.DEV${RESET}"
echo -e "${CYAN}=============================================================${RESET}"
log "Project: ${BOLD}${PROJECT_ID}${RESET}"
log "Region : ${BOLD}${REGION}${RESET}"
echo

# =======================
# TASK 1: Create cluster & instance
# =======================
echo -e "${BOLD}${CYAN}== Task 1: Create cluster & instance ==${RESET}"

if gcloud alloydb clusters describe "${CLUSTER_TASK1}" \
  --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  ok "Cluster '${CLUSTER_TASK1}' already exists (skip)."
else
  log "Creating cluster '${CLUSTER_TASK1}'..."
  gcloud alloydb clusters create "${CLUSTER_TASK1}" \
    --password="${DB_PASSWORD}" \
    --network="${NETWORK}" \
    --region="${REGION}" \
    --project="${PROJECT_ID}"
  ok "Cluster created."
fi

if gcloud alloydb instances describe "${INSTANCE_TASK1}" \
  --cluster="${CLUSTER_TASK1}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" >/dev/null 2>&1; then
  ok "Instance '${INSTANCE_TASK1}' already exists (skip)."
else
  log "Creating PRIMARY instance '${INSTANCE_TASK1}' (HA)..."
  gcloud alloydb instances create "${INSTANCE_TASK1}" \
    --instance-type=PRIMARY \
    --cpu-count=2 \
    --availability-type=REGIONAL \
    --cluster="${CLUSTER_TASK1}" \
    --region="${REGION}" \
    --project="${PROJECT_ID}"
  ok "Instance created."
fi

# =======================
# PRINT info for Task 2
# =======================
ALLOYDB_IP="$(gcloud alloydb instances describe "${INSTANCE_TASK1}" \
  --cluster="${CLUSTER_TASK1}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="value(ipAddress)" 2>/dev/null || true)"

[[ -n "${ALLOYDB_IP}" ]] || die "Cannot fetch AlloyDB private IP. Ensure instance is READY."

# ✅ FIX: Get client VM zone WITHOUT interactive prompt
CLIENT_ZONE="$(gcloud compute instances list \
  --project="${PROJECT_ID}" \
  --filter="name=(${CLIENT_VM})" \
  --format="value(zone)" 2>/dev/null | head -n 1 | awk -F/ '{print $NF}')"

[[ -n "${CLIENT_ZONE}" ]] || die "Cannot detect zone for VM '${CLIENT_VM}'. Check Compute Engine > VM instances."

echo
echo -e "${BOLD}${GREEN}=================================================${RESET}"
echo -e "${BOLD}${GREEN}TASK 2 – MANUAL STEP (REQUIRED)${RESET}"
echo -e "${BOLD}${GREEN}=================================================${RESET}"
echo
echo "AlloyDB Private IP : ${ALLOYDB_IP}"
echo "Postgres user      : postgres"
echo "Postgres password  : ${DB_PASSWORD}"
echo
echo "SSH to client VM:"
echo "gcloud compute ssh ${CLIENT_VM} --zone=${CLIENT_ZONE}"
echo
echo "Inside VM:"
echo "export ALLOYDB=${ALLOYDB_IP}"
echo "echo \$ALLOYDB > alloydbip.txt"
echo "psql -h \$ALLOYDB -U postgres"
echo
echo -e "${BOLD}${GREEN}=================================================${RESET}"
echo
warn "👉 NOW perform Task 2 manually (Create and load a table)"
warn "👉 After you FINISH Task 2 and click 'Check my progress', come back here."
echo

# =======================
# WAIT for user confirmation
# =======================
while true; do
  read -r -p "$(echo -e ${BOLD}${YELLOW}Type Y to continue with Task 3:${RESET} )" CONFIRM
  case "${CONFIRM}" in
    Y|y) break ;;
    *) echo -e "${YELLOW}Please type Y when Task 2 is completed.${RESET}" ;;
  esac
done

# =======================
# TASK 3: Create cluster & instance with CLI
# =======================
echo
echo -e "${BOLD}${CYAN}== Task 3: Create cluster & instance with CLI ==${RESET}"

if gcloud alloydb clusters describe "${CLUSTER_TASK3}" \
  --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  ok "Cluster '${CLUSTER_TASK3}' already exists (skip)."
else
  log "Creating cluster '${CLUSTER_TASK3}'..."
  gcloud alloydb clusters create "${CLUSTER_TASK3}" \
    --password="${DB_PASSWORD}" \
    --network="${NETWORK}" \
    --region="${REGION}" \
    --project="${PROJECT_ID}"
  ok "Cluster created."
fi

if gcloud alloydb instances describe "${INSTANCE_TASK3}" \
  --cluster="${CLUSTER_TASK3}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" >/dev/null 2>&1; then
  ok "Instance '${INSTANCE_TASK3}' already exists (skip)."
else
  log "Creating PRIMARY instance '${INSTANCE_TASK3}'..."
  gcloud alloydb instances create "${INSTANCE_TASK3}" \
    --instance-type=PRIMARY \
    --cpu-count=2 \
    --region="${REGION}" \
    --cluster="${CLUSTER_TASK3}" \
    --project="${PROJECT_ID}"
  ok "Instance created."
fi

echo
ok "All required lab tasks completed."
warn "👉 Go back to Qwiklabs and click 'Check my progress' for Task 3."