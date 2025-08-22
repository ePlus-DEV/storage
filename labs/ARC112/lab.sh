#!/usr/bin/env bash
# ============================================================================
#  ePlus.DEV Dataplex Setup Script
#  Copyright (c) 2025 ePlus.DEV. All rights reserved.
#  License: For educational/lab use only. No warranty of any kind.
# ============================================================================

set -euo pipefail

# ---- Colors ----------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ---- Helpers ---------------------------------------------------------------
die() { echo -e "${RED}✖ $*${NC}" >&2; exit 1; }
info() { echo -e "${YELLOW}➜ $*${NC}"; }
ok()   { echo -e "${GREEN}✔ $*${NC}"; }
hl()   { echo -e "${CYAN}$*${NC}"; }

# ---- Require gcloud/gsutil -------------------------------------------------
command -v gcloud >/dev/null 2>&1 || die "gcloud not found in PATH"
command -v gsutil >/dev/null 2>&1 || die "gsutil not found in PATH"

# ---- Show active account ---------------------------------------------------
info "Active account:"
gcloud auth list || true

# ---- Ask for ZONE --------------------------------------------------------
# Set the ZONE variable
ZONE="$(gcloud compute instances list --project=$DEVSHELL_PROJECT_ID --format='value(ZONE)')"
[[ -n "$REGION" ]] || die "REGION must not be empty"

# Enable the App Engine API
gcloud services enable appengine.googleapis.com


sleep 10
# SSH into the lab-setup instance and enable the App Engine API
gcloud compute ssh --zone "$ZONE" "lab-setup" --project "$DEVSHELL_PROJECT_ID" --quiet --command "gcloud services enable appengine.googleapis.com && git clone https://github.com/GoogleCloudPlatform/python-docs-samples.git
"

# Clone the sample repository
git clone https://github.com/GoogleCloudPlatform/python-docs-samples.git

# Navigate to the hello_world directory
cd python-docs-samples/appengine/standard_python3/hello_world

# Update the main.py file with the message
sed -i "32c\    return \"$MESSAGE\"" main.py

# Check and update the REGION variable
if [ "$REGION" == "us-west" ]; then
  REGION="us-west1"
fi

# Create the App Engine app with the specified service account and region
gcloud app create --service-account=$DEVSHELL_PROJECT_ID@$DEVSHELL_PROJECT_ID.iam.gserviceaccount.com --region=$REGION

# Deploy the App Engine app
gcloud app deploy --quiet


gcloud compute ssh --zone "$ZONE" "lab-setup" --project "$DEVSHELL_PROJECT_ID" --quiet --command "gcloud services enable appengine.googleapis.com && git clone https://github.com/GoogleCloudPlatform/python-docs-samples.git
"

# ---- Summary ---------------------------------------------------------------
echo -e "\n${GREEN}✔ Lab Complete!${NC}\n"
cat <<EOF
© 2025 ePlus.DEV
EOF