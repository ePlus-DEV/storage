#!/usr/bin/env bash
# Copyright (c) 2026 ePlus.DEV | Unlicense
# Official GSP344: https://www.skills.google/focuses/14677
set -euo pipefail
# ============================================================
# 📺 https://eplus.dev
# ============================================================

# Define color variables
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BLACK_TEXT=

[[ -t 1 ]] && clear || true

# Welcome Banner
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}        🚀 WELCOME TO ePlus.DEV 🚀${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo
echo "${MAGENTA_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"
echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}       ePlus.DEV – Starting Execution       ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo

gcloud auth list

# ── Project Setup ────────────────────────────────────────────
DEVSHELL_PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
[[ -n "$DEVSHELL_PROJECT_ID" && "$DEVSHELL_PROJECT_ID" != '(unset)' ]] || { echo 'ERROR: Set the active lab project.' >&2; exit 1; }
export DEVSHELL_PROJECT_ID

# ── Dynamically Fetch Region from Lab ────────────────────────
REGION="${REGION:-$(gcloud compute project-info describe --project="$DEVSHELL_PROJECT_ID" --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)}"
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
fi
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  [[ -t 0 ]] || { echo "ERROR: Set REGION to the lab region." >&2; exit 1; }
  read -r -p "Lab region: " REGION
fi
[[ "$REGION" =~ ^[a-z]+(-[a-z]+)+[0-9]+$ ]] || { echo "ERROR: Invalid region: $REGION" >&2; exit 1; }

export REGION

export DATASET_SERVICE=netflix-dataset-service
export FRONTEND_STAGING_SERVICE=frontend-staging-service
export FRONTEND_PRODUCTION_SERVICE=frontend-production-service
export AR_REPO=rest-api-repo
export FRONTEND_REPO=frontend-repo

echo "${YELLOW_TEXT}${BOLD_TEXT}Project : $DEVSHELL_PROJECT_ID${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT}Region  : $REGION${RESET_FORMAT}"
echo

# Enable required APIs
echo "${BLUE_TEXT}${BOLD_TEXT}Enabling APIs...${RESET_FORMAT}"
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  firestore.googleapis.com

# Task 1 : Create Firestore database
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 1] Creating Firestore database in $REGION...${RESET_FORMAT}"
if gcloud firestore databases describe --database='(default)' --project="$DEVSHELL_PROJECT_ID" >/dev/null 2>&1; then
  echo 'Firestore database already exists; reusing.'
else
  gcloud firestore databases create --location="$REGION" --project="$DEVSHELL_PROJECT_ID"
fi
sleep 10

# Task 2 : Import CSV into Firestore
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 2] Importing Netflix CSV into Firestore...${RESET_FORMAT}"
if [[ -e "$HOME/pet-theory" ]]; then
  [[ -d "$HOME/pet-theory/.git" ]] || { echo 'ERROR: Existing ~/pet-theory is not a Git checkout; refusing to delete it.' >&2; exit 1; }
  REPO_ORIGIN="$(git -C "$HOME/pet-theory" remote get-url origin)"
  [[ "$REPO_ORIGIN" == 'https://github.com/rosera/pet-theory.git' ]] || { echo "ERROR: Existing ~/pet-theory has unexpected origin: $REPO_ORIGIN" >&2; exit 1; }
else
  git clone https://github.com/rosera/pet-theory.git "$HOME/pet-theory"
fi

cd ~/pet-theory/lab06/firebase-import-csv/solution || exit
npm install
node index.js netflix_titles_original.csv

# Create Artifact Registry repository
echo
echo "${BLUE_TEXT}${BOLD_TEXT}Creating Artifact Registry repository: $AR_REPO...${RESET_FORMAT}"
gcloud artifacts repositories create $AR_REPO \
  --repository-format=docker \
  --location=$REGION \
  --description="REST API repo" || true

gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

# Task 3 : Deploy REST API v0.1
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 3] Building & Deploying REST API v0.1...${RESET_FORMAT}"
cd ~/pet-theory/lab06/firebase-rest-api/solution-01 || exit
npm install

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.1 .

gcloud run deploy $DATASET_SERVICE \
  --image ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.1 \
  --allow-unauthenticated \
  --max-instances=1 \
  --region=$REGION \
  --quiet

SERVICE_URL=$(gcloud run services describe $DATASET_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

echo "${GREEN_TEXT}Service URL: $SERVICE_URL${RESET_FORMAT}"
echo "${YELLOW_TEXT}Testing v0.1 endpoint...${RESET_FORMAT}"
curl -s $SERVICE_URL
echo

# Task 4 : Deploy REST API v0.2
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 4] Building & Deploying REST API v0.2...${RESET_FORMAT}"
cd ~/pet-theory/lab06/firebase-rest-api/solution-02 || exit
npm install

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.2 .

gcloud run deploy $DATASET_SERVICE \
  --image ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.2 \
  --allow-unauthenticated \
  --max-instances=1 \
  --region=$REGION \
  --quiet

SERVICE_URL=$(gcloud run services describe $DATASET_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

echo "${GREEN_TEXT}Service URL: $SERVICE_URL${RESET_FORMAT}"
echo "${YELLOW_TEXT}Testing v0.2 /2019 endpoint...${RESET_FORMAT}"
curl -s $SERVICE_URL/2019
echo

# Task 5 : Deploy Staging Frontend
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 5] Building & Deploying Staging Frontend...${RESET_FORMAT}"

gcloud artifacts repositories create $FRONTEND_REPO \
  --repository-format=docker \
  --location=$REGION \
  --description="Repository for Frontend images" || true

cd ~/pet-theory/lab06/firebase-frontend || exit

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-staging:0.1 .

gcloud run deploy $FRONTEND_STAGING_SERVICE \
  --image=${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-staging:0.1 \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

STAGING_URL=$(gcloud run services describe $FRONTEND_STAGING_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

# Task 6 : Deploy Production Frontend
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 6] Updating app.js and Deploying Production Frontend...${RESET_FORMAT}"

cd ~/pet-theory/lab06/firebase-frontend/public || exit
# Upstream app.js uses local sample data by default. The old sed matched a
# non-existent URL and silently left the production UI disconnected from API.
python3 - "$SERVICE_URL" <<'PY'
from pathlib import Path
import sys
p = Path('app.js')
s = p.read_text()
old = 'const REST_API_SERVICE = "data/netflix.json"'
new = 'const REST_API_SERVICE = "' + sys.argv[1].rstrip('/') + '/2019"'
if old not in s and new not in s:
    raise SystemExit('ERROR: Unexpected app.js REST_API_SERVICE; refusing silent no-op')
p.write_text(s.replace(old, new, 1))
PY

cd .. || exit

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-production:0.1 .

gcloud run deploy $FRONTEND_PRODUCTION_SERVICE \
  --image=${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-production:0.1 \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

PROD_URL=$(gcloud run services describe $FRONTEND_PRODUCTION_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

# Final Message
echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT} 🎉 LAB COMPLETED SUCCESSFULLY! 🎉 ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo
echo "${GREEN_TEXT}REST API      : $SERVICE_URL${RESET_FORMAT}"
echo "${GREEN_TEXT}Staging UI    : $STAGING_URL${RESET_FORMAT}"
echo "${GREEN_TEXT}Production UI : $PROD_URL${RESET_FORMAT}"
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}📢 Subscribe to Dr Abhishek ❤️${RESET_FORMAT}"
echo "${RED_TEXT}${BOLD_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"
echo
echo "${YELLOW_TEXT}Static changes only; runtime/grader PASS is unverified. Click Check my progress.${RESET_FORMAT}"\033[0;90m'; RED_TEXT=

[[ -t 1 ]] && clear || true

# Welcome Banner
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}        🚀 WELCOME TO ePlus.DEV 🚀${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo
echo "${MAGENTA_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"
echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}         INITIATING EXECUTION...       ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo

gcloud auth list

# ── Project Setup ────────────────────────────────────────────
DEVSHELL_PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
[[ -n "$DEVSHELL_PROJECT_ID" && "$DEVSHELL_PROJECT_ID" != '(unset)' ]] || { echo 'ERROR: Set the active lab project.' >&2; exit 1; }
export DEVSHELL_PROJECT_ID

# ── Dynamically Fetch Region from Lab ────────────────────────
REGION="${REGION:-$(gcloud compute project-info describe --project="$DEVSHELL_PROJECT_ID" --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)}"
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
fi
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  [[ -t 0 ]] || { echo "ERROR: Set REGION to the lab region." >&2; exit 1; }
  read -r -p "Lab region: " REGION
fi
[[ "$REGION" =~ ^[a-z]+(-[a-z]+)+[0-9]+$ ]] || { echo "ERROR: Invalid region: $REGION" >&2; exit 1; }

export REGION

export DATASET_SERVICE=netflix-dataset-service
export FRONTEND_STAGING_SERVICE=frontend-staging-service
export FRONTEND_PRODUCTION_SERVICE=frontend-production-service
export AR_REPO=rest-api-repo
export FRONTEND_REPO=frontend-repo

echo "${YELLOW_TEXT}${BOLD_TEXT}Project : $DEVSHELL_PROJECT_ID${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT}Region  : $REGION${RESET_FORMAT}"
echo

# Enable required APIs
echo "${BLUE_TEXT}${BOLD_TEXT}Enabling APIs...${RESET_FORMAT}"
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  firestore.googleapis.com

# Task 1 : Create Firestore database
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 1] Creating Firestore database in $REGION...${RESET_FORMAT}"
if gcloud firestore databases describe --database='(default)' --project="$DEVSHELL_PROJECT_ID" >/dev/null 2>&1; then
  echo 'Firestore database already exists; reusing.'
else
  gcloud firestore databases create --location="$REGION" --project="$DEVSHELL_PROJECT_ID"
fi
sleep 10

# Task 2 : Import CSV into Firestore
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 2] Importing Netflix CSV into Firestore...${RESET_FORMAT}"
if [[ -e "$HOME/pet-theory" ]]; then
  [[ -d "$HOME/pet-theory/.git" ]] || { echo 'ERROR: Existing ~/pet-theory is not a Git checkout; refusing to delete it.' >&2; exit 1; }
  REPO_ORIGIN="$(git -C "$HOME/pet-theory" remote get-url origin)"
  [[ "$REPO_ORIGIN" == 'https://github.com/rosera/pet-theory.git' ]] || { echo "ERROR: Existing ~/pet-theory has unexpected origin: $REPO_ORIGIN" >&2; exit 1; }
else
  git clone https://github.com/rosera/pet-theory.git "$HOME/pet-theory"
fi

cd ~/pet-theory/lab06/firebase-import-csv/solution || exit
npm install
node index.js netflix_titles_original.csv

# Create Artifact Registry repository
echo
echo "${BLUE_TEXT}${BOLD_TEXT}Creating Artifact Registry repository: $AR_REPO...${RESET_FORMAT}"
gcloud artifacts repositories create $AR_REPO \
  --repository-format=docker \
  --location=$REGION \
  --description="REST API repo" || true

gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

