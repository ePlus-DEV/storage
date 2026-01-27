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