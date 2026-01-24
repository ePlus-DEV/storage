#!/bin/bash
# =============================================================
# 🚀 AlloyDB for PostgreSQL - Fundamental Lab
# 🧑‍💻 Script by ePlus.DEV
# =============================================================

set -e

# =======================
# 🌈 Color definitions
# =======================
GREEN="\033[1;32m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
BOLD="\033[1m"
RESET="\033[0m"

echo -e "${CYAN}"
echo "============================================================="
echo "🚀 AlloyDB - Database Fundamentals - GSP1083"
echo "📦 Create / Manage / Delete AlloyDB using gcloud CLI"
echo "© 2025 ePlus.DEV"
echo "============================================================="
echo -e "${RESET}"

# =======================
# 🔧 Variables
# =======================
PROJECT_ID=$(gcloud config get-value project)
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
NETWORK="peering-network"

CLUSTER_NAME="gcloud-lab-cluster"
INSTANCE_NAME="gcloud-lab-instance"
DB_PASSWORD="Change3Me"

# =======================
# 📌 Check project
# =======================
echo -e "${YELLOW}🔍 Using Project: ${PROJECT_ID}${RESET}"
echo -e "${YELLOW}🔍 Using REGION: ${REGION}${RESET}"
echo

# =======================
# 🧱 Create AlloyDB Cluster
# =======================
echo -e "${GREEN}🧱 Creating AlloyDB Cluster...${RESET}"

gcloud alloydb clusters create ${CLUSTER_NAME} \
  --password=${DB_PASSWORD} \
  --network=${NETWORK} \
  --region=${REGION} \
  --project=${PROJECT_ID}

echo -e "${GREEN}✅ Cluster created${RESET}"
echo

# =======================
# 🖥️ Create Primary Instance
# =======================
echo -e "${GREEN}🖥️ Creating Primary Instance (this takes ~7–9 minutes)...${RESET}"

gcloud alloydb instances create ${INSTANCE_NAME} \
  --instance-type=PRIMARY \
  --cpu-count=2 \
  --region=${REGION} \
  --cluster=${CLUSTER_NAME} \
  --project=${PROJECT_ID}

echo -e "${GREEN}✅ Instance created${RESET}"
echo

# =======================
# 📋 List AlloyDB Clusters
# =======================
echo -e "${CYAN}📋 Listing AlloyDB clusters:${RESET}"
gcloud alloydb clusters list
echo

# =======================
# 🧨 Delete Cluster (Task 4)
# =======================
echo -e "${RED}🧨 Deleting AlloyDB cluster...${RESET}"
echo -e "${YELLOW}(This will delete all instances inside the cluster)${RESET}"

gcloud alloydb clusters delete ${CLUSTER_NAME} \
  --force \
  --region=${REGION} \
  --project=${PROJECT_ID} \
  --quiet

echo
echo -e "${GREEN}✅ Cluster deleted successfully${RESET}"
echo

# =======================
# 🔍 Final verification
# =======================
echo -e "${CYAN}🔍 Remaining AlloyDB clusters:${RESET}"
gcloud alloydb clusters list

echo
echo -e "${BOLD}${GREEN}🎉 AlloyDB lab completed successfully! - ePlus.DEV${RESET}"