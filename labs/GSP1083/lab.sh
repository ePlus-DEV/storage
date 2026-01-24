#!/bin/bash
# =============================================================
# 🚀 AlloyDB for PostgreSQL - Qwiklabs
# 🧑‍💻 Script by ePlus.DEV | © 2025 ePlus.DEV
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

log()  { echo -e "${CYAN}▶ ${RESET}$*"; }
ok()   { echo -e "${GREEN}✔ ${RESET}$*"; }
warn() { echo -e "${YELLOW}⚠ ${RESET}$*"; }
die()  { echo -e "${RED}✘ ${RESET}$*"; exit 1; }

echo -e "${CYAN}"
echo "============================================================="
echo "🚀 AlloyDB - Database Fundamentals - GSP1083"
echo "© 2026 - ePlus.DEV"
echo "============================================================="
echo -e "${RESET}"

# =======================
# 🔧 Config
# =======================
PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
NETWORK="peering-network"
DB_PASSWORD="Change3Me"

# Checkpoint #1 resources (same names as lab UI instructions)
CLUSTER_UI="lab-cluster"
INSTANCE_UI="lab-instance"

# Checkpoint #3 resources (same names as lab CLI instructions)
CLUSTER_CLI="gcloud-lab-cluster"
INSTANCE_CLI="gcloud-lab-instance"

[[ -n "${PROJECT_ID}" ]] || die "Cannot detect PROJECT_ID. Open Cloud Shell in the lab first."

log "Project: ${BOLD}${PROJECT_ID}${RESET}"
log "Region : ${BOLD}${REGION}${RESET}"
log "Network: ${BOLD}${NETWORK}${RESET}"
echo

# =======================
# Helper: create cluster if missing
# =======================
create_cluster_if_missing() {
  local cluster="$1"
  if gcloud alloydb clusters describe "${cluster}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    ok "Cluster '${cluster}' already exists (skip)."
    return 0
  fi

  log "Creating cluster: ${BOLD}${cluster}${RESET}"
  gcloud alloydb clusters create "${cluster}" \
    --password="${DB_PASSWORD}" \
    --network="${NETWORK}" \
    --region="${REGION}" \
    --project="${PROJECT_ID}"
  ok "Cluster '${cluster}' created."
}

# =======================
# Helper: create instance if missing
# =======================
create_instance_if_missing() {
  local cluster="$1"
  local instance="$2"

  if gcloud alloydb instances describe "${instance}" --cluster="${cluster}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    ok "Instance '${instance}' in cluster '${cluster}' already exists (skip)."
    return 0
  fi

  log "Creating PRIMARY instance: ${BOLD}${instance}${RESET} (cluster: ${cluster})"
  # Use REGIONAL for "Multiple zones (Highly Available)" equivalent
  gcloud alloydb instances create "${instance}" \
    --instance-type=PRIMARY \
    --cpu-count=2 \
    --availability-type=REGIONAL \
    --cluster="${cluster}" \
    --region="${REGION}" \
    --project="${PROJECT_ID}"
  ok "Instance '${instance}' created."
}

# =======================
# ✅ Checkpoint #1: Create cluster + instance (lab-cluster/lab-instance)
# =======================
echo -e "${BOLD}${CYAN}== Checkpoint 1: Create a cluster and instance ==${RESET}"
create_cluster_if_missing "${CLUSTER_UI}"
create_instance_if_missing "${CLUSTER_UI}" "${INSTANCE_UI}"
echo

# =======================
# ✅ Checkpoint #2: Create and load a table (via alloydb-client VM)
# =======================
echo -e "${BOLD}${CYAN}== Checkpoint 2: Create and load a table ==${RESET}"

log "Getting AlloyDB private IP for instance '${INSTANCE_UI}'..."
ALLOYDB_IP="$(gcloud alloydb instances describe "${INSTANCE_UI}" \
  --cluster="${CLUSTER_UI}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="value(ipAddress)" 2>/dev/null || true)"

