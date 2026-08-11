#!/bin/bash

# Define color variables

BLACK=`tput setaf 0`
RED=`tput setaf 1`
GREEN=`tput setaf 2`
YELLOW=`tput setaf 3`
BLUE=`tput setaf 4`
MAGENTA=`tput setaf 5`
CYAN=`tput setaf 6`
WHITE=`tput setaf 7`

BG_BLACK=`tput setab 0`
BG_RED=`tput setab 1`
BG_GREEN=`tput setab 2`
BG_YELLOW=`tput setab 3`
BG_BLUE=`tput setab 4`
BG_MAGENTA=`tput setab 5`
BG_CYAN=`tput setab 6`
BG_WHITE=`tput setab 7`

BOLD=`tput bold`
RESET=`tput sgr0`

#----------------------------------------------------start--------------------------------------------------#

echo "${BG_MAGENTA}${BOLD}Starting Execution - ePlus.DEV ${RESET}"

ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])" 2>/dev/null)
if [ -z "$ZONE" ]; then
while [ -z "$ZONE" ]; do
read -p "Please enter the ZONE: " ZONE
done
fi
export ZONE

REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null)
if [ -z "$REGION" ]; then
if [ -n "$ZONE" ]; then
REGION="${ZONE%-*}"
fi
fi
if [ -z "$REGION" ]; then
while [ -z "$REGION" ]; do
read -p "Please enter the REGION: " REGION
done
fi
export REGION

export PROJECT_ID=$(gcloud config get-value project)

gcloud config set compute/region $REGION

gcloud services enable \
container.googleapis.com \
clouddeploy.googleapis.com \
artifactregistry.googleapis.com \
cloudbuild.googleapis.com \
clouddeploy.googleapis.com

for i in $(seq 30 -1 1); do sleep 1; done

gcloud container clusters create test --node-locations=$ZONE --num-nodes=1 --async
gcloud container clusters create staging --node-locations=$ZONE --num-nodes=1 --async
gcloud container clusters create prod --node-locations=$ZONE --num-nodes=1 --async

gcloud artifacts repositories create web-app \
--description="Image registry for tutorial web app" \
--repository-format=docker \
--location=$REGION

cd ~/
git clone https://github.com/GoogleCloudPlatform/cloud-deploy-tutorials.git
cd cloud-deploy-tutorials
git checkout c3cae80 --quiet
cd tutorials/base

envsubst < clouddeploy-config/skaffold.yaml.template > web/skaffold.yaml
sed -i "s/{{project-id}}/$PROJECT_ID/g" web/skaffold.yaml

if ! gsutil ls "gs://${PROJECT_ID}_cloudbuild/" &>/dev/null; then
gsutil mb -p "${PROJECT_ID}" -l "${REGION}" -b on "gs://${PROJECT_ID}_cloudbuild/"
sleep 5
fi

cd web
skaffold build --interactive=false \
--default-repo $REGION-docker.pkg.dev/$PROJECT_ID/web-app \
--file-output artifacts.json
cd ..

gcloud artifacts docker images list \
$REGION-docker.pkg.dev/$PROJECT_ID/web-app \
--include-tags \
--format yaml

gcloud config set deploy/region $REGION

cp clouddeploy-config/delivery-pipeline.yaml.template clouddeploy-config/delivery-pipeline.yaml
gcloud beta deploy apply --file=clouddeploy-config/delivery-pipeline.yaml

gcloud beta deploy delivery-pipelines describe web-app

while true; do
cluster_statuses=$(gcloud container clusters list --format="csv(name,status)" | tail -n +2)
all_running=true
if [ -z "$cluster_statuses" ]; then
all_running=false
else
echo "$cluster_statuses" | while IFS=, read -r cluster_name cluster_status; do
cluster_name_trimmed=$(echo "$cluster_name" | tr -d '[:space:]')
cluster_status_trimmed=$(echo "$cluster_status" | tr -d '[:space:]')
if [ -z "$cluster_name_trimmed" ]; then continue; fi
if [[ "$cluster_status_trimmed" != "RUNNING" ]]; then
all_running=false
fi
done
fi
if [ "$all_running" = true ] && [ -n "$cluster_statuses" ]; then
break
fi
for i in $(seq 10 -1 1); do sleep 1; done
done

CONTEXTS=("test" "staging" "prod")
for CONTEXT in ${CONTEXTS[@]}; do
gcloud container clusters get-credentials ${CONTEXT} --region ${REGION}
kubectl config rename-context gke_${PROJECT_ID}*${REGION}*${CONTEXT} ${CONTEXT}
done

