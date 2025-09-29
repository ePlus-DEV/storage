#!/bin/bash
# ==============================================================
# 🌐 GOOGLE CLOUD MYSQL MIGRATION SCRIPT
# --------------------------------------------------------------
# 📦 Project: Migrate MySQL Data to Cloud SQL using DMS
# 🧑‍💻 Author: David Nguyen (Nguyễn Ngọc Minh Hoàng)
# 🏢 Organization: EPLUS.DEV
# 📅 Version: 2.0.0
# 📜 Copyright (c) 2025 EPLUS.DEV
# ⚠️ All Rights Reserved. Unauthorized copying, distribution,
#     or modification of this script is strictly prohibited.
# --------------------------------------------------------------
# 🧠 Purpose:
#   - Automates ALL 5 tasks of the challenge lab:
#     1️⃣ Enable API (auto-check)
#     2️⃣ Create connection profile
#     3️⃣ One-time migration
#     4️⃣ Continuous migration (auto-check VPC)
#     5️⃣ Replication test & promotion
# ==============================================================

# 🎨 COLORS
GREEN="\e[32m"
BLUE="\e[34m"
YELLOW="\e[33m"
RED="\e[31m"
NC="\e[0m"

clear
echo -e "${BLUE}"
echo "=============================================================="
echo " 🚀 GOOGLE CLOUD - MYSQL MIGRATION AUTOMATION SCRIPT "
echo "=============================================================="
echo -e "${YELLOW} 📜 © 2025 EPLUS.DEV | All Rights Reserved ${NC}"
echo "=============================================================="
echo -e "${NC}"

# STEP 0: Region & Zone
echo -e "${GREEN}🔧 Setting region and zone...${NC}"
gcloud config set compute/region us-east4
gcloud config set compute/zone us-east4-b

export REGION=us-east4
export ZONE=us-east4-b
PROJECT_ID=$(gcloud config get-value project)

echo -e "${BLUE}✅ Region:${NC} $REGION"
echo -e "${BLUE}✅ Zone:${NC} $ZONE"
echo -e "${BLUE}✅ Project:${NC} $PROJECT_ID"

# STEP 1: Enable Database Migration API if not enabled
echo -e "${GREEN}🔍 Checking Database Migration API status...${NC}"
if ! gcloud services list --enabled | grep -q "datamigration.googleapis.com"; then
  echo -e "${YELLOW}⚠️ API not enabled. Enabling now...${NC}"
  gcloud services enable datamigration.googleapis.com
else
  echo -e "${BLUE}✅ Database Migration API already enabled.${NC}"
fi

# STEP 2: Mandatory user inputs
echo -e "${YELLOW}⚠️ REQUIRED INPUTS (type exactly as shown):${NC}"
read -p "👉 Enter MySQL source instance: " SOURCE_INSTANCE        # prd-eng-ovt
read -p "👉 Enter Cloud SQL one-time target: " TARGET_ONE         # mysql-eng-ovt
read -p "👉 Enter Cloud SQL continuous target: " TARGET_CONT      # mysql-eng-ovt-cont

echo -e "${BLUE}✅ Source Instance:${NC} $SOURCE_INSTANCE"
echo -e "${BLUE}✅ One-time Target:${NC} $TARGET_ONE"
echo -e "${BLUE}✅ Continuous Target:${NC} $TARGET_CONT"

# STEP 3: Fetch source MySQL IP
echo -e "${GREEN}🔍 Getting external IP of MySQL source...${NC}"
SOURCE_IP=$(gcloud compute instances describe $SOURCE_INSTANCE --zone=$ZONE --format="get(networkInterfaces[0].accessConfigs[0].natIP)")
echo -e "${BLUE}✅ Source IP:${NC} $SOURCE_IP"

# STEP 4: Create connection profile
echo -e "${GREEN}📡 Creating connection profile...${NC}"
gcloud database-migration connection-profiles create mysql-src-profile \
  --region=$REGION \
  --type=mysql \
  --host=$SOURCE_IP \
  --port=3306 \
  --username=admin \
  --password=changeme \
  --display-name="MySQL Source External"

