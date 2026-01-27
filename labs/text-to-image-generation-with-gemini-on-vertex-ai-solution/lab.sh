#!/bin/bash
# =============================================================
# 🚀 Vertex AI Gemini Lab (clone then replace)
# © 2026 ePlus.DEV
# =============================================================

set -euo pipefail

# =======================
# 🌈 Colors
# =======================
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
BOLD="\033[1m"
RESET="\033[0m"

# =======================
# 📄 File source
# =======================
RAW_URL="https://raw.githubusercontent.com/ePlus-DEV/storage/main/labs/text-to-image-generation-with-gemini-on-vertex-ai-solution/main.py"
TARGET_FILE="main.py"

echo -e "${CYAN}${BOLD}▶ Fetching main.py from repository...${RESET}"

# =======================
# ⬇️ Clone (download) main.py
# =======================
curl -fsSL "${RAW_URL}?nocache=$(date +%s)" -o "${TARGET_FILE}"
echo -e "${GREEN}✔ main.py downloaded${RESET}"

# =======================
# 🔧 Project & Region
# =======================
PROJECT_ID=$(gcloud config get-value project 2>/dev/null || true)
if [[ -z "$PROJECT_ID" ]]; then
  echo -e "${RED}❌ PROJECT_ID not set. Run: gcloud config set project <PROJECT_ID>${RESET}"
  exit 1
fi

REGION=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)
REGION="${REGION:-us-central1}"

echo -e "${GREEN}✔ Project : ${PROJECT_ID}${RESET}"
echo -e "${GREEN}✔ Region  : ${REGION}${RESET}"

# =======================
# 🔌 Enable Vertex AI
# =======================
echo -e "${CYAN}▶ Enabling Vertex AI API...${RESET}"
gcloud services enable aiplatform.googleapis.com >/dev/null

# =======================
# 📦 Install SDK
# =======================
echo -e "${CYAN}▶ Installing google-cloud-aiplatform...${RESET}"
pip3 install --user --upgrade google-cloud-aiplatform