# Task 3 : Deploy REST API v0.1
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 3] Building & Deploying REST API v0.1...${RESET_FORMAT}"
cd ~/pet-theory/lab06/firebase-rest-api/solution-01 || exit
npm install

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.1 .

gcloud run deploy $DATASET_SERVICE \
  --image ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.1 \
  --allow-unauthenticated \
  --max-instances=1 \
  --region=$REGION \
  --quiet

SERVICE_URL=$(gcloud run services describe $DATASET_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

echo "${GREEN_TEXT}Service URL: $SERVICE_URL${RESET_FORMAT}"
echo "${YELLOW_TEXT}Testing v0.1 endpoint...${RESET_FORMAT}"
curl -s $SERVICE_URL
echo

# Task 4 : Deploy REST API v0.2
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 4] Building & Deploying REST API v0.2...${RESET_FORMAT}"
cd ~/pet-theory/lab06/firebase-rest-api/solution-02 || exit
npm install

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.2 .

gcloud run deploy $DATASET_SERVICE \
  --image ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.2 \
  --allow-unauthenticated \
  --max-instances=1 \
  --region=$REGION \
  --quiet

SERVICE_URL=$(gcloud run services describe $DATASET_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

echo "${GREEN_TEXT}Service URL: $SERVICE_URL${RESET_FORMAT}"
echo "${YELLOW_TEXT}Testing v0.2 /2019 endpoint...${RESET_FORMAT}"
curl -s $SERVICE_URL/2019
echo

# Task 5 : Deploy Staging Frontend
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 5] Building & Deploying Staging Frontend...${RESET_FORMAT}"

gcloud artifacts repositories create $FRONTEND_REPO \
  --repository-format=docker \
  --location=$REGION \
  --description="Repository for Frontend images" || true

cd ~/pet-theory/lab06/firebase-frontend || exit

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-staging:0.1 .

gcloud run deploy $FRONTEND_STAGING_SERVICE \
  --image=${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-staging:0.1 \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

STAGING_URL=$(gcloud run services describe $FRONTEND_STAGING_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

# Task 6 : Deploy Production Frontend
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 6] Updating app.js and Deploying Production Frontend...${RESET_FORMAT}"

cd ~/pet-theory/lab06/firebase-frontend/public || exit
# Upstream app.js uses local sample data by default. The old sed matched a
# non-existent URL and silently left the production UI disconnected from API.
python3 - "$SERVICE_URL" <<'PY'
from pathlib import Path
import sys
p = Path('app.js')
s = p.read_text()
old = 'const REST_API_SERVICE = "data/netflix.json"'
new = 'const REST_API_SERVICE = "' + sys.argv[1].rstrip('/') + '/2019"'
if old not in s and new not in s:
    raise SystemExit('ERROR: Unexpected app.js REST_API_SERVICE; refusing silent no-op')
p.write_text(s.replace(old, new, 1))
PY

cd .. || exit

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-production:0.1 .

gcloud run deploy $FRONTEND_PRODUCTION_SERVICE \
  --image=${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-production:0.1 \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

PROD_URL=$(gcloud run services describe $FRONTEND_PRODUCTION_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

# Final Message
echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT} 🎉 LAB COMPLETED SUCCESSFULLY! 🎉 ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo
echo "${GREEN_TEXT}REST API      : $SERVICE_URL${RESET_FORMAT}"
echo "${GREEN_TEXT}Staging UI    : $STAGING_URL${RESET_FORMAT}"
echo "${GREEN_TEXT}Production UI : $PROD_URL${RESET_FORMAT}"
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}📢 Subscribe to Dr Abhishek ❤️${RESET_FORMAT}"
echo "${RED_TEXT}${BOLD_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"
echo
echo "${YELLOW_TEXT}Static changes only; runtime/grader PASS is unverified. Click Check my progress.${RESET_FORMAT}"\033[0;91m'; GREEN_TEXT=

[[ -t 1 ]] && clear || true

# Welcome Banner
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}        🚀 WELCOME TO ePlus.DEV 🚀${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo
echo "${MAGENTA_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"
echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}         INITIATING EXECUTION...       ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo

gcloud auth list

# ── Project Setup ────────────────────────────────────────────
DEVSHELL_PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
[[ -n "$DEVSHELL_PROJECT_ID" && "$DEVSHELL_PROJECT_ID" != '(unset)' ]] || { echo 'ERROR: Set the active lab project.' >&2; exit 1; }
export DEVSHELL_PROJECT_ID

# ── Dynamically Fetch Region from Lab ────────────────────────
REGION="${REGION:-$(gcloud compute project-info describe --project="$DEVSHELL_PROJECT_ID" --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)}"
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
fi
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  [[ -t 0 ]] || { echo "ERROR: Set REGION to the lab region." >&2; exit 1; }
  read -r -p "Lab region: " REGION
fi
[[ "$REGION" =~ ^[a-z]+(-[a-z]+)+[0-9]+$ ]] || { echo "ERROR: Invalid region: $REGION" >&2; exit 1; }

export REGION

export DATASET_SERVICE=netflix-dataset-service
export FRONTEND_STAGING_SERVICE=frontend-staging-service
export FRONTEND_PRODUCTION_SERVICE=frontend-production-service
export AR_REPO=rest-api-repo
export FRONTEND_REPO=frontend-repo

echo "${YELLOW_TEXT}${BOLD_TEXT}Project : $DEVSHELL_PROJECT_ID${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT}Region  : $REGION${RESET_FORMAT}"
echo

# Enable required APIs
echo "${BLUE_TEXT}${BOLD_TEXT}Enabling APIs...${RESET_FORMAT}"
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  firestore.googleapis.com

# Task 1 : Create Firestore database
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 1] Creating Firestore database in $REGION...${RESET_FORMAT}"
if gcloud firestore databases describe --database='(default)' --project="$DEVSHELL_PROJECT_ID" >/dev/null 2>&1; then
  echo 'Firestore database already exists; reusing.'
else
  gcloud firestore databases create --location="$REGION" --project="$DEVSHELL_PROJECT_ID"
fi
sleep 10

# Task 2 : Import CSV into Firestore
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 2] Importing Netflix CSV into Firestore...${RESET_FORMAT}"
if [[ -e "$HOME/pet-theory" ]]; then
  [[ -d "$HOME/pet-theory/.git" ]] || { echo 'ERROR: Existing ~/pet-theory is not a Git checkout; refusing to delete it.' >&2; exit 1; }
  REPO_ORIGIN="$(git -C "$HOME/pet-theory" remote get-url origin)"
  [[ "$REPO_ORIGIN" == 'https://github.com/rosera/pet-theory.git' ]] || { echo "ERROR: Existing ~/pet-theory has unexpected origin: $REPO_ORIGIN" >&2; exit 1; }
else
  git clone https://github.com/rosera/pet-theory.git "$HOME/pet-theory"
fi

cd ~/pet-theory/lab06/firebase-import-csv/solution || exit
npm install
node index.js netflix_titles_original.csv

# Create Artifact Registry repository
echo
echo "${BLUE_TEXT}${BOLD_TEXT}Creating Artifact Registry repository: $AR_REPO...${RESET_FORMAT}"
gcloud artifacts repositories create $AR_REPO \
  --repository-format=docker \
  --location=$REGION \
  --description="REST API repo" || true

gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

# Task 3 : Deploy REST API v0.1
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 3] Building & Deploying REST API v0.1...${RESET_FORMAT}"
cd ~/pet-theory/lab06/firebase-rest-api/solution-01 || exit
npm install

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.1 .

gcloud run deploy $DATASET_SERVICE \
  --image ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.1 \
  --allow-unauthenticated \
  --max-instances=1 \
  --region=$REGION \
  --quiet

SERVICE_URL=$(gcloud run services describe $DATASET_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

echo "${GREEN_TEXT}Service URL: $SERVICE_URL${RESET_FORMAT}"
echo "${YELLOW_TEXT}Testing v0.1 endpoint...${RESET_FORMAT}"
curl -s $SERVICE_URL
echo

# Task 4 : Deploy REST API v0.2
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 4] Building & Deploying REST API v0.2...${RESET_FORMAT}"
cd ~/pet-theory/lab06/firebase-rest-api/solution-02 || exit
npm install

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.2 .

gcloud run deploy $DATASET_SERVICE \
  --image ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.2 \
  --allow-unauthenticated \
  --max-instances=1 \
  --region=$REGION \
  --quiet

SERVICE_URL=$(gcloud run services describe $DATASET_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

echo "${GREEN_TEXT}Service URL: $SERVICE_URL${RESET_FORMAT}"
echo "${YELLOW_TEXT}Testing v0.2 /2019 endpoint...${RESET_FORMAT}"
curl -s $SERVICE_URL/2019
echo

# Task 5 : Deploy Staging Frontend
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 5] Building & Deploying Staging Frontend...${RESET_FORMAT}"

gcloud artifacts repositories create $FRONTEND_REPO \
  --repository-format=docker \
  --location=$REGION \
  --description="Repository for Frontend images" || true

cd ~/pet-theory/lab06/firebase-frontend || exit

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-staging:0.1 .

