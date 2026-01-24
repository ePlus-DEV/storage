#!/bin/bash
# =============================================================
# 🧩 AlloyDB - Task 2 helper (NO AUTO SSH)
# ✅ Provides info + commands to MANUALLY SSH and load tables/data
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
DB_PASSWORD="Change3Me"

CLUSTER_UI="lab-cluster"
INSTANCE_UI="lab-instance"

[[ -n "${PROJECT_ID}" ]] || die "Cannot detect PROJECT_ID. Use Cloud Shell of the LAB."

get_instance_private_ip() {
  local ip
  ip="$(gcloud alloydb instances describe "${INSTANCE_UI}" \
    --cluster="${CLUSTER_UI}" --region="${REGION}" --project="${PROJECT_ID}" \
    --format="value(ipAddress)" 2>/dev/null || true)"
  if [[ -z "${ip}" ]]; then
    ip="$(gcloud alloydb instances describe "${INSTANCE_UI}" \
      --cluster="${CLUSTER_UI}" --region="${REGION}" --project="${PROJECT_ID}" \
      --format="value(networkConfig.ipAddress)" 2>/dev/null || true)"
  fi
  echo "${ip}"
}

echo -e "${CYAN}=============================================================${RESET}"
echo -e "${CYAN}🧩 AlloyDB - Task 2 manual helper (SSH + SQL)${RESET}"
echo -e "${CYAN}© 2025 ePlus.DEV${RESET}"
echo -e "${CYAN}=============================================================${RESET}"

log "Project: ${BOLD}${PROJECT_ID}${RESET}"
log "Region : ${BOLD}${REGION}${RESET}"
echo

log "Detecting alloydb-client VM zone..."
CLIENT_ZONE="$(gcloud compute instances describe alloydb-client \
  --project="${PROJECT_ID}" \
  --format="value(zone)" 2>/dev/null | awk -F/ '{print $NF}')"

[[ -n "${CLIENT_ZONE}" ]] || die "Cannot find VM 'alloydb-client'. Open Compute Engine > VM instances to confirm."

ok "alloydb-client zone: ${BOLD}${CLIENT_ZONE}${RESET}"

log "Getting AlloyDB private IP (lab-instance)..."
ALLOYDB_IP="$(get_instance_private_ip)"
[[ -n "${ALLOYDB_IP}" ]] || die "Cannot get AlloyDB private IP. Ensure lab-instance is READY."

ok "AlloyDB private IP: ${BOLD}${ALLOYDB_IP}${RESET}"
echo

warn "COPY/PASTE these commands (manual steps for Task 2):"
echo -e "${YELLOW}
# 1) SSH into alloydb-client
gcloud compute ssh alloydb-client --zone=${CLIENT_ZONE} --project=${PROJECT_ID}

# 2) On the VM, set env + persist IP
export ALLOYDB=${ALLOYDB_IP}
echo \$ALLOYDB > alloydbip.txt

# 3) Connect to PostgreSQL (password: ${DB_PASSWORD})
psql -h \$ALLOYDB -U postgres

# 4) Run SQL (create + insert)
CREATE TABLE regions (
    region_id bigint NOT NULL,
    region_name varchar(25)
);

ALTER TABLE regions ADD PRIMARY KEY (region_id);

INSERT INTO regions VALUES (1, 'Europe');
INSERT INTO regions VALUES (2, 'Americas');
INSERT INTO regions VALUES (3, 'Asia');
INSERT INTO regions VALUES (4, 'Middle East and Africa');

SELECT region_id, region_name FROM regions;

\\q

# 5) Download + load SQL file
gsutil cp gs://spls/gsp1083/hrm_load.sql hrm_load.sql

psql -h \$ALLOYDB -U postgres
\\i hrm_load.sql
\\dt
\\q

# 6) Exit VM
exit
${RESET}"

echo
ok "After doing the above, go back to Qwiklabs and click: Check my progress → 'Create and load a table'."
ok "Done - ePlus.DEV"