#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Terraform Modules Lab - Final One-Shot Script
# Copyright © ePlus.DEV
# ============================================================

export PATH="$HOME/bin:$PATH"

PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
REGION="us-east4"
BUCKET_NAME="$PROJECT_ID"

TASK1_ROOT="$HOME/terraform-google-network"
TASK1_DIR="$TASK1_ROOT/examples/simple_project"

TASK2_ROOT="$HOME/tf-gcs-module-lab"
TASK2_MODULE_DIR="$TASK2_ROOT/modules/gcs-static-website-bucket"

TF_VERSION="1.9.8"

RED="\033[0;31m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
YELLOW="\033[1;33m"
MAGENTA="\033[0;35m"
BOLD="\033[1m"
NC="\033[0m"

banner() {
  clear || true
  echo -e "${CYAN}${BOLD}"
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║             TERRAFORM MODULES LAB - FINAL SCRIPT            ║"
  echo "║                    Copyright © ePlus.DEV                    ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
}

log() {
  echo -e "${GREEN}${BOLD}==>${NC} $1"
}

step() {
  echo -e "\n${BLUE}${BOLD}▶ $1${NC}"
}

warn() {
  echo -e "${YELLOW}${BOLD}WARNING:${NC} $1"
}

fail() {
  echo -e "${RED}${BOLD}ERROR:${NC} $1"
  exit 1
}

check_project() {
  if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
    fail "Project ID was not found. Please use the lab Cloud Shell account."
  fi

  echo -e "${MAGENTA}${BOLD}Project ID:${NC} ${PROJECT_ID}"
  echo -e "${MAGENTA}${BOLD}Region    :${NC} ${REGION}"
}

install_terraform() {
  step "Installing Terraform"

  mkdir -p "$HOME/bin"
  export PATH="$HOME/bin:$PATH"

  if command -v terraform >/dev/null 2>&1 && terraform version 2>/dev/null | head -n 1 | grep -q '^Terraform v'; then
    log "Terraform is ready: $(terraform version | head -n 1)"
    return
  fi

  log "Installing Terraform v${TF_VERSION} into \$HOME/bin..."

  sudo apt-get update -y >/dev/null
  sudo apt-get install -y unzip curl >/dev/null

  cd /tmp
  rm -f "terraform_${TF_VERSION}_linux_amd64.zip" terraform

  curl -fsSL "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip" \
    -o "terraform_${TF_VERSION}_linux_amd64.zip"

  unzip -o "terraform_${TF_VERSION}_linux_amd64.zip" >/dev/null
  chmod +x terraform
  mv terraform "$HOME/bin/terraform"

  hash -r
  terraform version | head -n 1 | grep -q '^Terraform v' || fail "Terraform installation failed."

  log "Terraform installed: $(terraform version | head -n 1)"
}

enable_apis() {
  step "Enabling Google Cloud APIs"

  gcloud services enable \
    compute.googleapis.com \
    storage.googleapis.com \
    cloudaicompanion.googleapis.com \
    --quiet || true

  log "APIs are enabled or already active."
}

task1_create_then_destroy() {
  step "Task 1: Provision infrastructure, then destroy it with Terraform"

  rm -rf "$TASK1_ROOT"
  mkdir -p "$TASK1_DIR"
  cd "$TASK1_DIR"

  cat > variables.tf <<EOFVARS
variable "project_id" {
  description = "The project ID to host the network in"
  type        = string
  default     = "$PROJECT_ID"
}

variable "network_name" {
  description = "The name of the network to be created"
  type        = string
  default     = "example-vpc"
}
EOFVARS

  cat > main.tf <<'EOFMAIN'
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = "us-east4"
}

module "test-vpc-module" {
  source       = "terraform-google-modules/network/google"
  version      = "~> 6.0"
  project_id   = var.project_id
  network_name = var.network_name
  mtu          = 1460

  subnets = [
    {
      subnet_name   = "subnet-01"
      subnet_ip     = "10.10.10.0/24"
      subnet_region = "us-east4"
    },
    {
      subnet_name           = "subnet-02"
      subnet_ip             = "10.10.20.0/24"
      subnet_region         = "us-east4"
      subnet_private_access = true
      subnet_flow_logs      = true
    },
    {
      subnet_name               = "subnet-03"
      subnet_ip                 = "10.10.30.0/24"
      subnet_region             = "us-east4"
      subnet_flow_logs          = true
      subnet_flow_logs_interval = "INTERVAL_10_MIN"
      subnet_flow_logs_sampling = 0.7
      subnet_flow_logs_metadata = "INCLUDE_ALL_METADATA"
      subnet_flow_logs_filter   = "false"
    }
  ]
}
EOFMAIN

  cat > outputs.tf <<'EOFOUT'
output "network_name" {
  value       = module.test-vpc-module.network_name
  description = "The name of the VPC being created"
}

