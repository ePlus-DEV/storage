#!/usr/bin/env bash
# Copyright (c) 2026 ePlus.DEV | Unlicense
set -euo pipefail

# Detect the lab-provided project and location; never assume a fixed region.
PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != "(unset)" ]] || { echo "ERROR: Set the lab project in gcloud first." >&2; exit 1; }
REGION="$(gcloud compute project-info describe --project="$PROJECT_ID" --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)"
ZONE="$(gcloud compute project-info describe --project="$PROJECT_ID" --format="value(commonInstanceMetadata.items[google-compute-default-zone])" 2>/dev/null || true)"
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"; fi
if [[ -z "$ZONE" || "$ZONE" == "(unset)" ]]; then ZONE="$(gcloud config get-value compute/zone 2>/dev/null || true)"; fi
if [[ -z "$ZONE" || "$ZONE" == "(unset)" ]]; then read -r -p "Enter lab zone: " ZONE; fi
[[ "$ZONE" =~ ^[a-z]+(-[a-z]+)+[0-9]+-[a-z]$ ]] || { echo "ERROR: Invalid zone '$ZONE'." >&2; exit 1; }
ZONE_REGION="$(printf '%s' "$ZONE" | sed -E 's/-[a-z]$//')"
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then REGION="$ZONE_REGION"; fi
[[ "$REGION" == "$ZONE_REGION" ]] || { echo "ERROR: Region '$REGION' does not match zone '$ZONE'." >&2; exit 1; }
command -v terraform >/dev/null || { echo "ERROR: Terraform is required." >&2; exit 1; }
echo "ePlus.DEV – Starting Execution | GCE Instance | $PROJECT_ID / $ZONE"

BUCKET_NAME="$PROJECT_ID-tf-state"
if gcloud storage buckets describe "gs://$BUCKET_NAME" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Reusing Terraform state bucket gs://$BUCKET_NAME"
else
  gcloud storage buckets create "gs://$BUCKET_NAME" --project="$PROJECT_ID" --location="$REGION" --uniform-bucket-level-access
fi
gcloud storage buckets update "gs://$BUCKET_NAME" --versioning --project="$PROJECT_ID"

ORIGINAL_DIR="$PWD"
if [[ -e "$ORIGINAL_DIR/terraform.tfstate" ]]; then
  echo "ERROR: Existing local Terraform state; migrate it manually to avoid recreating managed resources." >&2
  exit 1
fi
WORKDIR="$HOME/terraform-gce-$PROJECT_ID"
mkdir -p "$WORKDIR"
cd "$WORKDIR"


[[ -f main.tf ]] || cat > main.tf <<EOF_END
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
  backend "gcs" {
    bucket = "$PROJECT_ID-tf-state"
    prefix = "terraform/gce-instance"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_compute_instance" "default" {
  name         = "terraform-instance"
  machine_type = "e2-micro"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    subnetwork = "default"

    access_config {
    }
  }
}
EOF_END



[[ -f variables.tf ]] || cat > variables.tf <<EOF_END
variable "project_id" {
  type        = string
  description = "The ID of the Google Cloud project"
  default = "$PROJECT_ID"
}

variable "region" {
  type        = string
  description = "The region to deploy resources in"
  default     = "$REGION"
}

variable "zone" {
  type        = string
  description = "The zone to deploy resources in"
  default     = "$ZONE"
}
EOF_END



# cat > outputs.tf <<EOF_END
# output "project_id" {
#   value       = var.project_id
#   description = "The ID of the Google Cloud project."
# }

# output "bucket_name" {
#   value       = var.bucket_name
#   description = "The name of the bucket to store terraform state."
# }
# EOF_END


grep -q 'resource "google_compute_instance" "default"' main.tf || { echo "ERROR: Unexpected main.tf; inspect before continuing." >&2; exit 1; }
terraform init -input=false
terraform validate
terraform plan -input=false
terraform apply -auto-approve -input=false
gcloud compute instances describe terraform-instance --zone="$ZONE" --project="$PROJECT_ID" >/dev/null
echo "Verified terraform-instance exists; grader not checked."