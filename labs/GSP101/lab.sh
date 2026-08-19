#!/bin/bash

# ============================================================
# Colors
# ============================================================
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'
TEAL_TEXT=$'\033[38;5;50m'

BOLD_TEXT=$'\033[1m'
RESET_FORMAT=$'\033[0m'

clear

# ============================================================
# Banner
# ============================================================
echo "${CYAN_TEXT}${BOLD_TEXT}"
echo "======================================================================"
echo "                   GOOGLE CLOUD VM SETUP"
echo "                       © ePlus.DEV"
echo "======================================================================"
echo "${RESET_FORMAT}"

# ============================================================
# Detect Project ID
# ============================================================
PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
    echo "${RED_TEXT}✗ Could not detect Project ID.${RESET_FORMAT}"
    return 1 2>/dev/null || exit 1
fi

export DEVSHELL_PROJECT_ID="$PROJECT_ID"

# ============================================================
# Input Instance Name
# ============================================================
echo "${CYAN_TEXT}${BOLD_TEXT}Please enter the required value:${RESET_FORMAT}"
echo

read -rp "$(echo "${YELLOW_TEXT}Instance name: ${RESET_FORMAT}")" INSTANCE_NAME

export INSTANCE_NAME

if [[ -z "$INSTANCE_NAME" ]]; then
    echo
    echo "${RED_TEXT}✗ Instance name cannot be empty.${RESET_FORMAT}"
    return 1 2>/dev/null || exit 1
fi

REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)
ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])" 2>/dev/null || true)

echo
echo "${GREEN_TEXT}${BOLD_TEXT}✓ Configuration${RESET_FORMAT}"
echo "  Instance name : ${CYAN_TEXT}${INSTANCE_NAME}${RESET_FORMAT}"
echo "  Zone          : ${CYAN_TEXT}${ZONE}${RESET_FORMAT}"
echo "  Project ID    : ${CYAN_TEXT}${PROJECT_ID}${RESET_FORMAT}"
echo

# ============================================================
# Create VM
# ============================================================
echo "${CYAN_TEXT}${BOLD_TEXT}======================================================================"
echo "[1/4] Creating Compute Engine instance"
echo "======================================================================${RESET_FORMAT}"
echo

gcloud compute instances create "$INSTANCE_NAME" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --machine-type=f1-micro \
    --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default \
    --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install apache2 -y
systemctl enable apache2
systemctl start apache2
',enable-oslogin=true \
    --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD \
    --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append \
    --tags=http-server,https-server \
    --create-disk=auto-delete=yes,boot=yes,device-name="$INSTANCE_NAME",image=projects/debian-cloud/global/images/debian-12-bookworm-v20240312,mode=rw,size=10,type=projects/"$PROJECT_ID"/zones/"$ZONE"/diskTypes/pd-balanced \
    --no-shielded-secure-boot \
    --shielded-vtpm \
    --shielded-integrity-monitoring \
    --labels=goog-ec-src=vm_add-gcloud \
    --reservation-affinity=any

if [[ $? -ne 0 ]]; then
    echo
    echo "${RED_TEXT}✗ Failed to create instance.${RESET_FORMAT}"
    return 1 2>/dev/null || exit 1
fi

echo
echo "${GREEN_TEXT}✓ Instance created successfully.${RESET_FORMAT}"

# ============================================================
# Get External IP
# ============================================================
echo
echo "${CYAN_TEXT}${BOLD_TEXT}======================================================================"
echo "[2/4] Getting external IP"
echo "======================================================================${RESET_FORMAT}"
echo

IP="$(gcloud compute instances describe "$INSTANCE_NAME" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --format='get(networkInterfaces[0].accessConfigs[0].natIP)')"

if [[ -z "$IP" ]]; then
    echo "${RED_TEXT}✗ Could not determine external IP.${RESET_FORMAT}"
    return 1 2>/dev/null || exit 1
fi

echo "${GREEN_TEXT}✓ External IP:${RESET_FORMAT} ${YELLOW_TEXT}${IP}${RESET_FORMAT}"

# ============================================================
# Firewall
# ============================================================
echo
echo "${CYAN_TEXT}${BOLD_TEXT}======================================================================"
echo "[3/4] Configuring HTTP firewall rule"
echo "======================================================================${RESET_FORMAT}"
echo

if gcloud compute firewall-rules describe allow-http \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

    echo "${YELLOW_TEXT}⚠ Firewall rule allow-http already exists. Skipping.${RESET_FORMAT}"

else

    gcloud compute firewall-rules create allow-http \
        --project="$PROJECT_ID" \
        --network=default \
        --action=ALLOW \
        --direction=INGRESS \
        --target-tags=http-server \
        --source-ranges=0.0.0.0/0 \
        --rules=tcp:80 \
        --description="Allow incoming HTTP traffic"

    echo "${GREEN_TEXT}✓ Firewall rule created.${RESET_FORMAT}"
fi

# ============================================================
# Wait for Apache
# ============================================================
echo
echo "${CYAN_TEXT}${BOLD_TEXT}======================================================================"
echo "[4/4] Waiting for Apache web server"
echo "======================================================================${RESET_FORMAT}"
echo

SUCCESS=false

for i in {1..12}; do

    printf "\r${YELLOW_TEXT}Checking Apache... %02d/12${RESET_FORMAT}" "$i"

    if curl -fsS --connect-timeout 5 "http://${IP}" >/dev/null 2>&1; then
        SUCCESS=true
        break
    fi

    sleep 5
done

echo
echo

if [[ "$SUCCESS" == "true" ]]; then
    echo "${GREEN_TEXT}${BOLD_TEXT}✓ Apache is running!${RESET_FORMAT}"
else
    echo "${YELLOW_TEXT}⚠ Apache may still be starting. Continue with the lab.${RESET_FORMAT}"
fi

# ============================================================
# Complete
# ============================================================
echo
echo "${CYAN_TEXT}${BOLD_TEXT}======================================================================"
echo "                         LAB COMPLETE"
echo "======================================================================${RESET_FORMAT}"
echo
echo "${GREEN_TEXT}Instance name :${RESET_FORMAT} $INSTANCE_NAME"
echo "${GREEN_TEXT}Zone          :${RESET_FORMAT} $ZONE"
echo "${GREEN_TEXT}External IP   :${RESET_FORMAT} $IP"
echo "${GREEN_TEXT}Web Server    :${RESET_FORMAT} ${CYAN_TEXT}http://${IP}${RESET_FORMAT}"
echo
echo "${MAGENTA_TEXT}${BOLD_TEXT}                         © ePlus.DEV${RESET_FORMAT}"
echo