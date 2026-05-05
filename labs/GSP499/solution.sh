#!/bin/bash
# ============================================
# 🌟 Google Cloud IAP Deployment Script
# ✅ Updated to use Python 3.11 (python311)
# ============================================

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

COLORS=(
  "$(tput setaf 1)"  # Red
  "$(tput setaf 2)"  # Green
  "$(tput setaf 3)"  # Yellow
  "$(tput setaf 4)"  # Blue
  "$(tput setaf 5)"  # Magenta
  "$(tput setaf 6)"  # Cyan
)

CREATE_MESSAGES=(
  "Time to register your app: "
  "Let's begin by creating OAuth consent credentials: "
  "Set up your client app in Google Cloud: "
  "Start by defining your OAuth screen here: "
)

IAP_MESSAGES=(
  "Now head over to configure IAP: "
  "Enable and manage IAP settings below: "
  "Secure your app with Identity-Aware Proxy: "
  "Next stop: IAP console "
)

BOLD=`tput bold`
RESET=`tput sgr0`

TEXT_COLORS=($RED $GREEN $YELLOW $BLUE $MAGENTA $CYAN)
BG_COLORS=($BG_RED $BG_GREEN $BG_YELLOW $BG_BLUE $BG_MAGENTA $BG_CYAN)

RANDOM_TEXT_COLOR=${TEXT_COLORS[$RANDOM % ${#TEXT_COLORS[@]}]}
RANDOM_BG_COLOR=${BG_COLORS[$RANDOM % ${#BG_COLORS[@]}]}

#----------------------------------------------------start--------------------------------------------------#

echo "${RANDOM_BG_COLOR}${RANDOM_TEXT_COLOR}${BOLD}Starting Execution - ePlus.DEV${RESET}"

# Step 0: set compute region
echo "${BOLD}${GREEN}Setting compute region...${RESET}"
export REGION=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-region])")

# Step 1: Enable IAP API
echo "${BOLD}${RED}Enabling IAP API...${RESET}"
gcloud services enable iap.googleapis.com

# Step 2: Download sample application
echo "${BOLD}${GREEN}Downloading sample application...${RESET}"
gsutil cp gs://spls/gsp499/user-authentication-with-iap.zip .

# Step 3: Unzip the downloaded file
echo "${BOLD}${YELLOW}Unzipping the application package...${RESET}"
unzip user-authentication-with-iap.zip

# Step 4: Navigate to HelloWorld directory
echo "${BOLD}${BLUE}Navigating to 1-HelloWorld directory...${RESET}"
cd user-authentication-with-iap/1-HelloWorld

# Step 5: Enable Flex API
echo "${BOLD}${RED}Enabling Flex API...${RESET}"
gcloud services enable appengineflex.googleapis.com

# Step 6: Modify app.yaml for Python 3.11
echo "${BOLD}${GREEN}Updating app.yaml to Python 3.11...${RESET}"
sed -i 's/python37/python311/g' app.yaml
sed -i 's/python39/python311/g' app.yaml

# Step 7: Create App Engine app
echo "${BOLD}${MAGENTA}Creating App Engine application...${RESET}"
gcloud app create --region=$REGION

# Step 8: Deploy HelloWorld application with retry
echo "${BOLD}${RED}Deploying HelloWorld application...${RESET}"
deploy_function() {
  yes | gcloud app deploy
}

deploy_success=false
while [ "$deploy_success" = false ]; do
  if deploy_function; then
    echo "${BOLD}${GREEN}Function deployed successfully...${RESET}"
    deploy_success=true
  else
    echo "${BOLD}${YELLOW}Retrying deployment in 10 seconds...${RESET}"
    sleep 10
  fi
done

# Step 9: Navigate to 2-HelloUser
echo "${BOLD}${MAGENTA}Navigating to 2-HelloUser...${RESET}"
cd ~/user-authentication-with-iap/2-HelloUser

# Step 10: Modify app.yaml for Python 3.11
echo "${BOLD}${GREEN}Updating app.yaml to Python 3.11...${RESET}"
sed -i 's/python37/python311/g' app.yaml
sed -i 's/python39/python311/g' app.yaml

# Step 11: Deploy 2-HelloUser application with retry
echo "${BOLD}${RED}Deploying 2-HelloUser application...${RESET}"
deploy_function() {
  yes | gcloud app deploy
}

deploy_success=false
while [ "$deploy_success" = false ]; do
  if deploy_function; then
    echo "${BOLD}${GREEN}Function deployed successfully...${RESET}"
    deploy_success=true
  else
    echo "${BOLD}${YELLOW}Retrying deployment in 10 seconds...${RESET}"
    sleep 10
  fi
done

# Step 12: Navigate to 3-HelloVerifiedUser
echo "${BOLD}${MAGENTA}Navigating to 3-HelloVerifiedUser...${RESET}"
cd ~/user-authentication-with-iap/3-HelloVerifiedUser

# Step 13: Modify app.yaml for Python 3.11
echo "${BOLD}${GREEN}Updating app.yaml to Python 3.11...${RESET}"
sed -i 's/python37/python311/g' app.yaml
sed -i 's/python39/python311/g' app.yaml

# Step 14: Deploy 3-HelloUser application with retry
echo "${BOLD}${RED}Deploying 3-HelloUser application...${RESET}"
deploy_function() {
  yes | gcloud app deploy
}

deploy_success=false
while [ "$deploy_success" = false ]; do
  if deploy_function; then
    echo "${BOLD}${GREEN}Function deployed successfully...${RESET}"
    deploy_success=true
  else
    echo "${BOLD}${YELLOW}Retrying deployment in 10 seconds...${RESET}"
    sleep 10
  fi
done

# Step 15: Generate application details JSON
echo "${BOLD}${BLUE}Generating application details JSON...${RESET}"
EMAIL="$(gcloud config get-value core/account 2>/dev/null)"
LINK=$(gcloud app browse 2>/dev/null | grep -o 'https://.*')
LINKU=${LINK#https://}
PROJECT_ID="$DEVSHELL_PROJECT_ID"

cat > details.json << EOF
{
  "App name": "IAP Example",
  "Application home page": "$LINK",
  "Application privacy Policy link": "$LINK/privacy",
  "Authorized domains": "$LINKU",
  "Developer Contact Information": "$EMAIL"
}
EOF

jq -r 'to_entries[] | "\(.key): \(.value)"' details.json | while IFS=: read -r key value; do
  COLOR=${COLORS[$RANDOM % ${#COLORS[@]}]}
  printf "${BOLD}${COLOR}%-35s${RESET}: %s\n" "$key" "$value"
done

# OAuth client creation
echo
RANDOM_MSG1=${CREATE_MESSAGES[$RANDOM % ${#CREATE_MESSAGES[@]}]}
COLOR1=${COLORS[$RANDOM % ${#COLORS[@]}]}
echo "${BOLD}${COLOR1}${RANDOM_MSG1}${RESET}""https://console.cloud.google.com/auth/branding?project=$DEVSHELL_PROJECT_ID"

# IAP configuration
echo
RANDOM_MSG2=${IAP_MESSAGES[$RANDOM % ${#IAP_MESSAGES[@]}]}
COLOR2=${COLORS[$RANDOM % ${#COLORS[@]}]}
echo "${BOLD}${COLOR2}${RANDOM_MSG2}${RESET}""https://console.cloud.google.com/security/iap?project=$DEVSHELL_PROJECT_ID"

# Congratulatory message
function random_congrats() {
    MESSAGES=(
        "${GREEN}Congratulations! You’ve successfully completed the lab!${RESET}"
        "${CYAN}Well done! Your hard work has paid off!${RESET}"
        "${YELLOW}Amazing job! You’re awesome!${RESET}"
        "${BLUE}Outstanding! Your dedication shows!${RESET}"
        "${MAGENTA}Great work! You’ve mastered it!${RESET}"
    )
    RANDOM_INDEX=$((RANDOM % ${#MESSAGES[@]}))
    echo -e "${BOLD}${MESSAGES[$RANDOM_INDEX]}"
}

random_congrats
echo -e "\n"

# Cleanup temp files
cd
remove_files() {
    for file in *; do
        if [[ "$file" == gsp* || "$file" == arc* || "$file" == shell* ]]; then
            if [[ -f "$file" ]]; then
                rm "$file"
                echo "File removed: $file"
            fi
        fi
    done
}
remove_files