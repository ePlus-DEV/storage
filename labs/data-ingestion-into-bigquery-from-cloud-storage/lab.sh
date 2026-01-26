#!/bin/bash
# =============================================================
# 🎨 BigQuery Load CSV (Require Bucket Input)
# © 2026 ePlus.DEV
# =============================================================

set -euo pipefail

# =======================
# 🌈 Colors
# =======================
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
BOLD="\033[1m"
RESET="\033[0m"

# =======================
# ⌨️ Require bucket input
# =======================
echo -e "${CYAN}${BOLD}👉 Enter Cloud Storage bucket name (WITHOUT gs://):${RESET}"
read -r BUCKET

if [[ -z "$BUCKET" ]]; then
  echo -e "${RED}❌ Bucket is required. Exit.${RESET}"
  exit 1
fi

GCS_URI="gs://${BUCKET}/employees.csv"
echo -e "${GREEN}✔ Using source: ${GCS_URI}${RESET}"

# =======================
# 🗄️ Create dataset
# =======================
echo -e "${CYAN}▶ Creating dataset work_day (if not exists)...${RESET}"
bq mk work_day 2>/dev/null && \
  echo -e "${GREEN}✔ Dataset created${RESET}" || \
  echo -e "${YELLOW}✔ Dataset already exists${RESET}"

# =======================
# 📥 Load CSV
# =======================
echo -e "${CYAN}▶ Loading employees.csv into BigQuery...${RESET}"
bq load \
  --source_format=CSV \
  --skip_leading_rows=1 \
  work_day.employee \
  "${GCS_URI}" \
  employee_id:INTEGER,device_id:STRING,username:STRING,department:STRING,office:STRING

echo -e "${GREEN}${BOLD}🎉 Load completed successfully!${RESET}"