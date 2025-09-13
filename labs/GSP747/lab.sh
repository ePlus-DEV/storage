#!/bin/bash

# Colors
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# Env variables
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
export REGION=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-region])")
export GITHUB_USERNAME=$(gh api user -q ".login")

echo "${CYAN}${BOLD}==> Project: $PROJECT_ID | Number: $PROJECT_NUMBER | Region: $REGION${RESET}"

cd ~/my_hugo_site || exit 1

# 1. Fix config.toml (remove duplicate theme lines)
echo "${YELLOW}Cleaning config.toml...${RESET}"
if grep -q '^theme' config.toml; then
  THEME_LINE=$(grep '^theme' config.toml | head -n 1)
  grep -v '^theme' config.toml > config.fixed.toml
  echo "$THEME_LINE" >> config.fixed.toml
  mv config.fixed.toml config.toml
  echo "${GREEN}✔ config.toml cleaned (only one theme line).${RESET}"
fi

# 2. Ensure firebase.json exists
if [ ! -f "firebase.json" ]; then
  echo "${YELLOW}firebase.json not found → creating minimal config...${RESET}"
  cat > firebase.json <<EOF
{
  "hosting": {
    "public": "public",
    "ignore": [
      "firebase.json",
      "**/.*",
      "**/node_modules/**"
    ]
  }
}
EOF

  cat > .firebaserc <<EOF
{
  "projects": {
    "default": "$PROJECT_ID"
  }
}
EOF
  echo "${GREEN}✔ firebase.json and .firebaserc created.${RESET}"
else
  echo "${CYAN}firebase.json already exists. Skipping.${RESET}"
fi

# 3. Commit & push fixes
echo "${YELLOW}Pushing fixes to GitHub...${RESET}"
git add config.toml firebase.json .firebaserc || true
git commit -m "Fix config.toml and add Firebase hosting config" || true
git push origin main

# 4. Wait for Cloud Build to trigger
echo "${YELLOW}Waiting for Cloud Build to start...${RESET}"
sleep 20
LATEST_BUILD_ID=$(gcloud builds list --region=$REGION --format="value(ID)" --limit=1)
echo "${CYAN}${BOLD}==> Latest Build ID: $LATEST_BUILD_ID${RESET}"

# 5. Stream logs until build finishes
echo "${YELLOW}Streaming Cloud Build logs (1–3 mins)...${RESET}"
gcloud builds log $LATEST_BUILD_ID --region=$REGION

# 6. Extract Firebase Hosting URL
echo "${GREEN}Looking for Firebase Hosting URL...${RESET}"
gcloud builds log $LATEST_BUILD_ID --region=$REGION | grep "Hosting URL" || echo "⚠️ No Hosting URL found. Wait a few minutes for CDN to update."
