#!/usr/bin/env bash
# Copyright (c) 2026 ePlus.DEV | Unlicense
# GSP918 — Migrate to Cloud SQL for PostgreSQL Using Database Migration Service
# Official tasks: https://www.skills.google/focuses/22792
#
# This script operates ONLY on the active, authorized lab project.
# Runtime/grader unverified: review the prompts before running.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  bash "${BASH_SOURCE[0]}" "$@"
  return $?
fi
set -Eeuo pipefail
umask 077

if [[ -n "${NO_COLOR:-}" ]]; then
  RED='' GREEN='' YELLOW='' BLUE='' RESET=''
elif [[ -t 1 || "${FORCE_COLOR:-0}" == 1 ]]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'
  YELLOW=$'\033[0;33m'; BLUE=$'\033[0;34m'; RESET=$'\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' RESET=''
fi
say()  { printf '%b\n' "${BLUE}$*${RESET}"; }
ok()   { printf '%b\n' "${GREEN}✔ $*${RESET}"; }
warn() { printf '%b\n' "${YELLOW}⚠ $*${RESET}" >&2; }
die()  { printf '%b\n' "${RED}✖ $*${RESET}" >&2; exit 1; }
step() { printf '\n%b\n' "${BLUE}========== STEP $1/8 — $2 ==========${RESET}"; }
trap 'die "Failed at line $LINENO (exit $?)"' ERR
say "ePlus.DEV – Starting Execution | GSP918"
say "Copyright (c) 2026 ePlus.DEV | Unlicense"
for cmd in gcloud awk grep sed; do
  command -v "$cmd" >/dev/null || die "Missing required command: $cmd"
done

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != "(unset)" ]] ||
  read -r -p "Authorized lab project ID: " PROJECT_ID
[[ -n "$PROJECT_ID" ]] || die "Project ID is required"
SOURCE_VM="${SOURCE_VM:-postgresql-vm}"
DEST_INSTANCE="${DEST_INSTANCE:-postgresql-cloudsql}"
SOURCE_PROFILE="${SOURCE_PROFILE:-postgres-vm}"
DEST_PROFILE="${DEST_PROFILE:-gsp918-cloudsql-destination}"
JOB_ID="${JOB_ID:-vm-to-cloudsql}"
NETWORK="${NETWORK:-default}"
SOURCE_USER="migration_admin"

step 1 "Detect the provisioned lab resources"
VM_ZONE="$(gcloud compute instances list --project="$PROJECT_ID" \
  --filter="name=$SOURCE_VM" --format='value(zone)' | head -n 1 | awk -F/ '{print $NF}')"
[[ -n "$VM_ZONE" ]] || read -r -p "Zone of $SOURCE_VM: " VM_ZONE
[[ -n "$VM_ZONE" ]] || die "Source VM not found"
REGION="${REGION:-${VM_ZONE%-?}}"
[[ -n "$REGION" ]] || die "Cannot determine region"
SOURCE_IP="$(gcloud compute instances describe "$SOURCE_VM" --project="$PROJECT_ID" \
  --zone="$VM_ZONE" --format='value(networkInterfaces[0].networkIP)')"
[[ -n "$SOURCE_IP" ]] || die "Source VM has no internal IP"
SQL_REGION="$(gcloud sql instances describe "$DEST_INSTANCE" --project="$PROJECT_ID" \
  --format='value(region)')" || die "Expected existing Cloud SQL instance $DEST_INSTANCE"
[[ "$SQL_REGION" == "$REGION" ]] ||
  die "Cloud SQL region $SQL_REGION differs from VM region $REGION"
say "Project: $PROJECT_ID | Region: $REGION | VM zone: $VM_ZONE"
say "Source VM: $SOURCE_VM ($SOURCE_IP) | Existing Cloud SQL: $DEST_INSTANCE"
warn "Use only the temporary Google Skills lab project. No project/region is hardcoded."
for api in datamigration.googleapis.com servicenetworking.googleapis.com; do
  if ! gcloud services list --enabled --project="$PROJECT_ID" \
    --filter="config.name=$api" --format='value(config.name)' 2>/dev/null | grep -Fxq "$api"; then
    warn "$api is not confirmed enabled; attempting enable (may be denied by lab IAM)."
    gcloud services enable "$api" --project="$PROJECT_ID" >/dev/null 2>&1 ||
      warn "Cannot enable $api; continuing if lab provisioned it."
  fi
done

