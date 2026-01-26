#!/bin/bash
# =============================================================
# 🧪 BigQuery Challenge Lab - work_day / employee
# © 2026 ePlus.DEV
# =============================================================

set -euo pipefail

# ====== Config (from lab statement) ======
DATASET="work_day"
TABLE="employee"
LOCATION="US"
BUCKET_NAME="qwiklabs-gcp-00-c94a6d4b9dbf-d4f1-bucket"
GCS_URI="gs://${BUCKET_NAME}/employees.csv"
SCHEMA="employee_id:INTEGER,device_id:STRING,username:STRING,department:STRING,office:STRING"

# ====== Project ======
PROJECT_ID=$(gcloud config get-value project 2>/dev/null || true)
if [[ -z "$PROJECT_ID" ]]; then
  echo "⚠️  PROJECT_ID not found."
  read -rp "👉 Please enter PROJECT_ID: " PROJECT_ID
fi
[[ -z "$PROJECT_ID" ]] && echo "❌ PROJECT_ID is required." && exit 1
echo "✅ Using PROJECT_ID: $PROJECT_ID"

# ====== Check GCS file exists ======
echo "▶ Checking source file: ${GCS_URI}"
gsutil ls "${GCS_URI}" >/dev/null

# ====== Create dataset if missing ======
echo "▶ Ensuring dataset ${DATASET} exists..."
if bq --location="${LOCATION}" show "${PROJECT_ID}:${DATASET}" >/dev/null 2>&1; then
  echo "✔ Dataset exists"
else
  bq --location="${LOCATION}" mk "${PROJECT_ID}:${DATASET}"
  echo "✔ Dataset created"
fi

# ====== Create table if missing ======
echo "▶ Ensuring table ${DATASET}.${TABLE} exists..."
if bq --location="${LOCATION}" show "${PROJECT_ID}:${DATASET}.${TABLE}" >/dev/null 2>&1; then
  echo "✔ Table exists"
else
  bq --location="${LOCATION}" mk \
    --table "${PROJECT_ID}:${DATASET}.${TABLE}" \
    "${SCHEMA}"
  echo "✔ Table created"
fi

# ====== Load CSV ======
echo "▶ Loading CSV into ${DATASET}.${TABLE} ..."
bq --location="${LOCATION}" load \
  --source_format=CSV \
  --skip_leading_rows=1 \
  "${PROJECT_ID}:${DATASET}.${TABLE}" \
  "${GCS_URI}" \
  "${SCHEMA}"

echo "🎉 DONE: Loaded data into ${PROJECT_ID}:${DATASET}.${TABLE}"