#!/bin/bash
# =============================================================
# 📊 BigQuery Load CSV (Require Bucket Input)
# © 2026 ePlus.DEV
# =============================================================

set -euo pipefail

# =======================
# 🔧 Require BUCKET
# =======================
read -rp "👉 Enter Cloud Storage bucket name (without gs://): " BUCKET

if [[ -z "$BUCKET" ]]; then
  echo "❌ Bucket name is required. Exiting."
  exit 1
fi

GCS_URI="gs://${BUCKET}/employees.csv"

# =======================
# 🗄️ Create dataset
# =======================
echo "▶ Creating dataset work_day (if not exists)..."
bq mk work_day 2>/dev/null || echo "✔ Dataset work_day already exists"

# =======================
# 📥 Load CSV
# =======================
echo "▶ Loading employees.csv from ${GCS_URI} ..."
bq load \
  --source_format=CSV \
  --skip_leading_rows=1 \
  work_day.employee \
  "${GCS_URI}" \
  employee_id:INTEGER,device_id:STRING,username:STRING,department:STRING,office:STRING

echo "🎉 Done!"