step 2 "Prepare PostgreSQL pglogical and migration user"
if [[ -z "${MIGRATION_PASSWORD:-}" ]]; then
  [[ -t 0 ]] || die "Set MIGRATION_PASSWORD via an interactive Cloud Shell prompt"
  read -r -s -p "Enter the source migration_admin password shown in the lab: " MIGRATION_PASSWORD
  printf '\n'
fi
[[ -n "$MIGRATION_PASSWORD" ]] || die "Migration password cannot be blank"
remote_prepare() {
  printf 'MIGRATION_PASSWORD=%q\n' "$MIGRATION_PASSWORD"
  cat <<'REMOTE'
set -Eeuo pipefail
PG_VERSION_NUM="$(sudo -u postgres psql -Atqc 'SHOW server_version_num')"
PG_MAJOR="$((PG_VERSION_NUM / 10000))"
[[ "$PG_MAJOR" -ge 12 ]] || { echo "Unexpected PostgreSQL version"; exit 1; }
sudo apt-get update -qq
sudo apt-get install -y "postgresql-${PG_MAJOR}-pglogical"
LIBRARIES="$(sudo -u postgres psql -Atqc 'SHOW shared_preload_libraries')"
if [[ ",$LIBRARIES," != *,pglogical,* ]]; then
  LIBRARIES="${LIBRARIES:+$LIBRARIES,}pglogical"
  sudo -u postgres psql -v ON_ERROR_STOP=1 -c \
    "ALTER SYSTEM SET shared_preload_libraries = '$LIBRARIES';"
fi
sudo -u postgres psql -v ON_ERROR_STOP=1 <<'SQL'
ALTER SYSTEM SET wal_level = 'logical';
ALTER SYSTEM SET max_worker_processes = '10';
ALTER SYSTEM SET max_replication_slots = '10';
ALTER SYSTEM SET max_wal_senders = '10';
ALTER SYSTEM SET listen_addresses = '*';
SQL
sudo systemctl restart "postgresql@${PG_MAJOR}-main"
# Escape a single quote before interpolating into a SQL string literal.
SQL_PASSWORD="${MIGRATION_PASSWORD//\'/\'\'}"
sudo -u postgres psql -v ON_ERROR_STOP=1 -d postgres <<SQL
SELECT format('CREATE ROLE migration_admin LOGIN REPLICATION PASSWORD %L',
              '$SQL_PASSWORD')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'migration_admin') \gexec
ALTER DATABASE orders OWNER TO migration_admin;
SQL
for db in postgres orders gmemegen_db; do
  sudo -u postgres psql -v ON_ERROR_STOP=1 -d "$db" <<'SQL'
CREATE EXTENSION IF NOT EXISTS pglogical;
GRANT ALL ON SCHEMA pglogical TO migration_admin;
GRANT SELECT ON ALL TABLES IN SCHEMA pglogical TO migration_admin;
GRANT ALL ON SCHEMA public TO migration_admin;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO migration_admin;
SQL
done
sudo -u postgres psql -v ON_ERROR_STOP=1 -d orders <<'SQL'
ALTER TABLE public.distribution_centers OWNER TO migration_admin;
ALTER TABLE public.inventory_items OWNER TO migration_admin;
ALTER TABLE public.order_items OWNER TO migration_admin;
ALTER TABLE public.products OWNER TO migration_admin;
ALTER TABLE public.users OWNER TO migration_admin;
SQL
sudo -u postgres psql -Atqc 'SHOW wal_level; SHOW shared_preload_libraries'
REMOTE
}
remote_prepare | gcloud compute ssh "$SOURCE_VM" --project="$PROJECT_ID" \
  --zone="$VM_ZONE" --command='sudo bash -s' -- -T
unset MIGRATION_PASSWORD
ok "pglogical, migration role and source ownership prepared"

step 3 "Create or reuse DMS source/destination connection profiles"
if ! gcloud database-migration connection-profiles describe "$SOURCE_PROFILE" \
  --project="$PROJECT_ID" --region="$REGION" >/dev/null 2>&1; then
  say "Enter the SAME source migration_admin password at the gcloud prompt."
  gcloud database-migration connection-profiles create postgresql "$SOURCE_PROFILE" \
    --project="$PROJECT_ID" --region="$REGION" --role=SOURCE \
    --host="$SOURCE_IP" --port=5432 --username="$SOURCE_USER" \
    --prompt-for-password --no-async
else
  ok "Source profile already exists: $SOURCE_PROFILE"
