#!/bin/bash
# =============================================================
# 🚀 AlloyDB for PostgreSQL - Fundamental Lab (Qwiklabs)
# 🧑‍💻 Script by ePlus.DEV
# =============================================================

set -euo pipefail

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
echo "📦 Create Cluster + Instance + List + Delete (with confirm)"
echo "© 2026 ePlus.DEV"
echo "============================================================="
echo -e "${RESET}"

# =======================
# 🔧 Variables
# =======================
PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
NETWORK="peering-network"

CLUSTER_NAME="gcloud-lab-cluster"
INSTANCE_NAME="gcloud-lab-instance"
DB_PASSWORD="Change3Me"

if [[ -z "${PROJECT_ID}" ]]; then
  echo -e "${RED}❌ Cannot detect PROJECT_ID. Are you in Cloud Shell and logged in?${RESET}"
  exit 1
fi

echo -e "${YELLOW}🔍 Project: ${BOLD}${PROJECT_ID}${RESET}"
echo -e "${YELLOW}🌍 Region : ${BOLD}${REGION}${RESET}"
echo -e "${YELLOW}🛜 Network: ${BOLD}${NETWORK}${RESET}"
echo

# =======================
# 🧱 Create AlloyDB Cluster
# =======================
echo -e "${GREEN}🧱 Creating AlloyDB Cluster: ${BOLD}${CLUSTER_NAME}${RESET}"
gcloud alloydb clusters create "${CLUSTER_NAME}" \
  --password="${DB_PASSWORD}" \
  --network="${NETWORK}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}"

echo -e "${GREEN}✅ Cluster created${RESET}"
echo

# =======================
# 🖥️ Create Primary Instance
# =======================
echo -e "${GREEN}🖥️ Creating Primary Instance: ${BOLD}${INSTANCE_NAME}${RESET}"
echo -e "${YELLOW}⏳ This may take ~7–9 minutes...${RESET}"

gcloud alloydb instances create "${INSTANCE_NAME}" \
  --instance-type=PRIMARY \
  --cpu-count=2 \
  --region="${REGION}" \
  --cluster="${CLUSTER_NAME}" \
  --project="${PROJECT_ID}"

echo -e "${GREEN}✅ Instance created${RESET}"
echo

# =======================
# 📋 List AlloyDB Clusters
# =======================
echo -e "${CYAN}📋 Listing AlloyDB clusters:${RESET}"
gcloud alloydb clusters list --project="${PROJECT_ID}"
echo

echo -e "${CYAN}📋 Listing AlloyDB instances (optional):${RESET}"
gcloud alloydb instances list --region="${REGION}" --project="${PROJECT_ID}" || true
echo

# =======================
# 🧨 Delete Cluster (Task 4)
# =======================
echo -e "${RED}=============================================================${RESET}"
echo -e "${RED}⚠️  DELETE STEP (Task 4)${RESET}"
echo -e "${YELLOW}👉 IMPORTANT: Go back to Qwiklabs and click:${RESET}"
echo -e "${YELLOW}   ✅ \"Check my progress\" for Task 3 (Create cluster and instance with CLI)${RESET}"
echo -e "${YELLOW}   Make sure it shows COMPLETED before deleting.${RESET}"
echo -e "${RED}=============================================================${RESET}"
echo

read -p "$(echo -e ${BOLD}${CYAN}Type YES to confirm deletion:${RESET} )" CONFIRM
if [[ "${CONFIRM}" != "YES" ]]; then
  echo -e "${GREEN}✅ Cancelled. Cluster is still running.${RESET}"
  exit 0
fi

echo
echo -e "${RED}🧨 Proceeding to delete cluster: ${BOLD}${CLUSTER_NAME}${RESET}"
echo -e "${YELLOW}⚠️ gcloud will ask final confirmation: Do you want to continue (Y/n)?${RESET}"
echo

gcloud alloydb clusters delete "${CLUSTER_NAME}" \
  --force \
  --region="${REGION}" \
  --project="${PROJECT_ID}"

echo
echo -e "${GREEN}✅ Cluster deleted successfully${RESET}"
echo

# =======================
# 🔍 Final verification
# =======================
echo -e "${CYAN}🔍 Remaining AlloyDB clusters:${RESET}"
gcloud alloydb clusters list --project="${PROJECT_ID}"
echo

echo -e "${BOLD}${GREEN}🎉 Done! - ePlus.DEV${RESET}"