#!/bin/bash
# ==========================================================
# © Copyright ePlus.DEV
# Enhance Scalability using Managed Instance Groups
# ==========================================================

# ------------------ COLORS ------------------
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
BOLD=$(tput bold)
RESET=$(tput sgr0)
# --------------------------------------------

clear
echo "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo "${CYAN}${BOLD}© Copyright ePlus.DEV${RESET}"
echo "${MAGENTA}${BOLD}Enhance Scalability using Managed Instance Groups${RESET}"
echo "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo

# ------------------ CONFIG ------------------
MIG_NAME="dev-instance-group"
TEMPLATE_NAME="dev-instance-template"
MIN_REPLICAS=1
MAX_REPLICAS=3
CPU_TARGET=0.60
# --------------------------------------------

# ------------------ REGION DETECT ------------------
echo "${BLUE}▶ Detecting REGION from gcloud config...${RESET}"
REGION="$(gcloud config get-value compute/region 2>/dev/null | tr -d '\r')"

if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  echo "${YELLOW}⚠ REGION not found in config.${RESET}"
  echo "${CYAN}Please enter REGION manually (example: us-central1):${RESET}"
  read -rp "REGION = " REGION
fi

if [[ -z "$REGION" ]]; then
  echo "${RED}${BOLD}✖ REGION is required. Script stopped.${RESET}"
  exit 1
fi

echo "${GREEN}✔ Using REGION: ${REGION}${RESET}"
echo

# ------------------ VALIDATE TEMPLATE ------------------
echo "${BLUE}▶ Checking instance template...${RESET}"
if ! gcloud compute instance-templates describe "$TEMPLATE_NAME" >/dev/null 2>&1; then
  echo "${RED}${BOLD}✖ Instance template '$TEMPLATE_NAME' not found.${RESET}"
  exit 1
fi
echo "${GREEN}✔ Instance template exists.${RESET}"
echo

# ------------------ CREATE MIG ------------------
echo "${BLUE}▶ Creating Managed Instance Group...${RESET}"
if gcloud compute instance-groups managed create "$MIG_NAME" \
    --template="$TEMPLATE_NAME" \
    --size="$MIN_REPLICAS" \
    --region="$REGION" \
    >/dev/null 2>&1; then
  echo "${GREEN}✔ Managed Instance Group created.${RESET}"
else
  echo "${YELLOW}⚠ Managed Instance Group may already exist. Continue...${RESET}"
fi
echo

# ------------------ AUTOSCALING ------------------
echo "${BLUE}▶ Configuring autoscaling...${RESET}"
gcloud compute instance-groups managed set-autoscaling "$MIG_NAME" \
  --region="$REGION" \
  --min-num-replicas="$MIN_REPLICAS" \
  --max-num-replicas="$MAX_REPLICAS" \
  --target-cpu-utilization="$CPU_TARGET" \
  --mode=on \
  >/dev/null 2>&1

if [[ $? -ne 0 ]]; then
  echo "${RED}${BOLD}✖ Failed to configure autoscaling.${RESET}"
  exit 1
fi

echo "${GREEN}✔ Autoscaling enabled (CPU ${CPU_TARGET}, ${MIN_REPLICAS}-${MAX_REPLICAS}).${RESET}"
echo

# ------------------ DONE ------------------
echo "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo "${GREEN}${BOLD}🎉 DONE! Lab requirement completed successfully.${RESET}"
echo "${CYAN}${BOLD}✔ dev-instance-group${RESET}"
echo "${CYAN}${BOLD}✔ Autoscaling: ON${RESET}"
echo "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo "${CYAN}${BOLD}© ePlus.DEV${RESET}"