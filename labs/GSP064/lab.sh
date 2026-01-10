# Define color variables
BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'
ORANGE_TEXT=$'\033[38;5;214m'  

read -p "${ORANGE_TEXT}${BOLD_TEXT}Enter USERNAME_2 (example: student-04-c2c81ceb6cb1@qwiklabs.net): ${RESET_FORMAT}" REGION_1

gsutil mb -l us -b on gs://$DEVSHELL_PROJECT_ID

echo "subscribe to quicklab " > sample.txt

gsutil cp sample.txt gs://$DEVSHELL_PROJECT_ID

gcloud projects remove-iam-policy-binding $DEVSHELL_PROJECT_ID \
  --member=user:$USERNAME_2 \
  --role=roles/viewer

gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID \
  --member=user:$USERNAME_2 \
  --role=roles/storage.objectViewer