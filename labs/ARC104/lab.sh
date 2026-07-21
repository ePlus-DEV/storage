#!/bin/bash
clear

# ==============================================================================
# ORBIT OF OPS COMMAND CENTER: ARC104 CHALLENGE LAB AUTOMATION
# ==============================================================================
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
MAGENTA=$(tput setaf 5)
WHITE=$(tput setaf 7)
BOLD=$(tput bold)
RESET=$(tput sgr0)

  echo "${CYAN}${BOLD}"
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║         CLOUD RUN FUNCTIONS - CHALLENGE LAB                 ║"
  echo "║                    Copyright © ePlus.DEV                     ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo "${RESET}"
echo "${MAGENTA}${BOLD}>>> INITIATING ARC104: CHALLENGE LAB PIPELINE <<<${RESET}"
echo ""

# ==============================================================================
# PHASE 1: COLLECTING DYNAMIC LAB VARIABLES
# ==============================================================================
echo "${YELLOW}${BOLD}Please look at your Qwiklabs instruction panel and provide the requested names:${RESET}"
read -p "Enter the Cloud Storage Function Name (from Task 2): " STORAGE_FUNCTION
read -p "Enter the HTTP Function Name (from Task 3): " HTTP_FUNCTION
echo ""

export PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null)
if [ -z "$REGION" ]; then export REGION="us-central1"; fi

gcloud config set compute/region $REGION --quiet

# ==============================================================================
# PHASE 2: API ACTIVATION & IAM SETUP
# ==============================================================================
echo "${YELLOW}[*] Enabling Google Cloud Service APIs...${RESET}"
gcloud services enable \
  artifactregistry.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  eventarc.googleapis.com \
  run.googleapis.com \
  logging.googleapis.com \
  pubsub.googleapis.com \
  --quiet

echo -e "\n${YELLOW}[*] Provisioning Eventarc & Pub/Sub Service Role Bindings...${RESET}"
SERVICE_ACCOUNT=$(gsutil kms serviceaccount -p $PROJECT_NUMBER)
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$SERVICE_ACCOUNT" --role="roles/pubsub.publisher" --quiet
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com" --role="roles/eventarc.eventReceiver" --quiet

echo -e "\n${MAGENTA}${BOLD}[!] Waiting 90 seconds for Eventarc IAM permissions to propagate to prevent API crashes...${RESET}"
sleep 90

# ==============================================================================
# PHASE 3: TASK 1 & 2 - STORAGE BUCKET & STORAGE FUNCTION
# ==============================================================================
echo -e "\n${BLUE}[*] Creating Cloud Storage Bucket (Task 1)...${RESET}"
export BUCKET="gs://$PROJECT_ID"
gsutil mb -l $REGION $BUCKET 2>/dev/null || true

echo -e "\n${CYAN}[*] Generating Source Code for Storage Function...${RESET}"
mkdir -p ~/storage_function && cd ~/storage_function

cat << EOF > index.js
const functions = require('@google-cloud/functions-framework');

functions.cloudEvent('$STORAGE_FUNCTION', (cloudevent) => {
  console.log('A new event in your Cloud Storage bucket has been logged!');
  console.log(cloudevent);
});
EOF

cat << 'EOF' > package.json
{
  "name": "nodejs-functions-gen2-codelab",
  "version": "0.0.1",
  "main": "index.js",
  "dependencies": {
    "@google-cloud/functions-framework": "^2.0.0"
  }
}
EOF

echo -e "\n${MAGENTA}[*] Deploying Storage Function (Task 2)...${RESET}"
MAX_RETRIES=3
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if gcloud functions deploy $STORAGE_FUNCTION \
    --gen2 \
    --runtime=nodejs24 \
    --entry-point=$STORAGE_FUNCTION \
    --source=. \
    --region=$REGION \
    --trigger-bucket=$BUCKET \
    --trigger-location=$REGION \
    --max-instances=2 \
    --quiet; then
    break
  else
    RETRY_COUNT=$((RETRY_COUNT+1))
    echo -e "\n${YELLOW}Eventarc API glitch detected. Retrying deployment in 30 seconds...${RESET}"
    sleep 30
  fi
done

# Fire test event for Task 2 verification
echo "Triggering the function..." > test-event.txt
gsutil cp test-event.txt $BUCKET/test-event.txt 2>/dev/null

# ==============================================================================
# PHASE 4: TASK 3 - HTTP FUNCTION WITH MIN INSTANCES
# ==============================================================================
echo -e "\n${CYAN}[*] Generating Source Code for HTTP Function...${RESET}"
mkdir -p ~/http_function && cd ~/http_function

cat << EOF > index.js
const functions = require('@google-cloud/functions-framework');

functions.http('$HTTP_FUNCTION', (req, res) => {
  res.status(200).send('HTTP function (2nd gen) has been called!');
});
EOF

cat << 'EOF' > package.json
{
  "name": "nodejs-functions-gen2-codelab",
  "version": "0.0.1",
  "main": "index.js",
  "dependencies": {
    "@google-cloud/functions-framework": "^2.0.0"
  }
}
EOF

echo -e "\n${MAGENTA}[*] Deploying HTTP Function with Scale Settings (Task 3)...${RESET}"
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if gcloud functions deploy $HTTP_FUNCTION \
    --gen2 \
    --runtime=nodejs24 \
    --entry-point=$HTTP_FUNCTION \
    --source=. \
    --region=$REGION \
    --trigger-http \
    --allow-unauthenticated \
    --min-instances=1 \
    --max-instances=2 \
    --quiet; then
    break
  else
    RETRY_COUNT=$((RETRY_COUNT+1))
    echo -e "\n${YELLOW}API glitch detected. Retrying deployment in 30 seconds...${RESET}"
    sleep 30
  fi
done

echo -e "\n${GREEN}${BOLD}====================================================================${RESET}"
echo "${GREEN}${BOLD}>>> PIPELINE COMPLETE! YOU CAN NOW CLICK 'CHECK MY PROGRESS' <<<${RESET}"
echo "${GREEN}${BOLD}====================================================================${RESET}"
