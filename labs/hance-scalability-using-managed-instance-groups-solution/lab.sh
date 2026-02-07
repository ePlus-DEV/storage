#!/bin/bash
# ==========================================================
# © Copyright ePlus.DEV
# Enhance Scalability using Managed Instance Groups
# ==========================================================

# ------------------ COLORS ------------------
BLACK=$(tput setaf 0)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)

BOLD=$(tput bold)
RESET=$(tput sgr0)
# --------------------------------------------

echo "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo "${CYAN}${BOLD}© Copyright ePlus.DEV${RESET}"
echo "${MAGENTA}${BOLD}Enhance Scalability using Managed Instance Groups${RESET}"
echo "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

# ------------------ CONFIG ------------------
MIG_NAME="dev-instance-group"
TEMPLATE_NAME="dev-instance-template"
BASE_NAME="dev-instance"

MIN_REPLICAS=1
MAX_REPLICAS=3
CPU_TARGET=0.60
# --------------------------------------------

echo "${BLUE}▶ Detecting REGION...${RESET}"
REGION="$(gcloud config get-value compute/region 2>/dev/null | tr -d '\r')"

if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  REGION="$(gcloud compute regions list --limit=1 --format="value(name)")"
  echo "${YELLOW}⚠ Region not set, auto-selected: ${REGION}${RESET}"
else
  echo "${GREEN}✔ Using REGION: ${REGION}${RESET}"
fi

# ------------------ VALIDATE TEMPLATE ------------------
echo "${BLUE}▶ Checking instance template...${RESET}"
if ! gcloud compute instance-templates describe "$TEMPLATE_NAME" >/dev/null 2>&1; then
  echo "${RED}✖ Instance template '$TEMPLATE_NAME' not found${RESET}"
  exit 1
fi
echo "${GREEN}✔ Instance template found${RESET}"

# ------------------ CREATE MIG ------------------
echo "${BLUE}▶ Creating Managed Instance Group...${RESET}"
gcloud compute instance-groups managed create "$MIG_NAME" \
  --template="$TEMPLATE_NAME" \
  --base-instance-name="$BASE_NAME" \
  --size="$MIN_REPLICAS" \
  --region="$REGION" \
  >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  echo "${GREEN}✔ MIG '$MIG_NAME' created successfully${RESET}"
else
  echo "${YELLOW}⚠ MIG may already exist, continuing...${RESET}"
fi

# ------------------ AUTOSCALING ------------------
echo "${BLUE}▶ Configuring autoscaling...${RESET}"
gcloud compute instance-groups managed set-autoscaling "$MIG_NAME" \
  --region="$REGION" \
  --min-num-replicas="$MIN_REPLICAS" \
  --max-num-replicas="$MAX_REPLICAS" \
  --target-cpu-utilization="$CPU_TARGET" \
  >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
  echo "${GREEN}✔ Autoscaling enabled (CPU ${CPU_TARGET} | ${MIN_REPLICAS}-${MAX_REPLICAS})${RESET}"
else
  echo "${RED}✖ Failed to configure autoscaling${RESET}"
  exit 1
fi

# ------------------ VERIFY ------------------
echo "${BLUE}▶ Verifying configuration...${RESET}"
gcloud compute instance-groups managed describe "$MIG_NAME" \
  --region="$REGION" \
  --format="value(name,autoscaler.autoscalingPolicy.cpuUtilization.utilizationTarget)" \
  2>/dev/null

echo
echo "${MAGENTA}${BOLD}🎉 DONE! Lab objective completed.${RESET}"
echo "${CYAN}${BOLD}✔ Managed Instance Group: ${MIG_NAME}${RESET}"
echo "${CYAN}${BOLD}✔ Autoscaling: ENABLED${RESET}"
echo "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo "${CYAN}${BOLD}© ePlus.DEV${RESET}"