for CONTEXT_NAME in ${CONTEXTS[@]}; do
MAX_RETRIES=20
RETRY_COUNT=0
SUCCESS=false
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
if kubectl --context ${CONTEXT_NAME} apply -f kubernetes-config/web-app-namespace.yaml; then
SUCCESS=true
break
else
RETRY_COUNT=$((RETRY_COUNT+1))
sleep 5
fi
done
done

for CONTEXT in ${CONTEXTS[@]}; do
envsubst < clouddeploy-config/target-$CONTEXT.yaml.template > clouddeploy-config/target-$CONTEXT.yaml
gcloud beta deploy apply --file=clouddeploy-config/target-$CONTEXT.yaml --region=${REGION} --project=${PROJECT_ID}
done

gcloud beta deploy releases create web-app-001 \
--delivery-pipeline web-app \
--build-artifacts web/artifacts.json \
--source web/ \
--project=${PROJECT_ID} \
--region=${REGION}

while true; do
status=$(gcloud beta deploy rollouts list --delivery-pipeline web-app --release web-app-001 --filter="targetId=test" --format="value(state)" | head -n 1)
if [ "$status" == "SUCCEEDED" ]; then break; fi
if [[ "$status" == "FAILED" || "$status" == "CANCELLED" || "$status" == "HALTED" ]]; then break; fi
sleep 10
done

kubectx test
kubectl get all -n web-app


# ============================================================
# TASK 8 - PROMOTE APPLICATION TO STAGING
# FIXED - ePlus.DEV
# ============================================================

echo
echo "${BG_CYAN}${BOLD} TASK 8 - PROMOTE TO STAGING - ePlus.DEV ${RESET}"
echo


# ------------------------------------------------------------
# Helper: repair failed Cloud Deploy rollout
# Only used by Task 8 and Task 9
# ------------------------------------------------------------

