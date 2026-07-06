#!/bin/bash
set -e

# =====================================================================
#  ePlus.DEV - Artifact Analysis / Vulnerability Scanning Lab Solver
#  Copyright (c) ePlus.DEV. All rights reserved.
# =====================================================================

# ---------- Colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

banner() {
  clear
  echo -e "${CYAN}=====================================================================${NC}"
  echo -e "${BOLD}${MAGENTA}        ePlus.DEV - Artifact Analysis Vulnerability Lab${NC}"
  echo -e "${CYAN}=====================================================================${NC}"
  echo -e "${GREEN} Copyright (c) ePlus.DEV. All rights reserved.${NC}"
  echo -e "${YELLOW} Region: ${REGION:-auto} | Scan Location: ${SCAN_LOCATION:-auto}${NC}"
  echo -e "${CYAN}=====================================================================${NC}"
  echo ""
}

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

run() {
  echo -e "${CYAN}>>> $*${NC}"
  "$@"
}

# ---------- Configuration ----------
# This lab uses Artifact Registry in us-central1 and On-Demand Scanning location us.
# You may override before running:
#   REGION=europe-west4 SCAN_LOCATION=europe ./eplus_artifact_scan_lab.sh
REGION="${REGION:-us-central1}"
SCAN_LOCATION="${SCAN_LOCATION:-us}"
REPO_NAME="artifact-scanning-repo"
IMAGE_NAME="sample-image"
WORKDIR="vuln-scan"

banner

# ---------- Validate project ----------
PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  error "PROJECT_ID is not set. Run: gcloud config set project YOUR_PROJECT_ID"
  exit 1
fi

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
IMAGE_PATH="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${IMAGE_NAME}"

success "PROJECT_ID=$PROJECT_ID"
success "PROJECT_NUMBER=$PROJECT_NUMBER"
success "REGION=$REGION"
success "SCAN_LOCATION=$SCAN_LOCATION"

# ---------- Enable APIs ----------
info "Enabling required APIs..."
run gcloud services enable \
  cloudkms.googleapis.com \
  cloudbuild.googleapis.com \
  container.googleapis.com \
  containerregistry.googleapis.com \
  artifactregistry.googleapis.com \
  containerscanning.googleapis.com \
  ondemandscanning.googleapis.com \
  binaryauthorization.googleapis.com
success "Required APIs enabled."

# ---------- IAM for Cloud Build ----------
info "Granting Cloud Build permissions..."
run gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser" \
  --quiet

run gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/ondemandscanning.admin" \
  --quiet
success "Cloud Build permissions configured."

# ---------- Work directory ----------
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# ---------- Task 1: Build image with Cloud Build ----------
info "Creating vulnerable sample application..."
cat > Dockerfile <<'EOF_DOCKER'
FROM gcr.io/google-appengine/debian11

# System
RUN apt update && apt install python3-pip -y

# App
WORKDIR /app
COPY . ./

RUN pip3 install Flask==1.1.4
RUN pip3 install gunicorn==20.1.0

CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 main:app
EOF_DOCKER

cat > main.py <<'EOF_PY'
import os
from flask import Flask

app = Flask(__name__)

@app.route("/")
def hello_world():
    name = os.environ.get("NAME", "Worlds")
    return "Hello {}!".format(name)

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
EOF_PY

cat > cloudbuild.yaml <<EOF_CB1
steps:
- id: "build"
  name: "gcr.io/cloud-builders/docker"
  args: ["build", "-t", "${IMAGE_PATH}", "."]
  waitFor: ["-"]
EOF_CB1

info "Task 1: Building image with Cloud Build..."
run gcloud builds submit
success "Task 1 completed."

# ---------- Task 2: Artifact Registry ----------
info "Creating Artifact Registry repository if needed..."
if gcloud artifacts repositories describe "$REPO_NAME" --location="$REGION" >/dev/null 2>&1; then
  warn "Repository already exists: $REPO_NAME"
else
  run gcloud artifacts repositories create "$REPO_NAME" \
    --repository-format=docker \
    --location="$REGION" \
    --description="Docker repository"
fi

run gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

