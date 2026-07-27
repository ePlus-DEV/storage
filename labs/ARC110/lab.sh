#!/bin/bash

set -Eeuo pipefail

# ANSI color codes
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#===============================================================================
# Helper functions
#===============================================================================

section() {
    echo ""
    echo -e "${CYAN}=====================================${NC}"
    echo -e "   ${YELLOW}$1${NC}"
    echo -e "${CYAN}=====================================${NC}"
}

success() {
    echo -e "${CYAN}✔ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

error() {
    echo -e "${RED}✘ $1${NC}"
}

clean_input() {
    printf '%s' "$1" | tr -d '\r\n' | xargs
}

on_error() {
    local EXIT_CODE=$?
    local LINE_NUMBER=$1

    echo ""
    error "Command failed at line ${LINE_NUMBER}."

    if [[ -n "${WORK_DIR:-}" ]] &&
       [[ -f "${WORK_DIR}/dataflow-launch.log" ]]; then

        echo ""
        echo -e "${YELLOW}Last Dataflow launch messages:${NC}"
        tail -n 40 "${WORK_DIR}/dataflow-launch.log" || true
    fi

    exit "$EXIT_CODE"
}

trap 'on_error $LINENO' ERR

#===============================================================================
# Banner
#===============================================================================

clear

echo -e "${CYAN}=====================================${NC}"
echo -e "   ${YELLOW}Copyright (c) 2025 ePlus.DEV${NC}"
echo -e "${CYAN}=====================================${NC}\n"

echo ""
echo ""
echo "Please export the values."

#===============================================================================
# Detect Google Cloud project
#===============================================================================

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
USER_EMAIL=$(gcloud config get-value account 2>/dev/null)

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
    error "Google Cloud project could not be detected."
    exit 1
fi

export PROJECT_ID
export BUCKET_NAME="${PROJECT_ID}-bucket"

SCHEDULER_JOB="quicklab"
WORK_DIR="$HOME/pubsub-dataflow-lab"

mkdir -p "$WORK_DIR"

#===============================================================================
# Input values from Terminal
#===============================================================================

echo ""

while true; do
    read -p "Enter TOPIC_ID: " TOPIC_ID
    TOPIC_ID=$(clean_input "$TOPIC_ID")
    TOPIC_ID="${TOPIC_ID##*/}"

    if [[ -n "$TOPIC_ID" ]]; then
        break
    fi

    error "TOPIC_ID cannot be empty."
done

while true; do
    read -p "Enter MESSAGE: " MESSAGE
    MESSAGE=$(printf '%s' "$MESSAGE" | tr -d '\r\n')

    if [[ -n "$MESSAGE" ]]; then
        break
    fi

    error "MESSAGE cannot be empty."
done

while true; do
    read -p "Enter ZONE: " ZONE
    ZONE=$(clean_input "$ZONE")

    if [[ -n "$ZONE" ]]; then
        break
    fi

    error "ZONE cannot be empty."
done

# Automatically derive the region:
# us-east1-c -> us-east1
# us-west1-a -> us-west1
REGION="${ZONE%-*}"

export TOPIC_ID
export MESSAGE
export ZONE
export REGION

DATAFLOW_JOB="pubsub-to-gcs-$(date +%Y%m%d-%H%M%S)"
OUTPUT_PATH="gs://${BUCKET_NAME}/samples/output"

WORKER_DISK_TYPE="compute.googleapis.com/projects/${PROJECT_ID}/zones/${ZONE}/diskTypes/pd-standard"

echo ""
echo -e "${CYAN}=====================================${NC}"
echo -e "   ${YELLOW}LAB CONFIGURATION${NC}"
echo -e "${CYAN}=====================================${NC}"
echo "Project ID   : $PROJECT_ID"
echo "User Account : $USER_EMAIL"
echo "Topic ID     : $TOPIC_ID"
echo "Message      : $MESSAGE"
echo "Zone         : $ZONE"
echo "Region       : $REGION"
echo "Bucket       : gs://$BUCKET_NAME"
echo "Machine Type : e2-standard-2"
echo "Worker Disk  : pd-standard"
echo "Window Size  : 2 minutes"

gcloud config set project "$PROJECT_ID" --quiet
gcloud config set compute/region "$REGION" --quiet
gcloud config set compute/zone "$ZONE" --quiet

#===============================================================================
# Enable required APIs
#===============================================================================

section "ENABLE REQUIRED APIS"

gcloud services enable \
    pubsub.googleapis.com \
    cloudscheduler.googleapis.com \
    appengine.googleapis.com \
    compute.googleapis.com \
    storage.googleapis.com \
    cloudresourcemanager.googleapis.com \
    serviceusage.googleapis.com \
    --project="$PROJECT_ID" \
    --quiet

success "Required APIs have been enabled."

#===============================================================================
# Task 1 - Create Pub/Sub topic
#===============================================================================

section "TASK 1 - CREATE PUB/SUB TOPIC"

if gcloud pubsub topics describe "$TOPIC_ID" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

    warning "Pub/Sub topic already exists: $TOPIC_ID"
else
    gcloud pubsub topics create "$TOPIC_ID" \
        --project="$PROJECT_ID"

    success "Created Pub/Sub topic: $TOPIC_ID"
fi

echo ""
gcloud pubsub topics describe "$TOPIC_ID" \
    --project="$PROJECT_ID" \
    --format="yaml(name)"

#===============================================================================
# Task 2 - Create App Engine application
#===============================================================================

section "TASK 2 - CREATE APP ENGINE APP"

if gcloud app describe \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

    APP_LOCATION=$(gcloud app describe \
        --project="$PROJECT_ID" \
        --format="value(locationId)")

    warning "App Engine app already exists in: $APP_LOCATION"
else
    gcloud app create \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --quiet

    success "Created App Engine app in $REGION."
fi

#===============================================================================
# Task 2 - Create Cloud Scheduler job
#===============================================================================

section "TASK 2 - CREATE CLOUD SCHEDULER JOB"

echo -e "${YELLOW}Waiting for Cloud Scheduler initialization...${NC}"
sleep 15

if gcloud scheduler jobs describe "$SCHEDULER_JOB" \
    --project="$PROJECT_ID" \
    --location="$REGION" >/dev/null 2>&1; then

    warning "Cloud Scheduler job already exists. Updating it..."

    gcloud scheduler jobs update pubsub "$SCHEDULER_JOB" \
        --project="$PROJECT_ID" \
        --location="$REGION" \
        --schedule="* * * * *" \
        --time-zone="Etc/UTC" \
        --topic="$TOPIC_ID" \
        --message-body="$MESSAGE" \
        --description="Publish a message every minute" \
        --quiet
else
    gcloud scheduler jobs create pubsub "$SCHEDULER_JOB" \
        --project="$PROJECT_ID" \
        --location="$REGION" \
        --schedule="* * * * *" \
        --time-zone="Etc/UTC" \
        --topic="$TOPIC_ID" \
        --message-body="$MESSAGE" \
        --description="Publish a message every minute" \
        --quiet
fi

success "Cloud Scheduler job has been configured."

echo ""
echo -e "${YELLOW}Running Cloud Scheduler job...${NC}"

gcloud scheduler jobs run "$SCHEDULER_JOB" \
    --project="$PROJECT_ID" \
    --location="$REGION"

success "Cloud Scheduler job was started."

echo ""
gcloud scheduler jobs describe "$SCHEDULER_JOB" \
    --project="$PROJECT_ID" \
    --location="$REGION" \
    --format="yaml(name,schedule,timeZone,state,pubsubTarget.topicName)"

#===============================================================================
# Task 3 - Create or restore Cloud Storage bucket
#===============================================================================

section "TASK 3 - CREATE CLOUD STORAGE BUCKET"

if gcloud storage buckets describe "gs://$BUCKET_NAME" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

    warning "Bucket already exists: gs://$BUCKET_NAME"

else
    echo -e "${YELLOW}Checking soft-deleted buckets...${NC}"

    SOFT_BUCKET_URI=$(
        gcloud storage ls \
            --buckets \
            --soft-deleted \
            --full \
            --project="$PROJECT_ID" 2>/dev/null |
        grep -Eo "gs://${BUCKET_NAME}#[0-9]+" |
        tail -n 1 || true
    )

    if [[ -n "$SOFT_BUCKET_URI" ]]; then
        warning "Soft-deleted bucket found:"
        echo "$SOFT_BUCKET_URI"

        echo ""
        echo -e "${YELLOW}Restoring bucket...${NC}"

        gcloud storage restore "$SOFT_BUCKET_URI" \
            --project="$PROJECT_ID"

        BUCKET_READY="false"

        for ATTEMPT in $(seq 1 30); do
            if gcloud storage buckets describe "gs://$BUCKET_NAME" \
                --project="$PROJECT_ID" >/dev/null 2>&1; then

                BUCKET_READY="true"
                break
            fi

            echo -e "${YELLOW}Waiting for bucket restoration ${ATTEMPT}/30...${NC}"
            sleep 5
        done

        if [[ "$BUCKET_READY" != "true" ]]; then
            error "Bucket restoration did not complete."
            exit 1
        fi

        success "Bucket was restored successfully."

    else
        echo -e "${YELLOW}Creating gs://${BUCKET_NAME} in ${REGION}...${NC}"

        set +e

        CREATE_OUTPUT=$(
            gcloud storage buckets create "gs://$BUCKET_NAME" \
                --project="$PROJECT_ID" \
                --location="$REGION" 2>&1
        )

        CREATE_STATUS=$?

        set -e

        echo "$CREATE_OUTPUT"

        if [[ "$CREATE_STATUS" -ne 0 ]]; then
            if echo "$CREATE_OUTPUT" | grep -q "HTTPError 409"; then
                error "Bucket name is unavailable."

                echo ""
                echo "Check soft-deleted buckets manually:"
                echo "gcloud storage ls --buckets --soft-deleted --full"
                exit 1
            fi

            error "Bucket creation failed."
            exit "$CREATE_STATUS"
        fi

        success "Created bucket: gs://$BUCKET_NAME"
    fi
fi

echo ""
gcloud storage buckets describe "gs://$BUCKET_NAME" \
    --project="$PROJECT_ID" \
    --format="yaml(name,location,storageClass,softDeletePolicy)"

#===============================================================================
# Cancel previous Dataflow jobs
#===============================================================================

section "CHECK OLD DATAFLOW JOBS"

OLD_JOB_IDS=$(
    gcloud dataflow jobs list \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --status=active \
        --format="value(id,name)" 2>/dev/null |
    awk '$2 ~ /^pubsub-to-gcs-/ {print $1}' || true
)

if [[ -n "$OLD_JOB_IDS" ]]; then
    while IFS= read -r OLD_JOB_ID; do
        [[ -z "$OLD_JOB_ID" ]] && continue

        warning "Cancelling old Dataflow job: $OLD_JOB_ID"

        gcloud dataflow jobs cancel "$OLD_JOB_ID" \
            --project="$PROJECT_ID" \
            --region="$REGION" \
            --quiet || true
    done <<< "$OLD_JOB_IDS"

    echo -e "${YELLOW}Waiting for old Dataflow jobs to stop...${NC}"

    for ATTEMPT in $(seq 1 30); do
        REMAINING_JOB_IDS=$(
            gcloud dataflow jobs list \
                --project="$PROJECT_ID" \
                --region="$REGION" \
                --status=active \
                --format="value(id,name)" 2>/dev/null |
            awk '$2 ~ /^pubsub-to-gcs-/ {print $1}' || true
        )

        if [[ -z "$REMAINING_JOB_IDS" ]]; then
            success "Old Dataflow jobs have stopped."
            break
        fi

        echo -e "${YELLOW}Waiting for cancellation ${ATTEMPT}/30...${NC}"
        sleep 5
    done
else
    warning "No active old Dataflow jobs were found."
fi

#===============================================================================
# Task 4 - Disable and enable Dataflow API
#===============================================================================

section "TASK 4 - RESET DATAFLOW API"

echo -e "${YELLOW}Disabling Dataflow API...${NC}"

gcloud services disable dataflow.googleapis.com \
    --project="$PROJECT_ID" \
    --force \
    --quiet || true

sleep 5

echo -e "${YELLOW}Enabling Dataflow API...${NC}"

gcloud services enable dataflow.googleapis.com \
    --project="$PROJECT_ID" \
    --quiet

DATAFLOW_API_READY="false"

for ATTEMPT in $(seq 1 30); do
    ENABLED_SERVICE=$(
        gcloud services list \
            --project="$PROJECT_ID" \
            --enabled \
            --filter="config.name=dataflow.googleapis.com" \
            --format="value(config.name)" 2>/dev/null || true
    )

    if [[ "$ENABLED_SERVICE" == "dataflow.googleapis.com" ]]; then
        DATAFLOW_API_READY="true"
        break
    fi

    echo -e "${YELLOW}Waiting for Dataflow API ${ATTEMPT}/30...${NC}"
    sleep 5
done

if [[ "$DATAFLOW_API_READY" != "true" ]]; then
    error "Dataflow API could not be enabled."
    exit 1
fi

success "Dataflow API is enabled."

sleep 15

#===============================================================================
# Prepare Python pipeline
#===============================================================================

section "TASK 4 - PREPARE PYTHON PIPELINE"

cd "$WORK_DIR"

echo -e "${YELLOW}Downloading PubSubToGCS.py...${NC}"

curl -fsSL \
    "https://raw.githubusercontent.com/GoogleCloudPlatform/python-docs-samples/main/pubsub/streaming-analytics/PubSubToGCS.py" \
    -o PubSubToGCS.py

if [[ ! -s PubSubToGCS.py ]]; then
    error "PubSubToGCS.py could not be downloaded."
    exit 1
fi

if command -v python3.11 >/dev/null 2>&1; then
    PYTHON_BIN="python3.11"
elif command -v python3.12 >/dev/null 2>&1; then
    PYTHON_BIN="python3.12"
else
    PYTHON_BIN="python3"
fi

VENV_PATH="$WORK_DIR/venv"

if [[ ! -d "$VENV_PATH" ]]; then
    "$PYTHON_BIN" -m venv "$VENV_PATH"
fi

"$VENV_PATH/bin/python" -m pip install \
    --upgrade \
    pip \
    setuptools \
    wheel \
    --quiet

echo -e "${YELLOW}Installing Apache Beam...${NC}"

"$VENV_PATH/bin/python" -m pip install \
    --upgrade \
    "apache-beam[gcp]" \
    --quiet

success "Python environment is ready."

#===============================================================================
# Run Dataflow pipeline
#===============================================================================

section "TASK 4 - RUN DATAFLOW PIPELINE"

echo "Job Name      : $DATAFLOW_JOB"
echo "Input Topic   : projects/$PROJECT_ID/topics/$TOPIC_ID"
echo "Output Path   : $OUTPUT_PATH"
echo "Window Size   : 2 minutes"
echo "Machine Type  : e2-standard-2"
echo "Worker Disk   : pd-standard"
echo "Worker Zone   : $ZONE"
echo "Region        : $REGION"
echo ""

rm -f "$WORK_DIR/dataflow-launch.log"

nohup "$VENV_PATH/bin/python" PubSubToGCS.py \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --runner=DataflowRunner \
    --streaming \
    --job_name="$DATAFLOW_JOB" \
    --input_topic="projects/$PROJECT_ID/topics/$TOPIC_ID" \
    --output_path="$OUTPUT_PATH" \
    --window_size=2 \
    --num_shards=2 \
    --temp_location="gs://$BUCKET_NAME/temp/$DATAFLOW_JOB" \
    --staging_location="gs://$BUCKET_NAME/staging/$DATAFLOW_JOB" \
    --machine_type="e2-standard-2" \
    --worker_disk_type="$WORKER_DISK_TYPE" \
    --worker_zone="$ZONE" \
    --num_workers=1 \
    --max_num_workers=2 \
    > "$WORK_DIR/dataflow-launch.log" 2>&1 &

LAUNCH_PID=$!

echo "Local Launcher PID: $LAUNCH_PID"
echo "Launch Log        : $WORK_DIR/dataflow-launch.log"

#===============================================================================
# Wait until Dataflow job is running
#===============================================================================

section "WAIT UNTIL DATAFLOW JOB IS RUNNING"

JOB_ID=""
JOB_STATE=""

for ATTEMPT in $(seq 1 90); do
    JOB_ID=$(
        gcloud dataflow jobs list \
            --project="$PROJECT_ID" \
            --region="$REGION" \
            --filter="name=$DATAFLOW_JOB" \
            --format="value(id)" \
            --limit=1 2>/dev/null || true
    )

    if [[ -z "$JOB_ID" ]]; then
        echo -e "${YELLOW}Attempt ${ATTEMPT}/90: waiting for job submission...${NC}"
    else
        JOB_STATE=$(
            gcloud dataflow jobs describe "$JOB_ID" \
                --project="$PROJECT_ID" \
                --region="$REGION" \
                --format="value(currentState)" 2>/dev/null || true
        )

        echo "Attempt ${ATTEMPT}/90: $JOB_STATE"

        case "$JOB_STATE" in
            JOB_STATE_RUNNING)
                success "Dataflow job is running."
                break
                ;;

            JOB_STATE_FAILED|JOB_STATE_CANCELLED|JOB_STATE_DRAINED)
                error "Dataflow job entered state: $JOB_STATE"

                echo ""
                tail -n 100 "$WORK_DIR/dataflow-launch.log"
                exit 1
                ;;
        esac
    fi

    if ! kill -0 "$LAUNCH_PID" >/dev/null 2>&1 &&
       [[ -z "$JOB_ID" ]]; then

        error "Dataflow launcher stopped before creating the job."

        echo ""
        cat "$WORK_DIR/dataflow-launch.log"
        exit 1
    fi

    sleep 10