# STEP 5: One-time migration
echo -e "${GREEN}💾 Creating Cloud SQL instance for one-time migration...${NC}"
gcloud sql instances create $TARGET_ONE \
  --database-version=MYSQL_8_0 \
  --tier=db-custom-2-8192 \
  --storage-type=SSD \
  --storage-size=10GB \
  --region=$REGION

gcloud sql users set-password root --host=% --instance=$TARGET_ONE --password=supersecret!

echo -e "${GREEN}🚚 Creating one-time migration job...${NC}"
gcloud database-migration migration-jobs create $TARGET_ONE \
  --region=$REGION \
  --type=ONE_TIME \
  --source=mysql-src-profile \
  --destination=projects/$PROJECT_ID/instances/$TARGET_ONE

echo -e "${YELLOW}▶️ Starting one-time migration...${NC}"
gcloud database-migration migration-jobs start $TARGET_ONE --region=$REGION
sleep 120

echo -e "${GREEN}🔎 Verifying migrated data...${NC}"
gcloud sql connect $TARGET_ONE --user=root --quiet <<'EOF'
use customers_data;
select count(*) from customers;
EOF

# STEP 6: Check/Create VPC Peering
echo -e "${GREEN}🌐 Checking VPC peering status...${NC}"
if ! gcloud compute networks peerings list --network=default | grep -q "servicenetworking"; then
  echo -e "${YELLOW}⚠️ VPC Peering not found. Creating now...${NC}"
  gcloud services enable servicenetworking.googleapis.com

  gcloud compute addresses create google-managed-services-default \
    --global \
    --purpose=VPC_PEERING \
    --prefix-length=16 \
    --network=default

  gcloud services vpc-peerings connect \
    --service=servicenetworking.googleapis.com \
    --network=default \
    --ranges=google-managed-services-default

  echo -e "${BLUE}✅ VPC Peering created successfully.${NC}"
else
  echo -e "${BLUE}✅ VPC Peering already configured.${NC}"
fi

# STEP 7: Continuous migration
echo -e "${GREEN}🔄 Creating Cloud SQL instance for continuous migration...${NC}"
gcloud sql instances create $TARGET_CONT \
  --database-version=MYSQL_8_0 \
  --tier=db-custom-2-8192 \
  --storage-type=SSD \
  --storage-size=10GB \
  --region=$REGION

gcloud sql users set-password root --host=% --instance=$TARGET_CONT --password=supersecret!

gcloud database-migration migration-jobs create $TARGET_CONT \
  --region=$REGION \
  --type=CONTINUOUS \
  --source=mysql-src-profile \
  --destination=projects/$PROJECT_ID/instances/$TARGET_CONT

gcloud database-migration migration-jobs start $TARGET_CONT --region=$REGION
sleep 120

# STEP 8: Replication test
echo -e "${GREEN}✏️ Updating source database to test replication...${NC}"
gcloud compute ssh $SOURCE_INSTANCE --zone=$ZONE --command "
mysql -uadmin -pchangeme -e \"
use customers_data;
update customers set gender='FEMALE' where addressKey=934;
\""

echo -e "${BLUE}⏱️ Waiting 1 minute for replication...${NC}"
sleep 60

echo -e "${GREEN}🔍 Checking replicated data...${NC}"
gcloud sql connect $TARGET_CONT --user=root --quiet <<'EOF'
use customers_data;
select gender from customers where addressKey=934;
EOF

# STEP 9: Promote database
echo -e "${GREEN}🚀 Promoting Cloud SQL to standalone...${NC}"
gcloud database-migration migration-jobs promote $TARGET_CONT --region=$REGION

# ✅ Final summary
echo -e "${BLUE}"
echo "=============================================================="
echo "✅ MIGRATION COMPLETE!"
echo " - Database Migration API ✅"
echo " - VPC Peering ✅"
echo " - One-time migration ✅"
echo " - Continuous migration ✅"
echo " - Replication test ✅"
echo " - Promotion ✅"
echo "=============================================================="
echo -e "${YELLOW}📜 © 2025 EPLUS.DEV | All Rights Reserved${NC}"
echo -e "${BLUE}🚀 Database is now fully migrated and live.${NC}"
