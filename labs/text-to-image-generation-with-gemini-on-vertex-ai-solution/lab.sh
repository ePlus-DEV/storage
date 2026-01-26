#!/bin/bash
# =============================================================
# 🚀 Lab Bootstrap - Fetch & Run main.py
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
# 📄 File config
# =======================
RAW_URL="https://raw.githubusercontent.com/ePlus-DEV/storage/main/labs/text-to-image-generation-with-gemini-on-vertex-ai-solution/main.py"
TARGET_FILE="main.py"

echo -e "${CYAN}${BOLD}▶ Fetching main.py from repository...${RESET}"

# =======================
# ⬇️ Download main.py (no cache)
# =======================
curl -fsSL "${RAW_URL}?nocache=$(date +%s)" -o "${TARGET_FILE}"

echo -e "${GREEN}✔ main.py downloaded successfully${RESET}"

# =======================
# 🔍 Check python
# =======================
if ! command -v python3 >/dev/null 2>&1; then
  echo -e "${RED}❌ python3 not found${RESET}"
  exit 1
fi

# =======================
# ▶ Run main.py
# =======================
echo -e "${CYAN}▶ Running main.py...${RESET}"
python3 "${TARGET_FILE}"

echo -e "${GREEN}${BOLD}🎉 Done!${RESET}"