done

if [[ "$JOB_STATE" != "JOB_STATE_RUNNING" ]]; then
    error "Dataflow job did not reach JOB_STATE_RUNNING."

    echo ""
    tail -n 100 "$WORK_DIR/dataflow-launch.log"
    exit 1
fi

echo ""
echo "Dataflow Job ID: $JOB_ID"
echo "Dataflow State : $JOB_STATE"

#===============================================================================
# Publish test messages
#===============================================================================

section "PUBLISH TEST MESSAGES"

gcloud scheduler jobs run "$SCHEDULER_JOB" \
    --project="$PROJECT_ID" \
    --location="$REGION" \
    --quiet || true

for MESSAGE_NUMBER in 1 2 3 4; do
    gcloud pubsub topics publish "$TOPIC_ID" \
        --project="$PROJECT_ID" \
        --message="$MESSAGE"

    success "Published message ${MESSAGE_NUMBER}/4."
    sleep 10
done

#===============================================================================
# Check Cloud Storage output files
#===============================================================================

section "CHECK DATAFLOW OUTPUT FILES"

OUTPUT_FOUND="false"

for ATTEMPT in $(seq 1 32); do
    OUTPUT_FILES=$(
        gcloud storage ls \
            "${OUTPUT_PATH}*" \
            --project="$PROJECT_ID" 2>/dev/null || true
    )

    if [[ -n "$OUTPUT_FILES" ]]; then
        OUTPUT_FOUND="true"
        break
    fi

    echo -e "${YELLOW}Output check ${ATTEMPT}/32: waiting for the two-minute window...${NC}"
    sleep 15