output "network_self_link" {
  value       = module.test-vpc-module.network_self_link
  description = "The URI of the VPC being created"
}

output "project_id" {
  value       = module.test-vpc-module.project_id
  description = "VPC project id"
}

output "subnets_names" {
  value       = module.test-vpc-module.subnets_names
  description = "The names of the subnets being created"
}

output "subnets_ips" {
  value       = module.test-vpc-module.subnets_ips
  description = "The IP and CIDR ranges of the subnets being created"
}

output "subnets_regions" {
  value       = module.test-vpc-module.subnets_regions
  description = "The regions where subnets are created"
}

output "subnets_private_access" {
  value       = module.test-vpc-module.subnets_private_access
  description = "Whether the subnets have private Google access enabled"
}

output "subnets_flow_logs" {
  value       = module.test-vpc-module.subnets_flow_logs
  description = "Whether the subnets have VPC flow logs enabled"
}

output "subnets_secondary_ranges" {
  value       = module.test-vpc-module.subnets_secondary_ranges
  description = "The secondary ranges associated with these subnets"
}

output "route_names" {
  value       = module.test-vpc-module.route_names
  description = "The routes associated with this VPC"
}
EOFOUT

  log "Initializing Terraform for Task 1..."
  terraform init

  log "Applying Task 1 infrastructure..."
  terraform apply -auto-approve

  log "Verifying Task 1 resources..."
  gcloud compute networks describe example-vpc --project "$PROJECT_ID" >/dev/null
  gcloud compute networks subnets describe subnet-01 --region "$REGION" --project "$PROJECT_ID" >/dev/null
  gcloud compute networks subnets describe subnet-02 --region "$REGION" --project "$PROJECT_ID" >/dev/null
  gcloud compute networks subnets describe subnet-03 --region "$REGION" --project "$PROJECT_ID" >/dev/null

  log "Destroying Task 1 infrastructure with Terraform..."
  terraform destroy -auto-approve

  cd "$HOME"
  rm -rf "$TASK1_ROOT"

  log "Task 1 completed: infrastructure was provisioned and destroyed with Terraform."
}

task2_create_bucket_and_upload() {
  step "Task 2: Build local module and upload website files to bucket"

  rm -rf "$TASK2_ROOT"
  mkdir -p "$TASK2_MODULE_DIR"
  cd "$TASK2_ROOT"

  cat > "$TASK2_MODULE_DIR/README.md" <<'EOFREADME'
# GCS static website bucket

This module provisions Cloud Storage buckets configured for static website hosting.
EOFREADME

  cat > "$TASK2_MODULE_DIR/LICENSE" <<'EOFLICENSE'
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
EOFLICENSE

  cat > "$TASK2_MODULE_DIR/website.tf" <<'EOFWEBSITE'
resource "google_storage_bucket" "bucket" {
  name                        = var.name
  project                     = var.project_id
  location                    = var.location
  storage_class               = var.storage_class
  labels                      = var.labels
  force_destroy               = var.force_destroy
  uniform_bucket_level_access = true

  website {
    main_page_suffix = "index.html"
    not_found_page   = "error.html"
  }

  versioning {
    enabled = var.versioning
  }

  dynamic "retention_policy" {
    for_each = var.retention_policy == null ? [] : [var.retention_policy]
    content {
      is_locked        = var.retention_policy.is_locked
      retention_period = var.retention_policy.retention_period
    }
  }

  dynamic "encryption" {
    for_each = var.encryption == null ? [] : [var.encryption]
    content {
      default_kms_key_name = var.encryption.default_kms_key_name
    }
  }

  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_rules
    content {
      action {
        type          = lifecycle_rule.value.action.type
        storage_class = lookup(lifecycle_rule.value.action, "storage_class", null)
      }

      condition {
        age                   = lookup(lifecycle_rule.value.condition, "age", null)
        created_before        = lookup(lifecycle_rule.value.condition, "created_before", null)
        with_state            = lookup(lifecycle_rule.value.condition, "with_state", null)
        matches_storage_class = lookup(lifecycle_rule.value.condition, "matches_storage_class", null)
        num_newer_versions    = lookup(lifecycle_rule.value.condition, "num_newer_versions", null)
      }
    }
  }
}
EOFWEBSITE

  cat > "$TASK2_MODULE_DIR/variables.tf" <<'EOFVARS'
variable "name" {
  description = "The name of the bucket."
  type        = string
}

variable "project_id" {
  description = "The ID of the project to create the bucket in."
  type        = string
}

variable "location" {
  description = "The location of the bucket."
  type        = string
}

variable "storage_class" {
  description = "The storage class of the new bucket."
  type        = string
  default     = null
}

variable "labels" {
  description = "A set of key/value label pairs to assign to the bucket."
  type        = map(string)
  default     = null
}

variable "bucket_policy_only" {
  description = "Enables bucket policy only access to a bucket."
  type        = bool
  default     = true
}

