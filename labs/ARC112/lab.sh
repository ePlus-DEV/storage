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
NC='\033[0m'

die() { echo -e "${RED}✖ $*${NC}" >&2; exit 1; }
info() { echo -e "${YELLOW}➜ $*${NC}"; }
ok()   { echo -e "${GREEN}✔ $*${NC}"; }

command -v gcloud >/dev/null 2>&1 || die "gcloud not found in PATH"
command -v gsutil >/dev/null 2>&1 || die "gsutil not found in PATH"

info "Active account:"
gcloud auth list || true

read -rp "$(echo -e "${CYAN}Enter MESSAGE: ${NC}")" MESSAGE
[[ -n "$MESSAGE" ]] || die "MESSAGE must not be empty"

gcloud services enable appengine.googleapis.com

# Detect zone & region
ZONE=$(gcloud compute instances list --filter="name=('lab-setup')" --format 'csv[no-heading](zone)')
REGION="${ZONE%-*}"
PROJECT_ID=$(gcloud config get-value project)

# Prepare VM
cat > prepare_disk.sh <<'EOF'
git clone https://github.com/GoogleCloudPlatform/python-docs-samples.git
cd python-docs-samples/appengine/standard_python3/hello_world
EOF

gcloud compute scp prepare_disk.sh lab-setup:/tmp --project="$PROJECT_ID" --zone="$ZONE" --quiet
gcloud compute ssh lab-setup --project="$PROJECT_ID" --zone="$ZONE" --quiet --command="bash /tmp/prepare_disk.sh"

git clone https://github.com/GoogleCloudPlatform/python-docs-samples.git
cd python-docs-samples/appengine/standard_python3/hello_world

gcloud app create --region="$REGION" --quiet

sed -i "s/Hello World!/${MESSAGE}/g" main.py
gcloud app deploy --quiet

ok "Lab Complete!"
echo "© 2025 ePlus.DEV"