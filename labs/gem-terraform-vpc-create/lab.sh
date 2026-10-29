#!/usr/bin/env bash
# ePlus.DEV - Starting Execution
# Copyright (c) 2026 ePlus.DEV | Unlicense
set -euo pipefail

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  CYAN=$'\033[1;36m'; GREEN=$'\033[1;32m'; RED=$'\033[1;31m'; RESET=$'\033[0m'
else
  CYAN=''; GREEN=''; RED=''; RESET=''
fi
log() { printf '%s[Task %s] %s%s\n' "$CYAN" "$1" "$2" "$RESET"; }
ok() { printf '%s✔ %s%s\n' "$GREEN" "$1" "$RESET"; }
die() { printf '%sERROR: %s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }
command -v gcloud >/dev/null 2>&1 || die 'gcloud CLI is required.'
command -v terraform >/dev/null 2>&1 || die 'Terraform CLI is required.'
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != '(unset)' ]] || die 'Set PROJECT_ID or select a gcloud project.'
REGION="${REGION:-$(gcloud compute project-info describe --project="$PROJECT_ID" --format='value(commonInstanceMetadata.items[google-compute-default-region])' 2>/dev/null || true)}"
if [[ -z "$REGION" || "$REGION" == '(unset)' ]]; then
  REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
fi
if [[ -z "$REGION" || "$REGION" == '(unset)' ]]; then
  ZONE="${ZONE:-$(gcloud config get-value compute/zone 2>/dev/null || true)}"
  [[ -n "$ZONE" && "$ZONE" != '(unset)' ]] && REGION="${ZONE%-*}"
fi
if [[ -z "$REGION" || "$REGION" == '(unset)' ]]; then
  if [[ -t 0 ]]; then read -r -p 'Lab region: ' REGION; fi
fi
[[ "$REGION" =~ ^[a-z]+(-[a-z]+)+[0-9]+$ ]] || die 'Provide a valid lab REGION; no region is hardcoded.'

# Never overwrite a user's existing Terraform configuration silently.
write_config() {
  local target="$1" temp
  temp="$(mktemp "${target}.XXXXXX")"
  cat > "$temp"
  if [[ -e "$target" ]]; then
    if ! cmp -s "$target" "$temp"; then
      rm -f "$temp"
      die "Existing $target differs; inspect it before rerunning."
    fi
    rm -f "$temp"
  else
    mv "$temp" "$target"
  fi
}

ensure_state_bucket() {
  local bucket="$1"
  if ! gcloud storage buckets describe "gs://$bucket" --project="$PROJECT_ID" >/dev/null 2>&1; then
    gcloud storage buckets create "gs://$bucket" --project="$PROJECT_ID" --location="$REGION" --uniform-bucket-level-access
  fi
  gcloud storage buckets update "gs://$bucket" --project="$PROJECT_ID" --versioning >/dev/null
}

apply_config() {
  local plan
  terraform init -input=false
  terraform validate
  plan="$(mktemp "${PWD}/terraform-plan.XXXXXX")"
  trap 'rm -f "$plan"' EXIT
  terraform plan -input=false -out="$plan"
  terraform apply -input=false "$plan"
  rm -f "$plan"
  trap - EXIT
}

printf '%s=== ePlus.DEV – Starting Execution ===%s\n' "$CYAN" "$RESET"
WORKDIR="${HOME}/terraform-vpc"
STATE_BUCKET="${PROJECT_ID}-terraform-state"
log 1 'Enable the Compute and Cloud Resource Manager APIs.'
gcloud services enable compute.googleapis.com cloudresourcemanager.googleapis.com --project="$PROJECT_ID"
log 2 'Create/reuse versioned Terraform state bucket.'
ensure_state_bucket "$STATE_BUCKET"
log 3 'Generate Terraform VPC/subnet/firewall configuration.'
mkdir -p "$WORKDIR"
cd "$WORKDIR"
write_config main.tf <<EOF
terraform {
  required_version = ">= 1.3.0"
  required_providers {
    google = { source = "hashicorp/google", version = ">= 5.0, < 9.0" }
  }
  backend "gcs" {
    bucket = "$STATE_BUCKET"
    prefix = "terraform/gem-terraform-vpc-create"
  }
}
provider "google" {
  project = "$PROJECT_ID"
  region  = "$REGION"
}
resource "google_compute_network" "vpc_network" {
  name                    = "custom-vpc-network"
  auto_create_subnetworks = false
}
resource "google_compute_subnetwork" "subnet_us" {
  name          = "subnet-us"
  ip_cidr_range = "10.10.1.0/24"
  region        = "$REGION"
  network       = google_compute_network.vpc_network.id
}
resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = google_compute_network.vpc_network.name
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["0.0.0.0/0"]
}
resource "google_compute_firewall" "allow_icmp" {
  name    = "allow-icmp"
  network = google_compute_network.vpc_network.name
  allow {
    protocol = "icmp"
  }
  source_ranges = ["0.0.0.0/0"]
}
EOF
log 4 'Initialize, validate, plan and apply Terraform.'
apply_config
log 5 'Verify VPC, subnet and firewall rules.'
gcloud compute networks describe custom-vpc-network --project="$PROJECT_ID" >/dev/null
gcloud compute networks subnets describe subnet-us --region="$REGION" --project="$PROJECT_ID" >/dev/null
for rule in allow-ssh allow-icmp; do
  gcloud compute firewall-rules describe "$rule" --project="$PROJECT_ID" >/dev/null
done
ok 'VPC, subnet and two lab firewall rules exist; Check my progress in the lab. (Runtime/grader not preverified.)'
