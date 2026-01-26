#!/bin/bash

set -euo pipefail

# =======================
# ⌨️ Require bucket input
# =======================
echo "Enter Cloud Storage bucket name (WITHOUT gs://)"
read -r BUCKET

if [[ -z "$BUCKET" ]]; then
  echo "❌ Bucket is required. Exit."
  exit 1
fi

GCS_URI="gs://${BUCKET}/employees.csv"

# =======================
# 🗄️ Create dataset
# =======================
bq mk work_day 2>/dev/null || true

# =======================
# 📥 Load CSV
# =======================
bq load \
  --source_format=CSV \
  --skip_leading_rows=1 \
  work_day.employee \
  "${GCS_URI}" \
  employee_id:INTEGER,device_id:STRING,username:STRING,department:STRING,office:STRING

echo "✅ Load completed"