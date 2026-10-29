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
# TASK 2: Create and load PostgreSQL tables on the client VM
# =======================
echo
echo -e "$BOLD$CYAN== Task 2: Create and load tables ==$RESET"

ALLOYDB_IP="$(gcloud alloydb instances describe "$INSTANCE_TASK1" \
  --cluster="$CLUSTER_TASK1" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --format="value(ipAddress)" 2>/dev/null || true)"
[[ -n "$ALLOYDB_IP" ]] || die "Cannot fetch the AlloyDB private IP. Check that the primary instance is READY."

CLIENT_ZONE="$(gcloud compute instances list \
  --project="$PROJECT_ID" \
  --filter="name=($CLIENT_VM)" \
  --format="value(zone)" 2>/dev/null | head -n 1 | awk -F/ '{print $NF}')"
[[ -n "$CLIENT_ZONE" ]] || die "Cannot locate the '$CLIENT_VM' VM zone."

log "AlloyDB private IP: $ALLOYDB_IP"
log "Client VM: $CLIENT_VM ($CLIENT_ZONE)"

# Keep SQL and database connections inside the lab-provided client VM. The
# AlloyDB private IP is generally unreachable from the Cloud Shell network.
TASK2_REMOTE_SCRIPT="$(mktemp)"
cat > "$TASK2_REMOTE_SCRIPT" <<'REMOTE_TASK2'
#!/bin/bash
set -euo pipefail

: "$ALLOYDB"
: "$PGPASSWORD"
export PGCONNECT_TIMEOUT=10
command -v psql >/dev/null 2>&1 || { echo "ERROR: psql is missing on the client VM." >&2; exit 1; }
printf '%s\n' "$ALLOYDB" > "$HOME/alloydbip.txt"

# Idempotent seed: rerunning the lab must not fail on existing region IDs.
psql -X -h "$ALLOYDB" -U postgres -d postgres -v ON_ERROR_STOP=1 <<'SQL'
CREATE TABLE IF NOT EXISTS public.regions (
  region_id bigint NOT NULL PRIMARY KEY,
  region_name varchar(25)
);
INSERT INTO public.regions (region_id, region_name) VALUES
  (1, 'Europe'),
  (2, 'Americas'),
  (3, 'Asia'),
  (4, 'Middle East and Africa')
ON CONFLICT (region_id)
DO UPDATE SET region_name = EXCLUDED.region_name;
SQL

REGIONS_OK="$(psql -X -h "$ALLOYDB" -U postgres -d postgres -v ON_ERROR_STOP=1 -Atc \
  "SELECT count(*) FROM public.regions WHERE (region_id,region_name) IN ((1,'Europe'),(2,'Americas'),(3,'Asia'),(4,'Middle East and Africa'))")"
[[ "$REGIONS_OK" == 4 ]] || { echo "ERROR: Expected four lab regions, got $REGIONS_OK." >&2; exit 1; }
echo "Verified four required rows in public.regions."

# The official lab also loads countries, departments, and jobs from hrm_load.sql.
# Avoid rerunning the DDL against already existing tables.
EXISTING_TABLES="$(psql -X -h "$ALLOYDB" -U postgres -d postgres -v ON_ERROR_STOP=1 -Atc \
  "SELECT count(*) FROM pg_tables WHERE schemaname='public' AND tablename IN ('countries','departments','jobs')")"
case "$EXISTING_TABLES" in
  0)
    if command -v gcloud >/dev/null 2>&1; then
      gcloud storage cp gs://spls/gsp1083/hrm_load.sql "$HOME/hrm_load.sql"
    elif command -v gsutil >/dev/null 2>&1; then
      gsutil cp gs://spls/gsp1083/hrm_load.sql "$HOME/hrm_load.sql"
    else
      echo "ERROR: Neither gcloud storage nor gsutil is available on the client VM." >&2
      exit 1
    fi
    # Roll back the entire SQL load on error, making retries safe.
    psql -X -h "$ALLOYDB" -U postgres -d postgres -v ON_ERROR_STOP=1 --single-transaction -f "$HOME/hrm_load.sql"
    ;;
  3)
    echo "The countries, departments and jobs tables already exist; skipping DDL."
    ;;
  *)
    echo "ERROR: Partial HRM table load ($EXISTING_TABLES/3). Inspect before retrying to avoid deleting existing data." >&2
    exit 1
    ;;
esac

# Check the exact four tables described in GSP1083, even on reruns.
TABLES_OK="$(psql -X -h "$ALLOYDB" -U postgres -d postgres -v ON_ERROR_STOP=1 -Atc \
  "SELECT count(*) FROM pg_tables WHERE schemaname='public' AND tablename IN ('regions','countries','departments','jobs')")"
[[ "$TABLES_OK" == 4 ]] || { echo "ERROR: Expected all four GSP1083 tables, found $TABLES_OK/4." >&2; exit 1; }

HRM_ROWS="$(psql -X -h "$ALLOYDB" -U postgres -d postgres -v ON_ERROR_STOP=1 -Atc \
  "SELECT CASE WHEN (SELECT count(*) FROM public.countries)>0 AND (SELECT count(*) FROM public.departments)>0 AND (SELECT count(*) FROM public.jobs)>0 THEN 1 ELSE 0 END")"
[[ "$HRM_ROWS" == 1 ]] || { echo "ERROR: One or more HRM tables contain no data." >&2; exit 1; }

# Match the lab's required verification commands: \dt, regions, jobs.
psql -X -h "$ALLOYDB" -U postgres -d postgres -v ON_ERROR_STOP=1 \
  -c '\dt public.*' \
  -c "SELECT region_id, region_name FROM public.regions ORDER BY region_id;" \
  -c "SELECT job_title, max_salary FROM public.jobs ORDER BY max_salary DESC;"
echo "Task 2 verified successfully: all four tables exist and are populated."
REMOTE_TASK2

if ! gcloud compute scp --quiet "$TASK2_REMOTE_SCRIPT" \
  "$CLIENT_VM:~/gsp1083-task2.sh" --zone="$CLIENT_ZONE" --project="$PROJECT_ID"; then
  rm -f "$TASK2_REMOTE_SCRIPT"
  die "Cannot copy Task 2 loader to the VM. Check gcloud SSH access / OS Login permissions."
fi
rm -f "$TASK2_REMOTE_SCRIPT"

if ! gcloud compute ssh --quiet "$CLIENT_VM" \
  --zone="$CLIENT_ZONE" --project="$PROJECT_ID" \
  --command="ALLOYDB='$ALLOYDB_IP' PGPASSWORD='$DB_PASSWORD' bash \"\$HOME/gsp1083-task2.sh\""; then
  die "Task 2 could not be verified. SSH into '$CLIENT_VM' to inspect the SQL error, then rerun the script."
fi
ok "Task 2 completed and verified. Click 'Check my progress' for Task 2."
echo

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