# Fallback (some environments expose it under networkConfig.ipAddress)
if [[ -z "${ALLOYDB_IP}" ]]; then
  ALLOYDB_IP="$(gcloud alloydb instances describe "${INSTANCE_UI}" \
    --cluster="${CLUSTER_UI}" \
    --region="${REGION}" \
    --project="${PROJECT_ID}" \
    --format="value(networkConfig.ipAddress)" 2>/dev/null || true)"
fi

[[ -n "${ALLOYDB_IP}" ]] || die "Cannot fetch private IP for '${INSTANCE_UI}'. Open AlloyDB > cluster overview and confirm instance is READY."

ok "AlloyDB Private IP: ${BOLD}${ALLOYDB_IP}${RESET}"

log "Detecting zone of VM 'alloydb-client'..."
CLIENT_ZONE="$(gcloud compute instances describe alloydb-client \
  --project="${PROJECT_ID}" \
  --format="value(zone)" 2>/dev/null | awk -F/ '{print $NF}')"

[[ -n "${CLIENT_ZONE}" ]] || die "Cannot detect zone for 'alloydb-client' VM."

ok "alloydb-client zone: ${BOLD}${CLIENT_ZONE}${RESET}"

warn "Running SQL + load script on alloydb-client (non-interactive)..."

gcloud compute ssh alloydb-client \
  --zone="${CLIENT_ZONE}" \
  --project="${PROJECT_ID}" \
  --command "bash -lc '
set -euo pipefail
export ALLOYDB=\"${ALLOYDB_IP}\"
echo \"\$ALLOYDB\" > alloydbip.txt

# Create regions + insert data
PGPASSWORD=\"${DB_PASSWORD}\" psql -h \"\$ALLOYDB\" -U postgres -v ON_ERROR_STOP=1 <<\"SQL\"
CREATE TABLE IF NOT EXISTS regions (
  region_id bigint NOT NULL,
  region_name varchar(25)
);

DO \$\$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = '\''regions_pkey'\'' AND conrelid = '\''regions'\''::regclass
  ) THEN
    ALTER TABLE regions ADD PRIMARY KEY (region_id);
  END IF;
END
\$\$;

INSERT INTO regions (region_id, region_name) VALUES
  (1, '\''Europe'\''),
  (2, '\''Americas'\''),
  (3, '\''Asia'\''),
  (4, '\''Middle East and Africa'\'')
ON CONFLICT (region_id) DO UPDATE
SET region_name = EXCLUDED.region_name;

SELECT region_id, region_name FROM regions ORDER BY region_id;
SQL

# Download and load hrm SQL
gsutil cp gs://spls/gsp1083/hrm_load.sql hrm_load.sql

PGPASSWORD=\"${DB_PASSWORD}\" psql -h \"\$ALLOYDB\" -U postgres -v ON_ERROR_STOP=1 <<\"SQL\"
\\i hrm_load.sql
\\dt
SQL
'"

ok "Tables created/loaded on AlloyDB."
echo

# =======================
# ✅ Checkpoint #3: Create cluster + instance with CLI (gcloud-lab-*)
# =======================
echo -e "${BOLD}${CYAN}== Checkpoint 3: Create a cluster and instance with CLI ==${RESET}"
create_cluster_if_missing "${CLUSTER_CLI}"
create_instance_if_missing "${CLUSTER_CLI}" "${INSTANCE_CLI}"
echo

# =======================
# ✅ Final: show resources
# =======================
echo -e "${BOLD}${CYAN}== Final verification ==${RESET}"
gcloud alloydb clusters list --project="${PROJECT_ID}"
echo
warn "Now go back to Qwiklabs and click:"
echo -e "${YELLOW}  • Check my progress (Create a cluster and instance)${RESET}"
echo -e "${YELLOW}  • Check my progress (Create and load a table)${RESET}"
echo -e "${YELLOW}  • Check my progress (Create a cluster and instance with CLI)${RESET}"
echo
ok "Done. - ePlus.DEV"