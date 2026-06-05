#!/bin/bash

# ==========================================================
# © ePlus.DEV - Google Cloud Skills Boost Automation Script
# Network and HTTP Load Balancer Setup
# ==========================================================

# Colors - ePlus.DEV style
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

# Function to show spinner while commands run
spinner() {
    local pid=$!
    local delay=0.25
    local spinstr='|/-\'
    while ps -p $pid > /dev/null 2>&1; do
        local temp=${spinstr#?}
        printf " ${CYAN}[%c]${NC}  " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "      \b\b\b\b\b\b"
}

print_banner() {
    clear
    echo -e "${MAGENTA}${BOLD}"
    echo "============================================================"
    echo "   ______      ____  __           ____  _______    __"
    echo "  / ____/___  / / / / /___  _____/ / / / ___/ /   / /"
    echo " / / __/ __ \/ / / / / __ \/ ___/ / /  \__ \/ /   / / "
    echo "/ /_/ / /_/ / / /_/ / /_/ / /  / / /  ___/ / /___/ /___"
    echo "\____/\____/_/\____/\____/_/  /_/_/  /____/_____/_____/"
    echo "============================================================"
    echo -e "${NC}"
    echo -e "${CYAN}${BOLD}        Network and HTTP Load Balancer Lab Setup${NC}"
    echo -e "${YELLOW}${BOLD}        © ePlus.DEV - Automation Script${NC}"
    echo -e "${GREEN}        Fast. Clean. Lab-ready.${NC}"
    echo "------------------------------------------------------------"
    echo ""
}

success() {
    echo -e "${GREEN}Done${NC}"
}

info() {
    echo -e "${CYAN}$1${NC}"
}

warn() {
    echo -e "${YELLOW}$1${NC}"
}

error() {
    echo -e "${RED}$1${NC}"
}

print_banner

# Fetch zone and region
echo -ne "${CYAN}Detecting default zone and region...${NC} "

ZONE=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-zone])" 2>/dev/null)

REGION=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null)

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

sleep 1 & spinner

if [ -z "$ZONE" ]; then
    echo ""
    warn "Could not detect default zone."
    read -p "Please enter your preferred zone, example us-central1-a: " ZONE
    REGION=${ZONE%-*}
else
    echo ""
    echo -e "${GREEN}Detected Project:${NC} ${WHITE}$PROJECT_ID${NC}"
    echo -e "${GREEN}Detected Zone:${NC} ${WHITE}$ZONE${NC}"
    echo -e "${GREEN}Detected Region:${NC} ${WHITE}$REGION${NC}"
fi

echo ""

# Create web instances
info "[1/13] Creating web instances: web1, web2, web3..."

for i in {1..3}; do
    echo -ne "Creating ${WHITE}web$i${NC}... "

    gcloud compute instances create web$i \
        --zone=$ZONE \
        --machine-type=e2-small \
        --tags=network-lb-tag \
        --image-family=debian-12 \
        --image-project=debian-cloud \
        --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install apache2 -y
service apache2 restart
echo "<h3>© ePlus.DEV - Web Server: web'$i'</h3>" | tee /var/www/html/index.html' \
        > /dev/null 2>&1 &

    spinner
    success
done

echo ""

# Create firewall rule
info "[2/13] Creating firewall rule for Network Load Balancer..."

echo -ne "Creating ${WHITE}www-firewall-network-lb${NC}... "

gcloud compute firewall-rules create www-firewall-network-lb \
    --allow tcp:80 \
    --target-tags network-lb-tag \
    > /dev/null 2>&1 &

spinner
success

echo ""

# Network Load Balancer Setup
info "[3/13] Setting up Network Load Balancer..."

echo -ne "Creating static IP address... "

gcloud compute addresses create network-lb-ip-1 \
    --region=$REGION \
    > /dev/null 2>&1 &

spinner
success

echo -ne "Creating legacy HTTP health check... "

gcloud compute http-health-checks create basic-check \
    > /dev/null 2>&1 &

spinner
success

echo -ne "Creating target pool... "

gcloud compute target-pools create www-pool \
    --region=$REGION \
    --http-health-check basic-check \
    > /dev/null 2>&1 &

spinner
success

echo -ne "Adding web instances to target pool... "

gcloud compute target-pools add-instances www-pool \
    --instances web1,web2,web3 \
    --zone=$ZONE \
    > /dev/null 2>&1 &

spinner
success

echo -ne "Creating forwarding rule for Network Load Balancer... "

gcloud compute forwarding-rules create www-rule \
    --region=$REGION \
    --ports 80 \
    --address network-lb-ip-1 \
    --target-pool www-pool \
    > /dev/null 2>&1 &

