#!/bin/bash
# ╔═══════════════════════════════════════════════════════════════╗
# ║        🌐 GOOGLE CLOUD SKILLS BOOST — LOAD BALANCER LAB       ║
# ║        Author: ePlus Dev | All Rights Reserved © 2025         ║
# ║        GitHub: https://eplus.dev | Made with 💻❤️            ║
# ╚═══════════════════════════════════════════════════════════════╝

# 🎨 Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 STARTING LOAD BALANCER DEPLOYMENT...${NC}\n"

# 📌 Get Project ID
PROJECT_ID=$(gcloud config get-value project)
OLD_BUCKET="${PROJECT_ID}-bucket"
NEW_BUCKET="${PROJECT_ID}-new"

echo -e "${YELLOW}📁 Project ID:${NC} ${GREEN}$PROJECT_ID${NC}"
echo -e "${YELLOW}🪣 Old Bucket:${NC} ${GREEN}$OLD_BUCKET${NC}"
echo -e "${YELLOW}🆕 New Bucket:${NC} ${GREEN}$NEW_BUCKET${NC}\n"

# 🪣 1. Create a new bucket
echo -e "${BLUE}➡️  Creating new bucket in europe-west4...${NC}"
gcloud storage buckets create gs://$NEW_BUCKET \
    --location=europe-west4
echo -e "${GREEN}✅ New bucket created successfully!${NC}\n"

# 🌍 2. Make the bucket public
echo -e "${BLUE}➡️  Making the bucket publicly readable...${NC}"
gcloud storage buckets add-iam-policy-binding gs://$NEW_BUCKET \
  --member=allUsers \
  --role=roles/storage.objectViewer
echo -e "${GREEN}✅ Bucket is now public!${NC}\n"

# 🔁 3. Sync content from the old bucket
echo -e "${BLUE}➡️  Syncing content from $OLD_BUCKET to $NEW_BUCKET...${NC}"
gcloud storage rsync -r gs://$OLD_BUCKET gs://$NEW_BUCKET
echo -e "${GREEN}✅ Content synced successfully!${NC}\n"

# 🌐 4. Create Backend Bucket & Load Balancer
echo -e "${BLUE}➡️  Creating Backend Bucket...${NC}"
gcloud compute backend-buckets create my-backend \
  --gcs-bucket-name=$NEW_BUCKET \
  --enable-cdn
echo -e "${GREEN}✅ Backend Bucket created!${NC}\n"

echo -e "${BLUE}➡️  Creating URL Map...${NC}"
gcloud compute url-maps create my-url-map \
  --default-backend-bucket=my-backend
echo -e "${GREEN}✅ URL Map created!${NC}\n"

echo -e "${BLUE}➡️  Creating HTTP Proxy...${NC}"
gcloud compute target-http-proxies create my-http-proxy \
  --url-map=my-url-map
echo -e "${GREEN}✅ Proxy created!${NC}\n"

echo -e "${BLUE}➡️  Reserving Global IP Address...${NC}"
gcloud compute addresses create lb-ipv4-1 \
  --ip-version=IPV4 \
  --global
echo -e "${GREEN}✅ Global IP reserved!${NC}\n"

echo -e "${BLUE}➡️  Creating Forwarding Rule...${NC}"
gcloud compute forwarding-rules create http-content-rule \
  --address=lb-ipv4-1 \
  --global \
  --target-http-proxy=my-http-proxy \
  --ports=80
echo -e "${GREEN}✅ Forwarding Rule created successfully!${NC}\n"

# 🧪 5. Create Health Check
echo -e "${BLUE}➡️  Creating HTTP Health Check...${NC}"
gcloud compute health-checks create http my-health-check \
  --request-path="/" \
  --port 80
echo -e "${GREEN}✅ Health Check created!${NC}\n"

# 🌍 6. Get Public IP
LB_IP=$(gcloud compute addresses describe lb-ipv4-1 \
  --global \
  --format="get(address)")

echo -e "${YELLOW}🌐 Access your website at:${NC} ${GREEN}http://$LB_IP${NC}\n"
echo -e "${BLUE}⏳ Please wait 2–3 minutes for the content to propagate via CDN...${NC}\n"

# ✅ Done
echo -e "${GREEN}🎉 Load Balancer deployment completed successfully!${NC}"
echo -e "${YELLOW}📝 Tip: Click 'Check my progress' in the lab to validate.${NC}"
