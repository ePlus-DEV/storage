#!/bin/bash

# ANSI color codes
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${CYAN}=====================================${NC}"
echo -e "   ${YELLOW}Copyright (c) 2025 ePlus.DEV${NC}"
echo -e "${CYAN}=====================================${NC}\n"

echo "Please export the values."
echo ""

# Prompt user to input values
read -p "Enter REGION (e.g. us-west1): " REGION
read -p "Enter ZONE (e.g. us-west1-a): " ZONE

PROJECT_ID=$(gcloud config get-value project)
BUCKET_NAME="${PROJECT_ID}-bucket"
TOPIC_ID="my-id"
MESSAGE="Hello!"
SCHEDULER_JOB="publisher-job"

export PROJECT_ID
export BUCKET_NAME
export TOPIC_ID
export MESSAGE
export REGION
export ZONE

echo ""
echo -e "${CYAN}=====================================${NC}"
echo -e "   ${YELLOW}LAB CONFIGURATION${NC}"
echo -e "${CYAN}=====================================${NC}"
echo "PROJECT_ID : $PROJECT_ID"
echo "BUCKET     : gs://$BUCKET_NAME"
echo "TOPIC_ID   : $TOPIC_ID"
echo "MESSAGE    : $MESSAGE"
echo "REGION     : $REGION"
echo "ZONE       : $ZONE"
echo ""

gcloud config set compute/region "$REGION"
gcloud config set compute/zone "$ZONE"

#======================================================================#
# Disable and enable APIs
#======================================================================#

echo ""
echo -e "${CYAN}=====================================${NC}"
echo -e "   ${YELLOW}RESET DATAFLOW API${NC}"
echo -e "${CYAN}=====================================${NC}"

gcloud services disable dataflow.googleapis.com \
  --project="$PROJECT_ID" \
  --force \
  --quiet || true

sleep 5

gcloud services enable \
  dataflow.googleapis.com \
  cloudscheduler.googleapis.com \
  pubsub.googleapis.com \
  appengine.googleapis.com \
  compute.googleapis.com \
  storage.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet

echo -e "${CYAN}Dataflow API has been enabled.${NC}"

sleep 20

#======================================================================#
# Task 1 - Create Cloud Storage bucket
#======================================================================#

echo ""
echo -e "${CYAN}=====================================${NC}"
echo -e "   ${YELLOW}TASK 1 - CREATE PROJECT RESOURCES${NC}"
echo -e "${CYAN}=====================================${NC}"

if gsutil ls -b "gs://$BUCKET_NAME" >/dev/null 2>&1; then
  echo -e "${YELLOW}Bucket already exists: gs://$BUCKET_NAME${NC}"
else
  gsutil mb \
    -p "$PROJECT_ID" \
    -l "$REGION" \
    "gs://$BUCKET_NAME"
fi

# Create Pub/Sub topic
if gcloud pubsub topics describe "$TOPIC_ID" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then

  echo -e "${YELLOW}Topic already exists: $TOPIC_ID${NC}"
else
  gcloud pubsub topics create "$TOPIC_ID" \
    --project="$PROJECT_ID"
fi

# Create App Engine application
if gcloud app describe \
  --project="$PROJECT_ID" >/dev/null 2>&1; then

  echo -e "${YELLOW}App Engine application already exists.${NC}"
else
  if [ "$REGION" == "us-central1" ]; then
    gcloud app create \
      --project="$PROJECT_ID" \
      --region="us-central" \
      --quiet

  elif [ "$REGION" == "europe-west1" ]; then
    gcloud app create \
      --project="$PROJECT_ID" \
      --region="europe-west" \
      --quiet

  else
    gcloud app create \
      --project="$PROJECT_ID" \
      --region="$REGION" \
      --quiet
  fi
fi

#======================================================================#
# Create Cloud Scheduler job
#======================================================================#

echo ""
echo -e "${CYAN}=====================================${NC}"
echo -e "   ${YELLOW}CREATE CLOUD SCHEDULER JOB${NC}"
echo -e "${CYAN}=====================================${NC}"

sleep 20

if gcloud scheduler jobs describe "$SCHEDULER_JOB" \
  --project="$PROJECT_ID" \
  --location="$REGION" >/dev/null 2>&1; then

  echo -e "${YELLOW}Scheduler job already exists. Updating...${NC}"

  gcloud scheduler jobs update pubsub "$SCHEDULER_JOB" \
    --project="$PROJECT_ID" \
    --location="$REGION" \
    --schedule="* * * * *" \
    --time-zone="Etc/UTC" \
    --topic="$TOPIC_ID" \
    --message-body="$MESSAGE" \
    --quiet
else
  gcloud scheduler jobs create pubsub "$SCHEDULER_JOB" \
    --project="$PROJECT_ID" \
    --location="$REGION" \
    --schedule="* * * * *" \
    --time-zone="Etc/UTC" \
    --topic="$TOPIC_ID" \
    --message-body="$MESSAGE" \
    --quiet
