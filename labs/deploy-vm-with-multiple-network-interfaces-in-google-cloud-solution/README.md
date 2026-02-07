# !/bin/bash

# ==========================================================

# © Copyright ePlus.DEV

# Create Multi-NIC VM on Google Cloud

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
echo -e "${WHITE}${BOLD}Deploy VM with Multiple Network Interfaces in Google Cloud
${RESET}"
echo -e "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo

# ========== CONFIG ==========

VM_NAME="multi-nic-vm"
MACHINE_TYPE="e2-medium"

NETWORK1="my-vpc1"
SUBNET1="subnet-a"

NETWORK2="my-vpc2"
SUBNET2="subnet-b"

# ============================

# ---------- ZONE ----------

echo -e "${BLUE}${BOLD}▶ Detecting ZONE from gcloud config...${RESET}"
ZONE="$(gcloud config get-value compute/zone 2>/dev/null | tr -d '\r')"

if [[ -z "$ZONE" || "$ZONE" == "(unset)" ]]; then
  echo -e "${YELLOW}${BOLD}⚠ ZONE not found in config.${RESET}"
  echo -ne "${CYAN}${BOLD}Enter ZONE (example: us-central1-a): ${RESET}"
  read ZONE
fi

if [[ -z "$ZONE" ]]; then
  echo -e "${RED}${BOLD}✖ ZONE is required. Exit.${RESET}"
  exit 1
fi

echo -e "${GREEN}${BOLD}✔ Using ZONE: ${ZONE}${RESET}"
echo

# ---------- CREATE VM ----------

echo -e "${BLUE}${BOLD}▶ Creating VM with multiple network interfaces...${RESET}"

if gcloud compute instances create "$VM_NAME" \
  --zone="$ZONE" \
  --machine-type="$MACHINE_TYPE" \
  --network-interface=network="$NETWORK1",subnet="$SUBNET1" \
  --network-interface=network="$NETWORK2",subnet="$SUBNET2" \
  >/dev/null 2>&1; then

  echo -e "${GREEN}${BOLD}✔ VM '${VM_NAME}' created successfully.${RESET}"
else
  echo -e "${YELLOW}${BOLD}⚠ VM '${VM_NAME}' may already exist. Skipped.${RESET}"
fi

echo
echo -e "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}${BOLD}✔ Task completed${RESET}"
echo -e "${CYAN}${BOLD}✔ VM Name       : ${VM_NAME}${RESET}"
echo -e "${CYAN}${BOLD}✔ Machine Type  : ${MACHINE_TYPE}${RESET}"
echo -e "${CYAN}${BOLD}✔ Networks      : ${NETWORK1}, ${NETWORK2}${RESET}"
echo -e "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${WHITE}${BOLD}© ePlus.DEV${RESET}"