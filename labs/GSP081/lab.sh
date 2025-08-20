#!/usr/bin/env bash
set -euo pipefail

# =========================
# ePlus.dev Cloud Run Lab
# All-in-one script
# =========================

# ----- Colors -----
BOLD="\033[1m"
RESET="\033[0m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
MAGENTA="\033[35m"
CYAN="\033[36m"

# ----- Branding header -----
echo -e "${MAGENTA}${BOLD}
┌─────────────────────────────────────────────────────────┐
│                 ePlus.dev — Cloud Run Lab               │
└─────────────────────────────────────────────────────────┘${RESET}"

# ----- Prereq checks -----
if ! command -v gcloud >/dev/null 2>&1; then
  echo -e "${RED}❌ gcloud is not installed. Please install Google Cloud SDK first.${RESET}"
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo -e "${RED}❌ curl is not installed. Please install curl first.${RESET}"
  exit 1
fi

# ----- Ask for region -----
read -rp "$(echo -e ${CYAN}${BOLD}"Enter region (example: us-east1): "${RESET})" REGION
REGION="${REGION:-us-east1}"

# ----- Config -----
SERVICE_NAME="gcfunction"
RUNTIME="nodejs20"
MAX_INSTANCES="5"

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  echo -e "${YELLOW}⚠ No project selected. Please run:${RESET}"
  echo -e "   ${BOLD}gcloud config set project <PROJECT_ID>${RESET}"
  exit 1
fi

echo -e "${BLUE}ℹ Project:${RESET} ${BOLD}${PROJECT_ID}${RESET}"
echo -e "${BLUE}ℹ Region :${RESET} ${BOLD}${REGION}${RESET}"
echo

# =========================
# Task 0: Enable APIs
# =========================
echo -e "${BOLD}🔧 Task 0: Enabling required APIs...${RESET}"
gcloud services enable \
  cloudfunctions.googleapis.com \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  eventarc.googleapis.com
echo -e "${GREEN}✅ APIs enabled.${RESET}"
echo

# =========================
# Task 1 & 2: Create + Deploy
# =========================
echo -e "${BOLD}🚀 Task 1 & 2: Creating source code and deploying Gen2 function (HTTPS)...${RESET}"

SRC_DIR="gcfunction_src"
mkdir -p "${SRC_DIR}"
cat > "${SRC_DIR}/index.js" <<'EOF'
exports.helloHttp = (req, res) => {
  const message = (req.body && req.body.message) || 'Hello World!';
  res.status(200).send({ message });
};
EOF

cat > "${SRC_DIR}/package.json" <<'EOF'
{
  "name": "gcfunction",
  "version": "1.0.0",
  "main": "index.js"
}
EOF

gcloud functions deploy "${SERVICE_NAME}" \
  --region="${REGION}" \
  --runtime="${RUNTIME}" \
  --trigger-http \
  --allow-unauthenticated \
  --gen2 \
  --max-instances="${MAX_INSTANCES}" \
  --entry-point="helloHttp" \
  --source="${SRC_DIR}"

echo -e "${GREEN}✅ Function deployed successfully.${RESET}"
echo

# =========================
# Task 3: Test function
# =========================
echo -e "${BOLD}🧪 Task 3: Testing the function...${RESET}"

FUNC_URL="$(gcloud functions describe "${SERVICE_NAME}" \
  --region="${REGION}" \
  --format="value(serviceConfig.uri)")"

if [[ -z "${FUNC_URL}" ]]; then
  echo -e "${RED}❌ Could not fetch function URL.${RESET}"
  exit 1
fi

echo -e "${BLUE}ℹ Trigger URL:${RESET} ${BOLD}${FUNC_URL}${RESET}"
echo -e "${BOLD}Sending payload: {\"message\":\"Hello World!\"}${RESET}"

HTTP_STATUS=$(curl -s -o /tmp/resp.json -w "%{http_code}" -X POST "${FUNC_URL}" \
  -H "Content-Type: application/json" \
  -d '{"message":"Hello World!"}')

echo -e "${BLUE}HTTP ${HTTP_STATUS}${RESET}"
echo -e "${GREEN}Response:${RESET} $(cat /tmp/resp.json)"
echo

# =========================
# Task 4: View logs
# =========================
echo -e "${BOLD}📜 Task 4: Viewing last 10 log entries...${RESET}"
gcloud functions logs read "${SERVICE_NAME}" --region="${REGION}" --limit=10 || true
echo

# =========================
# Task 5: Quiz (answers)
# =========================
echo -e "${BOLD}🧩 Task 5: Quiz — reference answers${RESET}"
echo -e "1) Cloud Run functions is serverless for event-driven services: ${GREEN}True${RESET}"
echo -e "2) Trigger type used in the lab: ${GREEN}HTTPS${RESET}"
echo

# ----- Footer branding -----
YEAR="$(date +%Y)"
echo -e "${MAGENTA}${BOLD}
┌─────────────────────────────────────────────────────────┐
│  © ${YEAR} ePlus.dev — All rights reserved              │
└─────────────────────────────────────────────────────────┘${RESET}"