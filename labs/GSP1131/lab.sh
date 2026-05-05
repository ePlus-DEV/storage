#!/bin/bash

# ==============================
# Artifact Registry Docker Lab
# ePlus.DEV
# ==============================

set -e

# Colors
RED='\033[0;91m'
GREEN='\033[0;92m'
YELLOW='\033[0;93m'
BLUE='\033[0;94m'
CYAN='\033[0;96m'
BOLD='\033[1m'
RESET='\033[0m'

REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
REPO_NAME="example-docker-repo"
REPO_DESC="Docker repository"
IMAGE_SOURCE="us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0"
IMAGE_NAME="sample-image"
IMAGE_TAG="tag1"

clear

echo -e "${CYAN}${BOLD}============================================================${RESET}"
echo -e "${CYAN}${BOLD}        Artifact Registry Docker Lab - Auto Script          ${RESET}"
echo -e "${CYAN}${BOLD}============================================================${RESET}"
echo ""

# Get Project ID
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [ -z "$PROJECT_ID" ]; then
  echo -e "${RED}ERROR: Cannot detect PROJECT_ID.${RESET}"
  echo -e "${YELLOW}Please make sure you are running this in Google Cloud Shell.${RESET}"
  exit 1
fi

echo -e "${BLUE}Project ID:${RESET} ${GREEN}$PROJECT_ID${RESET}"
echo -e "${BLUE}Region:${RESET} ${GREEN}$REGION${RESET}"
echo ""

# Enable required API
echo -e "${YELLOW}Enabling Artifact Registry API...${RESET}"
gcloud services enable artifactregistry.googleapis.com --project="$PROJECT_ID"

echo ""
echo -e "${YELLOW}Task 1: Creating Docker repository...${RESET}"

if gcloud artifacts repositories describe "$REPO_NAME" \
  --location="$REGION" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo -e "${GREEN}Repository already exists: $REPO_NAME${RESET}"
else
  gcloud artifacts repositories create "$REPO_NAME" \
    --repository-format=docker \
    --location="$REGION" \
    --description="$REPO_DESC" \
    --project="$PROJECT_ID"

  echo -e "${GREEN}Repository created successfully.${RESET}"
fi

echo ""
echo -e "${YELLOW}Listing repositories...${RESET}"
gcloud artifacts repositories list --project="$PROJECT_ID"

echo ""
echo -e "${YELLOW}Task 2: Configuring Docker authentication...${RESET}"
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
echo -e "${GREEN}Docker authentication configured.${RESET}"

echo ""
echo -e "${YELLOW}Task 3: Pulling sample image...${RESET}"
docker pull "$IMAGE_SOURCE"
echo -e "${GREEN}Sample image pulled successfully.${RESET}"

TARGET_IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${IMAGE_NAME}:${IMAGE_TAG}"

echo ""
echo -e "${YELLOW}Task 4: Tagging image...${RESET}"
docker tag "$IMAGE_SOURCE" "$TARGET_IMAGE"
echo -e "${GREEN}Image tagged as:${RESET}"
echo -e "${CYAN}$TARGET_IMAGE${RESET}"

echo ""
echo -e "${YELLOW}Pushing image to Artifact Registry...${RESET}"
docker push "$TARGET_IMAGE"
echo -e "${GREEN}Image pushed successfully.${RESET}"

echo ""
echo -e "${YELLOW}Task 5: Pulling image from Artifact Registry...${RESET}"
docker pull "$TARGET_IMAGE"
echo -e "${GREEN}Image pulled successfully from private repository.${RESET}"

echo ""
echo -e "${CYAN}${BOLD}============================================================${RESET}"
echo -e "${GREEN}${BOLD}Lab script completed successfully!${RESET}"
echo -e "${CYAN}${BOLD}============================================================${RESET}"
echo ""
echo -e "${BLUE}Repository:${RESET} ${GREEN}$REPO_NAME${RESET}"
echo -e "${BLUE}Image:${RESET} ${GREEN}$TARGET_IMAGE${RESET}"
echo ""
echo -e "${YELLOW}Now click 'Check my progress' in the lab page.${RESET}"