retry_failed_deploy_job() {

TARGET_NAME="$1"
ROLLOUT_NAME="$2"

echo
echo "${YELLOW}${BOLD}Detected failed ${TARGET_NAME} rollout.${RESET}"
echo "Rollout: ${ROLLOUT_NAME}"

ROLLOUT_JSON="/tmp/${TARGET_NAME}-rollout.json"

gcloud beta deploy rollouts describe "$ROLLOUT_NAME" \
--delivery-pipeline web-app \
--release web-app-001 \
--region="$REGION" \
--project="$PROJECT_ID" \
--format=json > "$ROLLOUT_JSON" 2>/dev/null

if [ $? -ne 0 ]; then
echo "${RED}Unable to inspect ${TARGET_NAME} rollout.${RESET}"
return 1
fi


FAILURE_CAUSE=$(jq -r '.deployFailureCause // empty' "$ROLLOUT_JSON")
FAILURE_REASON=$(jq -r '.failureReason // empty' "$ROLLOUT_JSON")

echo
echo "Failure cause  : ${FAILURE_CAUSE:-N/A}"
echo "Failure reason : ${FAILURE_REASON:-N/A}"


PHASE_ID=$(jq -r '
.phases[]
| select(.state=="FAILED")
| .id
' "$ROLLOUT_JSON" 2>/dev/null | head -n 1)


JOB_ID=$(jq -r --arg PHASE "$PHASE_ID" '
.phases[]
| select(.id==$PHASE)
| .deploymentJobs
| to_entries[]
| select(.value.state=="FAILED")
| .value.id
' "$ROLLOUT_JSON" 2>/dev/null | head -n 1)


JOB_RUN_FULL=$(jq -r --arg PHASE "$PHASE_ID" '
.phases[]
| select(.id==$PHASE)
| .deploymentJobs
| to_entries[]
| select(.value.state=="FAILED")
| .value.jobRun
' "$ROLLOUT_JSON" 2>/dev/null | head -n 1)


echo "Failed phase   : ${PHASE_ID:-UNKNOWN}"
echo "Failed job     : ${JOB_ID:-UNKNOWN}"


if [ -n "$JOB_RUN_FULL" ] && [ "$JOB_RUN_FULL" != "null" ]; then

JOB_RUN="${JOB_RUN_FULL##*/}"

echo
echo "${YELLOW}Failed job details:${RESET}"

gcloud beta deploy job-runs describe "$JOB_RUN" \
--delivery-pipeline web-app \
--release web-app-001 \
--rollout "$ROLLOUT_NAME" \
--region="$REGION" \
--project="$PROJECT_ID" \
--format="yaml(
state,
deployJobRun.failureCause,
deployJobRun.failureMessage,
deployJobRun.build
)" 2>/dev/null

fi


if [ -z "$PHASE_ID" ] || \
[ "$PHASE_ID" == "null" ] || \
[ -z "$JOB_ID" ] || \
[ "$JOB_ID" == "null" ]; then

echo
echo "${RED}Unable to detect failed deployment job.${RESET}"
return 1

fi


# ------------------------------------------------------------
# Wait until target cluster is actually RUNNING
# ------------------------------------------------------------

echo
echo "Checking ${TARGET_NAME} cluster..."

while true; do

TARGET_CLUSTER_STATUS=$(gcloud container clusters describe "$TARGET_NAME" \
--region="$REGION" \
--project="$PROJECT_ID" \
--format="value(status)" 2>/dev/null)

echo "${TARGET_NAME} cluster: ${TARGET_CLUSTER_STATUS:-UNKNOWN}"

if [ "$TARGET_CLUSTER_STATUS" == "RUNNING" ]; then
break
fi

sleep 5

done


# ------------------------------------------------------------
# Refresh credentials
# ------------------------------------------------------------

gcloud container clusters get-credentials "$TARGET_NAME" \
--region="$REGION" \
--project="$PROJECT_ID"

if [ $? -ne 0 ]; then
echo "${RED}Unable to get ${TARGET_NAME} cluster credentials.${RESET}"
return 1
fi


# ------------------------------------------------------------
# Ensure web-app namespace exists
# This does not recreate it when already present
# ------------------------------------------------------------

kubectl create namespace web-app \
--dry-run=client \
-o yaml 2>/dev/null | kubectl apply -f - >/dev/null 2>&1


# ------------------------------------------------------------
# Retry failed Cloud Deploy job
# ------------------------------------------------------------

echo
echo "${YELLOW}${BOLD}Retrying failed ${TARGET_NAME} deployment job...${RESET}"

gcloud beta deploy rollouts retry-job "$ROLLOUT_NAME" \
--delivery-pipeline web-app \
--release web-app-001 \
--phase-id="$PHASE_ID" \
--job-id="$JOB_ID" \
--region="$REGION" \
--project="$PROJECT_ID" \
--quiet

if [ $? -ne 0 ]; then
echo "${RED}Retry failed.${RESET}"
return 1
fi

echo "${GREEN}Retry submitted successfully.${RESET}"

return 0
}


# ------------------------------------------------------------
# Find existing staging rollout
# ------------------------------------------------------------

STAGING_ROLLOUT_FULL=$(gcloud beta deploy rollouts list \
--delivery-pipeline web-app \
--release web-app-001 \
--region="$REGION" \
--project="$PROJECT_ID" \
--filter="targetId=staging" \
--sort-by="~createTime" \
--limit=1 \
--format="value(name)" 2>/dev/null)

STAGING_ROLLOUT=""

if [ -n "$STAGING_ROLLOUT_FULL" ]; then
STAGING_ROLLOUT="${STAGING_ROLLOUT_FULL##*/}"
fi


# ------------------------------------------------------------
# Promote to staging only if rollout does not exist
# ------------------------------------------------------------

if [ -z "$STAGING_ROLLOUT" ]; then

echo "${YELLOW}Promoting release to staging...${RESET}"

gcloud beta deploy releases promote \
--delivery-pipeline web-app \
--release web-app-001 \
--to-target=staging \
--region="$REGION" \
--project="$PROJECT_ID" \
--quiet

if [ $? -eq 0 ]; then

echo "${GREEN}Promotion to staging submitted.${RESET}"

while [ -z "$STAGING_ROLLOUT" ]; do

STAGING_ROLLOUT_FULL=$(gcloud beta deploy rollouts list \
--delivery-pipeline web-app \
--release web-app-001 \
--region="$REGION" \
--project="$PROJECT_ID" \
--filter="targetId=staging" \
--sort-by="~createTime" \
--limit=1 \
--format="value(name)" 2>/dev/null)

if [ -n "$STAGING_ROLLOUT_FULL" ]; then
STAGING_ROLLOUT="${STAGING_ROLLOUT_FULL##*/}"
break
fi

echo "Waiting for staging rollout..."
sleep 5

done

else

echo "${RED}Promotion to staging failed.${RESET}"

fi

else

echo "Existing staging rollout: $STAGING_ROLLOUT"

fi


# ------------------------------------------------------------
# Wait / repair staging until SUCCEEDED
# ------------------------------------------------------------

TASK8_OK=false
STAGING_RETRIED=false

if [ -n "$STAGING_ROLLOUT" ]; then

while true; do

STAGING_STATE=$(gcloud beta deploy rollouts describe "$STAGING_ROLLOUT" \
--delivery-pipeline web-app \
--release web-app-001 \
--region="$REGION" \
--project="$PROJECT_ID" \
--format="value(state)" 2>/dev/null)

echo "Staging state: ${STAGING_STATE:-UNKNOWN}"


if [ "$STAGING_STATE" == "SUCCEEDED" ]; then

TASK8_OK=true

echo
echo "${GREEN}${BOLD}STAGING = SUCCEEDED${RESET}"

break

fi


if [ "$STAGING_STATE" == "FAILED" ]; then

if [ "$STAGING_RETRIED" == false ]; then

echo
echo "${YELLOW}Staging failed. Repairing deployment...${RESET}"

retry_failed_deploy_job \
"staging" \
"$STAGING_ROLLOUT"

if [ $? -eq 0 ]; then

STAGING_RETRIED=true

echo
echo "Waiting for staging retry..."

sleep 5
continue

else

echo "${RED}Unable to repair staging rollout.${RESET}"
break

fi

else

echo
echo "${RED}Staging failed again after retry.${RESET}"

gcloud beta deploy rollouts describe "$STAGING_ROLLOUT" \
--delivery-pipeline web-app \
--release web-app-001 \
--region="$REGION" \
--project="$PROJECT_ID" \
--format="yaml(
state,
deployFailureCause,
failureReason,
deployingBuild
)"

break

fi

fi


if [[ "$STAGING_STATE" == "CANCELLED" || \
"$STAGING_STATE" == "HALTED" ]]; then

echo
echo "${RED}Staging rollout stopped: $STAGING_STATE${RESET}"
break

fi

sleep 10

done

fi


if [ "$TASK8_OK" == true ]; then

echo
kubectx staging
kubectl get all -n web-app

echo
echo "${GREEN}${BOLD}TASK 8 COMPLETED - ePlus.DEV${RESET}"

else

echo
echo "${RED}${BOLD}TASK 8 FAILED - TASK 9 WILL NOT RUN${RESET}"

fi


# ============================================================
# TASK 9 - PROMOTE APPLICATION TO PROD
# FIXED - ePlus.DEV
# ============================================================

if [ "$TASK8_OK" == true ]; then

echo
echo "${BG_CYAN}${BOLD} TASK 9 - PROMOTE TO PROD - ePlus.DEV ${RESET}"
echo


# ------------------------------------------------------------
# Find existing prod rollout
# ------------------------------------------------------------

PROD_ROLLOUT_FULL=$(gcloud beta deploy rollouts list \
--delivery-pipeline web-app \
--release web-app-001 \
--region="$REGION" \
--project="$PROJECT_ID" \
--filter="targetId=prod" \
--sort-by="~createTime" \
--limit=1 \
--format="value(name)" 2>/dev/null)

PROD_ROLLOUT=""

if [ -n "$PROD_ROLLOUT_FULL" ]; then
PROD_ROLLOUT="${PROD_ROLLOUT_FULL##*/}"
fi


# ------------------------------------------------------------
# Promote explicitly to prod
# ------------------------------------------------------------

if [ -z "$PROD_ROLLOUT" ]; then

echo "${YELLOW}Promoting release to prod...${RESET}"

gcloud beta deploy releases promote \
--delivery-pipeline web-app \
--release web-app-001 \
--to-target=prod \
--region="$REGION" \
--project="$PROJECT_ID" \
--quiet

if [ $? -eq 0 ]; then

echo "${GREEN}Promotion to prod submitted.${RESET}"

while [ -z "$PROD_ROLLOUT" ]; do

PROD_ROLLOUT_FULL=$(gcloud beta deploy rollouts list \
--delivery-pipeline web-app \
--release web-app-001 \
--region="$REGION" \
--project="$PROJECT_ID" \
--filter="targetId=prod" \
--sort-by="~createTime" \
--limit=1 \
--format="value(name)" 2>/dev/null)

if [ -n "$PROD_ROLLOUT_FULL" ]; then

PROD_ROLLOUT="${PROD_ROLLOUT_FULL##*/}"

break

fi

echo "Waiting for prod rollout..."
sleep 5

done

else

echo "${RED}Promotion to prod failed.${RESET}"

fi

else

echo "Existing prod rollout: $PROD_ROLLOUT"

fi


# ------------------------------------------------------------
# Wait approval -> approve -> wait SUCCEEDED
# ------------------------------------------------------------

TASK9_OK=false
PROD_RETRIED=false

if [ -n "$PROD_ROLLOUT" ]; then

while true; do

PROD_STATE=$(gcloud beta deploy rollouts describe "$PROD_ROLLOUT" \
--delivery-pipeline web-app \
--release web-app-001 \
--region="$REGION" \
--project="$PROJECT_ID" \
--format="value(state)" 2>/dev/null)

PROD_APPROVAL=$(gcloud beta deploy rollouts describe "$PROD_ROLLOUT" \
--delivery-pipeline web-app \
--release web-app-001 \
--region="$REGION" \
--project="$PROJECT_ID" \
--format="value(approvalState)" 2>/dev/null)


echo "Prod state: ${PROD_STATE:-UNKNOWN} | Approval: ${PROD_APPROVAL:-UNKNOWN}"


# ------------------------------------------------------------
# Already completed
# ------------------------------------------------------------

if [ "$PROD_STATE" == "SUCCEEDED" ]; then

TASK9_OK=true
break

fi


# ------------------------------------------------------------
# Approve production rollout
# ------------------------------------------------------------

if [[ "$PROD_STATE" == "PENDING_APPROVAL" || \
"$PROD_APPROVAL" == "NEEDS_APPROVAL" ]]; then

echo
echo "${YELLOW}${BOLD}Approving production rollout...${RESET}"

gcloud beta deploy rollouts approve "$PROD_ROLLOUT" \
--delivery-pipeline web-app \
--release web-app-001 \
--region="$REGION" \
--project="$PROJECT_ID" \
--quiet

if [ $? -ne 0 ]; then

echo
echo "${RED}Unable to approve production rollout.${RESET}"

break

fi

echo "${GREEN}Production rollout approved.${RESET}"

sleep 5
continue

fi


# ------------------------------------------------------------
# Repair failed prod rollout if necessary
# ------------------------------------------------------------

if [ "$PROD_STATE" == "FAILED" ]; then

if [ "$PROD_RETRIED" == false ]; then

echo
echo "${YELLOW}Prod deployment failed. Repairing...${RESET}"

retry_failed_deploy_job \
"prod" \
"$PROD_ROLLOUT"

if [ $? -eq 0 ]; then

PROD_RETRIED=true

echo
echo "Waiting for prod retry..."

sleep 5
continue

else

echo "${RED}Unable to repair prod rollout.${RESET}"

break

fi

else

echo
echo "${RED}Prod failed again after retry.${RESET}"

gcloud beta deploy rollouts describe "$PROD_ROLLOUT" \
--delivery-pipeline web-app \
--release web-app-001 \
--region="$REGION" \
--project="$PROJECT_ID" \
--format="yaml(
state,
deployFailureCause,
failureReason,
deployingBuild
)"

