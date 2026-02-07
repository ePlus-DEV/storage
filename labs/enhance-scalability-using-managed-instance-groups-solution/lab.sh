#!/bin/bash
# ==========================================================
# © Copyright ePlus.DEV
# Enhance Scalability using Managed Instance Groups
# ==========================================================

# ========== COLORS ==========
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
RESET='\033[0m'
BOLD='\033[1m'
# ============================

clear
echo -e "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${CYAN}${BOLD}© Copyright ePlus.DEV${RESET}"
echo -e "${WHITE}${BOLD}Enhance Scalability using Managed Instance Groups${RESET}"
echo -e "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo

# ========== CONFIG ==========
MIG_NAME="dev-instance-group"
TEMPLATE_NAME="dev-instance-template"
MIN_REPLICAS=1
MAX_REPLICAS=3
CPU_TARGET=0.60
# ============================

# ---------- REGION ----------
echo -e "${BLUE}${BOLD}▶ Detecting REGION from gcloud config...${RESET}"
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  echo -e "${YELLOW}${BOLD}⚠ REGION not found in config.${RESET}"
  echo -ne "${CYAN}${BOLD}Enter REGION (example: us-central1): ${RESET}"
  read REGION
fi

if [[ -z "$REGION" ]]; then
  echo -e "${RED}${BOLD}✖ REGION is required. Exit.${RESET}"
  exit 1
fi

echo -e "${GREEN}${BOLD}✔ Using REGION: ${REGION}${RESET}"
echo

# ---------- TEMPLATE CHECK ----------
echo -e "${BLUE}${BOLD}▶ Checking instance template...${RESET}"
if ! gcloud compute instance-templates describe "$TEMPLATE_NAME" >/dev/null 2>&1; then
  echo -e "${RED}${BOLD}✖ Instance template '${TEMPLATE_NAME}' not found.${RESET}"
  exit 1
fi
echo -e "${GREEN}${BOLD}✔ Instance template exists.${RESET}"
echo

# ---------- CREATE MIG ----------
echo -e "${BLUE}${BOLD}▶ Creating Managed Instance Group...${RESET}"
if gcloud compute instance-groups managed create "$MIG_NAME" \
    --template="$TEMPLATE_NAME" \
    --size="$MIN_REPLICAS" \
    --region="$REGION" \
    >/dev/null 2>&1; then
  echo -e "${GREEN}${BOLD}✔ Managed Instance Group created.${RESET}"
else
  echo -e "${YELLOW}${BOLD}⚠ Managed Instance Group already exists. Continue.${RESET}"
fi
echo

# ---------- AUTOSCALING ----------
echo -e "${BLUE}${BOLD}▶ Configuring autoscaling...${RESET}"
if gcloud compute instance-groups managed set-autoscaling "$MIG_NAME" \
    --region="$REGION" \
    --min-num-replicas="$MIN_REPLICAS" \
    --max-num-replicas="$MAX_REPLICAS" \
    --target-cpu-utilization="$CPU_TARGET" \
    --mode=on \
    >/dev/null 2>&1; then
  echo -e "${GREEN}${BOLD}✔ Autoscaling enabled (CPU ${CPU_TARGET}, ${MIN_REPLICAS}-${MAX_REPLICAS}).${RESET}"
else
  echo -e "${RED}${BOLD}✖ Failed to configure autoscaling.${RESET}"
  exit 1
fi
echo

# ---------- DONE ----------
echo -e "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}${BOLD}✔ Lab requirement completed successfully${RESET}"
echo -e "${CYAN}${BOLD}✔ Managed Instance Group : ${MIG_NAME}${RESET}"
echo -e "${CYAN}${BOLD}✔ Autoscaling            : ON${RESET}"
echo -e "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${WHITE}${BOLD}© ePlus.DEV${RESET}"
