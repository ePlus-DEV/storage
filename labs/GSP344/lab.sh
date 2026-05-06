#!/bin/bash
set -e

# =========================
# Colors
# =========================
RED=$'\033[0;91m'
GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
CYAN=$'\033[0;96m'
BOLD=$'\033[1m'
NC=$'\033[0m'

clear

echo "${CYAN}${BOLD}============================================================${NC}"
echo "${GREEN}${BOLD} Starting Execution - ePlus.DEV ${NC}"
echo "${CYAN}${BOLD}============================================================${NC}"
echo ""

# =========================
# Helper functions
# =========================
ask_yes() {
  echo ""
  echo "${YELLOW}${BOLD}$1${NC}"
  read -p "Type y to continue: " CONFIRM
  if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "${RED}Stopped by user.${NC}"
    exit 0
  fi
}

check_progress_from_task5() {
  echo ""
  echo "${YELLOW}${BOLD}Please click 'Check my progress' now.${NC}"
  read -p "After checking, type y to continue: " CONFIRM
  if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "${RED}Stopped by user.${NC}"
    exit 0
  fi
}

# =========================
# Config
# =========================
PROJECT_ID=$(gcloud projects list --format='value(PROJECT_ID)' --filter='qwiklabs-gcp' | head -n 1)
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
REPO="rest-api-repo"

if [ -z "$PROJECT_ID" ]; then
  echo "${RED}Cannot detect Qwiklabs project ID.${NC}"
  exit 1
fi

gcloud config set project "$PROJECT_ID"

echo "${GREEN}Project ID:${NC} $PROJECT_ID"
echo "${GREEN}Region:${NC} $REGION"
echo "${GREEN}Artifact Registry Repo:${NC} $REPO"
echo ""

# =========================
# Enable APIs
# =========================
echo "${CYAN}${BOLD}Enabling required services...${NC}"
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  firestore.googleapis.com \
  appengine.googleapis.com

# =========================
# Task 1
# =========================
echo ""
echo "${CYAN}${BOLD}Task 1: Create Firestore database${NC}"

if gcloud firestore databases describe --database="(default)" >/dev/null 2>&1; then
  echo "${GREEN}Firestore database already exists. Skipping.${NC}"
else
  gcloud firestore databases create \
    --database="(default)" \
    --location="$REGION" \
    --edition=standard \
    --type=firestore-native || \
  gcloud firestore databases create \
    --location="$REGION" \
    --type=firestore-native
fi

echo "${GREEN}Task 1 done. No manual check pause here.${NC}"

# =========================
# Clone repo
# =========================
echo ""
echo "${CYAN}${BOLD}Clone / update pet-theory repository${NC}"

cd "$HOME"

if [ -d "$HOME/pet-theory" ]; then
  echo "${YELLOW}Folder ~/pet-theory already exists. Resetting repo automatically...${NC}"
  cd "$HOME/pet-theory"
  git reset --hard
  git clean -fd
  git pull || true
else
  git clone https://github.com/rosera/pet-theory.git
fi

# =========================
# Task 2
# =========================
echo ""
echo "${CYAN}${BOLD}Task 2: Import Netflix CSV into Firestore${NC}"

cd "$HOME/pet-theory/lab06/firebase-import-csv/solution"

npm install
node index.js netflix_titles_original.csv

echo "${GREEN}Task 2 done. No manual check pause here.${NC}"

# =========================
# Artifact Registry
# =========================
echo ""
echo "${CYAN}${BOLD}Create Artifact Registry repository${NC}"

if gcloud artifacts repositories describe "$REPO" --location="$REGION" >/dev/null 2>&1; then
  echo "${GREEN}Artifact Registry repository already exists. Skipping.${NC}"
else
  gcloud artifacts repositories create "$REPO" \
    --repository-format=docker \
    --location="$REGION" \
    --description="Docker repository for Netflix Firestore lab"
fi

# =========================
# Task 3
# =========================
echo ""
echo "${CYAN}${BOLD}Task 3: Build and deploy REST API v0.1${NC}"

cd "$HOME/pet-theory/lab06/firebase-rest-api/solution-01"

REST_IMAGE_V01="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO/rest-api:0.1"

gcloud builds submit --tag "$REST_IMAGE_V01" .

gcloud run deploy netflix-dataset-service \
  --image "$REST_IMAGE_V01" \
  --region "$REGION" \
  --platform managed \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

SERVICE_URL=$(gcloud run services describe netflix-dataset-service \
  --region "$REGION" \
  --format='value(status.url)')

echo ""
echo "${GREEN}REST API v0.1 URL:${NC} $SERVICE_URL"
echo "${CYAN}Testing REST API v0.1:${NC}"
curl -s "$SERVICE_URL"
echo ""

