#!/bin/bash
# ---------------------------------------------------
# Google Cloud SQL + BigQuery Lab - FULL AUTO SCRIPT
# ---------------------------------------------------

export PROJECT_ID=$(gcloud config get-value project)
export BUCKET_NAME=${PROJECT_ID}-bike-bucket
export INSTANCE_NAME=my-demo
export DB_NAME=bike
export ROOT_PASS="MyRootPass123!"
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

echo ">>> Project: $PROJECT_ID"

# ---------------------------------------------------
# 1. Tạo bucket
# ---------------------------------------------------
echo ">>> Creating Cloud Storage bucket..."
gsutil mb -l $REGION gs://$BUCKET_NAME/

# ---------------------------------------------------
# 2. Export dataset BigQuery thành CSV
# ---------------------------------------------------
echo ">>> Exporting CSV from BigQuery..."

bq query --use_legacy_sql=false --format=csv --max_rows=1000000 \
"SELECT start_station_name, COUNT(*) as num
 FROM \`bigquery-public-data.london_bicycles.cycle_hire\`
 GROUP BY start_station_name
 ORDER BY num DESC" > start_station_data.csv

bq query --use_legacy_sql=false --format=csv --max_rows=1000000 \
"SELECT end_station_name, COUNT(*) as num
 FROM \`bigquery-public-data.london_bicycles.cycle_hire\`
 GROUP BY end_station_name
 ORDER BY num DESC" > end_station_data.csv

# Upload CSV lên bucket
echo ">>> Uploading CSV files to bucket..."
gsutil cp start_station_data.csv gs://$BUCKET_NAME/
gsutil cp end_station_data.csv gs://$BUCKET_NAME/

# ---------------------------------------------------
# 3. Tạo Cloud SQL Instance
# ---------------------------------------------------
echo ">>> Creating Cloud SQL instance..."
gcloud sql instances create $INSTANCE_NAME \
  --database-version=MYSQL_8_0 \
  --cpu=4 --memory=16GB \
  --region=$REGION \
  --edition=ENTERPRISE \
  --storage-size=100 \
  --root-password=$ROOT_PASS

# ---------------------------------------------------
# 4. Đợi instance READY
# ---------------------------------------------------
echo ">>> Waiting for instance $INSTANCE_NAME to be READY..."
while true; do
  STATUS=$(gcloud sql instances describe $INSTANCE_NAME --format="value(state)" 2>/dev/null)
  if [[ "$STATUS" == "RUNNABLE" ]]; then
    echo ">>> Instance $INSTANCE_NAME is READY ✅"
    break
  else
    echo "   Current status: $STATUS ... retry in 15s"
    sleep 15
  fi
done

# ---------------------------------------------------
# 5. Tạo database + tables
# ---------------------------------------------------
echo ">>> Creating database and tables..."
gcloud sql connect $INSTANCE_NAME --user=root --quiet <<EOF
CREATE DATABASE IF NOT EXISTS $DB_NAME;
USE $DB_NAME;
CREATE TABLE IF NOT EXISTS london1 (start_station_name VARCHAR(255), num INT);
CREATE TABLE IF NOT EXISTS london2 (end_station_name VARCHAR(255), num INT);
EOF

# ---------------------------------------------------
# 6. Import CSV vào Cloud SQL
# ---------------------------------------------------
echo ">>> Importing CSV into london1..."
gcloud sql import csv $INSTANCE_NAME gs://$BUCKET_NAME/start_station_data.csv \
  --database=$DB_NAME --table=london1

echo ">>> Importing CSV into london2..."
gcloud sql import csv $INSTANCE_NAME gs://$BUCKET_NAME/end_station_data.csv \
  --database=$DB_NAME --table=london2

# ---------------------------------------------------
# 7. Cleanup + Insert + UNION Query test
# ---------------------------------------------------
echo ">>> Running cleanup and UNION query..."
gcloud sql connect $INSTANCE_NAME --user=root --quiet <<EOF
USE $DB_NAME;

-- Xóa header row
DELETE FROM london1 WHERE num=0;
DELETE FROM london2 WHERE num=0;

-- Thêm 1 dòng test
INSERT INTO london1 (start_station_name, num) VALUES ("test destination", 1);

-- UNION Query
SELECT start_station_name AS top_stations, num
FROM london1 WHERE num>100000
UNION
SELECT end_station_name, num
FROM london2 WHERE num>100000
ORDER BY top_stations DESC;
EOF

echo ">>> ALL DONE 🚀"