#!/bin/bash
# =============================================================
# 📊 BigQuery Load Employee Data
# © 2026 ePlus.DEV
# =============================================================

set -euo pipefail

# =======================
# 🔧 Get PROJECT_ID
# =======================
PROJECT_ID=$(gcloud config get-value project 2>/dev/null || true)

if [[ -z "$PROJECT_ID" ]]; then
  echo "⚠️  PROJECT_ID not found in gcloud config."
  read -rp "👉 Please enter PROJECT_ID: " PROJECT_ID
fi

if [[ -z "$PROJECT_ID" ]]; then
  echo "❌ PROJECT_ID is required. Exiting."
  exit 1
fi

echo "✅ Using PROJECT_ID: $PROJECT_ID"

# =======================
# 🗄️ Dataset config
# =======================
DATASET="work_day"
LOCATION="US"

echo "▶ Checking dataset '${DATASET}'..."

if bq --location="${LOCATION}" show "${PROJECT_ID}:${DATASET}" >/dev/null 2>&1; then
  echo "✔ Dataset '${DATASET}' already exists"
else
  echo "▶ Creating dataset '${DATASET}'..."
  bq --location="${LOCATION}" mk "${PROJECT_ID}:${DATASET}"
fi

# =======================
# 📥 Load CSV to BigQuery
# =======================
echo "▶ Loading employees.csv into BigQuery..."

bq load \
  --source_format=CSV \
  --skip_leading_rows=1 \
  "${PROJECT_ID}:${DATASET}.employee" \
  "gs://${PROJECT_ID}-bucket/employees.csv" \
  employee_id:INTEGER,device_id:STRING,username:STRING,department:STRING,office:STRING

echo "🎉 Done! Data loaded into ${DATASET}.employee"