echo "${GREEN}Task 3 done. No manual check pause here.${NC}"

# =========================
# Task 4
# =========================
echo ""
echo "${CYAN}${BOLD}Task 4: Build and deploy REST API v0.2${NC}"

cd "$HOME/pet-theory/lab06/firebase-rest-api/solution-02"

REST_IMAGE_V02="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO/rest-api:0.2"

gcloud builds submit --tag "$REST_IMAGE_V02" .

gcloud run deploy netflix-dataset-service \
  --image "$REST_IMAGE_V02" \
  --region "$REGION" \
  --platform managed \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

SERVICE_URL=$(gcloud run services describe netflix-dataset-service \
  --region "$REGION" \
  --format='value(status.url)')

echo ""
echo "${GREEN}REST API v0.2 URL:${NC} $SERVICE_URL"
echo "${CYAN}Testing REST API v0.2 with /2019:${NC}"
curl -s "$SERVICE_URL/2019" | head -c 800
echo ""
echo ""

echo "${GREEN}Task 4 done. No manual check pause here.${NC}"

# =========================
# Task 5
# =========================
echo ""
echo "${CYAN}${BOLD}Task 5: Deploy staging frontend${NC}"

cd "$HOME/pet-theory/lab06/firebase-frontend"

echo "${YELLOW}Reset frontend app.js before staging to keep demo dataset.${NC}"
git checkout -- public/app.js || true

echo "${CYAN}Checking staging app.js references:${NC}"
grep -nE "REST_API_SERVICE|data/netflix|fetch" public/app.js || true

STAGING_IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO/frontend-staging:0.1"

gcloud builds submit --tag "$STAGING_IMAGE" .

gcloud run deploy frontend-staging-service \
  --image "$STAGING_IMAGE" \
  --region "$REGION" \
  --platform managed \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

STAGING_URL=$(gcloud run services describe frontend-staging-service \
  --region "$REGION" \
  --format='value(status.url)')

echo ""
echo "${GREEN}Staging Frontend URL:${NC} $STAGING_URL"

check_progress_from_task5

# =========================
# Task 6
# =========================
echo ""
echo "${CYAN}${BOLD}Task 6: Deploy production frontend${NC}"

cd "$HOME/pet-theory/lab06/firebase-frontend/public"

ask_yes "This will patch public/app.js for production. Backup will be saved as app.js.before-production."

cp app.js app.js.before-production

PROD_API_URL="${SERVICE_URL}/2020"

echo "${GREEN}Production API URL to inject:${NC} $PROD_API_URL"

python3 <<PY
from pathlib import Path
import re

p = Path("app.js")
text = p.read_text()
prod_api_url = "$PROD_API_URL"

pattern_const = r'const\s+REST_API_SERVICE\s*=\s*["\\'][^"\\']*["\\'];'

if re.search(pattern_const, text):
    text = re.sub(
        pattern_const,
        f'const REST_API_SERVICE = "{prod_api_url}";',
        text
    )
elif "data/netflix.json" in text:
    text = text.replace("data/netflix.json", prod_api_url)
else:
    text = f'const REST_API_SERVICE = "{prod_api_url}";\\n' + text

p.write_text(text)
PY

echo ""
echo "${CYAN}After patch, app.js references:${NC}"
grep -nE "REST_API_SERVICE|data/netflix|run.app|fetch" app.js || true

cd "$HOME/pet-theory/lab06/firebase-frontend"

PROD_IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO/frontend-production:0.1"

gcloud builds submit --tag "$PROD_IMAGE" .

gcloud run deploy frontend-production-service \
  --image "$PROD_IMAGE" \
  --region "$REGION" \
  --platform managed \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

PROD_URL=$(gcloud run services describe frontend-production-service \
  --region "$REGION" \
  --format='value(status.url)')

echo ""
echo "${CYAN}${BOLD}============================================================${NC}"
echo "${GREEN}${BOLD}All tasks completed.${NC}"
echo "${CYAN}${BOLD}============================================================${NC}"
echo "${GREEN}REST API:${NC} $SERVICE_URL"
echo "${GREEN}REST API Test 2019:${NC} $SERVICE_URL/2019"
echo "${GREEN}REST API Test 2020:${NC} $SERVICE_URL/2020"
echo "${GREEN}Staging Frontend:${NC} $STAGING_URL"
echo "${GREEN}Production Frontend:${NC} $PROD_URL"
echo "${CYAN}${BOLD}============================================================${NC}"
echo ""
echo "${YELLOW}${BOLD}Now click Check my progress for Task 6.${NC}"