#!/bin/bash
# ==========================================================
#  Google Cloud Infrastructure Setup Script
# ----------------------------------------------------------
#  Author: ePlus.DEV © 2025
#  License: Proprietary – All rights reserved.
#  Description: Automates creation of web infrastructure
#               (Storage Bucket, VM, Persistent Disk, NGINX)
# ==========================================================

# 🌈 Terminal Colors
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

clear
echo -e "${MAGENTA}${BOLD}🚀 The Basics of Google Cloud Compute: Challenge Lab - ARC120 ${RESET}"
echo -e "${CYAN}Powered by ePlus.DEV © 2025 – All rights reserved.${RESET}\n"

# ==========================================================
# 📍 Project & Region Configuration
# ==========================================================
PROJECT_ID=$(gcloud config get-value project)

echo -e "${YELLOW}Detected Project:${RESET} ${GREEN}$PROJECT_ID${RESET}"

ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")

echo -e "${GREEN}✅ Zone confirmed:${RESET} $ZONE\n"

# ==========================================================
# 🔧 Variables
# ==========================================================
BUCKET_NAME="qwiklabs-gcp-00-c8124aa7472b-bucket"
INSTANCE_NAME="my-instance"
DISK_NAME="mydisk"

# ==========================================================
# 1️⃣ Create Cloud Storage Bucket
# ==========================================================
echo -e "${BLUE}🪣 Creating Cloud Storage bucket...${RESET}"
gsutil mb -l US gs://$BUCKET_NAME/
echo -e "${GREEN}✅ Bucket created:${RESET} gs://$BUCKET_NAME\n"

# ==========================================================
# 2️⃣ Create VM Instance with NGINX Startup Script
# ==========================================================
echo -e "${BLUE}🖥️ Creating Compute Engine VM instance...${RESET}"
gcloud compute instances create $INSTANCE_NAME \
  --zone=$ZONE \
  --machine-type=e2-medium \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=10GB \
  --boot-disk-type=pd-balanced \
  --tags=http-server \
  --metadata=startup-script='#!/bin/bash
    apt update -y
    apt install -y nginx
    systemctl enable nginx
    systemctl start nginx'

echo -e "${GREEN}✅ VM created:${RESET} $INSTANCE_NAME\n"

# ==========================================================
# 3️⃣ Create and Attach Persistent Disk
# ==========================================================
echo -e "${BLUE}💾 Creating persistent disk...${RESET}"
gcloud compute disks create $DISK_NAME \
  --size=200GB \
  --type=pd-balanced \
  --zone=$ZONE

echo -e "${BLUE}🔗 Attaching disk to instance...${RESET}"
gcloud compute instances attach-disk $INSTANCE_NAME \
  --disk=$DISK_NAME \
  --zone=$ZONE

echo -e "${GREEN}✅ Disk created and attached:${RESET} $DISK_NAME\n"

# ==========================================================
# 4️⃣ (Optional) Format & Mount Disk
# ==========================================================
echo -e "${BLUE}💿 Formatting and mounting disk (optional)...${RESET}"
gcloud compute ssh $INSTANCE_NAME --zone=$ZONE --command="
  sudo mkdir -p /mnt/data &&
  sudo mkfs.ext4 -F /dev/disk/by-id/google-$DISK_NAME &&
  sudo mount -o discard,defaults /dev/disk/by-id/google-$DISK_NAME /mnt/data &&
  echo '/dev/disk/by-id/google-$DISK_NAME /mnt/data ext4 discard,defaults 0 2' | sudo tee -a /etc/fstab
"
echo -e "${GREEN}✅ Disk formatted and mounted at /mnt/data${RESET}\n"

# ==========================================================
# ✅ Final Output
# ==========================================================
EXTERNAL_IP=$(gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

echo -e "${MAGENTA}${BOLD}🎉 Setup Complete!${RESET}\n"
echo -e "${CYAN}🌐 Access your NGINX web server at:${RESET} ${GREEN}http://$EXTERNAL_IP/${RESET}"
echo -e "${CYAN}🪣 Storage bucket:${RESET} ${GREEN}gs://$BUCKET_NAME${RESET}"
echo -e "${CYAN}💾 Persistent disk:${RESET} ${GREEN}$DISK_NAME (200GB)${RESET}"
echo -e "${CYAN}🖥️ VM instance:${RESET} ${GREEN}$INSTANCE_NAME${RESET}"
echo -e "\n${BOLD}✨ Infrastructure built successfully with ePlus.DEV ✨${RESET}"