gcloud run deploy $FRONTEND_STAGING_SERVICE \
  --image=${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-staging:0.1 \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

STAGING_URL=$(gcloud run services describe $FRONTEND_STAGING_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

# Task 6 : Deploy Production Frontend
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 6] Updating app.js and Deploying Production Frontend...${RESET_FORMAT}"

cd ~/pet-theory/lab06/firebase-frontend/public || exit
# Upstream app.js uses local sample data by default. The old sed matched a
# non-existent URL and silently left the production UI disconnected from API.
python3 - "$SERVICE_URL" <<'PY'
from pathlib import Path
import sys
p = Path('app.js')
s = p.read_text()
old = 'const REST_API_SERVICE = "data/netflix.json"'
new = 'const REST_API_SERVICE = "' + sys.argv[1].rstrip('/') + '/2019"'
if old not in s and new not in s:
    raise SystemExit('ERROR: Unexpected app.js REST_API_SERVICE; refusing silent no-op')
p.write_text(s.replace(old, new, 1))
PY

cd .. || exit

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-production:0.1 .

gcloud run deploy $FRONTEND_PRODUCTION_SERVICE \
  --image=${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-production:0.1 \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

PROD_URL=$(gcloud run services describe $FRONTEND_PRODUCTION_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

# Final Message
echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT} 🎉 LAB COMPLETED SUCCESSFULLY! 🎉 ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo
echo "${GREEN_TEXT}REST API      : $SERVICE_URL${RESET_FORMAT}"
echo "${GREEN_TEXT}Staging UI    : $STAGING_URL${RESET_FORMAT}"
echo "${GREEN_TEXT}Production UI : $PROD_URL${RESET_FORMAT}"
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}📢 Subscribe to Dr Abhishek ❤️${RESET_FORMAT}"
echo "${RED_TEXT}${BOLD_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"
echo
echo "${YELLOW_TEXT}Static changes only; runtime/grader PASS is unverified. Click Check my progress.${RESET_FORMAT}"\033[0;92m'
  YELLOW_TEXT=

[[ -t 1 ]] && clear || true

# Welcome Banner
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}        🚀 WELCOME TO ePlus.DEV 🚀${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo
echo "${MAGENTA_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"
echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}         INITIATING EXECUTION...       ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo

gcloud auth list

# ── Project Setup ────────────────────────────────────────────
DEVSHELL_PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
[[ -n "$DEVSHELL_PROJECT_ID" && "$DEVSHELL_PROJECT_ID" != '(unset)' ]] || { echo 'ERROR: Set the active lab project.' >&2; exit 1; }
export DEVSHELL_PROJECT_ID

# ── Dynamically Fetch Region from Lab ────────────────────────
REGION="${REGION:-$(gcloud compute project-info describe --project="$DEVSHELL_PROJECT_ID" --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)}"
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
fi
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  [[ -t 0 ]] || { echo "ERROR: Set REGION to the lab region." >&2; exit 1; }
  read -r -p "Lab region: " REGION
fi
[[ "$REGION" =~ ^[a-z]+(-[a-z]+)+[0-9]+$ ]] || { echo "ERROR: Invalid region: $REGION" >&2; exit 1; }

export REGION

export DATASET_SERVICE=netflix-dataset-service
export FRONTEND_STAGING_SERVICE=frontend-staging-service
export FRONTEND_PRODUCTION_SERVICE=frontend-production-service
export AR_REPO=rest-api-repo
export FRONTEND_REPO=frontend-repo

echo "${YELLOW_TEXT}${BOLD_TEXT}Project : $DEVSHELL_PROJECT_ID${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT}Region  : $REGION${RESET_FORMAT}"
echo

# Enable required APIs
echo "${BLUE_TEXT}${BOLD_TEXT}Enabling APIs...${RESET_FORMAT}"
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  firestore.googleapis.com

# Task 1 : Create Firestore database
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 1] Creating Firestore database in $REGION...${RESET_FORMAT}"
if gcloud firestore databases describe --database='(default)' --project="$DEVSHELL_PROJECT_ID" >/dev/null 2>&1; then
  echo 'Firestore database already exists; reusing.'
else
  gcloud firestore databases create --location="$REGION" --project="$DEVSHELL_PROJECT_ID"
fi
sleep 10

# Task 2 : Import CSV into Firestore
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 2] Importing Netflix CSV into Firestore...${RESET_FORMAT}"
if [[ -e "$HOME/pet-theory" ]]; then
  [[ -d "$HOME/pet-theory/.git" ]] || { echo 'ERROR: Existing ~/pet-theory is not a Git checkout; refusing to delete it.' >&2; exit 1; }
  REPO_ORIGIN="$(git -C "$HOME/pet-theory" remote get-url origin)"
  [[ "$REPO_ORIGIN" == 'https://github.com/rosera/pet-theory.git' ]] || { echo "ERROR: Existing ~/pet-theory has unexpected origin: $REPO_ORIGIN" >&2; exit 1; }
else
  git clone https://github.com/rosera/pet-theory.git "$HOME/pet-theory"
fi

cd ~/pet-theory/lab06/firebase-import-csv/solution || exit
npm install
node index.js netflix_titles_original.csv

# Create Artifact Registry repository
echo
echo "${BLUE_TEXT}${BOLD_TEXT}Creating Artifact Registry repository: $AR_REPO...${RESET_FORMAT}"
gcloud artifacts repositories create $AR_REPO \
  --repository-format=docker \
  --location=$REGION \
  --description="REST API repo" || true

gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

# Task 3 : Deploy REST API v0.1
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 3] Building & Deploying REST API v0.1...${RESET_FORMAT}"
cd ~/pet-theory/lab06/firebase-rest-api/solution-01 || exit
npm install

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.1 .

gcloud run deploy $DATASET_SERVICE \
  --image ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.1 \
  --allow-unauthenticated \
  --max-instances=1 \
  --region=$REGION \
  --quiet

SERVICE_URL=$(gcloud run services describe $DATASET_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

echo "${GREEN_TEXT}Service URL: $SERVICE_URL${RESET_FORMAT}"
echo "${YELLOW_TEXT}Testing v0.1 endpoint...${RESET_FORMAT}"
curl -s $SERVICE_URL
echo

# Task 4 : Deploy REST API v0.2
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 4] Building & Deploying REST API v0.2...${RESET_FORMAT}"
cd ~/pet-theory/lab06/firebase-rest-api/solution-02 || exit
npm install

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.2 .

gcloud run deploy $DATASET_SERVICE \
  --image ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.2 \
  --allow-unauthenticated \
  --max-instances=1 \
  --region=$REGION \
  --quiet

SERVICE_URL=$(gcloud run services describe $DATASET_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

echo "${GREEN_TEXT}Service URL: $SERVICE_URL${RESET_FORMAT}"
echo "${YELLOW_TEXT}Testing v0.2 /2019 endpoint...${RESET_FORMAT}"
curl -s $SERVICE_URL/2019
echo

# Task 5 : Deploy Staging Frontend
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 5] Building & Deploying Staging Frontend...${RESET_FORMAT}"

gcloud artifacts repositories create $FRONTEND_REPO \
  --repository-format=docker \
  --location=$REGION \
  --description="Repository for Frontend images" || true

cd ~/pet-theory/lab06/firebase-frontend || exit

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-staging:0.1 .

gcloud run deploy $FRONTEND_STAGING_SERVICE \
  --image=${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-staging:0.1 \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

STAGING_URL=$(gcloud run services describe $FRONTEND_STAGING_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

# Task 6 : Deploy Production Frontend
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 6] Updating app.js and Deploying Production Frontend...${RESET_FORMAT}"

cd ~/pet-theory/lab06/firebase-frontend/public || exit
# Upstream app.js uses local sample data by default. The old sed matched a
# non-existent URL and silently left the production UI disconnected from API.
python3 - "$SERVICE_URL" <<'PY'
from pathlib import Path
import sys
p = Path('app.js')
s = p.read_text()
old = 'const REST_API_SERVICE = "data/netflix.json"'
new = 'const REST_API_SERVICE = "' + sys.argv[1].rstrip('/') + '/2019"'
if old not in s and new not in s:
    raise SystemExit('ERROR: Unexpected app.js REST_API_SERVICE; refusing silent no-op')
p.write_text(s.replace(old, new, 1))
PY

cd .. || exit

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-production:0.1 .

gcloud run deploy $FRONTEND_PRODUCTION_SERVICE \
  --image=${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-production:0.1 \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

PROD_URL=$(gcloud run services describe $FRONTEND_PRODUCTION_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

# Final Message
echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT} 🎉 LAB COMPLETED SUCCESSFULLY! 🎉 ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo
echo "${GREEN_TEXT}REST API      : $SERVICE_URL${RESET_FORMAT}"
echo "${GREEN_TEXT}Staging UI    : $STAGING_URL${RESET_FORMAT}"
echo "${GREEN_TEXT}Production UI : $PROD_URL${RESET_FORMAT}"
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}📢 Subscribe to Dr Abhishek ❤️${RESET_FORMAT}"
echo "${RED_TEXT}${BOLD_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"
echo
echo "${YELLOW_TEXT}Static changes only; runtime/grader PASS is unverified. Click Check my progress.${RESET_FORMAT}"\033[0;93m'; BLUE_TEXT=

[[ -t 1 ]] && clear || true

# Welcome Banner
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}        🚀 WELCOME TO ePlus.DEV 🚀${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo
echo "${MAGENTA_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"
echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}         INITIATING EXECUTION...       ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo

gcloud auth list

# ── Project Setup ────────────────────────────────────────────
DEVSHELL_PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
[[ -n "$DEVSHELL_PROJECT_ID" && "$DEVSHELL_PROJECT_ID" != '(unset)' ]] || { echo 'ERROR: Set the active lab project.' >&2; exit 1; }
export DEVSHELL_PROJECT_ID

# ── Dynamically Fetch Region from Lab ────────────────────────
REGION="${REGION:-$(gcloud compute project-info describe --project="$DEVSHELL_PROJECT_ID" --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)}"
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
fi
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  [[ -t 0 ]] || { echo "ERROR: Set REGION to the lab region." >&2; exit 1; }
  read -r -p "Lab region: " REGION
fi
[[ "$REGION" =~ ^[a-z]+(-[a-z]+)+[0-9]+$ ]] || { echo "ERROR: Invalid region: $REGION" >&2; exit 1; }

export REGION

export DATASET_SERVICE=netflix-dataset-service
export FRONTEND_STAGING_SERVICE=frontend-staging-service
export FRONTEND_PRODUCTION_SERVICE=frontend-production-service
export AR_REPO=rest-api-repo
export FRONTEND_REPO=frontend-repo

echo "${YELLOW_TEXT}${BOLD_TEXT}Project : $DEVSHELL_PROJECT_ID${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT}Region  : $REGION${RESET_FORMAT}"
echo

# Enable required APIs
echo "${BLUE_TEXT}${BOLD_TEXT}Enabling APIs...${RESET_FORMAT}"
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  firestore.googleapis.com

# Task 1 : Create Firestore database
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 1] Creating Firestore database in $REGION...${RESET_FORMAT}"
if gcloud firestore databases describe --database='(default)' --project="$DEVSHELL_PROJECT_ID" >/dev/null 2>&1; then
  echo 'Firestore database already exists; reusing.'
else
  gcloud firestore databases create --location="$REGION" --project="$DEVSHELL_PROJECT_ID"
fi
sleep 10

# Task 2 : Import CSV into Firestore
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 2] Importing Netflix CSV into Firestore...${RESET_FORMAT}"
if [[ -e "$HOME/pet-theory" ]]; then
  [[ -d "$HOME/pet-theory/.git" ]] || { echo 'ERROR: Existing ~/pet-theory is not a Git checkout; refusing to delete it.' >&2; exit 1; }
  REPO_ORIGIN="$(git -C "$HOME/pet-theory" remote get-url origin)"
  [[ "$REPO_ORIGIN" == 'https://github.com/rosera/pet-theory.git' ]] || { echo "ERROR: Existing ~/pet-theory has unexpected origin: $REPO_ORIGIN" >&2; exit 1; }
else
  git clone https://github.com/rosera/pet-theory.git "$HOME/pet-theory"
fi

cd ~/pet-theory/lab06/firebase-import-csv/solution || exit
npm install
node index.js netflix_titles_original.csv

# Create Artifact Registry repository
echo
echo "${BLUE_TEXT}${BOLD_TEXT}Creating Artifact Registry repository: $AR_REPO...${RESET_FORMAT}"
gcloud artifacts repositories create $AR_REPO \
  --repository-format=docker \
  --location=$REGION \
  --description="REST API repo" || true

gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

# Task 3 : Deploy REST API v0.1
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 3] Building & Deploying REST API v0.1...${RESET_FORMAT}"
cd ~/pet-theory/lab06/firebase-rest-api/solution-01 || exit
npm install

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.1 .

