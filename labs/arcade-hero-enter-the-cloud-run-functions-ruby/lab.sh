#!/bin/bash

# ===============================
# 🪪 COPYRIGHT BANNER
# ===============================
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}"
echo "==========================================================="
echo "         🚀 GOOGLE CLOUD FUNCTIONS DEPLOY SCRIPT"
echo "==========================================================="
echo -e "${YELLOW} Author    : David Nguyen - ePlus.DEV"
echo -e "${YELLOW} Year      : $(date +%Y)"
echo -e "${YELLOW} Description: Auto-deploy Ruby 2nd Gen Cloud Function"
echo -e "${CYAN}===========================================================${NC}"

# ===============================
# ⚙️ CONFIG
# ===============================
FUNCTION_NAME="cf-demo"
REGION="us-west1"
RUNTIME="ruby32"
ENTRY_POINT="hello"
MAX_INSTANCES=5

echo -e "${BLUE}✅ Project:${NC} $(gcloud config get-value project)"
echo -e "${BLUE}📍 Region:${NC} $REGION"
echo -e "${BLUE}💎 Runtime:${NC} $RUNTIME"
echo -e "${BLUE}🧪 Function:${NC} $FUNCTION_NAME"

# ===============================
# 📁 SOURCE SETUP
# ===============================
rm -rf $FUNCTION_NAME
mkdir $FUNCTION_NAME
cd $FUNCTION_NAME

cat <<EOF > app.rb
require "functions_framework"

FunctionsFramework.http("$ENTRY_POINT") do |request|
  "Hello from Ruby Cloud Function 🚀"
end
EOF

cat <<EOF > Gemfile
source "https://rubygems.org"
gem "functions_framework", "~> 1.0"
EOF

# ===============================
# 💎 BUNDLER SETUP
# ===============================
echo -e "${GREEN}📦 Installing Bundler 2.7.2...${NC}"
gem uninstall bundler -a -q
gem install bundler -v 2.7.2 --no-document

# Tạo Gemfile.lock tương thích
echo -e "${GREEN}🔐 Creating Gemfile.lock...${NC}"
bundle lock

# ===============================
# 🛰 DEPLOY
# ===============================
echo -e "${CYAN}🚀 Deploying function...${NC}"
gcloud functions deploy $FUNCTION_NAME \
  --gen2 \
  --region=$REGION \
  --runtime=$RUNTIME \
  --trigger-http \
  --allow-unauthenticated \
  --max-instances=$MAX_INSTANCES \
  --entry-point=$ENTRY_POINT \
  --source=.

# ===============================
# 🌐 URL
# ===============================
echo -e "${GREEN}🌐 Function URL:${NC}"
gcloud functions describe $FUNCTION_NAME \
  --region=$REGION \
  --format="value(serviceConfig.uri)"

echo -e "${CYAN}"
echo "==========================================================="
echo -e "${GREEN}✨ Deployment Completed Successfully ✨${NC}"
echo -e "${YELLOW}© $(date +%Y) David Nguyen | MIT License"
echo -e "${CYAN}==========================================================="
