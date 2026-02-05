#!/bin/bash
# ============================================================
#  Google Cloud VM + NGINX Setup Script
#  Author: ePlus.DEV (Nguyễn Ngọc Minh Hoàng)
#  Description: Creates VM, installs NGINX, enables HTTP access
#  Version: 1.0
#  © 2025 ePlus.DEV - All rights reserved
# ============================================================

# 🟡 Set project region/zone (⚠️ Edit if needed)
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")

# 🌍 Configure gcloud defaults
echo -e "\033[1;36m📍 Setting region and zone...\033[0m"
gcloud config set compute/region $REGION
gcloud config set compute/zone $ZONE

# 🖥️ Create VM Instance
echo -e "\033[1;36m🖥️ Creating VM instance 'gcelab'...\033[0m"
gcloud compute instances create gcelab \
  --machine-type=e2-medium \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=10GB \
  --tags=http-server

# 🌐 Allow HTTP traffic (port 80)
echo -e "\033[1;36m🔓 Configuring firewall rules for HTTP...\033[0m"
gcloud compute firewall-rules create allow-http \
  --allow tcp:80 \
  --target-tags=http-server \
  --description="Allow HTTP traffic on port 80"

# 🪄 Connect to VM and install NGINX
echo -e "\033[1;36m🔧 Connecting to VM and installing NGINX...\033[0m"
gcloud compute ssh gcelab --zone=$ZONE --command "
  echo -e '\033[1;33m📦 Updating packages...\033[0m'
  sudo apt-get update -y

  echo -e '\033[1;33m🌐 Installing NGINX...\033[0m'
  sudo apt-get install -y nginx

  echo -e '\033[1;33m⚙️ Enabling and starting NGINX service...\033[0m'
  sudo systemctl enable nginx
  sudo systemctl start nginx

  echo -e '\033[1;32m✅ NGINX status:\033[0m'
  sudo systemctl status nginx --no-pager
"

# 📡 Output External IP for browser check
echo -e "\033[1;36m🌐 Getting External IP...\033[0m"
EXTERNAL_IP=$(gcloud compute instances describe gcelab --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
echo -e "\033[1;32m✅ Setup complete! Visit: http://$EXTERNAL_IP/\033[0m"
