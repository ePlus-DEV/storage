#!/usr/bin/env bash
set -euo pipefail

export CLOUDSDK_CORE_DISABLE_PROMPTS=1

# =========================
# Colors / Branding
# =========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

line() {
  echo -e "${CYAN}${BOLD}============================================================${NC}"
}

ok() {
  echo -e "${GREEN}✔ $1${NC}"
}

warn() {
  echo -e "${YELLOW}➜ $1${NC}"
}

err() {
  echo -e "${RED}✘ $1${NC}"
}

info() {
  echo -e "${BLUE}• $1${NC}"
}

# =========================
# Header
# =========================
clear || true
line
echo -e "${MAGENTA}${BOLD}        Vertex AI Workbench ASR Lab Creator${NC}"
echo -e "${CYAN}${BOLD}             Powered by ePlus DEV${NC}"
echo -e "${YELLOW}             Color branding by ePlus.DEV${NC}"
line

# =========================
# Variables
# =========================
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
DEFAULT_ZONE="$(gcloud compute project-info describe --format='value(commonInstanceMetadata.items[google-compute-default-zone])' 2>/dev/null || true)"
ZONE="${ZONE:-${DEFAULT_ZONE:-us-east4-c}}"
REGION="${ZONE%-*}"
INSTANCE_NAME="lab-workbench"
MACHINE_TYPE="e2-standard-4"

if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  err "PROJECT_ID was not found."
  echo -e "${YELLOW}Please run:${NC} gcloud config set project YOUR_PROJECT_ID"
  exit 1
fi

ok "PROJECT_ID: ${PROJECT_ID}"
ok "ZONE      : ${ZONE}"
ok "REGION    : ${REGION}"
ok "INSTANCE  : ${INSTANCE_NAME}"

# =========================
# Enable APIs
# =========================
warn "Enabling required APIs..."
gcloud services enable \
  notebooks.googleapis.com \
  aiplatform.googleapis.com \
  speech.googleapis.com \
  compute.googleapis.com \
  storage.googleapis.com >/dev/null

ok "Required APIs have been enabled"

# =========================
# Create instance
# =========================
warn "Checking whether the instance already exists..."
if gcloud workbench instances describe "${INSTANCE_NAME}" --project="${PROJECT_ID}" --location="${ZONE}" >/dev/null 2>&1; then
  info "Instance ${INSTANCE_NAME} already exists. Skipping creation."
else
  warn "Creating Vertex AI Workbench instance..."
  gcloud workbench instances create "${INSTANCE_NAME}" \
    --project="${PROJECT_ID}" \
    --location="${ZONE}" \
    --vm-image-project="cloud-notebooks-managed" \
    --vm-image-family="workbench-instances" \
    --machine-type="${MACHINE_TYPE}" \
    --metadata=idle-timeout-seconds=10800
  ok "Instance creation command submitted"
fi

# =========================
# Show state
# =========================
warn "Checking instance status..."
STATE="$(gcloud workbench instances describe "${INSTANCE_NAME}" \
  --project="${PROJECT_ID}" \
  --location="${ZONE}" \
  --format='value(state)' 2>/dev/null || true)"

if [[ -n "${STATE}" ]]; then
  ok "STATE: ${STATE}"
else
  warn "Could not retrieve the instance state yet."
fi

# =========================
# Links / Next steps
# =========================
CONSOLE_URL="https://console.cloud.google.com/vertex-ai/workbench/instances?project=${PROJECT_ID}"

echo
line
echo -e "${GREEN}${BOLD}DONE. OPEN THE FOLLOWING PAGE TO CONTINUE:${NC}"
echo -e "${CYAN}${BOLD}${CONSOLE_URL}${NC}"
line
echo -e "${YELLOW}${BOLD}After the instance becomes ACTIVE:${NC}"
echo -e "${BLUE}1.${NC} Click ${BOLD}Open JupyterLab${NC}"
echo -e "${BLUE}2.${NC} Open ${BOLD}Terminal${NC} inside JupyterLab"

echo
echo -e "${MAGENTA}${BOLD}ePlus DEV - Script completed${NC}"