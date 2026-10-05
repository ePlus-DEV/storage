#!/bin/bash

set -euo pipefail

# ============================================================
# Managed Service for Apache Spark / Dataproc Lab
# Copyright (c) ePlus.DEV
# ============================================================

# ---------------- COLORS ----------------
RED=$'\033[0;91m'
GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
BLUE=$'\033[0;94m'
MAGENTA=$'\033[0;95m'
CYAN=$'\033[0;96m'
WHITE=$'\033[0;97m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

info() {
    echo -e "${CYAN}${BOLD}▶ $1${RESET}"
}

success() {
    echo -e "${GREEN}${BOLD}✔ $1${RESET}"
}

warning() {
    echo -e "${YELLOW}${BOLD}⚠ $1${RESET}"
}

error() {
    echo -e "${RED}${BOLD}✘ $1${RESET}"
}

step() {
    echo
    echo -e "${MAGENTA}${BOLD}============================================================${RESET}"
    echo -e "${MAGENTA}${BOLD}  $1${RESET}"
    echo -e "${MAGENTA}${BOLD}============================================================${RESET}"
    echo
}

clear

echo
echo -e "${MAGENTA}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${MAGENTA}${BOLD}║       MANAGED APACHE SPARK / DATAPROC LAB              ║${RESET}"
echo -e "${MAGENTA}${BOLD}║                    ePlus.DEV                            ║${RESET}"
echo -e "${MAGENTA}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
echo


# ============================================================
# LAB CONFIGURATION
# ============================================================

REGION="europe-west1"
CLUSTER_NAME="example-cluster"

PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
    error "Unable to detect PROJECT_ID."
    exit 1
fi

PROJECT_NUMBER="$(
    gcloud projects describe "$PROJECT_ID" \
        --format="value(projectNumber)"
)"

COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

echo -e "${WHITE}Project ID     : ${GREEN}${PROJECT_ID}${RESET}"
echo -e "${WHITE}Project Number : ${GREEN}${PROJECT_NUMBER}${RESET}"
echo -e "${WHITE}Region         : ${GREEN}${REGION}${RESET}"
echo -e "${WHITE}Cluster        : ${GREEN}${CLUSTER_NAME}${RESET}"
echo -e "${WHITE}Compute SA     : ${GREEN}${COMPUTE_SA}${RESET}"


# ============================================================
# TASK 1 - CONFIGURE REGION
# ============================================================

step "TASK 1.1 - CONFIGURE DATAPROC REGION"

gcloud config set project "$PROJECT_ID" --quiet >/dev/null
gcloud config set dataproc/region "$REGION" --quiet >/dev/null

success "Dataproc region configured: $REGION"


# ============================================================
# RESET DATAPROC API
# ============================================================

step "TASK 1.2 - RESET DATAPROC API"

info "Disabling Dataproc API..."

set +e

DISABLE_OUTPUT="$(
    gcloud services disable dataproc.googleapis.com \
        --project="$PROJECT_ID" \
        --force \
        --quiet \
        2>&1
)"

DISABLE_STATUS=$?

set -e

if [[ $DISABLE_STATUS -eq 0 ]]; then

    success "Dataproc API disabled."

elif echo "$DISABLE_OUTPUT" | grep -q "SU_CANNOT_DISABLE_IF_ENABLED_HIERARCHICALLY"; then

    warning "Dataproc API is enabled at ancestor level."
    warning "Skipping API disable safely."

else

    warning "Could not disable Dataproc API."
    echo "$DISABLE_OUTPUT"
    warning "Continuing with API enable..."

fi


info "Enabling Dataproc API..."

gcloud services enable dataproc.googleapis.com \
    --project="$PROJECT_ID" \
    --quiet

success "Dataproc API enabled."


# ============================================================
# IAM PERMISSIONS
# ============================================================

step "TASK 1.3 - CONFIGURE IAM PERMISSIONS"

info "Granting Storage Admin..."

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${COMPUTE_SA}" \
    --role="roles/storage.admin" \
    --quiet >/dev/null

success "Storage Admin granted."


info "Granting Dataproc Worker..."

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${COMPUTE_SA}" \
    --role="roles/dataproc.worker" \
    --quiet >/dev/null

success "Dataproc Worker granted."


