#!/bin/bash
# ============================================================
#  Cloud Filestore Basic Lab Automation (Qwiklabs)
#  Copyright (c) ePlus.DEV
#  License: For lab/learning use.
# ============================================================
set -euo pipefail

# ========================= COLORS =========================
ROYAL_BLUE=$'\033[38;5;27m'
NEON_GREEN=$'\033[38;5;46m'
ORANGE=$'\033[38;5;208m'
YELLOW=$'\033[38;5;226m'
RED=$'\033[38;5;196m'
WHITE=$'\033[1;97m'
BOLD=$'\033[1m'
RESET=$'\033[0m'
DIM=$'\033[38;5;244m'

# ========================= UI HELPERS =========================
line() { echo "${ROYAL_BLUE}${BOLD}============================================================${RESET}"; }
info() { echo "${ROYAL_BLUE}${BOLD}[INFO]${RESET} $*"; }
ok()   { echo "${NEON_GREEN}${BOLD}[OK]${RESET}   $*"; }
warn() { echo "${YELLOW}${BOLD}[WARN]${RESET} $*"; }
err()  { echo "${RED}${BOLD}[ERR]${RESET}  $*" >&2; }
die()  { err "$*"; exit 1; }

spinner() {
  local pid=$!
  local delay=0.1
  local spinstr='|/-\'
  while ps -p "$pid" >/dev/null 2>&1; do
    local temp=${spinstr#?}
    printf " ${ORANGE}[%c]${RESET}  " "$spinstr"
    spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\b\b\b\b\b\b"
  done
  printf "      \b\b\b\b\b\b"
}
run_bg() { ( "$@" ) >/tmp/epl_filestore_lab.log 2>&1 & spinner; }

# ========================= COPYRIGHT BANNER =========================
clear
echo -e "${ROYAL_BLUE}${BOLD}"
echo " ███████╗██████╗ ██╗     ██╗   ██╗███████╗"
echo " ██╔════╝██╔══██╗██║     ██║   ██║██╔════╝"
echo " █████╗  ██████╔╝██║     ██║   ██║███████╗"
echo " ██╔══╝  ██╔═══╝ ██║     ██║   ██║╚════██║"
echo " ███████╗██║     ███████╗╚██████╔╝███████║"
echo " ╚══════╝╚═╝     ╚══════╝ ╚═════╝ ╚══════╝"
echo -e "${RESET}"
echo -e "${NEON_GREEN}${BOLD}  ePlus.DEV Cloud Automation Script${RESET}"
echo -e "${ORANGE}  Cloud Filestore Lab – Qwiklabs${RESET}"
echo -e "${WHITE}${BOLD}  © $(date +%Y) ePlus.DEV – All rights reserved.${RESET}"
echo -e "${DIM}  For education & lab automation only.${RESET}"
line

# ========================= VARS =========================
VM_NAME="nfs-client"
FS_NAME="nfs-server"
NETWORK="default"
SHARE_NAME="vol1"
MOUNT_DIR="/mnt/test"
FILE_NAME="testfile"
FILE_CONTENT="This is a test"

# ========================= PRECHECK =========================
command -v gcloud >/dev/null 2>&1 || die "gcloud not found. Run in Cloud Shell."
PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
[[ -n "${PROJECT_ID}" ]] || die "No active project. Run: gcloud config set project <PROJECT_ID>"
ok "Project: ${PROJECT_ID}"

# ========================= AUTO REGION/ZONE =========================
# Priority:
# 1) Project metadata: google-compute-default-region / google-compute-default-zone
# 2) gcloud config: compute/region / compute/zone
# 3) If region exists but zone missing -> pick first UP zone in region
# 4) If both missing -> die

REGION="$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)"
ZONE="$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])" 2>/dev/null || true)"

if [[ -z "${REGION}" ]]; then
  REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
fi
if [[ -z "${ZONE}" ]]; then
  ZONE="$(gcloud config get-value compute/zone 2>/dev/null || true)"
fi

# If zone exists but region empty -> derive region from zone (e.g. europe-west4-b -> europe-west4)
if [[ -z "${REGION}" && -n "${ZONE}" ]]; then
  REGION="${ZONE%-*}"
fi

# If region exists but zone empty -> choose an available zone in region
if [[ -n "${REGION}" && -z "${ZONE}" ]]; then
  ZONE="$(gcloud compute zones list --filter="region:(${REGION}) AND status=UP" --format="value(name)" --limit=1 2>/dev/null || true)"
fi

[[ -n "${REGION}" && -n "${ZONE}" ]] || die "Cannot auto-detect REGION/ZONE. Set with: gcloud config set compute/region <r> && gcloud config set compute/zone <z>"

# Set config to avoid prompts later
gcloud config set compute/region "$REGION" >/dev/null
gcloud config set compute/zone "$ZONE" >/dev/null

