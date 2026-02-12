#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  © Copyright ePlus.DEV
# ============================================================

# --------- Colors (optimized) ----------
if command -v tput >/dev/null 2>&1; then
  BLACK="$(tput setaf 0)"; RED="$(tput setaf 1)"; GREEN="$(tput setaf 2)"; YELLOW="$(tput setaf 3)"
  BLUE="$(tput setaf 4)"; MAGENTA="$(tput setaf 5)"; CYAN="$(tput setaf 6)"; WHITE="$(tput setaf 7)"
  BOLD="$(tput bold)"; RESET="$(tput sgr0)"
else
  BLACK=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""; CYAN=""; WHITE=""; BOLD=""; RESET=""
fi

banner() { echo -e "${YELLOW}${BOLD}\n$*\n${RESET}"; }
info()   { echo -e "${CYAN}${BOLD}➜${RESET} $*"; }
ok()     { echo -e "${GREEN}${BOLD}✓${RESET} $*"; }
die()    { echo -e "${RED}${BOLD}✗${RESET} $*" >&2; exit 1; }

# --------- Project / Region ----------
PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
[[ -n "${PROJECT_ID}" ]] || die "Cannot detect PROJECT_ID. Run: gcloud config set project <PROJECT_ID>"

REGION="$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)"
if [[ -z "${REGION}" ]]; then
  REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
fi
[[ -n "${REGION}" ]] || die "Cannot detect REGION. Set it: gcloud config set compute/region <REGION>"

# --------- Vars ----------
INSTANCE_NAME="my-instance"
DB_NAME="mysql-db"
BQ_DATASET="mysql_db"
BQ_TABLE="info"

# Bucket: tránh lỗi 'already exists' / global unique
BUCKET_NAME="gs://${PROJECT_ID}-employee-info-$(date +%s)"

banner "Starting Execution - ePlus.DEV"

info "Project: ${PROJECT_ID}"
info "Region : ${REGION}"

# ============================================================
# TASK 1: Enable API
# ============================================================
info "Enabling Cloud SQL Admin API..."
gcloud services enable sqladmin.googleapis.com --project "${PROJECT_ID}"
ok "API enabled"

# ============================================================
# TASK 2: Create Cloud SQL instance + database
# ============================================================
info "Creating Cloud SQL instance: ${INSTANCE_NAME}"
gcloud sql instances create "${INSTANCE_NAME}" \
  --project="${PROJECT_ID}" \
  --database-version="MYSQL_5_7" \
  --tier="db-n1-standard-1" \
  --region="${REGION}"

ok "Task 2 Completed"

info "Creating database: ${DB_NAME}"
gcloud sql databases create "${DB_NAME}" \
  --instance="${INSTANCE_NAME}" \
  --project="${PROJECT_ID}"
ok "Database created"

# ============================================================
# TASK 3: BigQuery dataset + table, create CSV, upload to GCS, grant IAM
# ============================================================
info "Creating BigQuery dataset: ${BQ_DATASET}"
bq --project_id="${PROJECT_ID}" mk --dataset "${PROJECT_ID}:${BQ_DATASET}" >/dev/null
ok "Dataset created"

info "Creating BigQuery table: ${BQ_DATASET}.${BQ_TABLE}"
bq --project_id="${PROJECT_ID}" query --use_legacy_sql=false "
CREATE TABLE \`${PROJECT_ID}.${BQ_DATASET}.${BQ_TABLE}\` (
  name STRING,
  age INT64,
  occupation STRING
);"
ok "Table created"

info "Writing employee_info.csv"
cat > employee_info.csv <<'EOF_END'
"Sean", 23, "Content Creator"
"Emily", 34, "Cloud Engineer"
"Rocky", 40, "Event coordinator"
"Kate", 28, "Data Analyst"
"Juan", 51, "Program Manager"
"Jennifer", 32, "Web Developer"
EOF_END
ok "CSV created"

info "Creating bucket: ${BUCKET_NAME}"
gsutil mb -p "${PROJECT_ID}" "${BUCKET_NAME}" >/dev/null
ok "Bucket created"

info "Uploading CSV to bucket"
gsutil cp employee_info.csv "${BUCKET_NAME}/" >/dev/null
ok "Uploaded"

info "Granting Storage Admin to Cloud SQL service account"
SERVICE_EMAIL="$(gcloud sql instances describe "${INSTANCE_NAME}" --project="${PROJECT_ID}" --format="value(serviceAccountEmailAddress)")"
[[ -n "${SERVICE_EMAIL}" ]] || die "Cannot get Cloud SQL service account email"

gsutil iam ch "serviceAccount:${SERVICE_EMAIL}:roles/storage.admin" "${BUCKET_NAME}" >/dev/null
ok "IAM granted"

banner "Task 3 Completed\n\nLab Completed !!! - ePlus.DEV"
