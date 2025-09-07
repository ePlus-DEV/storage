#!/bin/bash

# Màu sắc
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RESET=$(tput sgr0)
BOLD=$(tput bold)

echo "${YELLOW}${BOLD}=== GCP Machine Image Creator ===${RESET}"

# Nhập thông tin
read -p "Enter ${BOLD}Machine Image Name${RESET}: " MACHINE_IMAGE
read -p "Enter ${BOLD}VM Name${RESET}: " VM_NAME
read -p "Enter ${BOLD}Zone${RESET}: " ZONE

echo "${YELLOW}>> Creating Machine Image: ${GREEN}$MACHINE_IMAGE${RESET}"
echo "${YELLOW}   From VM: ${GREEN}$VM_NAME${RESET}"
echo "${YELLOW}   In Zone: ${GREEN}$ZONE${RESET}"

# Chạy lệnh gcloud
if gcloud compute machine-images create "$MACHINE_IMAGE" \
  --source-instance="$VM_NAME" \
  --source-instance-zone="$ZONE"; then
  echo "${GREEN}${BOLD}✔ Machine Image created successfully!${RESET}"
else
  echo "${RED}${BOLD}✘ Failed to create Machine Image.${RESET}"
fi