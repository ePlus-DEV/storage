#!/bin/bash
# =============================================================
# 🚀 Lab Bootstrap (clone repo & run main.py)
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
# 📦 Repo config
# =======================
REPO_URL="https://github.com/ePlus-DEV/storage.git"
REPO_DIR="storage"
MAIN_PY="main.py"

echo -e "${CYAN}${BOLD}▶ Starting lab bootstrap...${RESET}"

# =======================
# 🔍 Check python
# =======================
if ! command -v python3 >/dev/null 2>&1; then
  echo -e "${RED}❌ python3 not found${RESET}"
  exit 1
fi

# =======================
# 📥 Clone or update repo
# =======================
if [[ -d "${REPO_DIR}/.git" ]]; then
  echo -e "${YELLOW}▶ Repo exists, pulling latest...${RESET}"
  (cd "${REPO_DIR}" && git pull)
else
  echo -e "${CYAN}▶ Cloning repository...${RESET}"
  git clone "${REPO_URL}"
fi

# =======================
# ▶ Run main.py
# =======================
if [[ ! -f "${REPO_DIR}/${MAIN_PY}" ]]; then
  echo -e "${RED}❌ main.py not found in repo${RESET}"
  exit 1
fi

echo -e "${GREEN}▶ Running main.py...${RESET}"
python3 "${REPO_DIR}/${MAIN_PY}"

echo -e "${GREEN}${BOLD}🎉 Done!${RESET}"
