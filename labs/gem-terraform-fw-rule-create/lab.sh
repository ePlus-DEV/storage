#!/usr/bin/env bash
# Copyright (c) 2026 ePlus.DEV | Unlicense
set -euo pipefail
YELLOW='\033[0;33m'
NC='\033[0m'
if [[ ! -t 1 || -n "${NO_COLOR:-}" ]]; then YELLOW=''; NC=''; fi
pattern=(
"**********************************************"
"**                 EPLUS.DEV                **"
"**********************************************"
)
for line in "${pattern[@]}"
do
    echo -e "${YELLOW}${line}${NC}"
done
PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != "(unset)" ]] || { echo "ERROR: Select the lab project first." >&2; exit 1; }
REGION="$(gcloud compute project-info describe --project="$PROJECT_ID" --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)"
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
fi
if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  read -r -p "Enter the lab-assigned region: " REGION
fi
[[ "$REGION" =~ ^[a-z]+(-[a-z]+)+[0-9]+$ ]] || { echo "ERROR: Invalid region '$REGION'." >&2; exit 1; }
command -v terraform >/dev/null || { echo "ERROR: Terraform is required." >&2; exit 1; }
echo "ePlus.DEV – Starting Execution | Firewall Policy | $PROJECT_ID / $REGION"


BUCKET_NAME="$PROJECT_ID-tf-state"
if gcloud storage buckets describe "gs://$BUCKET_NAME" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Reusing Terraform state bucket gs://$BUCKET_NAME"
else
  gcloud storage buckets create "gs://$BUCKET_NAME" --project="$PROJECT_ID" --location="$REGION" --uniform-bucket-level-access
fi
gcloud storage buckets update "gs://$BUCKET_NAME" --versioning --project="$PROJECT_ID"

# Keep each Terraform lab's state isolated; do not overwrite another lab's configuration.
ORIGINAL_DIR="$PWD"
if [[ -e "$ORIGINAL_DIR/terraform.tfstate" ]]; then
  echo "ERROR: Existing local Terraform state in $ORIGINAL_DIR. Migrate it manually before using the remote backend." >&2
  exit 1
fi
WORKDIR="$HOME/terraform-firewall-$PROJECT_ID"
mkdir -p "$WORKDIR"
cd "$WORKDIR"
if [[ ! -e main.tf ]]; then
cat > main.tf <<EOF_END
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "~> 4.0"
    }
  }
  backend "gcs" {
    bucket = "$BUCKET_NAME"
    prefix = "terraform/firewall-policy"
  }
}
provider "google" {
  project = "$PROJECT_ID"
  region = "$REGION"
}
EOF_END
fi


[[ -f firewall.tf ]] || cat > firewall.tf <<EOF_END
resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh-from-anywhere"
  network = "default"
  project = "$PROJECT_ID"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["ssh-allowed"]
}
EOF_END


[[ -f variables.tf ]] || cat > variables.tf <<EOF_END
variable "project_id" {
  type        = string
  default     = "$PROJECT_ID"
}

variable "bucket_name" {
  type = string
  default = "$PROJECT_ID-tf-state"
}

variable "region" {
  type = string
  default = "$REGION"
}
EOF_END


[[ -f outputs.tf ]] || cat > outputs.tf <<EOF_END
output "firewall_name" {
  value = google_compute_firewall.allow_ssh.name
}
EOF_END

grep -q 'resource "google_compute_firewall" "allow_ssh"' firewall.tf || { echo "ERROR: Unexpected firewall.tf; review manually." >&2; exit 1; }
terraform init -input=false
terraform validate
terraform plan -input=false
terraform apply -auto-approve -input=false
gcloud compute firewall-rules describe allow-ssh-from-anywhere --project="$PROJECT_ID" >/dev/null
echo "Verified firewall rule exists; grader not checked."
pattern=(
"**********************************************"
"**                 EPLUS.DEV                **"
"**********************************************"
)
for line in "${pattern[@]}"
do
    echo -e "${YELLOW}${line}${NC}"
done