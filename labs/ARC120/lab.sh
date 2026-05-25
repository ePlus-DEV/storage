#!/bin/bash

# ==============================
# ePlus.DEV - GCP Challenge Lab
# Cloud Storage + VM + Disk + NGINX
# ==============================

BLACK=`tput setaf 0`
RED=`tput setaf 1`
GREEN=`tput setaf 2`
YELLOW=`tput setaf 3`
BLUE=`tput setaf 4`
MAGENTA=`tput setaf 5`
CYAN=`tput setaf 6`
WHITE=`tput setaf 7`
BOLD=`tput bold`
RESET=`tput sgr0`

# ------------------------------
# Required variables
# ------------------------------
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")

export BUCKET_NAME="qwiklabs-gcp-00-78bba017b619-bucket"
export INSTANCE_NAME="my-instance"
export DISK_NAME="mydisk"

echo "${CYAN}${BOLD}"
echo "================================================="
echo "        ePlus.DEV - GCP Challenge Lab"
echo "================================================="
echo "${RESET}"

echo "${YELLOW}[INFO] Region       : ${REGION}${RESET}"
echo "${YELLOW}[INFO] Zone         : ${ZONE}${RESET}"
echo "${YELLOW}[INFO] Bucket       : ${BUCKET_NAME}${RESET}"
echo "${YELLOW}[INFO] VM Instance  : ${INSTANCE_NAME}${RESET}"
echo "${YELLOW}[INFO] Disk         : ${DISK_NAME}${RESET}"
echo ""

# ------------------------------
# Step 1: Set default region/zone
# ------------------------------
echo "${BLUE}${BOLD}[1/6] Setting default region and zone...${RESET}"

gcloud config set compute/region "${REGION}"
gcloud config set compute/zone "${ZONE}"

echo "${GREEN}[OK] Default region and zone configured.${RESET}"
echo ""

# ------------------------------
# Step 2: Create Cloud Storage bucket
# ------------------------------
echo "${BLUE}${BOLD}[2/6] Creating Cloud Storage bucket...${RESET}"

if gsutil ls -b "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
  echo "${YELLOW}[SKIP] Bucket already exists: gs://${BUCKET_NAME}${RESET}"
else
  gsutil mb -l US "gs://${BUCKET_NAME}"
  echo "${GREEN}[OK] Bucket created: gs://${BUCKET_NAME}${RESET}"
fi

echo ""

# ------------------------------
# Step 3: Create Compute Engine VM
# ------------------------------
echo "${BLUE}${BOLD}[3/6] Creating Compute Engine instance...${RESET}"

if gcloud compute instances describe "${INSTANCE_NAME}" --zone="${ZONE}" >/dev/null 2>&1; then
  echo "${YELLOW}[SKIP] VM already exists: ${INSTANCE_NAME}${RESET}"
else
  gcloud compute instances create "${INSTANCE_NAME}" \
    --zone="${ZONE}" \
    --machine-type="e2-medium" \
    --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default \
    --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install -y nginx
systemctl enable nginx
systemctl start nginx' \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
    --tags=http-server \
    --create-disk=auto-delete=yes,boot=yes,device-name="${INSTANCE_NAME}",image-family=debian-12,image-project=debian-cloud,mode=rw,size=10,type=pd-balanced

  echo "${GREEN}[OK] VM created: ${INSTANCE_NAME}${RESET}"
fi

echo ""

# ------------------------------
# Step 4: Create firewall rule for HTTP
# ------------------------------
echo "${BLUE}${BOLD}[4/6] Creating firewall rule for HTTP traffic...${RESET}"

if gcloud compute firewall-rules describe default-allow-http >/dev/null 2>&1; then
  echo "${YELLOW}[SKIP] Firewall rule already exists: default-allow-http${RESET}"
else
  gcloud compute firewall-rules create default-allow-http \
    --allow=tcp:80 \
    --target-tags=http-server \
    --description="Allow HTTP traffic on port 80"

  echo "${GREEN}[OK] Firewall rule created.${RESET}"
fi

echo ""

# ------------------------------
# Step 5: Create and attach persistent disk
# ------------------------------
echo "${BLUE}${BOLD}[5/6] Creating and attaching persistent disk...${RESET}"

if gcloud compute disks describe "${DISK_NAME}" --zone="${ZONE}" >/dev/null 2>&1; then
  echo "${YELLOW}[SKIP] Disk already exists: ${DISK_NAME}${RESET}"
else
  gcloud compute disks create "${DISK_NAME}" \
    --zone="${ZONE}" \
    --size=200GB \
    --type=pd-balanced

  echo "${GREEN}[OK] Disk created: ${DISK_NAME}${RESET}"
fi

ATTACHED_DISKS=$(gcloud compute instances describe "${INSTANCE_NAME}" \
  --zone="${ZONE}" \
  --format="value(disks[].source)" | grep "${DISK_NAME}" || true)

if [ -n "${ATTACHED_DISKS}" ]; then
  echo "${YELLOW}[SKIP] Disk already attached to ${INSTANCE_NAME}${RESET}"
else
  gcloud compute instances attach-disk "${INSTANCE_NAME}" \
    --zone="${ZONE}" \
    --disk="${DISK_NAME}"

  echo "${GREEN}[OK] Disk attached to ${INSTANCE_NAME}.${RESET}"
fi

echo ""

# ------------------------------
# Step 6: Install / verify NGINX
# ------------------------------
echo "${BLUE}${BOLD}[6/6] Installing and verifying NGINX...${RESET}"

gcloud compute ssh "${INSTANCE_NAME}" \
  --zone="${ZONE}" \
  --quiet \
  --command='
    echo "[VM] Updating OS..."
    sudo apt-get update -y

    echo "[VM] Installing NGINX..."
    sudo apt-get install -y nginx

    echo "[VM] Enabling NGINX..."
    sudo systemctl enable nginx
    sudo systemctl restart nginx

    echo "[VM] Checking NGINX status..."
    sudo systemctl status nginx --no-pager || true
  '

echo ""

# ------------------------------
# Show result
# ------------------------------
EXTERNAL_IP=$(gcloud compute instances describe "${INSTANCE_NAME}" \
  --zone="${ZONE}" \
  --format="get(networkInterfaces[0].accessConfigs[0].natIP)")

echo "${GREEN}${BOLD}"
echo "================================================="
echo "              LAB SETUP COMPLETED"
echo "================================================="
echo "${RESET}"

echo "${CYAN}Bucket:${RESET} gs://${BUCKET_NAME}"
echo "${CYAN}VM:${RESET} ${INSTANCE_NAME}"
echo "${CYAN}Disk:${RESET} ${DISK_NAME}"
echo "${CYAN}External IP:${RESET} ${EXTERNAL_IP}"
echo ""
echo "${YELLOW}${BOLD}Open this URL to test NGINX:${RESET}"
echo "http://${EXTERNAL_IP}/"
echo ""
echo "${GREEN}You should see: Welcome to nginx!${RESET}"