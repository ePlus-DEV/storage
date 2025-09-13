clear

#!/bin/bash
# Define color variables

BLACK=`tput setaf 0`
RED=`tput setaf 1`
GREEN=`tput setaf 2`
YELLOW=`tput setaf 3`
BLUE=`tput setaf 4`
MAGENTA=`tput setaf 5`
CYAN=`tput setaf 6`
WHITE=`tput setaf 7`

BG_BLACK=`tput setab 0`
BG_RED=`tput setab 1`
BG_GREEN=`tput setab 2`
BG_YELLOW=`tput setab 3`
BG_BLUE=`tput setab 4`
BG_MAGENTA=`tput setab 5`
BG_CYAN=`tput setab 6`
BG_WHITE=`tput setab 7`

BOLD=`tput bold`
RESET=`tput sgr0`

# Array of color codes excluding black and white
TEXT_COLORS=($RED $GREEN $YELLOW $BLUE $MAGENTA $CYAN)
BG_COLORS=($BG_RED $BG_GREEN $BG_YELLOW $BG_BLUE $BG_MAGENTA $BG_CYAN)

# Pick random colors
RANDOM_TEXT_COLOR=${TEXT_COLORS[$RANDOM % ${#TEXT_COLORS[@]}]}
RANDOM_BG_COLOR=${BG_COLORS[$RANDOM % ${#BG_COLORS[@]}]}

#----------------------------------------------------start--------------------------------------------------#

echo "${RANDOM_BG_COLOR}${RANDOM_TEXT_COLOR}${BOLD}Starting Execution - ePlus.DEV${RESET}"

# Config
GOOGLE_CLOUD_PROJECT="qwiklabs-gcp-01-xxxxxxx"   # thay bằng Project ID của bạn
GOOGLE_CLOUD_REGION="us-central1"
AR_REPO="gemini-repo"
SERVICE_NAME="gemini-streamlit-app"

echo "=== Clone source code ==="
git clone https://github.com/GoogleCloudPlatform/generative-ai.git --depth=1
cd generative-ai/gemini/sample-apps/gemini-streamlit-cloudrun

echo "=== Setup Python env ==="
python3 -m venv gemini-streamlit
source gemini-streamlit/bin/activate
pip install -r requirements.txt

echo "=== Create Artifact Registry repo ==="
gcloud artifacts repositories create "$AR_REPO" \
  --location="$GOOGLE_CLOUD_REGION" \
  --repository-format=Docker || echo "Repo có thể đã tồn tại, bỏ qua..."

echo "=== Build & push image ==="
gcloud builds submit \
  --tag "$GOOGLE_CLOUD_REGION-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/$AR_REPO/$SERVICE_NAME"

echo "=== Deploy to Cloud Run ==="
gcloud run deploy "$SERVICE_NAME" \
  --port=8080 \
  --image="$GOOGLE_CLOUD_REGION-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/$AR_REPO/$SERVICE_NAME" \
  --allow-unauthenticated \
  --region=$GOOGLE_CLOUD_REGION \
  --platform=managed \
  --project=$GOOGLE_CLOUD_PROJECT \
  --set-env-vars=GOOGLE_CLOUD_PROJECT=$GOOGLE_CLOUD_PROJECT,GOOGLE_CLOUD_REGION=$GOOGLE_CLOUD_REGION

echo "${RANDOM_BG_COLOR}${RANDOM_TEXT_COLOR}${BOLD}=== Done! Check Cloud Run service URL above. - ePlus.DEV ===${RESET}"