done

if [[ "$OUTPUT_FOUND" != "true" ]]; then
    error "No Dataflow output file was found."

    echo ""
    echo "Check output manually:"
    echo "gcloud storage ls \"${OUTPUT_PATH}*\""
    echo ""
    echo "Check Dataflow log:"
    echo "cat \"$WORK_DIR/dataflow-launch.log\""

    exit 1
fi

success "Dataflow output files were found."

echo ""
gcloud storage ls \
    --long \
    "${OUTPUT_PATH}*" \
    --project="$PROJECT_ID"

FIRST_FILE=$(
    gcloud storage ls \
        "${OUTPUT_PATH}*" \
        --project="$PROJECT_ID" 2>/dev/null |
    head -n 1
)

if [[ -n "$FIRST_FILE" ]]; then
    echo ""
    echo -e "${CYAN}=====================================${NC}"
    echo -e "   ${YELLOW}OUTPUT FILE CONTENT${NC}"
    echo -e "${CYAN}=====================================${NC}"

    gcloud storage cat "$FIRST_FILE"
fi

#===============================================================================
# Resource summary
#===============================================================================

section "RESOURCE SUMMARY"

echo -e "${YELLOW}Pub/Sub topic:${NC}"

gcloud pubsub topics list \
    --project="$PROJECT_ID" \
    --filter="name:$TOPIC_ID" \
    --format="table(name)"