ok "Auto Region: ${REGION}"
ok "Auto Zone  : ${ZONE}"
line

# ========================= ENABLE API =========================
info "Enabling Filestore API (if not already enabled)..."
run_bg gcloud services enable file.googleapis.com
ok "Filestore API enabled."
line

# ========================= CREATE VM =========================
if gcloud compute instances describe "$VM_NAME" --zone "$ZONE" >/dev/null 2>&1; then
  warn "VM '${VM_NAME}' already exists. Skipping create."
else
  info "Creating VM '${VM_NAME}' (e2-medium, Debian 12, allow-http)..."
  run_bg gcloud compute instances create "$VM_NAME" \
    --zone "$ZONE" \
    --machine-type "e2-medium" \
    --image-family "debian-12" \
    --image-project "debian-cloud" \
    --tags "http-server" \
    --quiet
  ok "VM created: ${VM_NAME}"
fi
line

# ========================= CREATE FILESTORE =========================
if gcloud filestore instances describe "$FS_NAME" --zone "$ZONE" >/dev/null 2>&1; then
  warn "Filestore instance '${FS_NAME}' already exists. Skipping create."
else
  info "Creating Filestore '${FS_NAME}' (BASIC_HDD, 1TB, share '${SHARE_NAME}', network '${NETWORK}')..."
  run_bg gcloud filestore instances create "$FS_NAME" \
    --zone "$ZONE" \
    --tier "BASIC_HDD" \
    --file-share "name=${SHARE_NAME},capacity=1TB" \
    --network "name=${NETWORK},connect-mode=DIRECT_PEERING" \
    --quiet
  ok "Filestore create requested: ${FS_NAME}"
fi
line

# ========================= WAIT FOR READY + GET IP =========================
info "Waiting for Filestore '${FS_NAME}' to be READY and grabbing IP..."
FS_IP=""
for i in {1..60}; do
  STATE="$(gcloud filestore instances describe "$FS_NAME" --zone "$ZONE" --format='value(state)' 2>/dev/null || true)"
  FS_IP="$(gcloud filestore instances describe "$FS_NAME" --zone "$ZONE" --format='value(networks[0].ipAddresses[0])' 2>/dev/null || true)"
  if [[ "${STATE}" == "READY" && -n "${FS_IP}" ]]; then
    ok "Filestore READY. IP: ${FS_IP}"
    break
  fi
  printf "${ORANGE}${BOLD}...${RESET} state=%s ip=%s (try %s/60)\r" "${STATE:-?}" "${FS_IP:-?}" "$i"
  sleep 10
done
echo ""
[[ -n "${FS_IP}" ]] || die "Could not get Filestore IP. Check Filestore instance status."

line

# ========================= REMOTE STEPS ON VM =========================
info "Installing NFS client + mounting share on VM + creating test file..."

REMOTE_SCRIPT=$(cat <<'EOF'
set -euo pipefail

sudo apt-get -y update
sudo apt-get -y install nfs-common

sudo mkdir -p "__MOUNT_DIR__"

if mountpoint -q "__MOUNT_DIR__"; then
  echo "[REMOTE] Already mounted: __MOUNT_DIR__"
else
  sudo mount "__FS_IP__:/__SHARE__" "__MOUNT_DIR__"
fi

sudo chmod go+rw "__MOUNT_DIR__"

echo "__CONTENT__" | sudo tee "__MOUNT_DIR__/__FILE__" >/dev/null

echo "[REMOTE] Listing share:"
ls -la "__MOUNT_DIR__"
echo "[REMOTE] File content:"
cat "__MOUNT_DIR__/__FILE__"
EOF
)

REMOTE_SCRIPT="${REMOTE_SCRIPT//__FS_IP__/${FS_IP}}"
REMOTE_SCRIPT="${REMOTE_SCRIPT//__SHARE__/${SHARE_NAME}}"
REMOTE_SCRIPT="${REMOTE_SCRIPT//__MOUNT_DIR__/${MOUNT_DIR}}"
REMOTE_SCRIPT="${REMOTE_SCRIPT//__FILE__/${FILE_NAME}}"
REMOTE_SCRIPT="${REMOTE_SCRIPT//__CONTENT__/${FILE_CONTENT}}"

run_bg gcloud compute ssh "$VM_NAME" --zone "$ZONE" --quiet --command "bash -lc $(printf '%q' "$REMOTE_SCRIPT")"

ok "Mounted ${FS_IP}:/${SHARE_NAME} at ${MOUNT_DIR} on VM '${VM_NAME}'."
ok "Created file: ${MOUNT_DIR}/${FILE_NAME}"
line

echo "${NEON_GREEN}${BOLD}DONE!${RESET} ${WHITE}Now click 'Check my progress' for tasks 1-4.${RESET}"
echo "${DIM}Log saved at: /tmp/epl_filestore_lab.log${RESET}"
line