variable "versioning" {
  description = "While set to true, versioning is fully enabled for this bucket."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "When deleting a bucket, this option deletes all contained objects."
  type        = bool
  default     = true
}

variable "iam_members" {
  description = "The list of IAM members to grant permissions on the bucket."
  type = list(object({
    role   = string
    member = string
  }))
  default = []
}

variable "retention_policy" {
  description = "Configuration of the bucket data retention policy."
  type = object({
    is_locked        = bool
    retention_period = number
  })
  default = null
}

variable "encryption" {
  description = "A Cloud KMS key used to encrypt objects inserted into this bucket."
  type = object({
    default_kms_key_name = string
  })
  default = null
}

variable "lifecycle_rules" {
  description = "The bucket lifecycle rules configuration."
  type = list(object({
    action    = any
    condition = any
  }))
  default = []
}
EOFVARS

  cat > "$TASK2_MODULE_DIR/outputs.tf" <<'EOFOUT'
output "bucket" {
  description = "The created storage bucket"
  value       = google_storage_bucket.bucket
}
EOFOUT

  cat > main.tf <<'EOFMAIN'
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = "us-east4"
}

module "gcs-static-website-bucket" {
  source = "./modules/gcs-static-website-bucket"

  name       = var.name
  project_id = var.project_id
  location   = "us-east4"

  lifecycle_rules = [{
    action = {
      type = "Delete"
    }
    condition = {
      age        = 365
      with_state = "ANY"
    }
  }]
}
EOFMAIN

  cat > variables.tf <<EOFROOTVARS
variable "project_id" {
  description = "The ID of the project in which to provision resources."
  type        = string
  default     = "$PROJECT_ID"
}

variable "name" {
  description = "Name of the bucket to create."
  type        = string
  default     = "$BUCKET_NAME"
}
EOFROOTVARS

  cat > outputs.tf <<'EOFROOTOUT'
output "bucket-name" {
  description = "Bucket name."
  value       = module.gcs-static-website-bucket.bucket.name
}

output "bucket-url" {
  description = "Bucket index URL."
  value       = "https://storage.cloud.google.com/${module.gcs-static-website-bucket.bucket.name}/index.html"
}
EOFROOTOUT

  log "Initializing Terraform for Task 2..."
  terraform init

  if gsutil ls -b "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
    warn "Bucket already exists. Importing it into Terraform state."
    terraform import module.gcs-static-website-bucket.google_storage_bucket.bucket "$BUCKET_NAME" || true
  fi

  log "Applying Task 2 bucket infrastructure..."
  terraform apply -auto-approve

  log "Downloading sample website files..."
  curl -fsSL "https://raw.githubusercontent.com/hashicorp/learn-terraform-modules/master/modules/aws-s3-static-website-bucket/www/index.html" -o index.html
  curl -fsSL "https://raw.githubusercontent.com/hashicorp/learn-terraform-modules/master/modules/aws-s3-static-website-bucket/www/error.html" -o error.html

  log "Uploading website files to Cloud Storage..."
  gsutil cp index.html error.html "gs://${BUCKET_NAME}"

  log "Verifying Task 2 resources..."
  gsutil ls -b "gs://${BUCKET_NAME}" >/dev/null
  gsutil ls "gs://${BUCKET_NAME}/index.html" >/dev/null
  gsutil ls "gs://${BUCKET_NAME}/error.html" >/dev/null

  log "Task 2 completed: bucket exists and files are uploaded."
}

summary() {
  echo ""
  echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}${BOLD}║                    LAB AUTOMATION DONE                      ║${NC}"
  echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "${GREEN}${BOLD}Provision infrastructure:${NC} created and destroyed with Terraform"
  echo -e "${GREEN}${BOLD}Upload files to the bucket:${NC} completed"
  echo ""
  echo -e "${BLUE}${BOLD}Bucket:${NC} gs://${BUCKET_NAME}"
  echo -e "${BLUE}${BOLD}Website URL:${NC} https://storage.cloud.google.com/${BUCKET_NAME}/index.html"
  echo ""
  echo -e "${YELLOW}${BOLD}Task 2 resources are kept alive for validation.${NC}"
  echo -e "${MAGENTA}${BOLD}Copyright © ePlus.DEV${NC}"
}

cleanup_task2() {
  banner
  check_project

  if [[ -d "$TASK2_ROOT" ]]; then
    cd "$TASK2_ROOT"
    terraform destroy -auto-approve || true
  fi

  rm -rf "$TASK2_ROOT"
  log "Task 2 cleanup completed."
}

run_all() {
  banner
  check_project
  install_terraform
  enable_apis
  task1_create_then_destroy
  task2_create_bucket_and_upload
  summary
}

case "${1:-run}" in
  run)
    run_all
    ;;
  cleanup)
    cleanup_task2
    ;;
  *)
    echo "Usage:"
    echo "  bash final-lab.sh"
    echo "  bash final-lab.sh cleanup"
    ;;
esac