gcloud run deploy $DATASET_SERVICE \
  --image ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.1 \
  --allow-unauthenticated \
  --max-instances=1 \
  --region=$REGION \
  --quiet

SERVICE_URL=$(gcloud run services describe $DATASET_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

echo "${GREEN_TEXT}Service URL: $SERVICE_URL${RESET_FORMAT}"
echo "${YELLOW_TEXT}Testing v0.1 endpoint...${RESET_FORMAT}"
curl -s $SERVICE_URL
echo

# Task 4 : Deploy REST API v0.2
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 4] Building & Deploying REST API v0.2...${RESET_FORMAT}"
cd ~/pet-theory/lab06/firebase-rest-api/solution-02 || exit
npm install

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.2 .

gcloud run deploy $DATASET_SERVICE \
  --image ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.2 \
  --allow-unauthenticated \
  --max-instances=1 \
  --region=$REGION \
  --quiet

SERVICE_URL=$(gcloud run services describe $DATASET_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

echo "${GREEN_TEXT}Service URL: $SERVICE_URL${RESET_FORMAT}"
echo "${YELLOW_TEXT}Testing v0.2 /2019 endpoint...${RESET_FORMAT}"
curl -s $SERVICE_URL/2019
echo

# Task 5 : Deploy Staging Frontend
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 5] Building & Deploying Staging Frontend...${RESET_FORMAT}"

gcloud artifacts repositories create $FRONTEND_REPO \
  --repository-format=docker \
  --location=$REGION \
  --description="Repository for Frontend images" || true

cd ~/pet-theory/lab06/firebase-frontend || exit

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-staging:0.1 .

gcloud run deploy $FRONTEND_STAGING_SERVICE \
  --image=${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-staging:0.1 \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

STAGING_URL=$(gcloud run services describe $FRONTEND_STAGING_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

# Task 6 : Deploy Production Frontend
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 6] Updating app.js and Deploying Production Frontend...${RESET_FORMAT}"

cd ~/pet-theory/lab06/firebase-frontend/public || exit
# Upstream app.js uses local sample data by default. The old sed matched a
# non-existent URL and silently left the production UI disconnected from API.
python3 - "$SERVICE_URL" <<'PY'
from pathlib import Path
import sys
p = Path('app.js')
s = p.read_text()
old = 'const REST_API_SERVICE = "data/netflix.json"'
new = 'const REST_API_SERVICE = "' + sys.argv[1].rstrip('/') + '/2019"'
if old not in s and new not in s:
    raise SystemExit('ERROR: Unexpected app.js REST_API_SERVICE; refusing silent no-op')
p.write_text(s.replace(old, new, 1))
PY

cd .. || exit

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-production:0.1 .

gcloud run deploy $FRONTEND_PRODUCTION_SERVICE \
  --image=${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-production:0.1 \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

PROD_URL=$(gcloud run services describe $FRONTEND_PRODUCTION_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

# Final Message
echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT} 🎉 LAB COMPLETED SUCCESSFULLY! 🎉 ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo
echo "${GREEN_TEXT}REST API      : $SERVICE_URL${RESET_FORMAT}"
echo "${GREEN_TEXT}Staging UI    : $STAGING_URL${RESET_FORMAT}"
echo "${GREEN_TEXT}Production UI : $PROD_URL${RESET_FORMAT}"
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}📢 Subscribe to Dr Abhishek ❤️${RESET_FORMAT}"
echo "${RED_TEXT}${BOLD_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"
echo
echo "${YELLOW_TEXT}Static changes only; runtime/grader PASS is unverified. Click Check my progress.${RESET_FORMAT}"\033[0;94m'; MAGENTA_TEXT=

[[ -t 1 ]] && clear || true

# Welcome Banner
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}        🚀 WELCOME TO ePlus.DEV 🚀${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo
echo "${MAGENTA_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"
echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}         INITIATING EXECUTION...       ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo

gcloud auth list

# ── Project Setup ────────────────────────────────────────────
DEVSHELL_PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
[[ -n "$DEVSHELL_PROJECT_ID" && "$DEVSHELL_PROJECT_ID" != '(unset)' ]] || { echo 'ERROR: Set the active lab project.' >&2; exit 1; }
export DEVSHELL_PROJECT_ID

# ── Dynamically Fetch Region from Lab ────────────────────────
REGION="${REGION:-$(gcloud compute project-info describe --project="$DEVSHELL_PROJECT_ID" --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)}"
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
fi
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  [[ -t 0 ]] || { echo "ERROR: Set REGION to the lab region." >&2; exit 1; }
  read -r -p "Lab region: " REGION
fi
[[ "$REGION" =~ ^[a-z]+(-[a-z]+)+[0-9]+$ ]] || { echo "ERROR: Invalid region: $REGION" >&2; exit 1; }

export REGION

export DATASET_SERVICE=netflix-dataset-service
export FRONTEND_STAGING_SERVICE=frontend-staging-service
export FRONTEND_PRODUCTION_SERVICE=frontend-production-service
export AR_REPO=rest-api-repo
export FRONTEND_REPO=frontend-repo

echo "${YELLOW_TEXT}${BOLD_TEXT}Project : $DEVSHELL_PROJECT_ID${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT}Region  : $REGION${RESET_FORMAT}"
echo

# Enable required APIs
echo "${BLUE_TEXT}${BOLD_TEXT}Enabling APIs...${RESET_FORMAT}"
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  firestore.googleapis.com

# Task 1 : Create Firestore database
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 1] Creating Firestore database in $REGION...${RESET_FORMAT}"
if gcloud firestore databases describe --database='(default)' --project="$DEVSHELL_PROJECT_ID" >/dev/null 2>&1; then
  echo 'Firestore database already exists; reusing.'
else
  gcloud firestore databases create --location="$REGION" --project="$DEVSHELL_PROJECT_ID"
fi
sleep 10

# Task 2 : Import CSV into Firestore
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 2] Importing Netflix CSV into Firestore...${RESET_FORMAT}"
if [[ -e "$HOME/pet-theory" ]]; then
  [[ -d "$HOME/pet-theory/.git" ]] || { echo 'ERROR: Existing ~/pet-theory is not a Git checkout; refusing to delete it.' >&2; exit 1; }
  REPO_ORIGIN="$(git -C "$HOME/pet-theory" remote get-url origin)"
  [[ "$REPO_ORIGIN" == 'https://github.com/rosera/pet-theory.git' ]] || { echo "ERROR: Existing ~/pet-theory has unexpected origin: $REPO_ORIGIN" >&2; exit 1; }
else
  git clone https://github.com/rosera/pet-theory.git "$HOME/pet-theory"
fi

cd ~/pet-theory/lab06/firebase-import-csv/solution || exit
npm install
node index.js netflix_titles_original.csv

# Create Artifact Registry repository
echo
echo "${BLUE_TEXT}${BOLD_TEXT}Creating Artifact Registry repository: $AR_REPO...${RESET_FORMAT}"
gcloud artifacts repositories create $AR_REPO \
  --repository-format=docker \
  --location=$REGION \
  --description="REST API repo" || true

gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

# Task 3 : Deploy REST API v0.1
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 3] Building & Deploying REST API v0.1...${RESET_FORMAT}"
cd ~/pet-theory/lab06/firebase-rest-api/solution-01 || exit
npm install

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.1 .

gcloud run deploy $DATASET_SERVICE \
  --image ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.1 \
  --allow-unauthenticated \
  --max-instances=1 \
  --region=$REGION \
  --quiet

SERVICE_URL=$(gcloud run services describe $DATASET_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

echo "${GREEN_TEXT}Service URL: $SERVICE_URL${RESET_FORMAT}"
echo "${YELLOW_TEXT}Testing v0.1 endpoint...${RESET_FORMAT}"
curl -s $SERVICE_URL
echo

# Task 4 : Deploy REST API v0.2
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 4] Building & Deploying REST API v0.2...${RESET_FORMAT}"
cd ~/pet-theory/lab06/firebase-rest-api/solution-02 || exit
npm install

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.2 .

gcloud run deploy $DATASET_SERVICE \
  --image ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.2 \
  --allow-unauthenticated \
  --max-instances=1 \
  --region=$REGION \
  --quiet

SERVICE_URL=$(gcloud run services describe $DATASET_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

echo "${GREEN_TEXT}Service URL: $SERVICE_URL${RESET_FORMAT}"
echo "${YELLOW_TEXT}Testing v0.2 /2019 endpoint...${RESET_FORMAT}"
curl -s $SERVICE_URL/2019
echo

# Task 5 : Deploy Staging Frontend
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 5] Building & Deploying Staging Frontend...${RESET_FORMAT}"

gcloud artifacts repositories create $FRONTEND_REPO \
  --repository-format=docker \
  --location=$REGION \
  --description="Repository for Frontend images" || true

cd ~/pet-theory/lab06/firebase-frontend || exit

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-staging:0.1 .

gcloud run deploy $FRONTEND_STAGING_SERVICE \
  --image=${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-staging:0.1 \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

STAGING_URL=$(gcloud run services describe $FRONTEND_STAGING_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

# Task 6 : Deploy Production Frontend
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 6] Updating app.js and Deploying Production Frontend...${RESET_FORMAT}"

cd ~/pet-theory/lab06/firebase-frontend/public || exit
# Upstream app.js uses local sample data by default. The old sed matched a
# non-existent URL and silently left the production UI disconnected from API.
python3 - "$SERVICE_URL" <<'PY'
from pathlib import Path
import sys
p = Path('app.js')
s = p.read_text()
old = 'const REST_API_SERVICE = "data/netflix.json"'
new = 'const REST_API_SERVICE = "' + sys.argv[1].rstrip('/') + '/2019"'
if old not in s and new not in s:
    raise SystemExit('ERROR: Unexpected app.js REST_API_SERVICE; refusing silent no-op')
p.write_text(s.replace(old, new, 1))
PY

cd .. || exit

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-production:0.1 .

gcloud run deploy $FRONTEND_PRODUCTION_SERVICE \
  --image=${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-production:0.1 \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

PROD_URL=$(gcloud run services describe $FRONTEND_PRODUCTION_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

# Final Message
echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT} 🎉 LAB COMPLETED SUCCESSFULLY! 🎉 ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo
echo "${GREEN_TEXT}REST API      : $SERVICE_URL${RESET_FORMAT}"
echo "${GREEN_TEXT}Staging UI    : $STAGING_URL${RESET_FORMAT}"
echo "${GREEN_TEXT}Production UI : $PROD_URL${RESET_FORMAT}"
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}📢 Subscribe to Dr Abhishek ❤️${RESET_FORMAT}"
echo "${RED_TEXT}${BOLD_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"
echo
echo "${YELLOW_TEXT}Static changes only; runtime/grader PASS is unverified. Click Check my progress.${RESET_FORMAT}"\033[0;95m'
  CYAN_TEXT=

[[ -t 1 ]] && clear || true

# Welcome Banner
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}        🚀 WELCOME TO ePlus.DEV 🚀${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo
echo "${MAGENTA_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"
echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}         INITIATING EXECUTION...       ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo

gcloud auth list

# ── Project Setup ────────────────────────────────────────────
DEVSHELL_PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
[[ -n "$DEVSHELL_PROJECT_ID" && "$DEVSHELL_PROJECT_ID" != '(unset)' ]] || { echo 'ERROR: Set the active lab project.' >&2; exit 1; }
export DEVSHELL_PROJECT_ID

# ── Dynamically Fetch Region from Lab ────────────────────────
REGION="${REGION:-$(gcloud compute project-info describe --project="$DEVSHELL_PROJECT_ID" --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)}"
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
fi
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  [[ -t 0 ]] || { echo "ERROR: Set REGION to the lab region." >&2; exit 1; }
  read -r -p "Lab region: " REGION
fi
[[ "$REGION" =~ ^[a-z]+(-[a-z]+)+[0-9]+$ ]] || { echo "ERROR: Invalid region: $REGION" >&2; exit 1; }

export REGION

export DATASET_SERVICE=netflix-dataset-service
export FRONTEND_STAGING_SERVICE=frontend-staging-service
export FRONTEND_PRODUCTION_SERVICE=frontend-production-service
export AR_REPO=rest-api-repo
export FRONTEND_REPO=frontend-repo

echo "${YELLOW_TEXT}${BOLD_TEXT}Project : $DEVSHELL_PROJECT_ID${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT}Region  : $REGION${RESET_FORMAT}"
echo

# Enable required APIs
echo "${BLUE_TEXT}${BOLD_TEXT}Enabling APIs...${RESET_FORMAT}"
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  firestore.googleapis.com

# Task 1 : Create Firestore database
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 1] Creating Firestore database in $REGION...${RESET_FORMAT}"
if gcloud firestore databases describe --database='(default)' --project="$DEVSHELL_PROJECT_ID" >/dev/null 2>&1; then
  echo 'Firestore database already exists; reusing.'
