#!/usr/bin/env bash
set -euo pipefail

# ================= Colors & helpers =================
BOLD=$(tput bold || true); DIM=$(tput dim || true); RESET=$(tput sgr0 || true)
RED=$(tput setaf 1 || true); GREEN=$(tput setaf 2 || true); YELLOW=$(tput setaf 3 || true); CYAN=$(tput setaf 6 || true); MAGENTA=$(tput setaf 5 || true)

banner(){ echo -e "\n${BOLD}${MAGENTA}==> $*${RESET}\n"; }
ok(){ echo -e "${GREEN}✔${RESET} $*"; }
warn(){ echo -e "${YELLOW}⚠${RESET} $*"; }
die(){ echo -e "${RED}✖${RESET} $*"; exit 1; }

# ================= Parameters (change only if needed) =================
CLOUDSQL_INSTANCE="postgres-orders"
ROOT_PASSWORD="supersecret!"
KMS_KEYRING_ID="cloud-sql-keyring"
KMS_KEY_ID="cloud-sql-key"

# ================= Detect project/account/region =================
banner "Detecting Project / Account / Region"
PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project -q || true)}"
[[ -z "${PROJECT_ID}" ]] && die "No project is set. Run: gcloud config set project <PROJECT_ID>"

ACCOUNT_EMAIL="$(gcloud config get-value account -q)"
ok "Project: ${PROJECT_ID}"
ok "Active account (IAM DB user): ${ACCOUNT_EMAIL}"

# Try to infer ZONE from bastion-vm. If not found, fallback to us-central1-a.
if gcloud compute instances describe bastion-vm --zone="$(gcloud compute instances list --filter="name=bastion-vm" --format="value(zone)")" >/dev/null 2>&1; then
  ZONE="$(gcloud compute instances list --filter="name=bastion-vm" --format="value(zone)")"
else
  warn "bastion-vm not found; falling back to us-central1-a"
  ZONE="us-central1-a"
fi
REGION="${ZONE%-*}"
ok "Zone: ${ZONE}"
ok "Region: ${REGION}"

# ================= Enable required APIs =================
banner "Enabling required APIs (if needed)"
gcloud services enable sqladmin.googleapis.com \
  cloudkms.googleapis.com \
  compute.googleapis.com \
  logging.googleapis.com \
  --project="${PROJECT_ID}" >/dev/null
ok "APIs enabled"

# ================= Create Cloud SQL service identity (for CMEK) =================
banner "Creating Cloud SQL service identity (if missing)"
gcloud beta services identity create \
  --service=sqladmin.googleapis.com \
  --project="${PROJECT_ID}" >/dev/null || true
ok "Service identity ensured"

PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"
CLOUDSQL_SA="service-${PROJECT_NUMBER}@gcp-sa-cloud-sql.iam.gserviceaccount.com"
ok "Cloud SQL SA: ${CLOUDSQL_SA}"

# ================= Create KMS keyring & key, bind IAM =================
banner "Creating KMS keyring & key, binding IAM (idempotent)"
if ! gcloud kms keyrings describe "${KMS_KEYRING_ID}" --location="${REGION}" >/dev/null 2>&1; then
  gcloud kms keyrings create "${KMS_KEYRING_ID}" --location="${REGION}"
  ok "Created keyring ${KMS_KEYRING_ID}"
else
  ok "Keyring ${KMS_KEYRING_ID} exists"
fi

if ! gcloud kms keys describe "${KMS_KEY_ID}" --keyring="${KMS_KEYRING_ID}" --location="${REGION}" >/dev/null 2>&1; then
  gcloud kms keys create "${KMS_KEY_ID}" \
    --location="${REGION}" --keyring="${KMS_KEYRING_ID}" --purpose=encryption
  ok "Created key ${KMS_KEY_ID}"
else
  ok "Key ${KMS_KEY_ID} exists"
fi

gcloud kms keys add-iam-policy-binding "${KMS_KEY_ID}" \
  --location="${REGION}" --keyring="${KMS_KEYRING_ID}" \
  --member="serviceAccount:${CLOUDSQL_SA}" \
  --role="roles/cloudkms.cryptoKeyEncrypterDecrypter" >/dev/null || true
ok "Bound ${CLOUDSQL_SA} to roles/cloudkms.cryptoKeyEncrypterDecrypter"

KEY_NAME="$(gcloud kms keys describe "${KMS_KEY_ID}" \
  --keyring="${KMS_KEYRING_ID}" --location="${REGION}" --format='value(name)')"
ok "Full KMS key resource: ${KEY_NAME}"

