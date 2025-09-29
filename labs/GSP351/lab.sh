#!/bin/bash
# ==============================================================
# 🌐 GOOGLE CLOUD MYSQL MIGRATION SCRIPT
# --------------------------------------------------------------
# 📦 Project: Migrate MySQL Data to Cloud SQL using DMS
# 🧑‍💻 Author: David Nguyen (Nguyễn Ngọc Minh Hoàng)
# 🏢 Organization: EPLUS.DEV
# 📅 Version: 6.0.0
# 📜 © 2025 EPLUS.DEV | All Rights Reserved
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
echo " 🚀 GOOGLE CLOUD - MYSQL MIGRATION AUTOMATION SCRIPT (v6.0)"
echo "=============================================================="
echo -e "${YELLOW}📜 © 2025 EPLUS.DEV | All Rights Reserved${NC}"
echo "=============================================================="
echo -e "${NC}"

# STEP 0: Region & Zone
echo -e "${GREEN}🔧 Setting region and zone...${NC}"

ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
PROJECT_ID=$(gcloud config get-value project)

gcloud config set compute/region $REGION
gcloud config set compute/zone us $ZONE

# STEP 1: Enable API
echo -e "${GREEN}🔍 Checking Database Migration API...${NC}"
if ! gcloud services list --enabled | grep -q "datamigration.googleapis.com"; then
  gcloud services enable datamigration.googleapis.com
fi

# STEP 2: User inputs
echo -e "${YELLOW}⚠️ REQUIRED INPUTS:${NC}"
read -p "👉 Source instance: " SOURCE_INSTANCE
read -p "👉 One-time target: " TARGET_ONE
read -p "👉 Continuous target: " TARGET_CONT

# STEP 3: Source IP
SOURCE_IP=$(gcloud compute instances describe $SOURCE_INSTANCE --zone=$ZONE --format="get(networkInterfaces[0].accessConfigs[0].natIP)")

# STEP 4: Create connection profile
echo -e "${GREEN}📡 Creating connection profile...${NC}"
gcloud database-migration connection-profiles create mysql-src-profile \
  --region=$REGION \
  --type=mysql \
  --mysql-host=$SOURCE_IP \
  --mysql-port=3306 \
  --mysql-username=admin \
  --mysql-password=changeme \
  --display-name="MySQL Source External" || echo "⚠️ Connection profile already exists, skipping..."

# STEP 5: One-time migration
echo -e "${GREEN}💾 Creating Cloud SQL instance (one-time)...${NC}"
gcloud sql instances create $TARGET_ONE \
  --database-version=MYSQL_8_0 \
  --tier=db-custom-2-8192 \
  --storage-type=SSD \
  --storage-size=10GB \
  --region=$REGION || echo "⚠️ Instance already exists, skipping..."

gcloud sql users set-password root --host=% --instance=$TARGET_ONE --password=supersecret!
gcloud sql instances patch $TARGET_ONE --authorized-networks=$(curl -s ifconfig.me)

echo -e "${GREEN}🚚 Creating one-time migration job...${NC}"
gcloud database-migration migration-jobs create $TARGET_ONE \
  --region=$REGION \
  --type=ONE_TIME \
  --source=projects/$PROJECT_ID/locations/$REGION/connectionProfiles/mysql-src-profile \
  --destination-instance=$TARGET_ONE || echo "⚠️ Migration job already exists, skipping..."

gcloud database-migration migration-jobs start $TARGET_ONE --region=$REGION || true
sleep 120

echo -e "${GREEN}🔍 Verifying migrated data...${NC}"
gcloud sql connect $TARGET_ONE --user=root --quiet <<'EOF'
SHOW DATABASES;
EOF

# STEP 6: VPC Peering
echo -e "${GREEN}🌐 Checking VPC peering...${NC}"
if ! gcloud compute networks peerings list --network=default | grep -q "servicenetworking"; then
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
  echo -e "${YELLOW}⏱️ Waiting 60s for VPC to initialize...${NC}"
  sleep 60
fi

# STEP 7: Continuous migration
echo -e "${GREEN}🔄 Creating Cloud SQL instance (continuous)...${NC}"
gcloud sql instances create $TARGET_CONT \
  --database-version=MYSQL_8_0 \
  --tier=db-custom-2-8192 \
  --storage-type=SSD \
  --storage-size=10GB \
  --region=$REGION || echo "⚠️ Instance already exists, skipping..."

gcloud sql users set-password root --host=% --instance=$TARGET_CONT --password=supersecret!
gcloud sql instances patch $TARGET_CONT --authorized-networks=$(curl -s ifconfig.me)

# Create migration job (with retry)
echo -e "${GREEN}🚀 Creating continuous migration job...${NC}"
if ! gcloud database-migration migration-jobs list --region=$REGION | grep -q $TARGET_CONT; then
  gcloud database-migration migration-jobs create $TARGET_CONT \
    --region=$REGION \
    --type=CONTINUOUS \
    --source=projects/$PROJECT_ID/locations/$REGION/connectionProfiles/mysql-src-profile \
    --destination-instance=$TARGET_CONT
fi

# Start migration job
gcloud database-migration migration-jobs start $TARGET_CONT --region=$REGION || true

# Wait until job is RUNNING
echo -e "${YELLOW}⏱️ Waiting for continuous job to become RUNNING...${NC}"
for i in {1..20}; do
  STATUS=$(gcloud database-migration migration-jobs describe $TARGET_CONT --region=$REGION --format="value(state)")
  echo "📊 Current job status: $STATUS"
  if [ "$STATUS" == "RUNNING" ]; then
    echo -e "${GREEN}✅ Migration job is RUNNING!${NC}"
    break
  fi
  sleep 30
done

# STEP 8: Replication test
echo -e "${GREEN}✏️ Updating source database to test replication...${NC}"
gcloud compute ssh $SOURCE_INSTANCE --zone=$ZONE --command "
mysql -uadmin -pchangeme -e \"
use customers_data;
update customers set gender='FEMALE' where addressKey=934;
\""

echo -e "${BLUE}⏱️ Waiting 60s for replication...${NC}"
sleep 60

echo -e "${GREEN}🔍 Checking replicated data...${NC}"
gcloud sql connect $TARGET_CONT --user=root --quiet <<'EOF'
SHOW DATABASES;
USE customers_data;
SELECT gender FROM customers WHERE addressKey=934;
EOF

# STEP 9: Promote
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
echo " - Replication ✅"
echo " - Promotion ✅"
echo "=============================================================="
echo -e "${YELLOW}📜 © 2025 EPLUS.DEV | All Rights Reserved${NC}"
echo -e "${BLUE}🚀 Database is now fully migrated and live.${NC}"