else
  gcloud firestore databases create --location="$REGION" --project="$DEVSHELL_PROJECT_ID"
fi
sleep 10

# Task 2 : Import CSV into Firestore
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 2] Importing Netflix CSV into Firestore...${RESET_FORMAT}"
if [[ -e "$HOME/pet-theory" ]]; then
  [[ -d "$HOME/pet-theory/.git" ]] || { echo 'ERROR: Existing ~/pet-theory is not a Git checkout; refusing to delete it.' >&2; exit 1; }
  REPO_ORIGIN="$(git -C "$HOME/pet-theory" remote get-url origin)"
  [[ "$REPO_ORIGIN" == 'https://github.com/rosera/pet-theory.git' ]] || { echo "ERROR: Existing ~/pet-theory has unexpected origin: $REPO_ORIGIN" >&2; exit 1; }
else
  git clone https://github.com/rosera/pet-theory.git "$HOME/pet-theory"
fi

cd ~/pet-theory/lab06/firebase-import-csv/solution || exit
npm install
node index.js netflix_titles_original.csv

# Create Artifact Registry repository
echo
echo "${BLUE_TEXT}${BOLD_TEXT}Creating Artifact Registry repository: $AR_REPO...${RESET_FORMAT}"
gcloud artifacts repositories create $AR_REPO \
  --repository-format=docker \
  --location=$REGION \
  --description="REST API repo" || true

gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

# Task 3 : Deploy REST API v0.1
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 3] Building & Deploying REST API v0.1...${RESET_FORMAT}"
cd ~/pet-theory/lab06/firebase-rest-api/solution-01 || exit
npm install

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.1 .

gcloud run deploy $DATASET_SERVICE \
  --image ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.1 \
  --allow-unauthenticated \
  --max-instances=1 \
  --region=$REGION \
  --quiet

SERVICE_URL=$(gcloud run services describe $DATASET_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

echo "${GREEN_TEXT}Service URL: $SERVICE_URL${RESET_FORMAT}"
echo "${YELLOW_TEXT}Testing v0.1 endpoint...${RESET_FORMAT}"
curl -s $SERVICE_URL
echo

# Task 4 : Deploy REST API v0.2
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 4] Building & Deploying REST API v0.2...${RESET_FORMAT}"
cd ~/pet-theory/lab06/firebase-rest-api/solution-02 || exit
npm install

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.2 .

gcloud run deploy $DATASET_SERVICE \
  --image ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.2 \
  --allow-unauthenticated \
  --max-instances=1 \
  --region=$REGION \
  --quiet

SERVICE_URL=$(gcloud run services describe $DATASET_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

echo "${GREEN_TEXT}Service URL: $SERVICE_URL${RESET_FORMAT}"
echo "${YELLOW_TEXT}Testing v0.2 /2019 endpoint...${RESET_FORMAT}"
curl -s $SERVICE_URL/2019
echo

# Task 5 : Deploy Staging Frontend
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 5] Building & Deploying Staging Frontend...${RESET_FORMAT}"

gcloud artifacts repositories create $FRONTEND_REPO \
  --repository-format=docker \
  --location=$REGION \
  --description="Repository for Frontend images" || true

cd ~/pet-theory/lab06/firebase-frontend || exit

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-staging:0.1 .

gcloud run deploy $FRONTEND_STAGING_SERVICE \
  --image=${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-staging:0.1 \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

STAGING_URL=$(gcloud run services describe $FRONTEND_STAGING_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

# Task 6 : Deploy Production Frontend
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 6] Updating app.js and Deploying Production Frontend...${RESET_FORMAT}"

cd ~/pet-theory/lab06/firebase-frontend/public || exit
# Upstream app.js uses local sample data by default. The old sed matched a
# non-existent URL and silently left the production UI disconnected from API.
python3 - "$SERVICE_URL" <<'PY'
from pathlib import Path
import sys
p = Path('app.js')
s = p.read_text()
old = 'const REST_API_SERVICE = "data/netflix.json"'
new = 'const REST_API_SERVICE = "' + sys.argv[1].rstrip('/') + '/2019"'
if old not in s and new not in s:
    raise SystemExit('ERROR: Unexpected app.js REST_API_SERVICE; refusing silent no-op')
p.write_text(s.replace(old, new, 1))
PY

cd .. || exit

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-production:0.1 .

gcloud run deploy $FRONTEND_PRODUCTION_SERVICE \
  --image=${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-production:0.1 \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

PROD_URL=$(gcloud run services describe $FRONTEND_PRODUCTION_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

# Final Message
echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT} 🎉 LAB COMPLETED SUCCESSFULLY! 🎉 ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo
echo "${GREEN_TEXT}REST API      : $SERVICE_URL${RESET_FORMAT}"
echo "${GREEN_TEXT}Staging UI    : $STAGING_URL${RESET_FORMAT}"
echo "${GREEN_TEXT}Production UI : $PROD_URL${RESET_FORMAT}"
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}📢 Subscribe to Dr Abhishek ❤️${RESET_FORMAT}"
echo "${RED_TEXT}${BOLD_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"
echo
echo "${YELLOW_TEXT}Static changes only; runtime/grader PASS is unverified. Click Check my progress.${RESET_FORMAT}"\033[0;96m'; WHITE_TEXT=

[[ -t 1 ]] && clear || true

# Welcome Banner
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}        🚀 WELCOME TO ePlus.DEV 🚀${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo
echo "${MAGENTA_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"
echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}         INITIATING EXECUTION...       ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo

gcloud auth list

# ── Project Setup ────────────────────────────────────────────
DEVSHELL_PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
[[ -n "$DEVSHELL_PROJECT_ID" && "$DEVSHELL_PROJECT_ID" != '(unset)' ]] || { echo 'ERROR: Set the active lab project.' >&2; exit 1; }
export DEVSHELL_PROJECT_ID

# ── Dynamically Fetch Region from Lab ────────────────────────
REGION="${REGION:-$(gcloud compute project-info describe --project="$DEVSHELL_PROJECT_ID" --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)}"
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
fi
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  [[ -t 0 ]] || { echo "ERROR: Set REGION to the lab region." >&2; exit 1; }
  read -r -p "Lab region: " REGION
fi
[[ "$REGION" =~ ^[a-z]+(-[a-z]+)+[0-9]+$ ]] || { echo "ERROR: Invalid region: $REGION" >&2; exit 1; }

export REGION

export DATASET_SERVICE=netflix-dataset-service
export FRONTEND_STAGING_SERVICE=frontend-staging-service
export FRONTEND_PRODUCTION_SERVICE=frontend-production-service
export AR_REPO=rest-api-repo
export FRONTEND_REPO=frontend-repo

echo "${YELLOW_TEXT}${BOLD_TEXT}Project : $DEVSHELL_PROJECT_ID${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT}Region  : $REGION${RESET_FORMAT}"
echo

# Enable required APIs
echo "${BLUE_TEXT}${BOLD_TEXT}Enabling APIs...${RESET_FORMAT}"
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  firestore.googleapis.com

# Task 1 : Create Firestore database
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 1] Creating Firestore database in $REGION...${RESET_FORMAT}"
if gcloud firestore databases describe --database='(default)' --project="$DEVSHELL_PROJECT_ID" >/dev/null 2>&1; then
  echo 'Firestore database already exists; reusing.'
else
  gcloud firestore databases create --location="$REGION" --project="$DEVSHELL_PROJECT_ID"
fi
sleep 10

# Task 2 : Import CSV into Firestore
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 2] Importing Netflix CSV into Firestore...${RESET_FORMAT}"
if [[ -e "$HOME/pet-theory" ]]; then
  [[ -d "$HOME/pet-theory/.git" ]] || { echo 'ERROR: Existing ~/pet-theory is not a Git checkout; refusing to delete it.' >&2; exit 1; }
  REPO_ORIGIN="$(git -C "$HOME/pet-theory" remote get-url origin)"
  [[ "$REPO_ORIGIN" == 'https://github.com/rosera/pet-theory.git' ]] || { echo "ERROR: Existing ~/pet-theory has unexpected origin: $REPO_ORIGIN" >&2; exit 1; }
else
  git clone https://github.com/rosera/pet-theory.git "$HOME/pet-theory"
fi

cd ~/pet-theory/lab06/firebase-import-csv/solution || exit
npm install
node index.js netflix_titles_original.csv

# Create Artifact Registry repository
echo
echo "${BLUE_TEXT}${BOLD_TEXT}Creating Artifact Registry repository: $AR_REPO...${RESET_FORMAT}"
gcloud artifacts repositories create $AR_REPO \
  --repository-format=docker \
  --location=$REGION \
  --description="REST API repo" || true

gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

# Task 3 : Deploy REST API v0.1
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 3] Building & Deploying REST API v0.1...${RESET_FORMAT}"
cd ~/pet-theory/lab06/firebase-rest-api/solution-01 || exit
npm install

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.1 .

gcloud run deploy $DATASET_SERVICE \
  --image ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.1 \
  --allow-unauthenticated \
  --max-instances=1 \
  --region=$REGION \
  --quiet