fi
if ! gcloud database-migration connection-profiles describe "$DEST_PROFILE" \
  --project="$PROJECT_ID" --region="$REGION" >/dev/null 2>&1; then
  say "Enter the existing Cloud SQL postgres password at the gcloud prompt."
  gcloud database-migration connection-profiles create postgresql "$DEST_PROFILE" \
    --project="$PROJECT_ID" --region="$REGION" --role=DESTINATION \
    --cloudsql-instance="$DEST_INSTANCE" --username=postgres \
    --prompt-for-password --no-async
else
  ok "Destination profile already exists: $DEST_PROFILE"
fi

step 4 "Create or reuse continuous DMS job using VPC peering"
if ! gcloud database-migration migration-jobs describe "$JOB_ID" \
  --project="$PROJECT_ID" --region="$REGION" >/dev/null 2>&1; then
  gcloud database-migration migration-jobs create "$JOB_ID" \
    --project="$PROJECT_ID" --region="$REGION" \
    --source="$SOURCE_PROFILE" --destination="$DEST_PROFILE" \
    --type=CONTINUOUS --all-databases \
    --peer-vpc="projects/$PROJECT_ID/global/networks/$NETWORK" --no-async
else
  ok "Migration job already exists: $JOB_ID"
fi

step 5 "Restrict PostgreSQL and firewall access to DMS peering CIDR"
DMS_CIDR="${DMS_CIDR:-}"
if [[ -z "$DMS_CIDR" ]]; then
  mapfile -t ROUTES < <(gcloud compute routes list --project="$PROJECT_ID" \
    --filter="name~peering-route" --format='value(destRange)' 2>/dev/null |
    grep -E '^[0-9]+(\.[0-9]+){3}/[0-9]+$' | sort -u || true)
  if [[ "${#ROUTES[@]}" -eq 1 ]]; then
    DMS_CIDR="${ROUTES[0]}"
  else
    warn "DMS peering CIDR could not be uniquely detected."
    printf 'Peering route candidates: %s\n' "${ROUTES[*]:-(none)}"
    [[ -t 0 ]] || die "Supply DMS_CIDR from VPC Network > VPC peering > Effective routes"
    read -r -p "Enter the DMS peering destination CIDR (e.g. 10.x.y.0/24): " DMS_CIDR
  fi
fi
[[ "$DMS_CIDR" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/([0-9]|[12][0-9]|3[0-2])$ ]] ||
  die "Invalid CIDR: $DMS_CIDR"
say "Restricting DMS access to: $DMS_CIDR"
remote_hba() {
  printf 'DMS_CIDR=%q\n' "$DMS_CIDR"
  cat <<'REMOTE'
set -Eeuo pipefail
HBA_FILE="$(sudo -u postgres psql -Atqc 'SHOW hba_file')"
for rule in "host all all $DMS_CIDR md5" \
            "host replication all $DMS_CIDR md5"; do
  grep -Fxq "$rule" "$HBA_FILE" || printf '%s\n' "$rule" | sudo tee -a "$HBA_FILE" >/dev/null
done
PG_VERSION_NUM="$(sudo -u postgres psql -Atqc 'SHOW server_version_num')"
sudo systemctl reload "postgresql@$((PG_VERSION_NUM / 10000))-main"
REMOTE
}
remote_hba | gcloud compute ssh "$SOURCE_VM" --project="$PROJECT_ID" \
  --zone="$VM_ZONE" --command='sudo bash -s' -- -T
if gcloud compute instances add-tags "$SOURCE_VM" --project="$PROJECT_ID" \
  --zone="$VM_ZONE" --tags=gsp918-pg-source >/dev/null 2>&1; then
  if ! gcloud compute firewall-rules describe gsp918-allow-dms-postgres \
    --project="$PROJECT_ID" >/dev/null 2>&1; then
    gcloud compute firewall-rules create gsp918-allow-dms-postgres \
      --project="$PROJECT_ID" --network="$NETWORK" --direction=INGRESS \
      --priority=1000 --allow=tcp:5432 --source-ranges="$DMS_CIDR" \
      --target-tags=gsp918-pg-source ||
      warn "Firewall rule creation denied; check source VM ingress manually."
  fi
else
  warn "Cannot set VM network tag; verify existing firewall allows DMS CIDR."
fi

step 6 "Demote destination, verify and start migration"
JOB_STATE="$(gcloud database-migration migration-jobs describe "$JOB_ID" \
  --project="$PROJECT_ID" --region="$REGION" --format='value(state)')"
