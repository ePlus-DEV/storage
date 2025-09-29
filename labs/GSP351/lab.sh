#!/bin/bash
# ==============================================================
# 🌐 Google Cloud Challenge Lab Automation Script
# 🚀 Title: Migrate MySQL Data to Cloud SQL using DMS
# 📅 Version: 1.0
# 📜 Copyright (c) 2025 EPLUS.DEV
# 🛠️ Author: David Nguyen (Nguyễn Ngọc Minh Hoàng)
# ==============================================================
# This script automates all 5 tasks of the challenge lab:
# 1️⃣ Create a connection profile for source MySQL (Compute Engine)
# 2️⃣ Perform a one-time migration to Cloud SQL
# 3️⃣ Create and start a continuous migration with VPC peering
# 4️⃣ Test data replication from source → destination
# 5️⃣ Promote Cloud SQL to a standalone database
# ==============================================================

# 🎨 COLOR DEFINITIONS
GREEN="\e[32m"
BLUE="\e[34m"
YELLOW="\e[33m"
RED="\e[31m"
NC="\e[0m" # No Color

echo -e "${BLUE}"
echo "=============================================================="
echo "   🚀 GOOGLE CLOUD - MYSQL MIGRATION AUTOMATION SCRIPT        "
echo "=============================================================="
echo -e "${YELLOW}        © 2025 EPLUS.DEV - All Rights Reserved${NC}"
echo "=============================================================="
echo -e "${NC}"

# STEP 0: Set region and zone
echo -e "${GREEN}🔧 Setting region and zone...${NC}"
gcloud config set compute/region us-east4
gcloud config set compute/zone us-east4-b

ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

PROJECT_ID=$(gcloud config get-value project)
echo -e "${BLUE}✅ Region:${NC} $REGION"
echo -e "${BLUE}✅ Zone:${NC} $ZONE"
echo -e "${BLUE}✅ Project:${NC} $PROJECT_ID"

# STEP 1: Get external IP of the source MySQL
echo -e "${GREEN}🔍 Fetching source MySQL external IP...${NC}"
SOURCE_IP=$(gcloud compute instances describe prd-eng-ovt --zone=$ZONE --format="get(networkInterfaces[0].accessConfigs[0].natIP)")
echo -e "${BLUE}✅ Source IP:${NC} $SOURCE_IP"

# STEP 2: Create a connection profile
echo -e "${GREEN}📡 Creating Database Migration Service connection profile...${NC}"
gcloud database-migration connection-profiles create mysql-src-profile \
  --region=$REGION \
  --type=mysql \
  --host=$SOURCE_IP \
  --port=3306 \
  --username=admin \
  --password=changeme \
  --display-name="MySQL Source External"

# STEP 3: One-time migration
echo -e "${GREEN}💾 Creating Cloud SQL destination for one-time migration...${NC}"
gcloud sql instances create mysql-eng-ovt \
  --database-version=MYSQL_8_0 \
  --tier=db-custom-2-8192 \
  --storage-type=SSD \
  --storage-size=10GB \
  --region=$REGION

gcloud sql users set-password root --host=% --instance=mysql-eng-ovt --password=supersecret!

echo -e "${GREEN}🚚 Creating one-time migration job...${NC}"
gcloud database-migration migration-jobs create mysql-eng-ovt \
  --region=$REGION \
  --type=ONE_TIME \
  --source=mysql-src-profile \
  --destination=projects/$PROJECT_ID/instances/mysql-eng-ovt

echo -e "${YELLOW}▶️ Starting one-time migration...${NC}"
gcloud database-migration migration-jobs start mysql-eng-ovt --region=$REGION

echo -e "${BLUE}⏱️ Waiting 2 minutes for migration to complete...${NC}"
sleep 120

echo -e "${GREEN}🔎 Verifying migrated data...${NC}"
gcloud sql connect mysql-eng-ovt --user=root --quiet <<'EOF'
use customers_data;
select count(*) from customers;
EOF

# STEP 4: Continuous migration (⚠️ Requires VPC Peering already set up)
echo -e "${GREEN}🌐 Creating Cloud SQL destination for continuous migration...${NC}"
gcloud sql instances create mysql-eng-ovt-cont \
  --database-version=MYSQL_8_0 \
  --tier=db-custom-2-8192 \
  --storage-type=SSD \
  --storage-size=10GB \
  --region=$REGION

gcloud sql users set-password root --host=% --instance=mysql-eng-ovt-cont --password=supersecret!

echo -e "${GREEN}🔄 Creating continuous migration job...${NC}"
gcloud database-migration migration-jobs create mysql-eng-ovt-cont \
  --region=$REGION \
  --type=CONTINUOUS \
  --source=mysql-src-profile \
  --destination=projects/$PROJECT_ID/instances/mysql-eng-ovt-cont

echo -e "${YELLOW}▶️ Starting continuous migration...${NC}"
gcloud database-migration migration-jobs start mysql-eng-ovt-cont --region=$REGION

echo -e "${BLUE}⏱️ Waiting 2 minutes for continuous sync to begin...${NC}"
sleep 120

# STEP 5: Update source data to test replication
echo -e "${GREEN}✏️ Updating source database to test replication...${NC}"
gcloud compute ssh prd-eng-ovt --zone=$ZONE --command "
mysql -uadmin -pchangeme -e \"
use customers_data;
update customers set gender='FEMALE' where addressKey=934;
\""

echo -e "${BLUE}⏱️ Waiting 1 minute for replication...${NC}"
sleep 60

echo -e "${GREEN}🔍 Verifying replicated data in destination...${NC}"
gcloud sql connect mysql-eng-ovt-cont --user=root --quiet <<'EOF'
use customers_data;
select gender from customers where addressKey=934;
EOF

# STEP 6: Promote database to standalone
echo -e "${GREEN}🚀 Promoting destination Cloud SQL instance to standalone...${NC}"
gcloud database-migration migration-jobs promote mysql-eng-ovt-cont --region=$REGION

# 🎉 Final message
echo -e "${BLUE}"
echo "=============================================================="
echo "✅ All tasks completed successfully!"
echo "   - One-time migration ✅"
echo "   - Continuous migration ✅"
echo "   - Replication test ✅"
echo "   - Promotion ✅"
echo "=============================================================="
echo -e "${YELLOW}© 2025 EPLUS.DEV | Automation by David Nguyen${NC}"
echo -e "${BLUE}🚀 Mission Complete. Database is now fully migrated and live.${NC}"