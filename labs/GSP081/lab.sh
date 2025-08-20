#!/usr/bin/env bash
set -euo pipefail

# =========================
# ePlus.dev Cloud Run Lab (Functions Gen2)
# Single-run helper script
# =========================

# ----- Colors -----
BOLD="\033[1m"; RESET="\033[0m"
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"
BLUE="\033[34m"; MAGENTA="\033[35m"; CYAN="\033[36m"

echo -e "${MAGENTA}${BOLD}
┌─────────────────────────────────────────────────────────┐
│                 ePlus.dev — Cloud Run Lab               │
└─────────────────────────────────────────────────────────┘${RESET}"

# ----- Pre-flight checks -----
command -v gcloud >/dev/null || { echo -e "${RED}gcloud not found. Install Google Cloud SDK.${RESET}"; exit 1; }
command -v curl   >/dev/null || { echo -e "${RED}curl not found. Install curl.${RESET}"; exit 1; }

# ----- Ask for region (default matches screenshot) -----
read -rp "$(echo -e ${CYAN}${BOLD}"Enter region [us-central1]: ${RESET})" REGION
REGION="${REGION:-us-central1}"

# ----- Config -----
SERVICE_NAME="gcfunction"
RUNTIME="nodejs22"      # UI shows Node.js 22
MAX_INSTANCES="5"

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  echo -e "${YELLOW}No project set. Run:${RESET} ${BOLD}gcloud config set project <PROJECT_ID>${RESET}"
  exit 1
fi

echo -e "${BLUE}Project:${RESET} ${BOLD}${PROJECT_ID}${RESET}"
echo -e "${BLUE}Region :${RESET} ${BOLD}${REGION}${RESET}"
echo

# =========================
# Task 0: Enable required APIs
# =========================
echo -e "${BOLD}🔧 Enabling required APIs...${RESET}"
gcloud services enable \
  cloudfunctions.googleapis.com \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  eventarc.googleapis.com
echo -e "${GREEN}✅ APIs enabled.${RESET}"
echo

# =========================
# Task 1 & 2: Create source + Deploy (Gen2, HTTPS, unauth, max 5)
# =========================
echo -e "${BOLD}🚀 Creating source and deploying Cloud Functions Gen2...${RESET}"

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
  --gen2 \
  --trigger-http \
  --allow-unauthenticated \
  --max-instances="${MAX_INSTANCES}" \
  --entry-point="helloHttp" \
  --source="${SRC_DIR}"

echo -e "${GREEN}✅ Deployed successfully.${RESET}"
echo

# =========================
# Task 3: Test function
# =========================
echo -e "${BOLD}🧪 Testing HTTPS trigger...${RESET}"
FUNC_URL="$(gcloud functions describe "${SERVICE_NAME}" --region="${REGION}" --format='value(serviceConfig.uri)')"
if [[ -z "${FUNC_URL}" ]]; then echo -e "${RED}Could not retrieve function URL.${RESET}"; exit 1; fi
echo -e "${BLUE}URL:${RESET} ${BOLD}${FUNC_URL}${RESET}"

HTTP_STATUS=$(curl -s -o /tmp/resp.json -w "%{http_code}" -X POST "${FUNC_URL}" \
  -H "Content-Type: application/json" \
  -d '{"message":"Hello World!"}')
echo -e "${BLUE}HTTP ${HTTP_STATUS}${RESET}"
echo -e "${GREEN}Response:${RESET} $(cat /tmp/resp.json)"
echo

# =========================
# Task 4: View logs (last 10)
# =========================
echo -e "${BOLD}📜 Last 10 logs...${RESET}"
gcloud functions logs read "${SERVICE_NAME}" --region="${REGION}" --limit=10 || true
echo

# =========================
# Task 5: Quiz (reference answers)
# =========================
echo -e "${BOLD}🧩 Quiz answers${RESET}"
echo -e "1) Cloud Run functions is serverless for event-driven services: ${GREEN}True${RESET}"
echo -e "2) Trigger type used in the lab: ${GREEN}HTTPS${RESET}"
echo

# ----- Footer -----
YEAR="$(date +%Y)"
echo -e "${MAGENTA}${BOLD}
┌─────────────────────────────────────────────────────────┐
│  © ${YEAR} ePlus.dev — All rights reserved              │
└─────────────────────────────────────────────────────────┘${RESET}"