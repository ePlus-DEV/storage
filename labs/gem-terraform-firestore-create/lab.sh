#!/bin/bash
# ============================================
#   Cloud Firestore Terraform Setup Script
#   © ePlus.DEV — All Rights Reserved
# ============================================

# ====== COLOR SETUP ======
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

echo -e "${CYAN}"
echo "============================================"
echo "     FIRESTORE TERRAFORM AUTO SETUP"
echo "               © ePlus.DEV"
echo "============================================"
echo -e "${RESET}"

# ====== AUTO DETECT PROJECT / REGION / ZONE ======
echo -e "${YELLOW}🔍 Detecting Google Cloud settings...${RESET}"

PROJECT_ID=$(gcloud projects list --format="value(projectId)" --limit=1)
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")

# Default fallback
if [ -z "$REGION" ]; then REGION="us-central1"; gcloud config set compute/region $REGION >/dev/null; fi
if [ -z "$ZONE" ]; then ZONE="us-central1-a"; gcloud config set compute/zone $ZONE >/dev/null; fi

echo -e "${GREEN}✔ PROJECT_ID: $PROJECT_ID${RESET}"
echo -e "${GREEN}✔ REGION:     $REGION${RESET}"
echo -e "${GREEN}✔ ZONE:       $ZONE${RESET}"

# ====== ENABLE APIs ======
echo -e "${CYAN}🔧 Enabling required APIs...${RESET}"

gcloud config set project $PROJECT_ID >/dev/null
gcloud services enable firestore.googleapis.com >/dev/null
gcloud services enable cloudbuild.googleapis.com >/dev/null

echo -e "${GREEN}✔ APIs enabled successfully${RESET}"

# ====== CREATE GCS BUCKET ======
BUCKET_NAME="${PROJECT_ID}-tf-state"

echo -e "${CYAN}📦 Creating Terraform state bucket: gs://$BUCKET_NAME ...${RESET}"

gsutil mb -l us gs://$BUCKET_NAME/ >/dev/null 2>/dev/null \
    && echo -e "${GREEN}✔ Bucket created${RESET}" \
    || echo -e "${YELLOW}⚠ Bucket already exists${RESET}"

# ====== CREATE TERRAFORM FILES ======
echo -e "${CYAN}📝 Generating Terraform files...${RESET}"

cat <<EOF > main.tf
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
    prefix = "terraform/state"
  }
}

provider "google" {
  project = "$PROJECT_ID"
  region  = "$REGION"
}

resource "google_firestore_database" "default" {
  name        = "default"
  project     = "$PROJECT_ID"
  location_id = "nam5"
  type        = "FIRESTORE_NATIVE"
}

output "firestore_database_name" {
  value = google_firestore_database.default.name
}
EOF

cat <<EOF > variables.tf
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

cat <<EOF > outputs.tf
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

terraform init
terraform plan
terraform apply -auto-approve

echo -e "${GREEN}"
echo "============================================"
echo "  🎉 Firestore created successfully!"
echo "  Terraform state stored in:"
echo "     → gs://$BUCKET_NAME"
echo "--------------------------------------------"
echo "            © ePlus.DEV"
echo "============================================"
echo -e "${RESET}"
