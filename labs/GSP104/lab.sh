#!/usr/bin/env bash
# =========================================================
# ePlus.DEV — Dataproc Lab Helper (Prompt for REGION)
# Automates: region setup, IAM for default Compute SA, Private Google Access,
# cluster create, SparkPi job, and scale up/down.
# =========================================================

set -euo pipefail

# ----- Styling -----
BOLD=$(tput bold || true); RESET=$(tput sgr0 || true)
GREEN=$(tput setaf 2 || true); BLUE=$(tput setaf 4 || true); YELLOW=$(tput setaf 3 || true); RED=$(tput setaf 1 || true)

# ----- Constants -----
CLUSTER="example-cluster"

echo "${BOLD}${BLUE}▶ Using active account & project from Cloud Shell...${RESET}"
gcloud auth list
PROJECT_ID="$(gcloud config get-value project -q)"
echo "${YELLOW}Project:${RESET} ${PROJECT_ID}"

echo "${BOLD}${BLUE}▶ Enabling required APIs (Compute, Dataproc)...${RESET}"
gcloud services enable compute.googleapis.com dataproc.googleapis.com

# ----- Prompt for REGION (mandatory) -----
while :; do
  read -rp "Enter REGION (e.g., us-central1): " REGION
  REGION="${REGION:-}"
  if [[ -z "$REGION" ]]; then
    echo "${RED}REGION cannot be empty.${RESET}"
    continue
  fi
  # Validate region exists
  if gcloud compute regions describe "$REGION" >/dev/null 2>&1; then
    break
  else
    echo "${RED}Region '$REGION' is not valid or not available. Available regions:${RESET}"
    gcloud compute regions list --format='value(name)'
  fi
done

ZONE="${REGION}-a"

echo "${BOLD}${BLUE}▶ Setting gcloud properties (compute & dataproc region/zone)...${RESET}"
gcloud config set project "${PROJECT_ID}" >/dev/null
gcloud config set compute/region "${REGION}" >/dev/null
gcloud config set compute/zone "${ZONE}" >/dev/null
gcloud config set dataproc/region "${REGION}" >/dev/null

echo "${BOLD}${BLUE}▶ Granting Storage Admin to Compute Engine default service account...${RESET}"
PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"
CE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${CE_SA}" \
  --role="roles/storage.admin" \
  --quiet

echo "${BOLD}${BLUE}▶ Enabling Private Google Access on default subnet in ${REGION}...${RESET}"
gcloud compute networks subnets update default \
  --region="${REGION}" \
  --enable-private-ip-google-access

echo "${BOLD}${BLUE}▶ Creating Dataproc cluster: ${CLUSTER} in ${REGION}... (few minutes)${RESET}"
gcloud dataproc clusters create "${CLUSTER}" \
  --region="${REGION}" \
  --worker-boot-disk-size=500 \
  --worker-machine-type=e2-standard-4 \
  --master-machine-type=e2-standard-4 \
  --quiet

echo "${BOLD}${GREEN}✓ Cluster created.${RESET}"

echo "${BOLD}${BLUE}▶ Submitting SparkPi job (1000 tasks)...${RESET}"
gcloud dataproc jobs submit spark \
  --region="${REGION}" \
  --cluster="${CLUSTER}" \
  --class=org.apache.spark.examples.SparkPi \
  --jars=file:///usr/lib/spark/examples/jars/spark-examples.jar -- 1000

echo "${BOLD}${GREEN}✓ Spark job finished. (Look for 'Pi is roughly ...')${RESET}"

echo "${BOLD}${BLUE}▶ Scaling workers to 4...${RESET}"
gcloud dataproc clusters update "${CLUSTER}" --region="${REGION}" --num-workers=4 --quiet
echo "${BOLD}${GREEN}✓ Scaled to 4 workers.${RESET}"

echo "${BOLD}${BLUE}▶ (Optional) Scaling back to 2...${RESET}"
gcloud dataproc clusters update "${CLUSTER}" --region="${REGION}" --num-workers=2 --quiet
echo "${BOLD}${GREEN}✓ Scaled to 2 workers.${RESET}"

echo "${BOLD}${GREEN}All tasks completed. Use 'Check my progress' in the lab UI.${RESET}"

# Cleanup (optional after verification):
# gcloud dataproc clusters delete "${CLUSTER}" --region="${REGION}" --quiet
