# Copyright (c) 2025 ePlus.DEV. All rights reserved.
# Unauthorized copying, modification, distribution, or use is strictly prohibited.

#!/usr/bin/env bash
set -euo pipefail

# ===== Pretty logs =====
log(){ echo -e "\n\033[1;35m==> $*\033[0m"; }
ok(){ echo -e "\033[1;32m✔\033[0m $*"; }
warn(){ echo -e "\033[1;33m⚠\033[0m $*"; }

wait_for_instance() {
  local inst="$1" state=""
  log "Waiting for Cloud SQL instance [$inst] to be RUNNABLE…"
  while true; do
    state=$(gcloud sql instances describe "$inst" --format="value(state)" 2>/dev/null || echo "")
    [[ "$state" == "RUNNABLE" ]] && break
    sleep 5
  done
  ok "Instance is RUNNABLE."
}

refresh_allowlist() {
  # Refresh authorized networks: bastion-vm NAT IP + current Cloud Shell IP
  if [[ -z "${ZONE:-}" ]]; then
    ZONE=$(gcloud compute instances list --filter="name=bastion-vm" --format="value(zone)")
  fi
  local BASTION_IP="$(gcloud compute instances describe bastion-vm --zone="$ZONE" --format='value(networkInterfaces[0].accessConfigs[0].natIP)')"
  local CS_IP="$(curl -s ifconfig.me)"
  log "Updating Authorized networks: Bastion=$BASTION_IP, CloudShell=$CS_IP"
  gcloud sql instances patch "$CLOUDSQL_INSTANCE" \
    --authorized-networks="${BASTION_IP}/32,${CS_IP}/32" --quiet || true
}

