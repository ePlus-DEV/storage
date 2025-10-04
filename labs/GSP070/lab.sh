#!/bin/bash
# =============================================================
# 🚀 Google App Engine Hello World Auto Deployment Script
# 📦 Version: 1.2
# ✨ Author: ePlus.DEV
# 🧑‍💻 Copyright (c) 2025 ePlus.DEV - All Rights Reserved
# =============================================================

# 🌈 Color definitions
GREEN="\033[1;32m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
BOLD="\033[1m"
RESET="\033[0m"

echo -e "${CYAN}"
echo "============================================================="
echo "🚀 Google App Engine Hello World Deployment (Go Runtime)"
echo "📦 Script by ePlus.DEV | © 2025 All Rights Reserved"
echo "============================================================="
echo -e "${RESET}"

export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export PROJECT_ID=$(gcloud config get-value project)

# 🌎 2. Set region
echo -e "${YELLOW}🌍 Setting region to $REGION...${RESET}"
gcloud config set compute/region $REGION

# 📡 3. Enable App Engine Admin API
echo -e "${YELLOW}🔧 Enabling App Engine Admin API...${RESET}"
gcloud services enable appengine.googleapis.com

# 📁 4. Clone the Hello World sample app
echo -e "${YELLOW}📦 Cloning Hello World sample app...${RESET}"
git clone https://github.com/GoogleCloudPlatform/golang-samples.git

# 🧭 5. Navigate to the app directory
cd golang-samples/appengine/go11x/helloworld || { echo -e "${RED}❌ Directory not found"; exit 1; }

# 🔨 6. Install App Engine Go SDK (if not installed)
echo -e "${YELLOW}🔧 Installing App Engine Go SDK...${RESET}"
sudo apt-get update -y
sudo apt-get install -y google-cloud-sdk-app-engine-go

# 🏗️ 7. Initialize App Engine (if not created)
echo -e "${YELLOW}⚙️ Initializing App Engine application...${RESET}"
gcloud app create --region=us-central || echo -e "${CYAN}✅ App Engine already initialized.${RESET}"

# 🚀 8. Deploy the application
echo -e "${GREEN}🚀 Deploying the app to Google App Engine...${RESET}"
gcloud app deploy --quiet

# 🌐 9. Open the deployed application
echo -e "${GREEN}🌐 Opening the deployed app in your browser...${RESET}"
gcloud app browse

# 📜 10. Done
echo -e "${CYAN}"
echo "============================================================="
echo "🎉 Deployment complete!"
echo "🌍 Check your browser — you should see the 'Hello, World!' page."
echo "✨ Script finished by ePlus.DEV - https://eplus.dev"
echo "============================================================="
echo -e "${RESET}"