cat > cloudbuild.yaml <<EOF_CB2
steps:
- id: "build"
  name: "gcr.io/cloud-builders/docker"
  args: ["build", "-t", "${IMAGE_PATH}", "."]
  waitFor: ["-"]

- id: "push"
  name: "gcr.io/cloud-builders/docker"
  args: ["push", "${IMAGE_PATH}"]

images:
- "${IMAGE_PATH}"
EOF_CB2

info "Task 2: Building and pushing image to Artifact Registry..."
run gcloud builds submit
success "Task 2 completed."

# ---------- Task 4: On-Demand Scanning ----------
info "Task 4: Building local Docker image..."
run docker build -t "$IMAGE_PATH" .

info "Starting On-Demand vulnerability scan..."
gcloud artifacts docker images scan "$IMAGE_PATH" \
  --format="value(response.scan)" > scan_id.txt

success "Scan ID: $(cat scan_id.txt)"
info "Listing vulnerabilities..."
run gcloud artifacts docker images list-vulnerabilities "$(cat scan_id.txt)"

info "Checking for CRITICAL vulnerabilities..."
if gcloud artifacts docker images list-vulnerabilities "$(cat scan_id.txt)" \
  --format="value(vulnerability.effectiveSeverity)" | grep -Fxq CRITICAL; then
  warn "Failed vulnerability check for CRITICAL level. This is expected for the vulnerable image."
else
  success "No CRITICAL vulnerabilities found."
fi

# ---------- Task 5: CI/CD scanning expected failure ----------
info "Creating Cloud Build pipeline with vulnerability scan. First run should fail if CRITICAL vulnerabilities exist."
cat > cloudbuild.yaml <<EOF_CB3
steps:
- id: "build"
  name: "gcr.io/cloud-builders/docker"
  args: ["build", "-t", "${IMAGE_PATH}", "."]
  waitFor: ["-"]

- id: "scan"
  name: "gcr.io/cloud-builders/gcloud"
  entrypoint: "bash"
  args:
  - "-c"
  - |
    (gcloud artifacts docker images scan \
    ${IMAGE_PATH} \
    --location ${SCAN_LOCATION} \
    --format="value(response.scan)") > /workspace/scan_id.txt

- id: "severity check"
  name: "gcr.io/cloud-builders/gcloud"
  entrypoint: "bash"
  args:
  - "-c"
  - |
    gcloud artifacts docker images list-vulnerabilities \$(cat /workspace/scan_id.txt) \
    --format="value(vulnerability.effectiveSeverity)" | if grep -Fxq CRITICAL; \
    then echo "Failed vulnerability check for CRITICAL level" && exit 1; \
    else echo "No CRITICAL vulnerability found, congrats !" && exit 0; fi

- id: "retag"
  name: "gcr.io/cloud-builders/docker"
  args: ["tag", "${IMAGE_PATH}", "${IMAGE_PATH}:good"]

- id: "push"
  name: "gcr.io/cloud-builders/docker"
  args: ["push", "${IMAGE_PATH}:good"]

images:
- "${IMAGE_PATH}"
EOF_CB3

set +e
gcloud builds submit
BUILD_STATUS=$?
set -e

if [[ $BUILD_STATUS -ne 0 ]]; then
  success "Build failed on CRITICAL vulnerability as expected."
else
  warn "Build did not fail. Continue to fixed image step."
fi

# ---------- Fix vulnerability ----------
info "Fixing vulnerability by replacing Dockerfile with safer base image..."
cat > Dockerfile <<'EOF_DOCKER_FIXED'
FROM python:3.12-alpine

# App
WORKDIR /app
COPY . ./

RUN pip3 install Flask==3.0.3
RUN pip3 install gunicorn==22.0.0
RUN pip3 install Werkzeug==3.0.3

CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 main:app
EOF_DOCKER_FIXED

info "Submitting fixed build. This should succeed."
run gcloud builds submit

success "Lab completed by ePlus.DEV."
echo -e "${CYAN}=====================================================================${NC}"
echo -e "${BOLD}${GREEN}DONE - ePlus.DEV${NC}"
echo -e "${CYAN}=====================================================================${NC}"