prompt_lab_email() {
  local default_email
  default_email="$(gcloud config get-value core/account -q || true)"
  while :; do
    read -r -p "Enter lab email for IAM DB user [${default_email}]: " LAB_USER
    LAB_USER="${LAB_USER:-$default_email}"
    if [[ "$LAB_USER" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
      echo "Using LAB_USER=$LAB_USER"
      break
    else
      echo "Invalid email. Please try again."
    fi
  done
}

# ===== Variables =====
log "Init variables"
export PROJECT_ID="$(gcloud config get-value core/project -q)"
export CLOUDSQL_INSTANCE="postgres-orders"
export KMS_KEYRING_ID="cloud-sql-keyring"
export KMS_KEY_ID="cloud-sql-key"

# Derive REGION from bastion-vm's zone (per lab)
export ZONE="$(gcloud compute instances list --filter="name=bastion-vm" --format="value(zone)")"
if [[ -z "$ZONE" ]]; then
  echo "bastion-vm not found. Please create/verify it per the lab." >&2
  exit 1
fi
export REGION="${ZONE::-2}"

# ===== Task 1. CMEK + Cloud SQL instance =====
log "Create Cloud SQL service identity (if not exists)"
gcloud beta services identity create --service=sqladmin.googleapis.com --project="$PROJECT_ID" || true
export PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"

log "Create KMS keyring/key & bind EncrypterDecrypter"
gcloud kms keyrings create "$KMS_KEYRING_ID" --location="$REGION" || true
gcloud kms keys create "$KMS_KEY_ID" \
  --location="$REGION" --keyring="$KMS_KEYRING_ID" --purpose="encryption" || true

gcloud kms keys add-iam-policy-binding "$KMS_KEY_ID" \
  --location="$REGION" --keyring="$KMS_KEYRING_ID" \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-cloud-sql.iam.gserviceaccount.com" \
  --role="roles/cloudkms.cryptoKeyEncrypterDecrypter" || true

export KEY_NAME="$(gcloud kms keys describe "$KMS_KEY_ID" --keyring="$KMS_KEYRING_ID" --location="$REGION" --format='value(name)')"

log "Fetch & allowlist IPs (bastion + Cloud Shell)"
refresh_allowlist

log "Create Cloud SQL PostgreSQL 13 with CMEK (if needed)"
if ! gcloud sql instances describe "$CLOUDSQL_INSTANCE" >/dev/null 2>&1; then
  gcloud sql instances create "$CLOUDSQL_INSTANCE" \
    --project="$PROJECT_ID" \
    --authorized-networks="$(gcloud compute instances describe bastion-vm --zone="$ZONE" --format='value(networkInterfaces[0].accessConfigs[0].natIP)')/32,$(curl -s ifconfig.me)/32" \
    --disk-encryption-key="$KEY_NAME" \
    --database-version=POSTGRES_13 \
    --cpu=1 \
    --memory=3840MB \
    --region="$REGION" \
    --root-password="supersecret!"
else
  warn "Instance $CLOUDSQL_INSTANCE already exists; skipping create."
fi

wait_for_instance "$CLOUDSQL_INSTANCE"
export POSTGRESQL_IP="$(gcloud sql instances describe "$CLOUDSQL_INSTANCE" --format="value(ipAddresses[0].ipAddress)")"

# ===== Task 2. Enable & configure pgAudit =====
log "Enable pgAudit flags at instance level + restart"
# IMPORTANT: supply all desired flags (patch overwrites)
gcloud sql instances patch "$CLOUDSQL_INSTANCE" \
  --database-flags=cloudsql.enable_pgaudit=on,pgaudit.log=all \
  --quiet
gcloud sql instances restart "$CLOUDSQL_INSTANCE" --quiet
wait_for_instance "$CLOUDSQL_INSTANCE"

log "Create DB 'orders' (if missing) & enable pgAudit in DB"
export PGPASSWORD="supersecret!"
psql "sslmode=disable user=postgres hostaddr=${POSTGRESQL_IP} dbname=postgres" \
  -tc "SELECT 1 FROM pg_database WHERE datname='orders'" | grep -q 1 || \
psql "sslmode=disable user=postgres hostaddr=${POSTGRESQL_IP} dbname=postgres" \
  -c "CREATE DATABASE orders;"

psql "sslmode=disable user=postgres hostaddr=${POSTGRESQL_IP} dbname=orders" \
  -c "CREATE EXTENSION IF NOT EXISTS pgaudit; ALTER DATABASE orders SET pgaudit.log='read,write';"

ok "Verify pgAudit extension/setting"
psql "sslmode=disable user=postgres hostaddr=${POSTGRESQL_IP} dbname=orders" -c "\dx" | sed -n '1,999p' >/dev/null
psql "sslmode=disable user=postgres hostaddr=${POSTGRESQL_IP} dbname=orders" -c "SHOW pgaudit.log;" | sed -n '1,999p' >/dev/null

log "Download & import lab data"
mkdir -p /tmp/orders && cd /tmp/orders
gsutil -m cp gs://spls/gsp920/create_orders_db.sql .
gsutil -m cp gs://spls/gsp920/DDL/distribution_centers_data.csv .
gsutil -m cp gs://spls/gsp920/DDL/inventory_items_data.csv .
gsutil -m cp gs://spls/gsp920/DDL/order_items_data.csv .
gsutil -m cp gs://spls/gsp920/DDL/products_data.csv .
gsutil -m cp gs://spls/gsp920/DDL/users_data.csv .

psql "sslmode=disable user=postgres hostaddr=${POSTGRESQL_IP}" -f create_orders_db.sql

log "Set auditor role & grant SELECT on order_items"
psql "sslmode=disable user=postgres hostaddr=${POSTGRESQL_IP} dbname=orders" <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='auditor') THEN
    CREATE ROLE auditor NOLOGIN;
  END IF;
END$$;
ALTER DATABASE orders SET pgaudit.role='auditor';
GRANT SELECT ON TABLE order_items TO auditor;
SQL

# (Recommended) Enable Data Access Audit Logs for Cloud SQL (best-effort via CLI)
log "Enable Data Access Audit Logs for Cloud SQL (best-effort via CLI)"
set +e
gcloud projects get-iam-policy "$PROJECT_ID" --format=json >/tmp/policy.json
if command -v jq >/dev/null 2>&1; then
  jq '
    .auditConfigs = (
      [(.auditConfigs // [])[] | select(.service != "cloudsql.googleapis.com")] +
      [{
        service: "cloudsql.googleapis.com",
        auditLogConfigs: [
          {logType:"ADMIN_READ"},
          {logType:"DATA_READ"},
          {logType:"DATA_WRITE"}
        ]
      }]
    )
  ' /tmp/policy.json > /tmp/policy.new.json && \
  gcloud projects set-iam-policy "$PROJECT_ID" /tmp/policy.new.json >/dev/null && \
  ok "Audit Logs enabled (or already enabled)."
else
  warn "jq not found; enable Audit Logs in UI: IAM & Admin → Audit Logs → Cloud SQL → Data/Admin Read/Write."
fi
set -e

# ===== Task 3. Cloud SQL IAM authentication =====
log "Enable cloudsql.iam_authentication (keep pgAudit flags) + restart"
refresh_allowlist
gcloud sql instances patch "$CLOUDSQL_INSTANCE" \
  --database-flags=cloudsql.enable_pgaudit=on,pgaudit.log=all,cloudsql.iam_authentication=on \
  --quiet
gcloud sql instances restart "$CLOUDSQL_INSTANCE" --quiet
wait_for_instance "$CLOUDSQL_INSTANCE"
refresh_allowlist
export POSTGRESQL_IP="$(gcloud sql instances describe "$CLOUDSQL_INSTANCE" --format="value(ipAddresses[0].ipAddress)")"

log "Prompt for lab email & create IAM DB user"
prompt_lab_email
gcloud sql users create "$LAB_USER" --instance="$CLOUDSQL_INSTANCE" --type=cloud_iam_user || true

log "Grant privileges on order_items to the IAM user"
psql "sslmode=disable user=postgres hostaddr=${POSTGRESQL_IP} dbname=orders" \
  -c "GRANT ALL PRIVILEGES ON TABLE order_items TO \"${LAB_USER}\";"

log "Test IAM login (OAuth token as 'password')"
export USERNAME="$LAB_USER"
export PGPASSWORD="$(gcloud auth print-access-token)"
psql --host="$POSTGRESQL_IP" "$USERNAME" --dbname=orders -c "SELECT COUNT(*) FROM order_items;" || {
  warn "If auth fails, refresh token: export PGPASSWORD=\$(gcloud auth print-access-token)"
  exit 1
}

# Optional: confirm you DON'T have access elsewhere (should be denied)
set +e
psql --host="$POSTGRESQL_IP" "$USERNAME" --dbname=orders -c "SELECT COUNT(*) FROM users;"
set -e

ok "All done: Task 1 → 3 (CMEK + pgAudit + IAM auth) completed."