echo ""
echo -e "${YELLOW}Cloud Scheduler job:${NC}"

gcloud scheduler jobs list \
    --project="$PROJECT_ID" \
    --location="$REGION" \
    --filter="name:$SCHEDULER_JOB" \
    --format="table(name.basename():label=ID,schedule,state)"

echo ""
echo -e "${YELLOW}Cloud Storage bucket:${NC}"

gcloud storage buckets describe "gs://$BUCKET_NAME" \
    --project="$PROJECT_ID" \
    --format="yaml(name,location,storageClass)"

echo ""
echo -e "${YELLOW}Dataflow job:${NC}"

gcloud dataflow jobs list \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --filter="name:$DATAFLOW_JOB" \
    --format="table(id:label=JOB_ID,name,state,type)"

#===============================================================================
# Completion banner
#===============================================================================

echo ""
echo -e "${CYAN}=====================================${NC}"
echo -e "   ${YELLOW}Congratulations For Completing!!!${NC}"
echo -e "              ${YELLOW}ePlus.DEV${NC}"
echo -e "${CYAN}=====================================${NC}\n"

echo -e "${YELLOW}Keep the Dataflow streaming job running until Task 4 passes.${NC}"
echo ""
echo "Manual output check:"
echo "gcloud storage ls --long \"${OUTPUT_PATH}*\""