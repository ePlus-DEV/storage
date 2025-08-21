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

# ---- Ask for REGION --------------------------------------------------------
read -rp "$(echo -e "${CYAN}Enter REGION [us-central1]: ${NC}")" INPUT_REGION
REGION="${INPUT_REGION:-us-central1}"
[[ -n "$REGION" ]] || die "REGION must not be empty"

# ---- Detect PROJECT_ID (ACTIVE) -------------------------------------------
PROJECT_ID="$(gcloud projects list --filter='lifecycleState:ACTIVE' --format='value(projectId)' | head -n1 || true)"
[[ -n "${PROJECT_ID:-}" ]] || die "No ACTIVE project found. Please Start/Resume your Qwiklabs lab."

hl "Using PROJECT_ID: $PROJECT_ID"
hl "Using REGION   : $REGION"

# ---- Set config ------------------------------------------------------------
gcloud config set project "$PROJECT_ID" >/dev/null
gcloud config set compute/region "$REGION" >/dev/null
ok "Configured gcloud project and region."

# ---- Enable APIs -----------------------------------------------------------
info "Enabling APIs (Data Catalog, Dataplex)..."
gcloud services enable datacatalog.googleapis.com dataplex.googleapis.com --project="$PROJECT_ID"
ok "APIs enabled."

# ---- Dataplex: Lake --------------------------------------------------------
LAKE="customer-engagements"
if gcloud dataplex lakes describe "$LAKE" --location="$REGION" >/dev/null 2>&1; then
  ok "Lake '$LAKE' already exists. Skipping."
else
  info "Creating Lake '$LAKE'..."
  gcloud dataplex lakes create "$LAKE" \
    --location="$REGION" \
    --display-name="Customer Engagements"
  ok "Lake created."
fi

# ---- Dataplex: Zone --------------------------------------------------------
ZONE="raw-event-data"
if gcloud dataplex zones describe "$ZONE" --lake="$LAKE" --location="$REGION" >/dev/null 2>&1; then
  ok "Zone '$ZONE' already exists. Skipping."
else
  info "Creating Zone '$ZONE'..."
  gcloud dataplex zones create "$ZONE" \
    --location="$REGION" \
    --lake="$LAKE" \
    --display-name="Raw Event Data" \
    --type=RAW \
    --resource-location-type=SINGLE_REGION \
    --discovery-enabled
  ok "Zone created."
fi

# ---- GCS bucket ------------------------------------------------------------
BUCKET="gs://${PROJECT_ID}"
if gsutil ls -b "$BUCKET" >/dev/null 2>&1; then
  ok "Bucket '$BUCKET' already exists. Skipping."
else
  info "Creating bucket '$BUCKET'..."
  gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "$BUCKET"
  ok "Bucket created."
fi

# ---- Dataplex: Asset -------------------------------------------------------
ASSET="raw-event-files"
RESOURCE_NAME="projects/${PROJECT_ID}/buckets/${PROJECT_ID}"
if gcloud dataplex assets describe "$ASSET" --lake="$LAKE" --zone="$ZONE" --location="$REGION" >/dev/null 2>&1; then
  ok "Asset '$ASSET' already exists. Skipping."
else
  info "Creating Asset '$ASSET' pointing to $RESOURCE_NAME ..."
  gcloud dataplex assets create "$ASSET" \
    --location="$REGION" \
    --lake="$LAKE" \
    --zone="$ZONE" \
    --display-name="Raw Event Files" \
    --resource-type=STORAGE_BUCKET \
    --resource-name="$RESOURCE_NAME"
  ok "Asset created."
fi

# ---- Summary ---------------------------------------------------------------
echo -e "\n${GREEN}✔ Setup Complete!${NC}\n"
cat <<EOF
${CYAN}Summary:${NC}
  Project   : $PROJECT_ID
  Region    : $REGION
  Lake      : $LAKE
  Zone      : $ZONE
  Bucket    : $BUCKET
  Asset     : $ASSET

${YELLOW}Useful commands:${NC}
  gcloud dataplex lakes list --location="$REGION"
  gcloud dataplex zones list --lake="$LAKE" --location="$REGION"
  gcloud dataplex assets list --lake="$LAKE" --zone="$ZONE" --location="$REGION"

© 2025 ePlus.DEV
EOF