# ================= Determine authorized IPs =================
banner "Collecting authorized IPs (bastion & Cloud Shell)"
# Bastion external IP
if gcloud compute instances describe bastion-vm --zone="${ZONE}" >/dev/null 2>&1; then
  AUTHORIZED_IP="$(gcloud compute instances describe bastion-vm --zone="${ZONE}" --format='value(networkInterfaces[0].accessConfigs.natIP)')"
  [[ -z "${AUTHORIZED_IP:-}" ]] && warn "bastion-vm has no external IP"
else
  warn "bastion-vm not found; skipping its IP allowlist"
  AUTHORIZED_IP=""
fi

# Cloud Shell public IP
CLOUD_SHELL_IP="$(curl -s ifconfig.me || true)"
[[ -z "${CLOUD_SHELL_IP}" ]] && die "Could not detect Cloud Shell IP"

ok "Bastion IP: ${AUTHORIZED_IP:-<none>}"
ok "Cloud Shell IP: ${CLOUD_SHELL_IP}"

AUTH_NETS="${CLOUD_SHELL_IP}/32"
if [[ -n "${AUTHORIZED_IP}" ]]; then
  AUTH_NETS="${AUTHORIZED_IP}/32,${CLOUD_SHELL_IP}/32"
fi
ok "Authorized networks: ${AUTH_NETS}"

# ================= Create Cloud SQL instance with CMEK =================
banner "Creating Cloud SQL instance with CMEK (if missing)"
if gcloud sql instances describe "${CLOUDSQL_INSTANCE}" >/dev/null 2>&1; then
  ok "Instance ${CLOUDSQL_INSTANCE} already exists (will ensure authorized networks)"
  # Ensure our IPs are allowlisted
  gcloud sql instances patch "${CLOUDSQL_INSTANCE}" \
    --authorized-networks="${AUTH_NETS}" \
    --quiet >/dev/null || true
else
  gcloud sql instances create "${CLOUDSQL_INSTANCE}" \
    --project="${PROJECT_ID}" \
    --authorized-networks="${AUTH_NETS}" \
    --disk-encryption-key="${KEY_NAME}" \
    --database-version=POSTGRES_13 \
    --cpu=1 \
    --memory=3840MB \
    --region="${REGION}" \
    --root-password="${ROOT_PASSWORD}" \
    --quiet
  ok "Created Cloud SQL instance ${CLOUDSQL_INSTANCE}"
fi

# Helper: wait until RUNNABLE
wait_runnable() {
  local inst="$1"
  echo -n "${DIM}Waiting for instance ${inst} to be RUNNABLE"
  while : ; do
    STATE="$(gcloud sql instances describe "${inst}" --format='value(state)')"
    if [[ "${STATE}" == "RUNNABLE" ]]; then
      echo -e "\r${RESET}"
      ok "Instance ${inst} is RUNNABLE"
      break
    fi
    echo -n "."
    sleep 5
  done
}

wait_runnable "${CLOUDSQL_INSTANCE}"

# ================= Enable pgAudit flags & restart =================
banner "Enabling pgAudit flags"
gcloud sql instances patch "${CLOUDSQL_INSTANCE}" \
  --database-flags="cloudsql.enable_pgaudit=on,pgaudit.log=all" \
  --quiet >/dev/null || true
ok "Patched flags: cloudsql.enable_pgaudit=on, pgaudit.log=all"

banner "Restarting instance to apply flags"
gcloud sql instances restart "${CLOUDSQL_INSTANCE}" --quiet
wait_runnable "${CLOUDSQL_INSTANCE}"

POSTGRESQL_IP="$(gcloud sql instances describe "${CLOUDSQL_INSTANCE}" --format='value(ipAddresses[0].ipAddress)')"
ok "Cloud SQL public IP: ${POSTGRESQL_IP}"

# ================= Create DB 'orders' & enable pgaudit at DB level =================
banner "Creating DB 'orders' and enabling pgaudit at DB level"
export PGPASSWORD="${ROOT_PASSWORD}"
psql "sslmode=disable user=postgres hostaddr=${POSTGRESQL_IP}" <<'SQL_CMDS' || true
CREATE DATABASE orders;
SQL_CMDS

psql "sslmode=disable user=postgres hostaddr=${POSTGRESQL_IP} dbname=orders" <<'SQL_CMDS'
CREATE EXTENSION IF NOT EXISTS pgaudit;
ALTER DATABASE orders SET pgaudit.log = 'read,write';
SQL_CMDS
ok "orders DB ready; pgaudit extension enabled and configured"

# ================= NOTE: Audit Logs (manual in Console) =================
banner "Reminder: Enable Cloud Audit Logs for Cloud SQL (Console)"
cat <<EOF
${CYAN}Go to: IAM & Admin > Audit Logs${RESET}
Filter: "Cloud SQL" and enable:
  - Admin read
  - Data read
  - Data write
