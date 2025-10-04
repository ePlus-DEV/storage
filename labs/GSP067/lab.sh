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

export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

gcloud auth list
gcloud services enable appengine.googleapis.com

git clone https://github.com/GoogleCloudPlatform/python-docs-samples.git

cd python-docs-samples/appengine/standard_python3/hello_world

sudo apt install python3 -y
sudo apt install python3.11-venv -y
python3 -m venv create myvenv
source myvenv/bin/activate


sed -i '32c\    return "Hello, Cruel World!"' main.py

sleep 30

gcloud app create --region=$REGION

gcloud app deploy --quiet