if [[ "$JOB_STATE" == COMPLETED ]]; then
  ok "Migration already completed"
  exit 0
fi
if [[ "$JOB_STATE" == NOT_STARTED || "$JOB_STATE" == READY ]]; then
  gcloud database-migration migration-jobs demote-destination "$JOB_ID" \
    --project="$PROJECT_ID" --region="$REGION"
  gcloud database-migration migration-jobs verify "$JOB_ID" \
    --project="$PROJECT_ID" --region="$REGION"
  gcloud database-migration migration-jobs start "$JOB_ID" \
    --project="$PROJECT_ID" --region="$REGION"
else
  warn "Existing migration state: $JOB_STATE; not repeating demotion/start."
fi
for attempt in $(seq 1 40); do
  JOB_STATE="$(gcloud database-migration migration-jobs describe "$JOB_ID" \
    --project="$PROJECT_ID" --region="$REGION" --format='value(state)' || true)"
  JOB_PHASE="$(gcloud database-migration migration-jobs describe "$JOB_ID" \
    --project="$PROJECT_ID" --region="$REGION" --format='value(phase)' || true)"
  say "DMS state=$JOB_STATE phase=$JOB_PHASE ($attempt/40)"
  [[ "$JOB_PHASE" == CDC ]] && break
  [[ "$JOB_STATE" == FAILED ]] && die "DMS job failed; inspect the migration job errors."
  sleep 30
done
[[ "$JOB_PHASE" == CDC ]] ||
  die "CDC not confirmed within 20 minutes; do not promote before verifying."

step 7 "Verify migrated data and one CDC insert"
remote_insert() {
  cat <<'REMOTE'
set -Eeuo pipefail
sudo -u postgres psql -v ON_ERROR_STOP=1 -d orders <<'SQL'
INSERT INTO public.distribution_centers(longitude,latitude,name,id)
SELECT -80.1918,25.7617,'Miami FL',11
WHERE NOT EXISTS (SELECT 1 FROM public.distribution_centers WHERE id=11);
SELECT count(*) AS miami_rows FROM public.distribution_centers WHERE id=11;
SQL
REMOTE
}
remote_insert | gcloud compute ssh "$SOURCE_VM" --project="$PROJECT_ID" \
  --zone="$VM_ZONE" --command='sudo bash -s' -- -T
say "Verify Cloud SQL postgres password (not logged or passed as a CLI argument)."
if [[ -z "${DEST_PASSWORD:-}" ]]; then
  [[ -t 0 ]] || die "An interactive Cloud SQL password is required for CDC verification."
  read -r -s -p "Cloud SQL postgres password: " DEST_PASSWORD
  printf '\n'
fi
[[ -n "$DEST_PASSWORD" ]] || die "Cloud SQL password is required"
CDC_OK=0
for attempt in $(seq 1 12); do
  if OUTPUT="$(printf '%s\n' '\pset tuples_only on' '\pset format unaligned' \
    'SELECT count(*) FROM public.distribution_centers WHERE id=11;' \
    '\q' | PGPASSWORD="$DEST_PASSWORD" gcloud sql connect "$DEST_INSTANCE" \
      --project="$PROJECT_ID" --user=postgres --database=orders --quiet 2>&1)"; then
    if printf '%s\n' "$OUTPUT" | grep -qx '1'; then
      CDC_OK=1
      break
    fi
  else
    warn "Cloud SQL verification attempt $attempt failed; retrying."
  fi
  sleep 15
done
unset DEST_PASSWORD
[[ "$CDC_OK" -eq 1 ]] ||
  die "Cannot confirm replicated Miami row in Cloud SQL. Verify manually before promotion."
ok "CDC row confirmed in Cloud SQL"

step 8 "Promote Cloud SQL to standalone primary"
gcloud database-migration migration-jobs promote "$JOB_ID" \
  --project="$PROJECT_ID" --region="$REGION"
for attempt in $(seq 1 30); do
  JOB_STATE="$(gcloud database-migration migration-jobs describe "$JOB_ID" \
    --project="$PROJECT_ID" --region="$REGION" --format='value(state)' || true)"
  [[ "$JOB_STATE" == COMPLETED ]] && break
  sleep 20
done
[[ "$JOB_STATE" == COMPLETED ]] ||
  die "Promotion requested but completion not confirmed; inspect DMS job."
ok "GSP918 workflow finished. Check all five official progress checkpoints."
warn "Static validated only; runtime/grader unverified until tested in an authorized lab."
