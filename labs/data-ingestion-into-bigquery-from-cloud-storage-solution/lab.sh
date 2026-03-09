#!/usr/bin/env bash

# ==========================================================
#  ePlus.DEV © BigQuery CSV Import Script
# ==========================================================

# ===== COLORS =====
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "============================================================================"
echo "        ePlus.DEV Data Ingestion into BigQuery from Cloud Storage           "
echo "============================================================================"
echo -e "${NC}"

# ===== INPUT BUCKET =====
echo -e "${YELLOW}Enter Cloud Storage Bucket:${NC}"
read -p "BUCKET: " BUCKET

echo -e "${BLUE}Using bucket:${NC} gs://$BUCKET"
echo

# ===== CREATE DATASET =====
echo -e "${CYAN}Creating dataset work_day...${NC}"
bq mk -d work_day >/dev/null 2>&1 || true

# ===== LOAD DATA =====
echo -e "${CYAN}Importing employees.csv into BigQuery...${NC}"

bq load \
--source_format=CSV \
--skip_leading_rows=1 \
work_day.employee \
gs://$BUCKET/employees.csv \
employee_id:INTEGER,device_id:STRING,username:STRING,department:STRING,office:STRING

echo
echo -e "${GREEN}✔ Import completed successfully${NC}"

# ===== VERIFY =====
echo -e "${CYAN}Preview data:${NC}"
bq query --use_legacy_sql=false \
'SELECT * FROM `work_day.employee` LIMIT 5'