fi

echo -e "${CYAN}Cloud Scheduler job created.${NC}"

# Start Scheduler
gcloud scheduler jobs run "$SCHEDULER_JOB" \
  --project="$PROJECT_ID" \
  --location="$REGION"

sleep 20

#======================================================================#
# Task 4 - Prepare Python environment
#======================================================================#

echo ""
echo -e "${CYAN}=====================================${NC}"
echo -e "   ${YELLOW}TASK 4 - PREPARE DATAFLOW PIPELINE${NC}"
echo -e "${CYAN}=====================================${NC}"

WORK_DIR="$HOME/pubsub-dataflow"
VENV_DIR="$WORK_DIR/venv"
DATAFLOW_LOG="$WORK_DIR/dataflow.log"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Download only required source files
curl -fsSL \
  "https://raw.githubusercontent.com/GoogleCloudPlatform/python-docs-samples/main/pubsub/streaming-analytics/PubSubToGCS.py" \
  -o PubSubToGCS.py

curl -fsSL \
  "https://raw.githubusercontent.com/GoogleCloudPlatform/python-docs-samples/main/pubsub/streaming-analytics/requirements.txt" \
  -o requirements.txt

if [ ! -s "PubSubToGCS.py" ]; then
  echo -e "${RED}Could not download PubSubToGCS.py.${NC}"
  exit 1
fi

# Select a compatible Python version
if command -v python3.11 >/dev/null 2>&1; then
  PYTHON_BIN="python3.11"
elif command -v python3.12 >/dev/null 2>&1; then
  PYTHON_BIN="python3.12"
elif command -v python3.10 >/dev/null 2>&1; then
  PYTHON_BIN="python3.10"
else
  PYTHON_BIN="python3"
fi

echo "Python version:"
"$PYTHON_BIN" --version

# Recreate virtual environment
rm -rf "$VENV_DIR"

"$PYTHON_BIN" -m venv "$VENV_DIR"

"$VENV_DIR/bin/python" -m pip install \
  --upgrade \
  pip \
  setuptools \
  wheel

"$VENV_DIR/bin/python" -m pip install \
  -r requirements.txt

# Verify Apache Beam
"$VENV_DIR/bin/python" -c \
  "import apache_beam; print('Apache Beam:', apache_beam.__version__)"

#======================================================================#
# Task 4 - Run Dataflow pipeline
#======================================================================#

echo ""
echo -e "${CYAN}=====================================${NC}"
echo -e "   ${YELLOW}TASK 4 - RUN DATAFLOW PIPELINE${NC}"
echo -e "${CYAN}=====================================${NC}"

DATAFLOW_JOB="pubsub-to-gcs-$(date +%Y%m%d-%H%M%S)"

WORKER_DISK_TYPE="compute.googleapis.com/projects/${PROJECT_ID}/zones/${ZONE}/diskTypes/pd-standard"

echo "Job Name      : $DATAFLOW_JOB"
echo "Project       : $PROJECT_ID"
echo "Region        : $REGION"
echo "Zone          : $ZONE"
echo "Input Topic   : projects/$PROJECT_ID/topics/$TOPIC_ID"
echo "Output Path   : gs://$BUCKET_NAME/samples/output"
echo "Window Size   : 2 minutes"
echo "Machine Type  : e2-standard-2"
echo "Worker Disk   : pd-standard"
echo ""

rm -f "$DATAFLOW_LOG"

nohup "$VENV_DIR/bin/python" PubSubToGCS.py \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --input_topic="projects/$PROJECT_ID/topics/$TOPIC_ID" \
  --output_path="gs://$BUCKET_NAME/samples/output" \
  --runner=DataflowRunner \
  --streaming \
  --job_name="$DATAFLOW_JOB" \
  --window_size=2 \
  --num_shards=2 \
  --temp_location="gs://$BUCKET_NAME/temp/$DATAFLOW_JOB" \
  --staging_location="gs://$BUCKET_NAME/staging/$DATAFLOW_JOB" \
  --machine_type="e2-standard-2" \
  --worker_disk_type="$WORKER_DISK_TYPE" \
  --worker_zone="$ZONE" \
  --num_workers=1 \
  --max_num_workers=2 \
  > "$DATAFLOW_LOG" 2>&1 &

DATAFLOW_PID=$!

echo "Local Dataflow launcher PID: $DATAFLOW_PID"
echo "Dataflow log: $DATAFLOW_LOG"

#======================================================================#
# Wait for Dataflow job
#======================================================================#

echo ""
echo -e "${CYAN}=====================================${NC}"
echo -e "   ${YELLOW}WAITING FOR DATAFLOW JOB${NC}"
echo -e "${CYAN}=====================================${NC}"

