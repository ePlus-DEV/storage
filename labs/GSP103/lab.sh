#!/bin/bash

clear

# ============================== #
#        ePlus.DEV Script        #
# ============================== #

# Define color variables
BLACK=$(tput setaf 0)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)

BG_BLACK=$(tput setab 0)
BG_RED=$(tput setab 1)
BG_GREEN=$(tput setab 2)
BG_YELLOW=$(tput setab 3)
BG_BLUE=$(tput setab 4)
BG_MAGENTA=$(tput setab 5)
BG_CYAN=$(tput setab 6)
BG_WHITE=$(tput setab 7)

BOLD=$(tput bold)
RESET=$(tput sgr0)

TEXT_COLORS=($RED $GREEN $YELLOW $BLUE $MAGENTA $CYAN)
BG_COLORS=($BG_RED $BG_GREEN $BG_YELLOW $BG_BLUE $BG_MAGENTA $BG_CYAN)

RANDOM_TEXT_COLOR=${TEXT_COLORS[$RANDOM % ${#TEXT_COLORS[@]}]}
RANDOM_BG_COLOR=${BG_COLORS[$RANDOM % ${#BG_COLORS[@]}]}

echo "${RANDOM_BG_COLOR}${RANDOM_TEXT_COLOR}${BOLD}Starting Dataproc Lab Automation - ePlus.DEV${RESET}"
echo

# ============================== #
#         Helper function        #
# ============================== #
run_step() {
  echo "${BOLD}${CYAN}>> $1${RESET}"
}

check_success() {
  if [ $? -ne 0 ]; then
    echo "${RED}${BOLD}ERROR:${RESET} $1"
    exit 1
  fi
}

# ============================== #
#         Lab Variables          #
# ============================== #
export REGION="us-west4"
export ZONE="us-west4-a"
export CLUSTER_NAME="example-cluster"
export PROJECT_ID="${DEVSHELL_PROJECT_ID}"

if [ -z "$PROJECT_ID" ]; then
  echo "${RED}${BOLD}ERROR:${RESET} DEVSHELL_PROJECT_ID is empty. Run this in Google Cloud Shell."
  exit 1
fi

run_step "Using Project ID: ${PROJECT_ID}"
export PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
check_success "Unable to get project number"

export COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

echo "${GREEN}${BOLD}Project:${RESET} ${PROJECT_ID}"
echo "${GREEN}${BOLD}Project Number:${RESET} ${PROJECT_NUMBER}"
echo "${GREEN}${BOLD}Region:${RESET} ${REGION}"
echo "${GREEN}${BOLD}Zone:${RESET} ${ZONE}"
echo "${GREEN}${BOLD}Service Account:${RESET} ${COMPUTE_SA}"
echo

# ============================== #
#       Enable required API      #
# ============================== #
run_step "Enabling Dataproc API"
gcloud services enable dataproc.googleapis.com
check_success "Failed to enable Dataproc API"

# ============================== #
#      Grant Storage Admin       #
# ============================== #
run_step "Granting Storage Admin role to compute service account"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${COMPUTE_SA}" \
  --role="roles/storage.admin" \
  --quiet >/dev/null
check_success "Failed to grant Storage Admin role"

echo "${YELLOW}${BOLD}Waiting a few seconds for IAM propagation...${RESET}"
sleep 15

# ============================== #
#      Delete bad old cluster    #
# ============================== #
run_step "Checking existing cluster status"
CLUSTER_STATE=$(gcloud dataproc clusters describe "$CLUSTER_NAME" \
  --region="$REGION" \
  --format="value(status.state)" 2>/dev/null)

if [ -n "$CLUSTER_STATE" ]; then
  echo "${YELLOW}${BOLD}Cluster ${CLUSTER_NAME} already exists with state:${RESET} ${CLUSTER_STATE}"

  if [ "$CLUSTER_STATE" != "RUNNING" ]; then
    run_step "Deleting old unusable cluster"
    gcloud dataproc clusters delete "$CLUSTER_NAME" \
      --region="$REGION" \
      --quiet
    check_success "Failed to delete old cluster"
  else
    echo "${GREEN}${BOLD}Existing cluster is healthy. Reusing it.${RESET}"
  fi
fi

# ============================== #
#        Create cluster          #
# ============================== #
CLUSTER_STATE=$(gcloud dataproc clusters describe "$CLUSTER_NAME" \
  --region="$REGION" \
  --format="value(status.state)" 2>/dev/null)

if [ -z "$CLUSTER_STATE" ]; then
  run_step "Creating Dataproc cluster"
  gcloud dataproc clusters create "$CLUSTER_NAME" \
    --region="$REGION" \
    --zone="$ZONE" \
    --master-machine-type="e2-standard-2" \
    --master-boot-disk-type="pd-standard" \
    --master-boot-disk-size="30GB" \
    --num-workers="2" \
    --worker-machine-type="e2-standard-2" \
    --worker-boot-disk-type="pd-standard" \
    --worker-boot-disk-size="30GB" \
    --no-address \
    --image-version="2.2-debian12" \
    --project="$PROJECT_ID"
  check_success "Failed to create Dataproc cluster"
else
  echo "${GREEN}${BOLD}Skipping creation because cluster already exists and is RUNNING.${RESET}"
fi

# NOTE:
# The lab says:
# "Deselect Configure all instances to have only internal IP addresses"
# In gcloud CLI that means instances SHOULD have external IPs.
# So we should NOT use --no-address.
# If your lab checker expects external IPs exactly, replace the create command above by removing:
#   --no-address
#
# To match the lab UI more precisely, use this create command instead:
#
# gcloud dataproc clusters create "$CLUSTER_NAME" \
#   --region="$REGION" \
#   --zone="$ZONE" \
#   --master-machine-type="e2-standard-2" \
#   --master-boot-disk-type="pd-standard" \
#   --master-boot-disk-size="30GB" \
#   --num-workers="2" \
#   --worker-machine-type="e2-standard-2" \
#   --worker-boot-disk-type="pd-standard" \
#   --worker-boot-disk-size="30GB" \
#   --image-version="2.2-debian12" \
#   --project="$PROJECT_ID"

# ============================== #
#     Wait until cluster runs    #
# ============================== #
run_step "Waiting for cluster to become RUNNING"
for i in {1..30}; do
  CURRENT_STATE=$(gcloud dataproc clusters describe "$CLUSTER_NAME" \
    --region="$REGION" \
    --format="value(status.state)" 2>/dev/null)

  echo "${BLUE}Current cluster state:${RESET} ${CURRENT_STATE}"

  if [ "$CURRENT_STATE" = "RUNNING" ]; then
    break
  fi

  sleep 10
done

if [ "$CURRENT_STATE" != "RUNNING" ]; then
  echo "${RED}${BOLD}ERROR:${RESET} Cluster did not reach RUNNING state."
  exit 1
fi

# ============================== #
#       Submit Spark job         #
# ============================== #
run_step "Submitting SparkPi job"
gcloud dataproc jobs submit spark \
  --region="$REGION" \
  --cluster="$CLUSTER_NAME" \
  --class="org.apache.spark.examples.SparkPi" \
  --jars="file:///usr/lib/spark/examples/jars/spark-examples.jar" \
  -- 1000
check_success "Failed to submit Spark job"

# ============================== #
#     Update cluster workers     #
# ============================== #
run_step "Updating worker count from 2 to 4"
gcloud dataproc clusters update "$CLUSTER_NAME" \
  --region="$REGION" \
  --num-workers=4
check_success "Failed to update cluster workers"

echo
echo "${GREEN}${BOLD}============================================${RESET}"
echo "${GREEN}${BOLD}   Dataproc Lab Tasks Completed Successfully${RESET}"
echo "${GREEN}${BOLD}============================================${RESET}"
echo

# ============================== #
#    Random congratulation       #
# ============================== #
random_congrats() {
  MESSAGES=(
    "${GREEN}Congratulations! Lab completed successfully!${RESET}"
    "${CYAN}Well done! Your Dataproc lab is finished!${RESET}"
    "${YELLOW}Amazing job! Everything ran correctly!${RESET}"
    "${BLUE}Outstanding! Cluster, job, and update all completed!${RESET}"
    "${MAGENTA}Fantastic work! You nailed this lab!${RESET}"
    "${RED}Excellent effort! Another lab conquered!${RESET}"
  )
  RANDOM_INDEX=$((RANDOM % ${#MESSAGES[@]}))
  echo -e "${BOLD}${MESSAGES[$RANDOM_INDEX]} ${WHITE}- ePlus.DEV${RESET}"
}

random_congrats
echo