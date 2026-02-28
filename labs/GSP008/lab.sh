#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# ePlus.DEV © 2026 - Earthquake Pipeline AUTO
# Color + Auto Detect Zone/Region
# ============================================================

# ---------- COLORS ----------
BOLD=$(tput bold 2>/dev/null || true)
RESET=$(tput sgr0 2>/dev/null || true)
RED=$(tput setaf 1 2>/dev/null || true)
GREEN=$(tput setaf 2 2>/dev/null || true)
YELLOW=$(tput setaf 3 2>/dev/null || true)
BLUE=$(tput setaf 4 2>/dev/null || true)
MAGENTA=$(tput setaf 5 2>/dev/null || true)
CYAN=$(tput setaf 6 2>/dev/null || true)

hr(){ printf "%s%s============================================================%s\n" "$BLUE" "$BOLD" "$RESET"; }
step(){ printf "%s%s➜ %s%s\n" "$CYAN" "$BOLD" "$*" "$RESET"; }
ok(){ printf "%s%s✔ %s%s\n" "$GREEN" "$BOLD" "$*" "$RESET"; }

clear
hr
printf "%s%s  ePlus.DEV © 2026 - EARTHQUAKE LAB AUTO  %s\n" "$MAGENTA" "$BOLD" "$RESET"
hr

# ---------- AUTO DETECT ----------
PROJECT_ID=$(gcloud config get-value project)

export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")

gcloud config set compute/zone "$ZONE" --quiet
gcloud config set compute/region "$REGION" --quiet

INSTANCE_NAME="earthquake-vm"
BUCKET_NAME="${PROJECT_ID}-earthquake-$(date +%s)"

ok "Project: $PROJECT_ID"
ok "Zone:    $ZONE"
ok "Region:  $REGION"
ok "Bucket:  $BUCKET_NAME"

# ---------- CREATE VM ----------
step "Creating VM"
gcloud compute instances create $INSTANCE_NAME \
  --zone=$ZONE \
  --machine-type=e2-medium \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --scopes=https://www.googleapis.com/auth/cloud-platform \
  --quiet

ok "VM Created"

sleep 20

# ---------- CREATE BUCKET ----------
step "Creating Cloud Storage bucket"
gsutil mb -l $REGION gs://$BUCKET_NAME
gsutil uniformbucketlevelaccess set off gs://$BUCKET_NAME

ok "Bucket Created"

# ---------- RUN PIPELINE ON VM ----------
step "Running ingest + transform inside VM"

gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command "

set -e

sudo apt-get update -y >/dev/null
sudo apt-get -y -qq install git python3.11-venv >/dev/null

python3 -m venv earthquake-data
source earthquake-data/bin/activate

wget -q https://storage.googleapis.com/spls/gsp008/requirements.txt
pip3 install -q -r requirements.txt

git clone -q https://github.com/GoogleCloudPlatform/training-data-analyst
cd training-data-analyst/CPB100/lab2b

bash ingest.sh
python3 transform.py

gsutil cp earthquakes.* gs://$BUCKET_NAME/earthquakes/

"

ok "Data processed and uploaded"

# ---------- MAKE PUBLIC ----------
step "Making files public"

gsutil iam ch allUsers:objectViewer gs://$BUCKET_NAME/earthquakes/earthquakes.png
gsutil iam ch allUsers:objectViewer gs://$BUCKET_NAME/earthquakes/earthquakes.htm

hr
ok "DONE"

printf "%sPNG:%s https://storage.googleapis.com/%s/earthquakes/earthquakes.png\n" "$YELLOW" "$RESET" "$BUCKET_NAME"
printf "%sHTML:%s https://storage.googleapis.com/%s/earthquakes/earthquakes.htm\n" "$YELLOW" "$RESET" "$BUCKET_NAME"

hr