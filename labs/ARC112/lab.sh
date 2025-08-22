#!/usr/bin/env bash
# ============================================================================
#  ePlus.DEV Dataplex Setup Script
#  Copyright (c) 2025 ePlus.DEV. All rights reserved.
#  License: For educational/lab use only. No warranty of any kind.
# ============================================================================

set -euo pipefail



# Set text styles
YELLOW=$(tput setaf 3)
BOLD=$(tput bold)
RESET=$(tput sgr0)

echo "Please set the below values correctly"
read -p "${YELLOW}${BOLD}Enter the MESSAGE: ${RESET}" MESSAGE

# Export variables after collecting input
export MESSAGE

export ZONE="$(gcloud compute instances list --project=$DEVSHELL_PROJECT_ID --format='value(ZONE)')"

export REGION=${ZONE%-*}

gcloud services enable appengine.googleapis.com

sleep 10

echo $ZONE
echo $REGION

gcloud compute ssh "lab-setup" --zone=$ZONE --project=$DEVSHELL_PROJECT_ID --quiet --command "git clone https://github.com/GoogleCloudPlatform/python-docs-samples.git"

git clone https://github.com/GoogleCloudPlatform/python-docs-samples.git
cd python-docs-samples/appengine/standard_python3/hello_world

sed -i "32c\    return \"$MESSAGE\"" main.py

if [ "$REGION" == "us-east" ]; then
  REGION="us-east1"
fi

gcloud app create --region=$REGION

gcloud app deploy --quiet

gcloud compute ssh "lab-setup" --zone=$ZONE --project=$DEVSHELL_PROJECT_ID --quiet --command "git clone https://github.com/GoogleCloudPlatform/python-docs-samples.git"

ok "Lab Complete!"
echo "© 2025 ePlus.DEV"