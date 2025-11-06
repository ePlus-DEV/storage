#!/bin/bash
set -e
# © 2025 ePlus.DEV — All Rights Reserved

# ===== COLORS =====
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
CYAN="\033[36m"
RESET="\033[0m"

echo -e "${CYAN}=== Auto-Detecting Project & Region ===${RESET}"

# Auto detect Project ID
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  PROJECT_ID=$(gcloud projects list --format="value(projectId)" --limit=1)
  gcloud config set project "$PROJECT_ID" >/dev/null
fi

# Auto detect Region
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
if [[ -z "$REGION" ]]; then
  REGION="us-east1"
fi

gcloud config set run/region "$REGION" >/dev/null

echo -e "${GREEN}✅ PROJECT_ID: $PROJECT_ID${RESET}"
echo -e "${GREEN}✅ REGION: $REGION${RESET}"

echo -e "${CYAN}=== Task 1: Create function files ===${RESET}"
mkdir -p gcf_hello_world && cd gcf_hello_world

echo -e "${BLUE}➤ Creating index.js...${RESET}"
cat > index.js <<'EOF'
const functions = require('@google-cloud/functions-framework');

// Register a CloudEvent callback with the Functions Framework that will
// be executed when the Pub/Sub trigger topic receives a message.
functions.cloudEvent('helloPubSub', cloudEvent => {
  // The Pub/Sub message is passed as the CloudEvent's data payload.
  const base64name = cloudEvent.data.message.data;

  const name = base64name
    ? Buffer.from(base64name, 'base64').toString()
    : 'World';

  console.log(`Hello, ${name}!`);
});
EOF

echo -e "${BLUE}➤ Creating package.json...${RESET}"
cat > package.json <<'EOF'
{
  "name": "gcf_hello_world",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0"
  }
}
EOF

echo -e "${YELLOW}Installing npm dependencies...${RESET}"
npm install

echo -e "${CYAN}=== Task 2: Deploying Function (No Prompt) ===${RESET}"
printf "n\n" | gcloud functions deploy nodejs-pubsub-function \
  --gen2 \
  --runtime=nodejs20 \
  --region="$REGION" \
  --source=. \
  --entry-point=helloPubSub \
  --trigger-topic cf-demo \
  --stage-bucket "${PROJECT_ID}-bucket" \
  --service-account "cloudfunctionsa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --allow-unauthenticated

echo -e "${GREEN}✅ Deployment complete. Checking function status...${RESET}"
gcloud functions describe nodejs-pubsub-function --region="$REGION"

echo -e "${CYAN}=== Task 3: Testing the function ===${RESET}"
gcloud pubsub topics publish cf-demo --message="Cloud Function Gen2"

echo -e "${CYAN}=== Task 4: Viewing logs ===${RESET}"
echo -e "${YELLOW}(If logs do not show yet, wait 5–10 minutes and run again)${RESET}"
gcloud functions logs read nodejs-pubsub-function --region="$REGION"

echo -e "${GREEN}🎉 DONE! Script executed successfully — ePlus.DEV${RESET}"