SERVICE_URL=$(gcloud run services describe $DATASET_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

echo "${GREEN_TEXT}Service URL: $SERVICE_URL${RESET_FORMAT}"
echo "${YELLOW_TEXT}Testing v0.1 endpoint...${RESET_FORMAT}"
curl -s $SERVICE_URL
echo

# Task 4 : Deploy REST API v0.2
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 4] Building & Deploying REST API v0.2...${RESET_FORMAT}"
cd ~/pet-theory/lab06/firebase-rest-api/solution-02 || exit
npm install

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.2 .

gcloud run deploy $DATASET_SERVICE \
  --image ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.2 \
  --allow-unauthenticated \
  --max-instances=1 \
  --region=$REGION \
  --quiet

SERVICE_URL=$(gcloud run services describe $DATASET_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

echo "${GREEN_TEXT}Service URL: $SERVICE_URL${RESET_FORMAT}"
echo "${YELLOW_TEXT}Testing v0.2 /2019 endpoint...${RESET_FORMAT}"
curl -s $SERVICE_URL/2019
echo

# Task 5 : Deploy Staging Frontend
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 5] Building & Deploying Staging Frontend...${RESET_FORMAT}"

gcloud artifacts repositories create $FRONTEND_REPO \
  --repository-format=docker \
  --location=$REGION \
  --description="Repository for Frontend images" || true

cd ~/pet-theory/lab06/firebase-frontend || exit

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-staging:0.1 .

gcloud run deploy $FRONTEND_STAGING_SERVICE \
  --image=${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-staging:0.1 \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

STAGING_URL=$(gcloud run services describe $FRONTEND_STAGING_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

# Task 6 : Deploy Production Frontend
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 6] Updating app.js and Deploying Production Frontend...${RESET_FORMAT}"

cd ~/pet-theory/lab06/firebase-frontend/public || exit
# Upstream app.js uses local sample data by default. The old sed matched a
# non-existent URL and silently left the production UI disconnected from API.
python3 - "$SERVICE_URL" <<'PY'
from pathlib import Path
import sys
p = Path('app.js')
s = p.read_text()
old = 'const REST_API_SERVICE = "data/netflix.json"'
new = 'const REST_API_SERVICE = "' + sys.argv[1].rstrip('/') + '/2019"'
if old not in s and new not in s:
    raise SystemExit('ERROR: Unexpected app.js REST_API_SERVICE; refusing silent no-op')
p.write_text(s.replace(old, new, 1))
PY

cd .. || exit

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-production:0.1 .

gcloud run deploy $FRONTEND_PRODUCTION_SERVICE \
  --image=${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-production:0.1 \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

PROD_URL=$(gcloud run services describe $FRONTEND_PRODUCTION_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

# Final Message
echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT} 🎉 LAB COMPLETED SUCCESSFULLY! 🎉 ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo
echo "${GREEN_TEXT}REST API      : $SERVICE_URL${RESET_FORMAT}"
echo "${GREEN_TEXT}Staging UI    : $STAGING_URL${RESET_FORMAT}"
echo "${GREEN_TEXT}Production UI : $PROD_URL${RESET_FORMAT}"
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}📢 Subscribe to Dr Abhishek ❤️${RESET_FORMAT}"
echo "${RED_TEXT}${BOLD_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"
echo
echo "${YELLOW_TEXT}Static changes only; runtime/grader PASS is unverified. Click Check my progress.${RESET_FORMAT}"\033[0;97m'; RESET_FORMAT=

[[ -t 1 ]] && clear || true

# Welcome Banner
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}        🚀 WELCOME TO ePlus.DEV 🚀${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo
echo "${MAGENTA_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"
echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}         INITIATING EXECUTION...       ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo

gcloud auth list

# ── Project Setup ────────────────────────────────────────────
DEVSHELL_PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
[[ -n "$DEVSHELL_PROJECT_ID" && "$DEVSHELL_PROJECT_ID" != '(unset)' ]] || { echo 'ERROR: Set the active lab project.' >&2; exit 1; }
export DEVSHELL_PROJECT_ID

# ── Dynamically Fetch Region from Lab ────────────────────────
REGION="${REGION:-$(gcloud compute project-info describe --project="$DEVSHELL_PROJECT_ID" --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)}"
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
fi
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  [[ -t 0 ]] || { echo "ERROR: Set REGION to the lab region." >&2; exit 1; }
  read -r -p "Lab region: " REGION
fi
[[ "$REGION" =~ ^[a-z]+(-[a-z]+)+[0-9]+$ ]] || { echo "ERROR: Invalid region: $REGION" >&2; exit 1; }

export REGION

export DATASET_SERVICE=netflix-dataset-service
export FRONTEND_STAGING_SERVICE=frontend-staging-service
export FRONTEND_PRODUCTION_SERVICE=frontend-production-service
export AR_REPO=rest-api-repo
export FRONTEND_REPO=frontend-repo

echo "${YELLOW_TEXT}${BOLD_TEXT}Project : $DEVSHELL_PROJECT_ID${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT}Region  : $REGION${RESET_FORMAT}"
echo

# Enable required APIs
echo "${BLUE_TEXT}${BOLD_TEXT}Enabling APIs...${RESET_FORMAT}"
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  firestore.googleapis.com

# Task 1 : Create Firestore database
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 1] Creating Firestore database in $REGION...${RESET_FORMAT}"
if gcloud firestore databases describe --database='(default)' --project="$DEVSHELL_PROJECT_ID" >/dev/null 2>&1; then
  echo 'Firestore database already exists; reusing.'
else
  gcloud firestore databases create --location="$REGION" --project="$DEVSHELL_PROJECT_ID"
fi
sleep 10

# Task 2 : Import CSV into Firestore
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 2] Importing Netflix CSV into Firestore...${RESET_FORMAT}"
if [[ -e "$HOME/pet-theory" ]]; then
  [[ -d "$HOME/pet-theory/.git" ]] || { echo 'ERROR: Existing ~/pet-theory is not a Git checkout; refusing to delete it.' >&2; exit 1; }
  REPO_ORIGIN="$(git -C "$HOME/pet-theory" remote get-url origin)"
  [[ "$REPO_ORIGIN" == 'https://github.com/rosera/pet-theory.git' ]] || { echo "ERROR: Existing ~/pet-theory has unexpected origin: $REPO_ORIGIN" >&2; exit 1; }
else
  git clone https://github.com/rosera/pet-theory.git "$HOME/pet-theory"
fi

cd ~/pet-theory/lab06/firebase-import-csv/solution || exit
npm install
node index.js netflix_titles_original.csv

# Create Artifact Registry repository
echo
echo "${BLUE_TEXT}${BOLD_TEXT}Creating Artifact Registry repository: $AR_REPO...${RESET_FORMAT}"
gcloud artifacts repositories create $AR_REPO \
  --repository-format=docker \
  --location=$REGION \
  --description="REST API repo" || true

gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

# Task 3 : Deploy REST API v0.1
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 3] Building & Deploying REST API v0.1...${RESET_FORMAT}"
cd ~/pet-theory/lab06/firebase-rest-api/solution-01 || exit
npm install

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.1 .

gcloud run deploy $DATASET_SERVICE \
  --image ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.1 \
  --allow-unauthenticated \
  --max-instances=1 \
  --region=$REGION \
  --quiet

SERVICE_URL=$(gcloud run services describe $DATASET_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

echo "${GREEN_TEXT}Service URL: $SERVICE_URL${RESET_FORMAT}"
echo "${YELLOW_TEXT}Testing v0.1 endpoint...${RESET_FORMAT}"
curl -s $SERVICE_URL
echo

# Task 4 : Deploy REST API v0.2
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 4] Building & Deploying REST API v0.2...${RESET_FORMAT}"
cd ~/pet-theory/lab06/firebase-rest-api/solution-02 || exit
npm install

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.2 .

gcloud run deploy $DATASET_SERVICE \
  --image ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.2 \
  --allow-unauthenticated \
  --max-instances=1 \
  --region=$REGION \
  --quiet

SERVICE_URL=$(gcloud run services describe $DATASET_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

echo "${GREEN_TEXT}Service URL: $SERVICE_URL${RESET_FORMAT}"
echo "${YELLOW_TEXT}Testing v0.2 /2019 endpoint...${RESET_FORMAT}"
curl -s $SERVICE_URL/2019
echo

# Task 5 : Deploy Staging Frontend
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 5] Building & Deploying Staging Frontend...${RESET_FORMAT}"

gcloud artifacts repositories create $FRONTEND_REPO \
  --repository-format=docker \
  --location=$REGION \
  --description="Repository for Frontend images" || true

cd ~/pet-theory/lab06/firebase-frontend || exit

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-staging:0.1 .

gcloud run deploy $FRONTEND_STAGING_SERVICE \
  --image=${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-staging:0.1 \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

STAGING_URL=$(gcloud run services describe $FRONTEND_STAGING_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

# Task 6 : Deploy Production Frontend
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 6] Updating app.js and Deploying Production Frontend...${RESET_FORMAT}"

cd ~/pet-theory/lab06/firebase-frontend/public || exit
# Upstream app.js uses local sample data by default. The old sed matched a
# non-existent URL and silently left the production UI disconnected from API.
python3 - "$SERVICE_URL" <<'PY'
from pathlib import Path
import sys
p = Path('app.js')
s = p.read_text()
old = 'const REST_API_SERVICE = "data/netflix.json"'
new = 'const REST_API_SERVICE = "' + sys.argv[1].rstrip('/') + '/2019"'
if old not in s and new not in s:
    raise SystemExit('ERROR: Unexpected app.js REST_API_SERVICE; refusing silent no-op')
p.write_text(s.replace(old, new, 1))
PY

cd .. || exit

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-production:0.1 .

gcloud run deploy $FRONTEND_PRODUCTION_SERVICE \
  --image=${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-production:0.1 \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

PROD_URL=$(gcloud run services describe $FRONTEND_PRODUCTION_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

# Final Message
echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT} 🎉 LAB COMPLETED SUCCESSFULLY! 🎉 ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo
echo "${GREEN_TEXT}REST API      : $SERVICE_URL${RESET_FORMAT}"
echo "${GREEN_TEXT}Staging UI    : $STAGING_URL${RESET_FORMAT}"
echo "${GREEN_TEXT}Production UI : $PROD_URL${RESET_FORMAT}"
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}📢 Subscribe to Dr Abhishek ❤️${RESET_FORMAT}"
echo "${RED_TEXT}${BOLD_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"
echo
echo "${YELLOW_TEXT}Static changes only; runtime/grader PASS is unverified. Click Check my progress.${RESET_FORMAT}"\033[0m'
  BOLD_TEXT=

[[ -t 1 ]] && clear || true

# Welcome Banner
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}        🚀 WELCOME TO ePlus.DEV 🚀${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo
echo "${MAGENTA_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"
echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}         INITIATING EXECUTION...       ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo

gcloud auth list

# ── Project Setup ────────────────────────────────────────────
DEVSHELL_PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
[[ -n "$DEVSHELL_PROJECT_ID" && "$DEVSHELL_PROJECT_ID" != '(unset)' ]] || { echo 'ERROR: Set the active lab project.' >&2; exit 1; }
export DEVSHELL_PROJECT_ID

# ── Dynamically Fetch Region from Lab ────────────────────────
REGION="${REGION:-$(gcloud compute project-info describe --project="$DEVSHELL_PROJECT_ID" --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)}"
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
fi
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  [[ -t 0 ]] || { echo "ERROR: Set REGION to the lab region." >&2; exit 1; }
  read -r -p "Lab region: " REGION
fi
[[ "$REGION" =~ ^[a-z]+(-[a-z]+)+[0-9]+$ ]] || { echo "ERROR: Invalid region: $REGION" >&2; exit 1; }

export REGION

export DATASET_SERVICE=netflix-dataset-service
export FRONTEND_STAGING_SERVICE=frontend-staging-service
export FRONTEND_PRODUCTION_SERVICE=frontend-production-service
export AR_REPO=rest-api-repo
export FRONTEND_REPO=frontend-repo

echo "${YELLOW_TEXT}${BOLD_TEXT}Project : $DEVSHELL_PROJECT_ID${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT}Region  : $REGION${RESET_FORMAT}"
echo

# Enable required APIs
echo "${BLUE_TEXT}${BOLD_TEXT}Enabling APIs...${RESET_FORMAT}"
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  firestore.googleapis.com

# Task 1 : Create Firestore database
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 1] Creating Firestore database in $REGION...${RESET_FORMAT}"
if gcloud firestore databases describe --database='(default)' --project="$DEVSHELL_PROJECT_ID" >/dev/null 2>&1; then
  echo 'Firestore database already exists; reusing.'
