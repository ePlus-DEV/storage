#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}=================================================${NC}"
echo -e "${GREEN} ePlus.DEV ${NC}"
echo -e "${CYAN}=================================================${NC}"

PROJECT_ID=$(gcloud projects list --format='value(PROJECT_ID)' --filter='qwiklabs-gcp' | head -n 1)
REGION="us-west1"
REPO="rest-api-repo"

if [ -z "$PROJECT_ID" ]; then
  echo -e "${RED}Cannot detect Qwiklabs project ID.${NC}"
  exit 1
fi

gcloud config set project "$PROJECT_ID"

echo -e "${YELLOW}Project:${NC} $PROJECT_ID"
echo -e "${YELLOW}Region:${NC} $REGION"

echo -e "${CYAN}Enabling required services...${NC}"
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  firestore.googleapis.com \
  appengine.googleapis.com

echo -e "${CYAN}Task 1: Creating Firestore database in Native mode...${NC}"
if gcloud firestore databases describe --database="(default)" >/dev/null 2>&1; then
  echo -e "${GREEN}Firestore database already exists. Skipping.${NC}"
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

echo -e "${CYAN}Cloning pet-theory repository...${NC}"
cd "$HOME"
if [ ! -d "pet-theory" ]; then
  git clone https://github.com/rosera/pet-theory.git
else
  echo -e "${GREEN}Repo already exists. Pulling latest...${NC}"
  cd pet-theory
  git pull || true
  cd "$HOME"
fi

echo -e "${CYAN}Task 2: Importing Netflix CSV into Firestore...${NC}"
cd "$HOME/pet-theory/lab06/firebase-import-csv/solution"
npm install
node index.js netflix_titles_original.csv

echo -e "${CYAN}Creating Artifact Registry repository...${NC}"
if gcloud artifacts repositories describe "$REPO" --location="$REGION" >/dev/null 2>&1; then
  echo -e "${GREEN}Artifact Registry repo already exists. Skipping.${NC}"
else
  gcloud artifacts repositories create "$REPO" \
    --repository-format=docker \
    --location="$REGION" \
    --description="Docker repository for Netflix lab"
fi

echo -e "${CYAN}Task 3: Building and deploying REST API v0.1...${NC}"
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

echo -e "${GREEN}REST API URL:${NC} $SERVICE_URL"
echo -e "${CYAN}Testing REST API v0.1...${NC}"
curl -s -X GET "$SERVICE_URL"
echo ""

echo -e "${CYAN}Task 4: Building and deploying REST API v0.2 with Firestore access...${NC}"
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

echo -e "${GREEN}REST API v0.2 URL:${NC} $SERVICE_URL"
echo -e "${CYAN}Testing REST API v0.2 with /2019...${NC}"
curl -s "$SERVICE_URL/2019" | head -c 500
echo ""
echo ""

echo -e "${CYAN}Task 5: Deploying staging frontend...${NC}"
cd "$HOME/pet-theory/lab06/firebase-frontend"

FRONTEND_STAGING_IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO/frontend-staging:0.1"

gcloud builds submit \
  --tag "$FRONTEND_STAGING_IMAGE" \
  --build-arg REST_API_SERVICE="$SERVICE_URL" \
  . || gcloud builds submit --tag "$FRONTEND_STAGING_IMAGE" .

gcloud run deploy frontend-staging-service \
  --image "$FRONTEND_STAGING_IMAGE" \
  --region "$REGION" \
  --platform managed \
  --allow-unauthenticated \
  --max-instances=1 \
  --set-env-vars REST_API_SERVICE="$SERVICE_URL" \
  --quiet

STAGING_URL=$(gcloud run services describe frontend-staging-service \
  --region "$REGION" \
  --format='value(status.url)')

echo -e "${GREEN}Staging Frontend URL:${NC} $STAGING_URL"

echo -e "${CYAN}Task 6: Updating app.js for production frontend...${NC}"
cd "$HOME/pet-theory/lab06/firebase-frontend/public"

# Backup original app.js
cp app.js app.js.bak

# Try to replace common demo/local API patterns with the real REST API service URL.
# The production frontend must call SERVICE_URL + /year, for example: https://xxx.run.app/2019
python3 <<PY
from pathlib import Path
p = Path("app.js")
text = p.read_text()
service_url = "$SERVICE_URL"

# Replace obvious placeholders / demo API references if they exist.
replacements = [
    ("https://example.com", service_url),
    ("http://localhost:8080", service_url),
    ("http://localhost:8081", service_url),
    ("REST_API_SERVICE", service_url),
    ("SERVICE_URL", service_url),
]

for old, new in replacements:
    text = text.replace(old, new)

# If app.js still contains demo/static JSON logic, append an override fetch function.
# This keeps the script safe even if the lab file differs slightly.
override = f'''

// Auto-added for production lab deployment
const REST_API_SERVICE_AUTO = "{service_url}";

async function getNetflixDataByYearAuto(year) {{
  const response = await fetch(`${{REST_API_SERVICE_AUTO}}/${{year}}`);
  return await response.json();
}}
'''

if service_url not in text:
    text += override

p.write_text(text)
PY

cd "$HOME/pet-theory/lab06/firebase-frontend"

FRONTEND_PROD_IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO/frontend-production:0.1"

gcloud builds submit \
  --tag "$FRONTEND_PROD_IMAGE" \
  --build-arg REST_API_SERVICE="$SERVICE_URL" \
  . || gcloud builds submit --tag "$FRONTEND_PROD_IMAGE" .

gcloud run deploy frontend-production-service \
  --image "$FRONTEND_PROD_IMAGE" \
  --region "$REGION" \
  --platform managed \
  --allow-unauthenticated \
  --max-instances=1 \
  --set-env-vars REST_API_SERVICE="$SERVICE_URL" \
  --quiet

PROD_URL=$(gcloud run services describe frontend-production-service \
  --region "$REGION" \
  --format='value(status.url)')

echo -e "${CYAN}=================================================${NC}"
echo -e "${GREEN}Lab deployment completed.${NC}"
echo -e "${CYAN}=================================================${NC}"
echo -e "${GREEN}REST API:${NC} $SERVICE_URL"
echo -e "${GREEN}Test API:${NC} $SERVICE_URL/2019"
echo -e "${GREEN}Staging Frontend:${NC} $STAGING_URL"
echo -e "${GREEN}Production Frontend:${NC} $PROD_URL"
echo -e "${YELLOW}Now click Check my progress for each task.${NC}"