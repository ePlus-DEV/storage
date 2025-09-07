#!/usr/bin/env bash
set -euo pipefail

# =====================================================================
# Google Cloud Internal TCP/UDP Load Balancer Lab Automator
# 
# Automates the setup of an Internal TCP/UDP passthrough Load Balancer.
# Author: ePlus.DEV
# Copyright (c) 2025 ePlus.DEV. All rights reserved.
# =====================================================================

# ================= Colors & helpers =================
BOLD=$(tput bold || true); RESET=$(tput sgr0 || true)
RED=$(tput setaf 1 || true); GREEN=$(tput setaf 2 || true); YELLOW=$(tput setaf 3 || true); MAGENTA=$(tput setaf 5 || true)
ok(){ echo -e "${GREEN}✔${RESET} $*"; }
warn(){ echo -e "${YELLOW}⚠${RESET} $*"; }
die(){ echo -e "${RED}✖${RESET} $*"; exit 1; }
banner(){ echo -e "\n${BOLD}${MAGENTA}==> $*${RESET}\n"; }

echo -e "${BOLD}${MAGENTA}Starting Execution - Internal ILB Lab Automator${RESET}"

# ================= Project =================
PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project -q || true)}"
[[ -z "${PROJECT_ID}" ]] && die "No PROJECT_ID found. Please set your gcloud project first."
gcloud config set project "${PROJECT_ID}" >/dev/null

# ================= Prompt user for zones =================
REGION="us-east4"
read -rp "Enter first zone in ${REGION} (e.g., us-east4-a): " ZONE_A
read -rp "Enter second zone in ${REGION} (different from first, e.g., us-east4-b): " ZONE_B

if [[ -z "${ZONE_A}" || -z "${ZONE_B}" ]]; then
  die "Both zones must be provided."
fi

# ================= Static config =================
VPC_NAME="my-internal-app"
SUBNET_A="subnet-a"
SUBNET_B="subnet-b"

FW_HTTP="app-allow-http"
FW_HC="app-allow-health-check"
TEMPLATE_1="instance-template-1"
TEMPLATE_2="instance-template-2"
MIG_1="instance-group-1"
MIG_2="instance-group-2"
UTIL_VM="utility-vm"
UTIL_VM_IP="10.10.20.50"
HC_NAME="my-ilb-health-check"
BS_NAME="my-ilb-backend"
ILB_IP_NAME="my-ilb-ip"
ILB_FR_NAME="my-ilb"
ILB_FRONTEND_IP="10.10.30.5"
STARTUP_SCRIPT_URL="gs://cloud-training/gcpnet/ilb/startup.sh"

# ==================================================
# Task 1: Firewall rules
# ==================================================
banner "Task 1: Firewall rules (HTTP + Health Check)"

gcloud compute firewall-rules create "${FW_HTTP}" \
  --network="${VPC_NAME}" \
  --direction=INGRESS \
  --action=ALLOW \
  --rules=tcp:80 \
  --source-ranges=10.10.0.0/16 \
  --target-tags=lb-backend \
  --quiet || warn "Firewall ${FW_HTTP} may already exist."

gcloud compute firewall-rules create "${FW_HC}" \
  --network="${VPC_NAME}" \
  --direction=INGRESS \
  --action=ALLOW \
  --rules=tcp \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-tags=lb-backend \
  --quiet || warn "Firewall ${FW_HC} may already exist."

# ==================================================
# Task 2: Instance Templates & MIGs
# ==================================================
banner "Task 2: Instance Templates and Managed Instance Groups"

# Template 1
gcloud compute instance-templates create "${TEMPLATE_1}" \
  --machine-type=e2-micro \
  --network="${VPC_NAME}" \
  --subnet="${SUBNET_A}" \
  --no-address \
  --tags=lb-backend \
  --metadata=startup-script-url="${STARTUP_SCRIPT_URL}" \
  --quiet || warn "Template ${TEMPLATE_1} may already exist."