else
  gcloud firestore databases create --location="$REGION" --project="$DEVSHELL_PROJECT_ID"
fi
sleep 10

# Task 2 : Import CSV into Firestore
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 2] Importing Netflix CSV into Firestore...${RESET_FORMAT}"
if [[ -e "$HOME/pet-theory" ]]; then
  [[ -d "$HOME/pet-theory/.git" ]] || { echo 'ERROR: Existing ~/pet-theory is not a Git checkout; refusing to delete it.' >&2; exit 1; }
  REPO_ORIGIN="$(git -C "$HOME/pet-theory" remote get-url origin)"
  [[ "$REPO_ORIGIN" == 'https://github.com/rosera/pet-theory.git' ]] || { echo "ERROR: Existing ~/pet-theory has unexpected origin: $REPO_ORIGIN" >&2; exit 1; }
else
  git clone https://github.com/rosera/pet-theory.git "$HOME/pet-theory"
fi

cd ~/pet-theory/lab06/firebase-import-csv/solution || exit
npm install
node index.js netflix_titles_original.csv

# Create Artifact Registry repository
echo
echo "${BLUE_TEXT}${BOLD_TEXT}Creating Artifact Registry repository: $AR_REPO...${RESET_FORMAT}"
gcloud artifacts repositories create $AR_REPO \
  --repository-format=docker \
  --location=$REGION \
  --description="REST API repo" || true

gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

# Task 3 : Deploy REST API v0.1
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 3] Building & Deploying REST API v0.1...${RESET_FORMAT}"
cd ~/pet-theory/lab06/firebase-rest-api/solution-01 || exit
npm install

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.1 .

gcloud run deploy $DATASET_SERVICE \
  --image ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.1 \
  --allow-unauthenticated \
  --max-instances=1 \
  --region=$REGION \
  --quiet

SERVICE_URL=$(gcloud run services describe $DATASET_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

echo "${GREEN_TEXT}Service URL: $SERVICE_URL${RESET_FORMAT}"
echo "${YELLOW_TEXT}Testing v0.1 endpoint...${RESET_FORMAT}"
curl -s $SERVICE_URL
echo

# Task 4 : Deploy REST API v0.2
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 4] Building & Deploying REST API v0.2...${RESET_FORMAT}"
cd ~/pet-theory/lab06/firebase-rest-api/solution-02 || exit
npm install

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.2 .

gcloud run deploy $DATASET_SERVICE \
  --image ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.2 \
  --allow-unauthenticated \
  --max-instances=1 \
  --region=$REGION \
  --quiet

SERVICE_URL=$(gcloud run services describe $DATASET_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

echo "${GREEN_TEXT}Service URL: $SERVICE_URL${RESET_FORMAT}"
echo "${YELLOW_TEXT}Testing v0.2 /2019 endpoint...${RESET_FORMAT}"
curl -s $SERVICE_URL/2019
echo

# Task 5 : Deploy Staging Frontend
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 5] Building & Deploying Staging Frontend...${RESET_FORMAT}"

gcloud artifacts repositories create $FRONTEND_REPO \
  --repository-format=docker \
  --location=$REGION \
  --description="Repository for Frontend images" || true

cd ~/pet-theory/lab06/firebase-frontend || exit

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-staging:0.1 .

gcloud run deploy $FRONTEND_STAGING_SERVICE \
  --image=${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-staging:0.1 \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

STAGING_URL=$(gcloud run services describe $FRONTEND_STAGING_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

# Task 6 : Deploy Production Frontend
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 6] Updating app.js and Deploying Production Frontend...${RESET_FORMAT}"

cd ~/pet-theory/lab06/firebase-frontend/public || exit
# Upstream app.js uses local sample data by default. The old sed matched a
# non-existent URL and silently left the production UI disconnected from API.
python3 - "$SERVICE_URL" <<'PY'
from pathlib import Path
import sys
p = Path('app.js')
s = p.read_text()
old = 'const REST_API_SERVICE = "data/netflix.json"'
new = 'const REST_API_SERVICE = "' + sys.argv[1].rstrip('/') + '/2019"'
if old not in s and new not in s:
    raise SystemExit('ERROR: Unexpected app.js REST_API_SERVICE; refusing silent no-op')
p.write_text(s.replace(old, new, 1))
PY

cd .. || exit

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-production:0.1 .

gcloud run deploy $FRONTEND_PRODUCTION_SERVICE \
  --image=${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-production:0.1 \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

PROD_URL=$(gcloud run services describe $FRONTEND_PRODUCTION_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

# Final Message
echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT} 🎉 LAB COMPLETED SUCCESSFULLY! 🎉 ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo
echo "${GREEN_TEXT}REST API      : $SERVICE_URL${RESET_FORMAT}"
echo "${GREEN_TEXT}Staging UI    : $STAGING_URL${RESET_FORMAT}"
echo "${GREEN_TEXT}Production UI : $PROD_URL${RESET_FORMAT}"
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}📢 Subscribe to Dr Abhishek ❤️${RESET_FORMAT}"
echo "${RED_TEXT}${BOLD_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"
echo
echo "${YELLOW_TEXT}Static changes only; runtime/grader PASS is unverified. Click Check my progress.${RESET_FORMAT}"\033[1m'; UNDERLINE_TEXT=

[[ -t 1 ]] && clear || true

# Welcome Banner
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}        🚀 WELCOME TO ePlus.DEV 🚀${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo
echo "${MAGENTA_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"
echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}         INITIATING EXECUTION...       ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo

gcloud auth list

# ── Project Setup ────────────────────────────────────────────
DEVSHELL_PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
[[ -n "$DEVSHELL_PROJECT_ID" && "$DEVSHELL_PROJECT_ID" != '(unset)' ]] || { echo 'ERROR: Set the active lab project.' >&2; exit 1; }
export DEVSHELL_PROJECT_ID

# ── Dynamically Fetch Region from Lab ────────────────────────
REGION="${REGION:-$(gcloud compute project-info describe --project="$DEVSHELL_PROJECT_ID" --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)}"
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
fi
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  [[ -t 0 ]] || { echo "ERROR: Set REGION to the lab region." >&2; exit 1; }
  read -r -p "Lab region: " REGION
fi
[[ "$REGION" =~ ^[a-z]+(-[a-z]+)+[0-9]+$ ]] || { echo "ERROR: Invalid region: $REGION" >&2; exit 1; }

export REGION

export DATASET_SERVICE=netflix-dataset-service
export FRONTEND_STAGING_SERVICE=frontend-staging-service
export FRONTEND_PRODUCTION_SERVICE=frontend-production-service
export AR_REPO=rest-api-repo
export FRONTEND_REPO=frontend-repo

echo "${YELLOW_TEXT}${BOLD_TEXT}Project : $DEVSHELL_PROJECT_ID${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT}Region  : $REGION${RESET_FORMAT}"
echo

# Enable required APIs
echo "${BLUE_TEXT}${BOLD_TEXT}Enabling APIs...${RESET_FORMAT}"
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  firestore.googleapis.com

# Task 1 : Create Firestore database
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 1] Creating Firestore database in $REGION...${RESET_FORMAT}"
if gcloud firestore databases describe --database='(default)' --project="$DEVSHELL_PROJECT_ID" >/dev/null 2>&1; then
  echo 'Firestore database already exists; reusing.'
else
  gcloud firestore databases create --location="$REGION" --project="$DEVSHELL_PROJECT_ID"
fi
sleep 10

# Task 2 : Import CSV into Firestore
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 2] Importing Netflix CSV into Firestore...${RESET_FORMAT}"
if [[ -e "$HOME/pet-theory" ]]; then
  [[ -d "$HOME/pet-theory/.git" ]] || { echo 'ERROR: Existing ~/pet-theory is not a Git checkout; refusing to delete it.' >&2; exit 1; }
  REPO_ORIGIN="$(git -C "$HOME/pet-theory" remote get-url origin)"
  [[ "$REPO_ORIGIN" == 'https://github.com/rosera/pet-theory.git' ]] || { echo "ERROR: Existing ~/pet-theory has unexpected origin: $REPO_ORIGIN" >&2; exit 1; }
else
  git clone https://github.com/rosera/pet-theory.git "$HOME/pet-theory"
fi

cd ~/pet-theory/lab06/firebase-import-csv/solution || exit
npm install
node index.js netflix_titles_original.csv

# Create Artifact Registry repository
echo
echo "${BLUE_TEXT}${BOLD_TEXT}Creating Artifact Registry repository: $AR_REPO...${RESET_FORMAT}"
gcloud artifacts repositories create $AR_REPO \
  --repository-format=docker \
  --location=$REGION \
  --description="REST API repo" || true

gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

# Task 3 : Deploy REST API v0.1
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 3] Building & Deploying REST API v0.1...${RESET_FORMAT}"
cd ~/pet-theory/lab06/firebase-rest-api/solution-01 || exit
npm install

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.1 .

gcloud run deploy $DATASET_SERVICE \
  --image ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.1 \
  --allow-unauthenticated \
  --max-instances=1 \
  --region=$REGION \
  --quiet

SERVICE_URL=$(gcloud run services describe $DATASET_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

echo "${GREEN_TEXT}Service URL: $SERVICE_URL${RESET_FORMAT}"
echo "${YELLOW_TEXT}Testing v0.1 endpoint...${RESET_FORMAT}"
curl -s $SERVICE_URL
echo

# Task 4 : Deploy REST API v0.2
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 4] Building & Deploying REST API v0.2...${RESET_FORMAT}"
cd ~/pet-theory/lab06/firebase-rest-api/solution-02 || exit
npm install

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.2 .