JOB_ID=""
JOB_STATE=""

for ATTEMPT in $(seq 1 90); do
  JOB_ID=$(gcloud dataflow jobs list \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --filter="name=$DATAFLOW_JOB" \
    --format="value(id)" \
    --limit=1 2>/dev/null || true)

  if [ -z "$JOB_ID" ]; then
    echo -e "${YELLOW}Attempt $ATTEMPT/90: waiting for job submission...${NC}"
  else
    JOB_STATE=$(gcloud dataflow jobs describe "$JOB_ID" \
      --project="$PROJECT_ID" \
      --region="$REGION" \
      --format="value(currentState)" 2>/dev/null || true)

    echo "Attempt $ATTEMPT/90: $JOB_STATE"

    if [ "$JOB_STATE" == "JOB_STATE_RUNNING" ]; then
      echo -e "${CYAN}Dataflow job is running.${NC}"
      break
    fi

    if [ "$JOB_STATE" == "JOB_STATE_FAILED" ] ||
       [ "$JOB_STATE" == "JOB_STATE_CANCELLED" ]; then

      echo -e "${RED}Dataflow job failed: $JOB_STATE${NC}"
      tail -n 100 "$DATAFLOW_LOG"
      exit 1
    fi
  fi

  if ! kill -0 "$DATAFLOW_PID" >/dev/null 2>&1 &&
     [ -z "$JOB_ID" ]; then

    echo -e "${RED}Dataflow launcher stopped before submitting the job.${NC}"
    cat "$DATAFLOW_LOG"
    exit 1
  fi

  sleep 10
done

if [ "$JOB_STATE" != "JOB_STATE_RUNNING" ]; then
  echo -e "${RED}Dataflow job did not reach RUNNING state.${NC}"
  tail -n 100 "$DATAFLOW_LOG"
  exit 1
fi

echo ""
echo "Dataflow Job ID: $JOB_ID"

#======================================================================#
# Publish messages after Dataflow starts
#======================================================================#

echo ""
echo -e "${CYAN}=====================================${NC}"
echo -e "   ${YELLOW}PUBLISH TEST MESSAGES${NC}"
echo -e "${CYAN}=====================================${NC}"

gcloud scheduler jobs run "$SCHEDULER_JOB" \
  --project="$PROJECT_ID" \
  --location="$REGION" \
  --quiet || true

for NUMBER in 1 2 3 4; do
  gcloud pubsub topics publish "$TOPIC_ID" \
    --project="$PROJECT_ID" \
    --message="$MESSAGE"

  echo "Published message $NUMBER/4"
  sleep 10
done

#======================================================================#
# Check output files
#======================================================================#

echo ""
echo -e "${CYAN}=====================================${NC}"
echo -e "   ${YELLOW}CHECK DATAFLOW OUTPUT${NC}"
echo -e "${CYAN}=====================================${NC}"

OUTPUT_FOUND="false"

for ATTEMPT in $(seq 1 32); do
  OUTPUT_FILES=$(gsutil ls \
    "gs://${BUCKET_NAME}/samples/output*" 2>/dev/null || true)

  if [ -n "$OUTPUT_FILES" ]; then
    OUTPUT_FOUND="true"
    break
  fi

  echo -e "${YELLOW}Waiting for the two-minute window $ATTEMPT/32...${NC}"
  sleep 15
done

if [ "$OUTPUT_FOUND" == "true" ]; then
  echo -e "${CYAN}Dataflow output files were found.${NC}"
  echo ""

  gsutil ls -l "gs://${BUCKET_NAME}/samples/"

  FIRST_FILE=$(gsutil ls \
    "gs://${BUCKET_NAME}/samples/output*" 2>/dev/null |
    head -n 1)

  if [ -n "$FIRST_FILE" ]; then
    echo ""
    echo -e "${CYAN}=====================================${NC}"
    echo -e "   ${YELLOW}OUTPUT FILE CONTENT${NC}"
    echo -e "${CYAN}=====================================${NC}"

    gsutil cat "$FIRST_FILE"
  fi
else
  echo -e "${YELLOW}No output file has appeared yet.${NC}"
  echo "Run this command later:"
  echo "gsutil ls gs://${BUCKET_NAME}/samples/"
fi

#======================================================================#
# Completion banner
#======================================================================#

echo ""
echo -e "${CYAN}=====================================${NC}"
echo -e "   ${YELLOW}Congratulations For Completing!!!${NC}"
echo -e "              ${YELLOW}ePlus.DEV${NC}"
echo -e "${CYAN}=====================================${NC}\n"

echo -e "${YELLOW}Keep the Dataflow job running until the lab check passes.${NC}"
echo ""
echo "Check output manually:"
echo "gsutil ls gs://${BUCKET_NAME}/samples/"
echo ""
echo "View Dataflow log:"
echo "cat $DATAFLOW_LOG"