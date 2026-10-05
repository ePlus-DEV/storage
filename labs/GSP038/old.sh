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

#----------------------------------------------------start--------------------------------------------------#

echo "${YELLOW}${BOLD}Starting${RESET}" "${GREEN}${BOLD}Execution - ePlus.DEV${RESET}"

export ZONE=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-zone])")

if [ -z "$ZONE" ]; then
  echo "${RED}${BOLD}Error:${RESET} Could not determine default zone."
  exit 1
fi

cat > prepare_disk.sh <<'EOF_END'
#!/bin/bash

set -e

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [ -z "$PROJECT_ID" ]; then
  echo "Project ID not found."
  exit 1
fi

echo "Using project: $PROJECT_ID"

gcloud services enable apikeys.googleapis.com language.googleapis.com --quiet

EXISTING_KEY_NAME=$(gcloud services api-keys list \
  --format="value(name)" \
  --filter="displayName=awesome" \
  --limit=1)

if [ -z "$EXISTING_KEY_NAME" ]; then
  echo "Creating API key..."
  gcloud services api-keys create --display-name="awesome" --quiet
fi

KEY_NAME=$(gcloud services api-keys list \
  --format="value(name)" \
  --filter="displayName=awesome" \
  --limit=1)

if [ -z "$KEY_NAME" ]; then
  echo "Failed to get API key name."
  exit 1
fi

API_KEY=$(gcloud services api-keys get-key-string "$KEY_NAME" --format="value(keyString)")

if [ -z "$API_KEY" ]; then
  echo "Failed to get API key string."
  exit 1
fi

echo "API_KEY: $API_KEY"

cat <<EOF > request.json
{
  "document": {
    "type": "PLAIN_TEXT",
    "content": "Joanne Rowling, who writes under the pen names J. K. Rowling and Robert Galbraith, is a British novelist and screenwriter who wrote the Harry Potter fantasy series."
  },
  "encodingType": "UTF8"
}
EOF

curl "https://language.googleapis.com/v1/documents:analyzeEntities?key=${API_KEY}" \
  -s -X POST \
  -H "Content-Type: application/json; charset=utf-8" \
  --data-binary @request.json > result.json

echo "===== API RESPONSE ====="
cat result.json
echo
EOF_END

gcloud compute scp prepare_disk.sh linux-instance:/tmp \
  --project=$DEVSHELL_PROJECT_ID \
  --zone=$ZONE \
  --quiet

gcloud compute ssh linux-instance \
  --project=$DEVSHELL_PROJECT_ID \
  --zone=$ZONE \
  --quiet \
  --command="chmod +x /tmp/prepare_disk.sh && bash /tmp/prepare_disk.sh"

echo "${RED}${BOLD}Congratulations${RESET}" "${WHITE}${BOLD}for${RESET}" "${GREEN}${BOLD}Completing the Lab !!! - ePlus.DEV${RESET}"

#-----------------------------------------------------end----------------------------------------------------------#