gcloud run deploy $DATASET_SERVICE \
  --image ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.2 \
  --allow-unauthenticated \
  --max-instances=1 \
  --region=$REGION \
  --quiet

SERVICE_URL=$(gcloud run services describe $DATASET_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

echo "${GREEN_TEXT}Service URL: $SERVICE_URL${RESET_FORMAT}"
echo "${YELLOW_TEXT}Testing v0.2 /2019 endpoint...${RESET_FORMAT}"
curl -s $SERVICE_URL/2019
echo

# Task 5 : Deploy Staging Frontend
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 5] Building & Deploying Staging Frontend...${RESET_FORMAT}"

gcloud artifacts repositories create $FRONTEND_REPO \
  --repository-format=docker \
  --location=$REGION \
  --description="Repository for Frontend images" || true

cd ~/pet-theory/lab06/firebase-frontend || exit

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-staging:0.1 .

gcloud run deploy $FRONTEND_STAGING_SERVICE \
  --image=${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-staging:0.1 \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

STAGING_URL=$(gcloud run services describe $FRONTEND_STAGING_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

# Task 6 : Deploy Production Frontend
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 6] Updating app.js and Deploying Production Frontend...${RESET_FORMAT}"

cd ~/pet-theory/lab06/firebase-frontend/public || exit
# Upstream app.js uses local sample data by default. The old sed matched a
# non-existent URL and silently left the production UI disconnected from API.
python3 - "$SERVICE_URL" <<'PY'
from pathlib import Path
import sys
p = Path('app.js')
s = p.read_text()
old = 'const REST_API_SERVICE = "data/netflix.json"'
new = 'const REST_API_SERVICE = "' + sys.argv[1].rstrip('/') + '/2019"'
if old not in s and new not in s:
    raise SystemExit('ERROR: Unexpected app.js REST_API_SERVICE; refusing silent no-op')
p.write_text(s.replace(old, new, 1))
PY

cd .. || exit

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-production:0.1 .

gcloud run deploy $FRONTEND_PRODUCTION_SERVICE \
  --image=${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-production:0.1 \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

PROD_URL=$(gcloud run services describe $FRONTEND_PRODUCTION_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

# Final Message
echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT} 🎉 LAB COMPLETED SUCCESSFULLY! 🎉 ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo
echo "${GREEN_TEXT}REST API      : $SERVICE_URL${RESET_FORMAT}"
echo "${GREEN_TEXT}Staging UI    : $STAGING_URL${RESET_FORMAT}"
echo "${GREEN_TEXT}Production UI : $PROD_URL${RESET_FORMAT}"
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}📢 Subscribe to Dr Abhishek ❤️${RESET_FORMAT}"
echo "${RED_TEXT}${BOLD_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"
echo
echo "${YELLOW_TEXT}Static changes only; runtime/grader PASS is unverified. Click Check my progress.${RESET_FORMAT}"\033[4m'
else
  BLACK_TEXT=''; RED_TEXT=''; GREEN_TEXT=''; YELLOW_TEXT=''; BLUE_TEXT=''
  MAGENTA_TEXT=''; CYAN_TEXT=''; WHITE_TEXT=''; RESET_FORMAT=''
  BOLD_TEXT=''; UNDERLINE_TEXT=''
fi

[[ -t 1 ]] && clear || true

# Welcome Banner
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}        🚀 WELCOME TO ePlus.DEV 🚀${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo
echo "${MAGENTA_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"
echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}         INITIATING EXECUTION...       ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================${RESET_FORMAT}"
echo

gcloud auth list

# ── Project Setup ────────────────────────────────────────────
DEVSHELL_PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
[[ -n "$DEVSHELL_PROJECT_ID" && "$DEVSHELL_PROJECT_ID" != '(unset)' ]] || { echo 'ERROR: Set the active lab project.' >&2; exit 1; }
export DEVSHELL_PROJECT_ID

# ── Dynamically Fetch Region from Lab ────────────────────────
REGION="${REGION:-$(gcloud compute project-info describe --project="$DEVSHELL_PROJECT_ID" --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)}"
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
fi
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  [[ -t 0 ]] || { echo "ERROR: Set REGION to the lab region." >&2; exit 1; }
  read -r -p "Lab region: " REGION
fi
[[ "$REGION" =~ ^[a-z]+(-[a-z]+)+[0-9]+$ ]] || { echo "ERROR: Invalid region: $REGION" >&2; exit 1; }

export REGION

export DATASET_SERVICE=netflix-dataset-service
export FRONTEND_STAGING_SERVICE=frontend-staging-service
export FRONTEND_PRODUCTION_SERVICE=frontend-production-service
export AR_REPO=rest-api-repo
export FRONTEND_REPO=frontend-repo

echo "${YELLOW_TEXT}${BOLD_TEXT}Project : $DEVSHELL_PROJECT_ID${RESET_FORMAT}"
echo "${YELLOW_TEXT}${BOLD_TEXT}Region  : $REGION${RESET_FORMAT}"
echo

# Enable required APIs
echo "${BLUE_TEXT}${BOLD_TEXT}Enabling APIs...${RESET_FORMAT}"
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  firestore.googleapis.com

# Task 1 : Create Firestore database
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 1] Creating Firestore database in $REGION...${RESET_FORMAT}"
if gcloud firestore databases describe --database='(default)' --project="$DEVSHELL_PROJECT_ID" >/dev/null 2>&1; then
  echo 'Firestore database already exists; reusing.'
else
  gcloud firestore databases create --location="$REGION" --project="$DEVSHELL_PROJECT_ID"
fi
sleep 10

# Task 2 : Import CSV into Firestore
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 2] Importing Netflix CSV into Firestore...${RESET_FORMAT}"
if [[ -e "$HOME/pet-theory" ]]; then
  [[ -d "$HOME/pet-theory/.git" ]] || { echo 'ERROR: Existing ~/pet-theory is not a Git checkout; refusing to delete it.' >&2; exit 1; }
  REPO_ORIGIN="$(git -C "$HOME/pet-theory" remote get-url origin)"
  [[ "$REPO_ORIGIN" == 'https://github.com/rosera/pet-theory.git' ]] || { echo "ERROR: Existing ~/pet-theory has unexpected origin: $REPO_ORIGIN" >&2; exit 1; }
else
  git clone https://github.com/rosera/pet-theory.git "$HOME/pet-theory"
fi

cd ~/pet-theory/lab06/firebase-import-csv/solution || exit
npm install
node index.js netflix_titles_original.csv

# Create Artifact Registry repository
echo
echo "${BLUE_TEXT}${BOLD_TEXT}Creating Artifact Registry repository: $AR_REPO...${RESET_FORMAT}"
gcloud artifacts repositories create $AR_REPO \
  --repository-format=docker \
  --location=$REGION \
  --description="REST API repo" || true

gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

# Task 3 : Deploy REST API v0.1
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 3] Building & Deploying REST API v0.1...${RESET_FORMAT}"
cd ~/pet-theory/lab06/firebase-rest-api/solution-01 || exit
npm install

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.1 .

gcloud run deploy $DATASET_SERVICE \
  --image ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.1 \
  --allow-unauthenticated \
  --max-instances=1 \
  --region=$REGION \
  --quiet

SERVICE_URL=$(gcloud run services describe $DATASET_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

echo "${GREEN_TEXT}Service URL: $SERVICE_URL${RESET_FORMAT}"
echo "${YELLOW_TEXT}Testing v0.1 endpoint...${RESET_FORMAT}"
curl -s $SERVICE_URL
echo

# Task 4 : Deploy REST API v0.2
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 4] Building & Deploying REST API v0.2...${RESET_FORMAT}"
cd ~/pet-theory/lab06/firebase-rest-api/solution-02 || exit
npm install

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.2 .

gcloud run deploy $DATASET_SERVICE \
  --image ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$AR_REPO/rest-api:0.2 \
  --allow-unauthenticated \
  --max-instances=1 \
  --region=$REGION \
  --quiet

SERVICE_URL=$(gcloud run services describe $DATASET_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

echo "${GREEN_TEXT}Service URL: $SERVICE_URL${RESET_FORMAT}"
echo "${YELLOW_TEXT}Testing v0.2 /2019 endpoint...${RESET_FORMAT}"
curl -s $SERVICE_URL/2019
echo

# Task 5 : Deploy Staging Frontend
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 5] Building & Deploying Staging Frontend...${RESET_FORMAT}"

gcloud artifacts repositories create $FRONTEND_REPO \
  --repository-format=docker \
  --location=$REGION \
  --description="Repository for Frontend images" || true

cd ~/pet-theory/lab06/firebase-frontend || exit

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-staging:0.1 .

gcloud run deploy $FRONTEND_STAGING_SERVICE \
  --image=${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-staging:0.1 \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

STAGING_URL=$(gcloud run services describe $FRONTEND_STAGING_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

# Task 6 : Deploy Production Frontend
echo
echo "${CYAN_TEXT}${BOLD_TEXT}[Task 6] Updating app.js and Deploying Production Frontend...${RESET_FORMAT}"

cd ~/pet-theory/lab06/firebase-frontend/public || exit
# Upstream app.js uses local sample data by default. The old sed matched a
# non-existent URL and silently left the production UI disconnected from API.
python3 - "$SERVICE_URL" <<'PY'
from pathlib import Path
import sys
p = Path('app.js')
s = p.read_text()
old = 'const REST_API_SERVICE = "data/netflix.json"'
new = 'const REST_API_SERVICE = "' + sys.argv[1].rstrip('/') + '/2019"'
if old not in s and new not in s:
    raise SystemExit('ERROR: Unexpected app.js REST_API_SERVICE; refusing silent no-op')
p.write_text(s.replace(old, new, 1))
PY

cd .. || exit

gcloud builds submit \
  --tag ${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-production:0.1 .

gcloud run deploy $FRONTEND_PRODUCTION_SERVICE \
  --image=${REGION}-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$FRONTEND_REPO/frontend-production:0.1 \
  --platform=managed \
  --region=$REGION \
  --allow-unauthenticated \
  --max-instances=1 \
  --quiet

PROD_URL=$(gcloud run services describe $FRONTEND_PRODUCTION_SERVICE \
  --region=$REGION \
  --format='value(status.url)')

# Final Message
echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT} 🎉 LAB COMPLETED SUCCESSFULLY! 🎉 ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo
echo "${GREEN_TEXT}REST API      : $SERVICE_URL${RESET_FORMAT}"
echo "${GREEN_TEXT}Staging UI    : $STAGING_URL${RESET_FORMAT}"
echo "${GREEN_TEXT}Production UI : $PROD_URL${RESET_FORMAT}"
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}📢 Subscribe to Dr Abhishek ❤️${RESET_FORMAT}"
echo "${RED_TEXT}${BOLD_TEXT}${UNDERLINE_TEXT}https://eplus.dev${RESET_FORMAT}"
echo
echo "${YELLOW_TEXT}Static changes only; runtime/grader PASS is unverified. Click Check my progress.${RESET_FORMAT}"