Then Save.
(Automating Data Access audit logs via CLI/org policy varies by org setup; follow lab steps in Console.)
EOF

# ================= Download sample data & populate =================
banner "Downloading sample data & populating orders DB"
WORKDIR="$(mktemp -d)"
pushd "${WORKDIR}" >/dev/null
gsutil -m cp gs://spls/gsp920/create_orders_db.sql .
gsutil -m cp gs://spls/gsp920/DDL/distribution_centers_data.csv .
gsutil -m cp gs://spls/gsp920/DDL/inventory_items_data.csv .
gsutil -m cp gs://spls/gsp920/DDL/order_items_data.csv .
gsutil -m cp gs://spls/gsp920/DDL/products_data.csv .
gsutil -m cp gs://spls/gsp920/DDL/users_data.csv .
ok "Data files downloaded"

export PGPASSWORD="${ROOT_PASSWORD}"
psql "sslmode=disable user=postgres hostaddr=${POSTGRESQL_IP}" -c "\i create_orders_db.sql"
ok "orders DB populated"
popd >/dev/null

# ================= Configure auditor role and grants =================
banner "Configuring auditor role & grants"
export PGPASSWORD="${ROOT_PASSWORD}"
psql "sslmode=disable user=postgres hostaddr=${POSTGRESQL_IP} dbname=orders" <<'SQL_CMDS'
CREATE ROLE auditor WITH NOLOGIN;
ALTER DATABASE orders SET pgaudit.role = 'auditor';
GRANT SELECT ON order_items TO auditor;
SQL_CMDS
ok "auditor role configured"

# ================= Create IAM DB user (Cloud SQL) =================
banner "Creating Cloud SQL IAM user"
# For Postgres, IAM user = email principal
gcloud sql users create "${ACCOUNT_EMAIL}" \
  --instance="${CLOUDSQL_INSTANCE}" \
  --type=IAM >/dev/null 2>&1 || true
ok "IAM DB user ensured: ${ACCOUNT_EMAIL}"

# Confirm iam_authentication flag appears (may require some time; patching triggers it automatically)
FLAGS="$(gcloud sql instances describe "${CLOUDSQL_INSTANCE}" --format="flattened(settings.databaseFlags[])")"
echo -e "${DIM}${FLAGS}${RESET}" | grep -i "iam" || warn "cloudsql.iam_authentication not printed yet (it is enabled when IAM user exists)."

# ================= Grant table privileges to IAM user =================
banner "Granting table privileges to IAM user on orders.order_items"
export PGPASSWORD="${ROOT_PASSWORD}"
psql "sslmode=disable user=postgres hostaddr=${POSTGRESQL_IP} dbname=orders" <<SQL_CMDS
GRANT ALL PRIVILEGES ON TABLE order_items TO "${ACCOUNT_EMAIL}";
SQL_CMDS
ok "Granted ALL on order_items to ${ACCOUNT_EMAIL}"

# ================= Test connections =================
banner "Testing IAM-auth connection (expected success after setup)"
export PGPASSWORD="$(gcloud auth print-access-token)"
psql --host="${POSTGRESQL_IP}" "${ACCOUNT_EMAIL}" --dbname=orders -c "SELECT COUNT(*) FROM order_items;" | sed 's/^/  /'
ok "SELECT on order_items via IAM user succeeded"

banner "Testing access denied to users table (expected permission denied)"
set +e
psql --host="${POSTGRESQL_IP}" "${ACCOUNT_EMAIL}" --dbname=orders -c "SELECT COUNT(*) FROM users;" >/tmp/iam_denied.txt 2>&1
RET=$?
set -e
if [[ ${RET} -ne 0 ]] && grep -qi "permission denied" /tmp/iam_denied.txt; then
  ok "Permission denied as expected on users table"
else
  warn "Unexpected result when querying users table; check grants"
  cat /tmp/iam_denied.txt || true
fi

# ================= pgAudit log viewing hint =================
banner "View pgAudit logs (Console)"
cat <<EOF
${CYAN}Go to: Logging > Logs Explorer${RESET}
Query:
resource.type="cloudsql_database"
logName="projects/${PROJECT_ID}/logs/cloudaudit.googleapis.com%2Fdata_access"
protoPayload.request.@type="type.googleapis.com/google.cloud.sql.audit.v1.PgAuditEntry"
Then click the latest bars to inspect SELECT/DDL activity.
EOF

banner "All done 🎉  Cloud SQL (PostgreSQL) with CMEK + pgAudit + IAM auth is ready."
echo -e "${BOLD}Instance:${RESET} ${CLOUDSQL_INSTANCE}"
echo -e "${BOLD}Region:${RESET}   ${REGION}"
echo -e "${BOLD}IP:${RESET}       ${POSTGRESQL_IP}"
