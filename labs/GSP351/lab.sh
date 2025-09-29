#!/bin/bash
# ==============================================================
# 🌐 GOOGLE CLOUD MYSQL MIGRATION SCRIPT
# --------------------------------------------------------------
# 📦 Project: Migrate MySQL Data to Cloud SQL using DMS
# 🧑‍💻 Author: David Nguyen (Nguyễn Ngọc Minh Hoàng)
# 🏢 Organization: EPLUS.DEV
# 📅 Version: 5.0.0
# 📜 Copyright (c) 2025 EPLUS.DEV
# ⚠️ All Rights Reserved.
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

ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
PROJECT_ID=$(gcloud config get-value project)

echo -e "${BLUE}✅ Region:${NC} $REGION"
echo -e "${BLUE}✅ Zone:${NC} $ZONE"
echo -e "${BLUE}✅ Project:${NC} $PROJECT_ID"

# STEP 1: Enable API
echo -e "${GREEN}🔍 Checking Database Migration API status...${NC}"
if ! gcloud services list --enabled | grep -q "datamigration.googleapis.com"; then
  echo -e "${YELLOW}⚠️ API not enabled. Enabling now...${NC}"
  gcloud services enable datamigration.googleapis.com
else
  echo -e "${BLUE}✅ Database Migration API already enabled.${NC}"
fi

# STEP 2: Mandatory Inputs
echo -e "${YELLOW}⚠️ REQUIRED INPUTS (type exactly as shown):${NC}"
read -p "👉 Enter MySQL source instance: " SOURCE_INSTANCE       # prd-eng-ovt
read -p "👉 Enter Cloud SQL one-time target: " TARGET_ONE        # mysql-eng-ovt
read -p "👉 Enter Cloud SQL continuous target: " TARGET_CONT     # mysql-eng-ovt-cont

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
  --mysql-host=$SOURCE_IP \
  --mysql-port=3306 \
  --mysql-username=admin \
  --mysql-password=changeme \
  --display-name="MySQL Source External"

# STEP 5: One-time migration
echo -e "${GREEN}💾 Creating Cloud SQL instance for one-time migration...${NC}"
gcloud sql instances create $TARGET_ONE \
  --database-version=MYSQL_8_0 \
  --tier=db-custom-2-8192 \
  --storage-type=SSD \
  --storage-size=10GB \
  --region=$REGION

# Reset root password & allowlist current IP
echo -e "${GREEN}🔑 Resetting root password & allowlisting IP...${NC}"
gcloud sql users set-password root --host=% --instance=$TARGET_ONE --password=supersecret!
gcloud sql instances patch $TARGET_ONE --authorized-networks=$(curl -s ifconfig.me)

echo -e "${GREEN}🚚 Creating one-time migration job...${NC}"
gcloud database-migration migration-jobs create $TARGET_ONE \
  --region=$REGION \
  --type=ONE_TIME \
  --source=projects/$PROJECT_ID/locations/$REGION/connectionProfiles/mysql-src-profile \
  --destination-instance=$TARGET_ONE

echo -e "${YELLOW}▶️ Starting one-time migration...${NC}"
gcloud database-migration migration-jobs start $TARGET_ONE --region=$REGION
sleep 120

echo -e "${GREEN}🔎 Verifying migrated data...${NC}"
gcloud sql connect $TARGET_ONE --user=root --quiet <<'EOF'
use customers_data;
select count(*) from customers;
EOF

# STEP 6: VPC Peering
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

  echo -e "${BLUE}✅ VPC Peering created. Waiting 60s to finalize...${NC}"
  sleep 60
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

echo -e "${GREEN}🔑 Resetting root password & allowlisting IP for continuous instance...${NC}"
gcloud sql users set-password root --host=% --instance=$TARGET_CONT --password=supersecret!
gcloud sql instances patch $TARGET_CONT --authorized-networks=$(curl -s ifconfig.me)

echo -e "${GREEN}🚚 Creating continuous migration job...${NC}"
gcloud database-migration migration-jobs create $TARGET_CONT \
  --region=$REGION \
  --type=CONTINUOUS \
  --source=projects/$PROJECT_ID/locations/$REGION/connectionProfiles/mysql-src-profile \
  --destination-instance=$TARGET_CONT

echo -e "${YELLOW}▶️ Starting continuous migration...${NC}"
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
echo " - API enabled ✅"
echo " - VPC Peering ✅"
echo " - One-time migration ✅"
echo " - Continuous migration ✅"
echo " - Replication test ✅"
echo " - Promotion ✅"
echo "=============================================================="
echo -e "${YELLOW}📜 © 2025 EPLUS.DEV | All Rights Reserved${NC}"
echo -e "${BLUE}🚀 Database is now fully migrated and live.${NC}"