spinner
success

IPADDRESS=$(gcloud compute forwarding-rules describe www-rule \
    --region=$REGION \
    --format="json" | jq -r .IPAddress)

echo -e "${GREEN}Network Load Balancer IP:${NC} ${WHITE}$IPADDRESS${NC}"
echo ""

# HTTP Load Balancer Setup
info "[4/13] Setting up HTTP Load Balancer..."

echo -ne "Creating instance template... "

gcloud compute instance-templates create lb-backend-template \
   --region=$REGION \
   --network=default \
   --subnet=default \
   --tags=allow-health-check \
   --machine-type=e2-medium \
   --image-family=debian-12 \
   --image-project=debian-cloud \
   --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install apache2 -y
a2ensite default-ssl
a2enmod ssl
vm_hostname="$(curl -H "Metadata-Flavor:Google" http://169.254.169.254/computeMetadata/v1/instance/name)"
echo "© ePlus.DEV - Page served from: $vm_hostname" | tee /var/www/html/index.html
systemctl restart apache2' \
   > /dev/null 2>&1 &

spinner
success

echo -ne "Creating managed instance group... "

gcloud compute instance-groups managed create lb-backend-group \
   --template=lb-backend-template \
   --size=2 \
   --zone=$ZONE \
   > /dev/null 2>&1 &

spinner
success

echo -ne "Creating health check firewall rule... "

gcloud compute firewall-rules create fw-allow-health-check \
  --network=default \
  --action=allow \
  --direction=ingress \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-tags=allow-health-check \
  --rules=tcp:80 \
  > /dev/null 2>&1 &

spinner
success

echo -ne "Creating global IPv4 address... "

gcloud compute addresses create lb-ipv4-1 \
  --ip-version=IPV4 \
  --global \
  > /dev/null 2>&1 &

spinner
success

LB_IP=$(gcloud compute addresses describe lb-ipv4-1 \
  --format="get(address)" \
  --global)

echo -e "${GREEN}HTTP Load Balancer IP:${NC} ${WHITE}$LB_IP${NC}"

echo -ne "Creating HTTP health check... "

gcloud compute health-checks create http http-basic-check \
  --port 80 \
  > /dev/null 2>&1 &

spinner
success

echo -ne "Creating backend service... "

gcloud compute backend-services create web-backend-service \
  --protocol=HTTP \
  --port-name=http \
  --health-checks=http-basic-check \
  --global \
  > /dev/null 2>&1 &

spinner
success

echo -ne "Adding backend to service... "

gcloud compute backend-services add-backend web-backend-service \
  --instance-group=lb-backend-group \
  --instance-group-zone=$ZONE \
  --global \
  > /dev/null 2>&1 &

spinner
success

echo -ne "Creating URL map... "

gcloud compute url-maps create web-map-http \
    --default-service web-backend-service \
    > /dev/null 2>&1 &

spinner
success

echo -ne "Creating target HTTP proxy... "

gcloud compute target-http-proxies create http-lb-proxy \
    --url-map web-map-http \
    > /dev/null 2>&1 &

spinner
success

echo -ne "Creating forwarding rule for HTTP Load Balancer... "

gcloud compute forwarding-rules create http-content-rule \
    --address=lb-ipv4-1 \
    --global \
    --target-http-proxy=http-lb-proxy \
    --ports=80 \
    > /dev/null 2>&1 &

spinner
success

echo ""
echo -e "${MAGENTA}${BOLD}============================================================${NC}"
echo -e "${GREEN}${BOLD} Setup Complete!${NC}"
echo -e "${MAGENTA}${BOLD}============================================================${NC}"
echo -e "${CYAN}Project ID:${NC} ${WHITE}$PROJECT_ID${NC}"
echo -e "${CYAN}Zone:${NC} ${WHITE}$ZONE${NC}"
echo -e "${CYAN}Region:${NC} ${WHITE}$REGION${NC}"
echo ""
echo -e "${YELLOW}Network Load Balancer IP:${NC} ${WHITE}$IPADDRESS${NC}"
echo -e "${YELLOW}HTTP Load Balancer IP:${NC} ${WHITE}$LB_IP${NC}"
echo ""
echo -e "${GREEN}Network LB Test:${NC} ${WHITE}http://$IPADDRESS${NC}"
echo -e "${GREEN}HTTP LB Test:${NC} ${WHITE}http://$LB_IP${NC}"
echo ""
echo -e "${MAGENTA}${BOLD}© ePlus.DEV - All rights reserved.${NC}"
echo -e "${MAGENTA}${BOLD}============================================================${NC}"