# Template 2
gcloud compute instance-templates create "${TEMPLATE_2}" \
  --machine-type=e2-micro \
  --network="${VPC_NAME}" \
  --subnet="${SUBNET_B}" \
  --no-address \
  --tags=lb-backend \
  --metadata=startup-script-url="${STARTUP_SCRIPT_URL}" \
  --quiet || warn "Template ${TEMPLATE_2} may already exist."

# MIG 1
gcloud compute instance-groups managed create "${MIG_1}" \
  --zone="${ZONE_A}" \
  --template="${TEMPLATE_1}" \
  --size=1 \
  --quiet || warn "MIG ${MIG_1} may already exist."
gcloud compute instance-groups managed set-autoscaling "${MIG_1}" \
  --zone="${ZONE_A}" \
  --min-num-replicas=1 \
  --max-num-replicas=1 \
  --target-cpu-utilization=0.8 \
  --cool-down-period=45

# MIG 2
gcloud compute instance-groups managed create "${MIG_2}" \
  --zone="${ZONE_B}" \
  --template="${TEMPLATE_2}" \
  --size=1 \
  --quiet || warn "MIG ${MIG_2} may already exist."
gcloud compute instance-groups managed set-autoscaling "${MIG_2}" \
  --zone="${ZONE_B}" \
  --min-num-replicas=1 \
  --max-num-replicas=1 \
  --target-cpu-utilization=0.8 \
  --cool-down-period=45

# Utility VM
gcloud compute instances create "${UTIL_VM}" \
  --zone="${ZONE_A}" \
  --machine-type=e2-micro \
  --subnet="${SUBNET_A}" \
  --no-address \
  --private-network-ip="${UTIL_VM_IP}" \
  --quiet || warn "Utility VM ${UTIL_VM} may already exist."

# ==================================================
# Task 3: Internal Load Balancer
# ==================================================
banner "Task 3: Internal TCP/UDP Passthrough Load Balancer"

gcloud compute health-checks create tcp "${HC_NAME}" --port=80 \
  --quiet || warn "Health check ${HC_NAME} may already exist."

gcloud compute backend-services create "${BS_NAME}" \
  --region="${REGION}" \
  --load-balancing-scheme=INTERNAL \
  --protocol=TCP \
  --health-checks="${HC_NAME}" \
  --quiet || warn "Backend service ${BS_NAME} may already exist."

gcloud compute backend-services add-backend "${BS_NAME}" \
  --region="${REGION}" \
  --instance-group="${MIG_1}" \
  --instance-group-zone="${ZONE_A}" --quiet || true

gcloud compute backend-services add-backend "${BS_NAME}" \
  --region="${REGION}" \
  --instance-group="${MIG_2}" \
  --instance-group-zone="${ZONE_B}" --quiet || true

gcloud compute addresses create "${ILB_IP_NAME}" \
  --region="${REGION}" \
  --subnet="${SUBNET_B}" \
  --addresses="${ILB_FRONTEND_IP}" \
  --quiet || warn "ILB IP ${ILB_IP_NAME} may already exist."

gcloud compute forwarding-rules create "${ILB_FR_NAME}" \
  --region="${REGION}" \
  --load-balancing-scheme=INTERNAL \
  --network="${VPC_NAME}" \
  --subnet="${SUBNET_B}" \
  --address="${ILB_IP_NAME}" \
  --backend-service="${BS_NAME}" \
  --ports=80 \
  --quiet || warn "Forwarding rule ${ILB_FR_NAME} may already exist."

# ==================================================
# Task 4: Verification
# ==================================================
banner "Task 4: Verification / Testing"

echo "Waiting 30s for health checks to stabilize..."
sleep 30

SSH_BASE=(gcloud compute ssh "${UTIL_VM}" --zone="${ZONE_A}" --quiet --command)

banner "Curl Internal Load Balancer (${ILB_FRONTEND_IP})"
for i in {1..4}; do
  echo -e "${YELLOW}Request #$i${RESET}"
  "${SSH_BASE[@]}" "curl -s ${ILB_FRONTEND_IP} | head -n 10"
  echo
done

ok "All done! The field identifying backend location in quiz answers is: Server Location"