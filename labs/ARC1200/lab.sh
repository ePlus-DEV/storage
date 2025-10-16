#!/bin/bash
# ==========================================
#  🌟 GOOGLE CLOUD STORAGE BUCKET SCRIPT
#  🪣 Create Public & Private Buckets
#  ✍️ Author: David Nguyen
# ==========================================

# ====== Color Variables ======
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ====== Bucket Names ======
export PROJECT_ID=$(gcloud config get-value project)
echo -e "${YELLOW}Using GCP Project ID:${NC} $PROJECT_ID"
PUBLIC_BUCKET="${PROJECT_ID}-public-bucket"
PRIVATE_BUCKET="${PROJECT_ID}-private-bucket"
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

# ====== Public Bucket ======
echo -e "\n${CYAN}${BOLD}🪣 STEP 1: Creating PUBLIC bucket...${NC}"
gsutil mb -l $REGION gs://$PUBLIC_BUCKET/

echo -e "${YELLOW}Granting public access (allUsers:objectViewer)...${NC}"
gsutil iam ch allUsers:objectViewer gs://$PUBLIC_BUCKET/

echo -e "${GREEN}✅ Public bucket created successfully:${NC} gs://$PUBLIC_BUCKET/"
echo -e "${YELLOW}Checking IAM policy for public bucket...${NC}"
gsutil iam get gs://$PUBLIC_BUCKET/

# ====== Test File for Public Bucket ======
echo -e "\n${CYAN}Uploading test file to public bucket...${NC}"
echo "This is a PUBLIC bucket test file." > test_public.txt
gsutil cp test_public.txt gs://$PUBLIC_BUCKET/

echo -e "${GREEN}🌍 Test URL:${NC} https://storage.googleapis.com/$PUBLIC_BUCKET/test_public.txt"

# ====== Private Bucket ======
echo -e "\n${CYAN}${BOLD}🔐 STEP 2: Creating PRIVATE bucket...${NC}"
gsutil mb -l $REGION gs://$PRIVATE_BUCKET/

echo -e "${YELLOW}Removing public access (no allUsers)...${NC}"
echo '{}' > iam-empty.json
gsutil iam set iam-empty.json gs://$PRIVATE_BUCKET/

echo -e "${GREEN}✅ Private bucket created successfully:${NC} gs://$PRIVATE_BUCKET/"
echo -e "${YELLOW}Checking IAM policy for private bucket...${NC}"
gsutil iam get gs://$PRIVATE_BUCKET/

# ====== Test File for Private Bucket ======
echo -e "\n${CYAN}Uploading test file to private bucket...${NC}"
echo "This is a PRIVATE bucket test file." > test_private.txt
gsutil cp test_private.txt gs://$PRIVATE_BUCKET/

echo -e "${RED}🔒 Test URL:${NC} https://storage.googleapis.com/$PRIVATE_BUCKET/test_private.txt"
echo -e "${YELLOW}(Expected: AccessDenied if accessed without permission)${NC}"

# ====== Done ======
echo -e "\n${GREEN}${BOLD}🎉 All steps completed successfully! - ePlus.DEV${NC}"
echo -e "${CYAN}Public Bucket:${NC} $PUBLIC_BUCKET"
echo -e "${CYAN}Private Bucket:${NC} $PRIVATE_BUCKET"