break

fi

fi


if [[ "$PROD_STATE" == "CANCELLED" || \
"$PROD_STATE" == "HALTED" || \
"$PROD_STATE" == "APPROVAL_REJECTED" ]]; then

echo
echo "${RED}Prod rollout stopped: $PROD_STATE${RESET}"

break

fi


sleep 10

done

fi


# ------------------------------------------------------------
# Final Task 9 result
# ------------------------------------------------------------

if [ "$TASK9_OK" == true ]; then

echo
echo "${GREEN}${BOLD}PROD = SUCCEEDED${RESET}"

kubectx prod
kubectl get all -n web-app

echo
echo "${GREEN}${BOLD}TASK 9 COMPLETED - ePlus.DEV${RESET}"

else

echo
echo "${RED}${BOLD}TASK 9 NOT COMPLETED${RESET}"

fi

fi


# ============================================================
# FINAL STATUS
# ============================================================

echo
echo "${CYAN}${BOLD}Final rollout status:${RESET}"
echo

gcloud beta deploy rollouts list \
--delivery-pipeline web-app \
--release web-app-001 \
--region="$REGION" \
--project="$PROJECT_ID" \
--format="table(targetId,state,approvalState,name)"

echo

echo "${BG_RED}${BOLD}Congratulations For Completing!!! - ePlus.DEV ${RESET}"

#-----------------------------------------------------end----------------------------------------------------------#