#!/bin/bash
# © 2025 Eplus.Dev - All Rights Reserved

# ====== COLOR ======
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

# ====== CONFIG ======
PARTNER_PROJECT=$(gcloud projects list --format="value(projectId)" --limit=1)
PARTNER_DATASET="demo_dataset"
PARTNER_VIEW="authorized_view_b9g4"
CUSTOMER_USER="student-00-30098cb3cb36@qwiklabs.net"

echo -e "${BLUE}=============================="
echo -e "STEP 1: Create Partner Authorized View"
echo -e "==============================${NC}"

# Create dataset if not exists
echo -e "${YELLOW}📁 Creating dataset if it doesn't exist...${NC}"
bq --location=US mk --dataset ${PARTNER_PROJECT}:${PARTNER_DATASET} >/dev/null 2>&1 && \
  echo -e "${GREEN}✅ Dataset created.${NC}" || echo -e "${YELLOW}⚠️ Dataset already exists.${NC}"

# Set project
gcloud config set project $PARTNER_PROJECT >/dev/null 2>&1

# Create authorized view
echo -e "${YELLOW}📊 Creating authorized view...${NC}"
bq query --use_legacy_sql=false "
CREATE OR REPLACE VIEW \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${PARTNER_VIEW}\` AS
SELECT * FROM \`bigquery-public-data.geo_us_boundaries.zip_codes\`;
" && echo -e "${GREEN}✅ Partner view created: ${PARTNER_VIEW}${NC}"

# Grant IAM to customer user
echo -e "${YELLOW}🔑 Granting Data Viewer role to customer...${NC}"
gcloud projects add-iam-policy-binding $PARTNER_PROJECT \
  --member="user:${CUSTOMER_USER}" \
  --role="roles/bigquery.dataViewer" >/dev/null 2>&1 && \
  echo -e "${GREEN}✅ Customer user granted access.${NC}" || \
  echo -e "${RED}❌ Could not grant IAM. Please do it manually in IAM console.${NC}"

# Manual step reminder
echo -e "${BLUE}==============================${NC}"
echo -e "${YELLOW}⚠️ MANUAL STEP REQUIRED${NC}"
echo -e "👉 Go to BigQuery Console:"
echo -e "   - Open dataset: ${BLUE}bigquery-public-data.geo_us_boundaries${NC}"
echo -e "   - Click: ${BLUE}SHARE DATASET > Authorized Views > ADD${NC}"
echo -e "   - Add: ${BLUE}${PARTNER_PROJECT}:${PARTNER_DATASET}.${PARTNER_VIEW}${NC}"
echo -e "${GREEN}✅ After done, run part2.sh${NC}"