#!/bin/bash
set -e

# ================== COLORS ==================
BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BOLD='\033[1m'
RESET='\033[0m'

clear

echo -e "${BLUE}${BOLD}"
echo "======================================================"
echo "   Apache Beam + Dataflow Lab Automation"
echo "   Author: ePlus.DEV"
echo "======================================================"
echo -e "${RESET}"

# ================== PROJECT INFO ==================
PROJECT_ID=$(gcloud config get-value project)
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
BUCKET_NAME="${PROJECT_ID}-bucket"
BUCKET="gs://${BUCKET_NAME}"

echo -e "${GREEN}✔ Project ID:${RESET} $PROJECT_ID"
echo -e "${GREEN}✔ Region:${RESET} $REGION"
echo -e "${GREEN}✔ Bucket:${RESET} $BUCKET"
sleep 2

# ================== SET REGION ==================
echo -e "${YELLOW}>> Setting compute region...${RESET}"
gcloud config set compute/region $REGION

# ================== ENABLE DATAFLOW API ==================
echo -e "${YELLOW}>> Restarting Dataflow API...${RESET}"
gcloud services disable dataflow.googleapis.com --quiet || true
gcloud services enable dataflow.googleapis.com --quiet

# ================== CREATE BUCKET ==================
echo -e "${YELLOW}>> Creating Cloud Storage bucket...${RESET}"
gsutil mb -l US -c STANDARD $BUCKET || echo "Bucket already exists"

# ================== RUN PYTHON 3.9 CONTAINER ==================
echo -e "${YELLOW}>> Starting Python 3.9 Docker container...${RESET}"

docker run -it --rm \
  -e DEVSHELL_PROJECT_ID=$PROJECT_ID \
  -v $HOME:/workspace \
  python:3.9 /bin/bash <<'EOF'

set -e

echo ">> Installing Apache Beam SDK..."
pip install 'apache-beam[gcp]'==2.67.0

echo ">> Running WordCount locally..."
python -m apache_beam.examples.wordcount --output local_output

echo ">> Local output:"
ls | grep local_output
cat local_output*

echo ">> Running WordCount on Dataflow..."
python -m apache_beam.examples.wordcount \
  --project $DEVSHELL_PROJECT_ID \
  --runner DataflowRunner \
  --staging_location gs://$DEVSHELL_PROJECT_ID-bucket/staging \
  --temp_location gs://$DEVSHELL_PROJECT_ID-bucket/temp \
  --output gs://$DEVSHELL_PROJECT_ID-bucket/results/output \
  --region us-east1

echo ">> Dataflow job submitted successfully"
EOF

# ================== DONE ==================
echo -e "${GREEN}${BOLD}"
echo "======================================================"
echo "   LAB COMPLETED SUCCESSFULLY"
echo "   ✔ Bucket created"
echo "   ✔ Apache Beam installed"
echo "   ✔ Local pipeline executed"
echo "   ✔ Dataflow job submitted"
echo "======================================================"
echo -e "${RESET}"

echo -e "${YELLOW}👉 Now go to:${RESET} Navigation menu → Dataflow"
echo -e "${YELLOW}👉 Wait until job status = SUCCEEDED${RESET}"
echo -e "${YELLOW}👉 Then Check my progress 🚀${RESET}"