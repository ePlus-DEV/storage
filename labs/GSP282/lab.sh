#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Colors
# ============================================================
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[1;34m'
CYAN=$'\033[0;36m'
MAGENTA=$'\033[0;35m'
WHITE=$'\033[1;37m'
NC=$'\033[0m'
BOLD=$'\033[1m'

clear

# ============================================================
# ePlus.DEV Banner
# ============================================================
echo "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           GOOGLE CLOUD INTRODUCTORY LAB                     ║"
echo "║                    Copyright © ePlus.DEV                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo "${NC}"

# ============================================================
# Detect project automatically
# ============================================================
PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  echo "${RED}✖ Unable to detect the Google Cloud project.${NC}"
  exit 1
fi

echo "${BLUE}Project ID:${NC} ${WHITE}${PROJECT_ID}${NC}"
echo

# ============================================================
# Get the Viewer account
# ============================================================
echo "${YELLOW}Copy the student account specified in Task 3.${NC}"
read -rp "Enter the student account: " VIEWER_ACCOUNT

VIEWER_ACCOUNT="${VIEWER_ACCOUNT//[[:space:]]/}"

if [[ ! "$VIEWER_ACCOUNT" =~ ^student-[A-Za-z0-9_-]+@qwiklabs\.net$ ]]; then
  echo
  echo "${RED}✖ Invalid Qwiklabs account:${NC} ${VIEWER_ACCOUNT}"
  echo "${YELLOW}Example: student-04-c247bdf3f89c@qwiklabs.net${NC}"
  exit 1
fi

echo
echo "${MAGENTA}──────────────────────────────────────────────────────────────${NC}"
echo "${CYAN}${BOLD}TASK 3: GRANT AN IAM ROLE${NC}"
echo "${MAGENTA}──────────────────────────────────────────────────────────────${NC}"

echo "${YELLOW}▶ Granting the Viewer role to:${NC} ${VIEWER_ACCOUNT}"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="user:${VIEWER_ACCOUNT}" \
  --role="roles/viewer" \
  --quiet

echo "${GREEN}✔ Viewer role granted successfully.${NC}"

echo
echo "${MAGENTA}──────────────────────────────────────────────────────────────${NC}"
echo "${CYAN}${BOLD}TASK 4: ENABLE DIALOGFLOW API${NC}"
echo "${MAGENTA}──────────────────────────────────────────────────────────────${NC}"

echo "${YELLOW}▶ Enabling Dialogflow API...${NC}"

gcloud services enable dialogflow.googleapis.com \
  --project="$PROJECT_ID"

echo "${GREEN}✔ Dialogflow API enabled successfully.${NC}"

# ============================================================
# Result
# ============================================================
echo
echo "${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                  ALL TRACKED TASKS COMPLETED                ║"
echo "║                    Copyright © ePlus.DEV                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo "${NC}"

echo "${WHITE}Return to the lab page and click:${NC}"
echo "${GREEN}1. Check my progress – Grant an IAM role${NC}"
echo "${GREEN}2. Check my progress – Enable the Dialogflow API${NC}"