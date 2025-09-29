#!/bin/bash
# ================================
# PART 1: Partner setup script
# ================================

PARTNER_PROJECT="student-01-653ba55a470f@qwiklabs.net"
PARTNER_DATASET="demo_dataset"
PARTNER_VIEW="authorized_view_b9g4"
CUSTOMER_USER="student-00-30098cb3cb36@qwiklabs.net"

echo "=============================="
echo "STEP 1: Create Partner Authorized View"
echo "=============================="

gcloud config set project $PARTNER_PROJECT

bq query --use_legacy_sql=false "
CREATE OR REPLACE VIEW \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${PARTNER_VIEW}\` AS
SELECT * FROM \`bigquery-public-data.geo_us_boundaries.zip_codes\`;
"

echo "✅ Partner view created: ${PARTNER_VIEW}"

echo "Grant Data Viewer role to customer user..."
gcloud projects add-iam-policy-binding $PARTNER_PROJECT \
  --member="user:${CUSTOMER_USER}" \
  --role="roles/bigquery.dataViewer"

echo "✅ Customer user has been granted access."

echo "=============================="
echo "⚠️ MANUAL STEP REQUIRED"
echo "=============================="
echo "👉 Go to BigQuery Console:"
echo "   - Open dataset: bigquery-public-data.geo_us_boundaries"
echo "   - Click: SHARE DATASET > Authorized Views > ADD"
echo "   - Add: ${PARTNER_PROJECT}:${PARTNER_DATASET}.${PARTNER_VIEW}"
echo "✅ After you finish, run part2_customer_setup.sh"
