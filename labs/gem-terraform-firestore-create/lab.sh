#!/usr/bin/env bash
# Copyright (c) 2026 ePlus.DEV | Unlicense
set -euo pipefail
# ============================================
#   Cloud Firestore Terraform Setup Script
#   Copyright (c) 2026 ePlus.DEV | Unlicense
# ============================================

# ====== COLOR SETUP ======
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"
if [[ ! -t 1 || -n "${NO_COLOR:-}" ]]; then RED=""; GREEN=""; YELLOW=""; CYAN=""; RESET=""; fi

echo -e "${CYAN}"
echo "============================================"
echo "     FIRESTORE TERRAFORM AUTO SETUP"
echo "               © ePlus.DEV"
echo "============================================"
echo -e "${RESET}"

# ====== AUTO DETECT PROJECT / REGION / ZONE ======
echo -e "${YELLOW}🔍 Detecting Google Cloud settings...${RESET}"

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != "(unset)" ]] || { echo "ERROR: Select the lab project first." >&2; exit 1; }
REGION="$(gcloud compute project-info describe --project="$PROJECT_ID" --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)"
ZONE="$(gcloud compute project-info describe --project="$PROJECT_ID" --format="value(commonInstanceMetadata.items[google-compute-default-zone])" 2>/dev/null || true)"
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"; fi
if [[ -z "$ZONE" || "$ZONE" == "(unset)" ]]; then ZONE="$(gcloud config get-value compute/zone 2>/dev/null || true)"; fi
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then read -r -p "Enter lab region: " REGION; fi
[[ "$REGION" =~ ^[a-z]+(-[a-z]+)+[0-9]+$ ]] || { echo "ERROR: Invalid region '$REGION'." >&2; exit 1; }
if [[ -n "$ZONE" && "$ZONE" != "(unset)" ]]; then
  [[ "$ZONE" == "$REGION"-[a-z] ]] || { echo "ERROR: Zone '$ZONE' does not belong to region '$REGION'." >&2; exit 1; }
fi
command -v terraform >/dev/null || { echo "ERROR: Terraform is required." >&2; exit 1; }
echo "ePlus.DEV – Starting Execution | Firestore | $PROJECT_ID"

echo -e "${GREEN}✔ PROJECT_ID: $PROJECT_ID${RESET}"
echo -e "${GREEN}✔ REGION:     $REGION${RESET}"
echo -e "${GREEN}✔ ZONE:       $ZONE${RESET}"

# ====== ENABLE APIs ======
echo -e "${CYAN}🔧 Enabling required APIs...${RESET}"

gcloud services enable firestore.googleapis.com cloudbuild.googleapis.com --project="$PROJECT_ID" >/dev/null

echo -e "${GREEN}✔ APIs enabled successfully${RESET}"

# ====== CREATE GCS BUCKET ======
BUCKET_NAME="${PROJECT_ID}-tf-state"

echo -e "${CYAN}📦 Creating Terraform state bucket: gs://$BUCKET_NAME ...${RESET}"

if gcloud storage buckets describe "gs://$BUCKET_NAME" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Reusing Terraform state bucket gs://$BUCKET_NAME"
else
  gcloud storage buckets create "gs://$BUCKET_NAME" --project="$PROJECT_ID" --location=us --uniform-bucket-level-access
fi
gcloud storage buckets update "gs://$BUCKET_NAME" --versioning --project="$PROJECT_ID"

# Separate state and generated configuration from other Terraform labs.
ORIGINAL_DIR="$PWD"
if [[ -e "$ORIGINAL_DIR/terraform.tfstate" ]]; then
  echo "ERROR: Existing local Terraform state; migrate it manually before rerunning." >&2
  exit 1
fi
WORKDIR="$HOME/terraform-firestore-$PROJECT_ID"
mkdir -p "$WORKDIR"
cd "$WORKDIR"


# ====== CREATE TERRAFORM FILES ======
echo -e "${CYAN}📝 Generating Terraform files...${RESET}"

[[ -f main.tf ]] || cat <<EOF > main.tf
# © ePlus.DEV
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
  backend "gcs" {
    bucket = "$BUCKET_NAME"
    prefix = "terraform/firestore-database"
  }
}

provider "google" {
  project = "$PROJECT_ID"
  region  = "$REGION"
}

resource "google_firestore_database" "default" {
  name        = "(default)"
  project     = "$PROJECT_ID"
  location_id = "nam5"
  type        = "FIRESTORE_NATIVE"
}

output "firestore_database_name" {
  value = google_firestore_database.default.name
}
EOF

[[ -f variables.tf ]] || cat <<EOF > variables.tf
# © ePlus.DEV
variable "project_id" {
  type    = string
  default = "$PROJECT_ID"
}

variable "bucket_name" {
  type    = string
  default = "$BUCKET_NAME"
}
EOF

[[ -f outputs.tf ]] || cat <<EOF > outputs.tf
# © ePlus.DEV
output "project_id" {
  value = var.project_id
}

output "bucket_name" {
  value = var.bucket_name
}
EOF

echo -e "${GREEN}✔ Terraform files created${RESET}"

# ====== TERRAFORM ACTIONS ======
echo -e "${CYAN}🚀 Running Terraform...${RESET}"

grep -q 'resource "google_firestore_database" "default"' main.tf || { echo "ERROR: Unexpected main.tf; inspect before continuing." >&2; exit 1; }
terraform init -input=false
terraform validate
terraform plan -input=false
terraform apply -auto-approve -input=false

echo -e "${GREEN}"
echo "============================================"
echo "  🎉 Firestore created successfully!"
echo "  Terraform state stored in:"
echo "     → gs://$BUCKET_NAME"
echo "--------------------------------------------"
echo "            © ePlus.DEV"
echo "============================================"
echo -e "${RESET}"
