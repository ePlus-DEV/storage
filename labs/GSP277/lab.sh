#!/bin/bash

# Enhanced Color Definitions
BLACK=$(tput setaf 0)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)

BOLD=$(tput bold)
RESET=$(tput sgr0)
UNDERLINE=$(tput smul)

clear

# Display Header
echo "${BLUE}${BOLD}============================================${RESET}"
echo "${BLUE}${BOLD}                   EPLUS.DEV                ${RESET}"
echo "${BLUE}${BOLD}============================================${RESET}"
echo

# Get Project ID
echo "${YELLOW}${BOLD}Step 1: Fetching Your Project ID${RESET}"
export BUCKET="$(gcloud config get-value project)"
if [ -z "$BUCKET" ]; then
  echo "${RED}✗ Failed to get project ID. Please ensure you're authenticated.${RESET}"
  exit 1
fi
echo "${GREEN}✓ Your Project ID: ${BUCKET}${RESET}"
echo

# Create Cloud Storage Bucket
echo "${YELLOW}${BOLD}Step 2: Creating Cloud Storage Bucket${RESET}"
BUCKET_NAME="${BUCKET}-bucket-$(date +%s)"
echo "Creating bucket: gs://${BUCKET_NAME}"

gsutil mb -p $BUCKET -l US gs://$BUCKET_NAME || {
  echo "${RED}✗ Failed to create bucket. Common issues:"
  echo "1. Bucket name must be globally unique"
  echo "2. Insufficient permissions"
  echo "3. Invalid project ID${RESET}"
  exit 1
}
echo "${GREEN}✓ Bucket created successfully: gs://${BUCKET_NAME}${RESET}"
echo

# Download Demo Image
echo "${YELLOW}${BOLD}Step 3: Downloading Demo Image${RESET}"
IMAGE_URL="https://raw.githubusercontent.com/Itsabhishek7py/GoogleCloudSkillsboost/main/APIs%20Explorer%20Qwik%20Start/demo-image.jpg"
IMAGE_FILE="demo-image-$(date +%s).jpg"

if ! curl -s -o $IMAGE_FILE -L "$IMAGE_URL"; then
  echo "${YELLOW}⚠️ Using fallback image URL${RESET}"
  IMAGE_URL="https://storage.googleapis.com/gweb-cloudblog-publish/images/Google_Cloud.max-1100x1100.jpg"
  curl -s -o $IMAGE_FILE -L "$IMAGE_URL" || {
    echo "${RED}✗ Failed to download image${RESET}"
    exit 1
  }
fi
echo "${GREEN}✓ Image downloaded: ${IMAGE_FILE}${RESET}"
echo

# Upload Image to Bucket
echo "${YELLOW}${BOLD}Step 4: Uploading Image to Bucket${RESET}"
gsutil cp $IMAGE_FILE gs://$BUCKET_NAME/demo-image.jpg || {
  echo "${RED}✗ Failed to upload image to bucket${RESET}"
  exit 1
}
echo "${GREEN}✓ Image uploaded to gs://${BUCKET_NAME}/demo-image.jpg${RESET}"
echo

# Set Public Access
echo "${YELLOW}${BOLD}Step 5: Configuring Public Access${RESET}"
gsutil acl ch -u AllUsers:R gs://$BUCKET_NAME/demo-image.jpg || {
  echo "${RED}✗ Failed to set public access${RESET}"
  exit 1
}
echo "${GREEN}✓ Image is now publicly accessible${RESET}"
echo

# Generate Public URL
PUBLIC_URL="https://storage.googleapis.com/${BUCKET_NAME}/demo-image.jpg"
echo "${YELLOW}${BOLD}Public Access URL:${RESET}"
echo "${BLUE}${UNDERLINE}${PUBLIC_URL}${RESET}"
echo

# Completion Message
echo "${GREEN}${BOLD}============================================${RESET}"
echo "${GREEN}${BOLD}   CLOUD STORAGE LAB COMPLETED SUCCESSFULLY!${RESET}"
echo "${GREEN}${BOLD}============================================${RESET}"
echo
echo "${WHITE}${BOLD}Congratulations on completing the lab!${RESET}"
echo
echo "${BLUE}${UNDERLINE}https://eplus.dev${RESET}"