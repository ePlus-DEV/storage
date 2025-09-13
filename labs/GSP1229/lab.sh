#!/bin/bash
set -e

# Define color variables
BLACK=`tput setaf 0`; RED=`tput setaf 1`; GREEN=`tput setaf 2`; YELLOW=`tput setaf 3`
BLUE=`tput setaf 4`; MAGENTA=`tput setaf 5`; CYAN=`tput setaf 6`; WHITE=`tput setaf 7`
BG_RED=`tput setab 1`; BG_GREEN=`tput setab 2`; BG_YELLOW=`tput setab 3`
BG_BLUE=`tput setab 4`; BG_MAGENTA=`tput setab 5`; BG_CYAN=`tput setab 6`
BOLD=`tput bold`; RESET=`tput sgr0`

TEXT_COLORS=($RED $GREEN $YELLOW $BLUE $MAGENTA $CYAN)
BG_COLORS=($BG_RED $BG_GREEN $BG_YELLOW $BG_BLUE $BG_MAGENTA $BG_CYAN)
RANDOM_TEXT_COLOR=${TEXT_COLORS[$RANDOM % ${#TEXT_COLORS[@]}]}
RANDOM_BG_COLOR=${BG_COLORS[$RANDOM % ${#BG_COLORS[@]}]}

banner () {
  local color=$1
  local msg=$2
  echo ""
  echo "${color}${BOLD}============================================================${RESET}"
  echo "${color}${BOLD}$msg${RESET}"
  echo "${color}${BOLD}============================================================${RESET}"
  echo ""
}

# 🚀 Start
banner "$RANDOM_BG_COLOR$RANDOM_TEXT_COLOR" "🚀 Starting Execution - ePlus.DEV"

# Config
export PROJECT_ID=$(gcloud config get-value project)
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
[[ -z "$REGION" ]] && { echo "${RED}⚠️ REGION not detected, please input:${RESET}"; read -r REGION; }
export AR_REPO="gemini-repo"
export SERVICE_NAME="gemini-streamlit-app"

banner "$CYAN" "🎯 Step 1: Clone source code"
rm -rf generative-ai
git clone https://github.com/GoogleCloudPlatform/generative-ai.git --depth=1
cd generative-ai/gemini/sample-apps/gemini-streamlit-cloudrun

banner "$MAGENTA" "🔧 Step 2: Setup Python environment"
python3 -m venv gemini-streamlit
source gemini-streamlit/bin/activate
pip install -r requirements.txt

banner "$YELLOW" "📦 Step 3: Create Artifact Registry repo"
gcloud artifacts repositories create "$AR_REPO" \
  --location="$REGION" \
  --repository-format=Docker || echo "${YELLOW}⚠️ Repo may already exist, ignore...${RESET}"

banner "$BLUE" "⚙️ Step 4: Build & push Docker image"
gcloud builds submit \
  --tag "$REGION-docker.pkg.dev/$PROJECT_ID/$AR_REPO/$SERVICE_NAME"

banner "$GREEN" "🚀 Step 5: Deploy to Cloud Run"
gcloud run deploy "$SERVICE_NAME" \
  --port=8080 \
  --image="$REGION-docker.pkg.dev/$PROJECT_ID/$AR_REPO/$SERVICE_NAME" \
  --allow-unauthenticated \
  --region=$REGION \
  --platform=managed \
  --project=$PROJECT_ID \
  --set-env-vars=PROJECT_ID=$PROJECT_ID,REGION=$REGION

banner "$BG_GREEN$WHITE" "🎉 Done! Check Cloud Run service URL above. - ePlus.DEV"