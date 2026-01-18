#!/bin/bash
set -euo pipefail

# =======================
#  ePlus.DEV - Qwiklabs
# =======================

# Define color variables
RESET_FORMAT=$'\033[0m'
BOLD_TEXT=$'\033[1m'

BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'
ORANGE_TEXT=$'\033[38;5;214m'

echo "${MAGENTA_TEXT}${BOLD_TEXT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}Deploy Kubernetes Load Balancer Service with Terraform - GSP233${RESET_FORMAT}"
echo "${YELLOW_TEXT}© Copyright ePlus.DEV${RESET_FORMAT}"
echo "${MAGENTA_TEXT}${BOLD_TEXT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET_FORMAT}"

# Prefer Qwiklabs env var, fallback to gcloud config

export REGION="${ZONE%-*}"

gsutil -m cp -r gs://spls/gsp233/* .

cd tf-gke-k8s-service-lb

terraform init

terraform apply -var="region=$REGION" -var="location=$ZONE" --auto-approve