# ============================================================
# PRIVATE GOOGLE ACCESS
# ============================================================

step "TASK 1.4 - ENABLE PRIVATE GOOGLE ACCESS"

info "Updating default subnet..."

gcloud compute networks subnets update default \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --enable-private-ip-google-access \
    --quiet

success "Private Google Access enabled."


# ============================================================
# CREATE DATAPROC CLUSTER
# ============================================================

step "TASK 1.5 - CREATE DATAPROC CLUSTER"

if gcloud dataproc clusters describe "$CLUSTER_NAME" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    >/dev/null 2>&1
then

    warning "Cluster $CLUSTER_NAME already exists."
    warning "Skipping cluster creation."

else

    info "Creating Dataproc cluster..."
    echo
    echo -e "${WHITE}Master machine : ${GREEN}e2-standard-4${RESET}"
    echo -e "${WHITE}Worker machine : ${GREEN}e2-standard-4${RESET}"
    echo -e "${WHITE}Worker disk    : ${GREEN}500 GB${RESET}"
    echo

    gcloud dataproc clusters create "$CLUSTER_NAME" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --worker-boot-disk-size=500 \
        --worker-machine-type=e2-standard-4 \
        --master-machine-type=e2-standard-4 \
        --quiet

fi


success "Cluster is ready."


# ============================================================
# GET DATAPROC SELECTED ZONE
# ============================================================

ZONE="$(
    gcloud dataproc clusters describe "$CLUSTER_NAME" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --format="value(config.gceClusterConfig.zoneUri)" \
        | awk -F/ '{print $NF}'
)"

if [[ -n "$ZONE" ]]; then
    success "Dataproc automatically selected zone: $ZONE"
fi


# ============================================================
# SHOW CLUSTER INFORMATION
# ============================================================

echo
info "Cluster information:"

gcloud dataproc clusters describe "$CLUSTER_NAME" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --format="table(
        clusterName:label=CLUSTER,
        status.state:label=STATUS,
        config.gceClusterConfig.zoneUri.basename():label=ZONE,
        config.masterConfig.machineTypeUri.basename():label=MASTER,
        config.workerConfig.machineTypeUri.basename():label=WORKER,
        config.workerConfig.numInstances:label=WORKERS
    )"


# ============================================================
# TASK 2 - SUBMIT SPARK JOB
# ============================================================

step "TASK 2 - SUBMIT SPARK JOB"

info "Submitting SparkPi job..."

gcloud dataproc jobs submit spark \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --cluster="$CLUSTER_NAME" \
    --class="org.apache.spark.examples.SparkPi" \
    --jars="file:///usr/lib/spark/examples/jars/spark-examples.jar" \
    -- 1000

success "SparkPi job completed."


# ============================================================
# TASK 3 - SCALE CLUSTER
# ============================================================

step "TASK 3 - SCALE CLUSTER TO 4 WORKERS"

info "Updating worker count to 4..."

gcloud dataproc clusters update "$CLUSTER_NAME" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --num-workers=4 \
    --quiet

success "Cluster scaled to 4 workers."


# ============================================================
# FINAL VERIFICATION
# ============================================================

step "FINAL VERIFICATION"

echo -e "${CYAN}${BOLD}Cluster:${RESET}"

gcloud dataproc clusters describe "$CLUSTER_NAME" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --format="table(
        clusterName:label=CLUSTER,
        status.state:label=STATUS,
        config.gceClusterConfig.zoneUri.basename():label=ZONE,
        config.workerConfig.numInstances:label=WORKERS
    )"

echo
echo -e "${CYAN}${BOLD}Recent Dataproc Jobs:${RESET}"

gcloud dataproc jobs list \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --filter="clusterName=${CLUSTER_NAME}" \
    --limit=5 \
    --format="table(
        reference.jobId:label=JOB_ID,
        type:label=TYPE,
        status.state:label=STATUS
    )"

echo
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}${BOLD}║                   LAB COMPLETED                         ║${RESET}"
echo -e "${GREEN}${BOLD}║                    ePlus.DEV                            ║${RESET}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"

echo
echo -e "${YELLOW}${BOLD}Now click 'Check my progress' in the lab.${RESET}"
echo
echo -e "${WHITE}Task 4 answer:${RESET}"
echo -e "${GREEN}${BOLD}TRUE${RESET}"
echo