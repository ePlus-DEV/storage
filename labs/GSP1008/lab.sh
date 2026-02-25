#!/bin/bash

# ========================= NEW COLOR DEFINITIONS =========================
ROYAL_BLUE=$'\033[38;5;27m'
NEON_GREEN=$'\033[38;5;46m'
ORANGE=$'\033[38;5;208m'
WHITE=$'\033[1;97m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

clear

# ========================= SPINNER FUNCTION =========================
spinner() {
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'
    while ps -p $pid > /dev/null 2>&1; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# ========================= WELCOME MESSAGE =========================
echo "${ROYAL_BLUE}${BOLD}============================================================${RESET}"
echo "${NEON_GREEN}${BOLD}                   🚀 EPLUS.DEV 🚀${RESET}"
echo "${ROYAL_BLUE}${BOLD}============================================================${RESET}"
echo
echo "${WHITE}Welcome to this automated Google Cloud setup script.${RESET}"
echo
echo "${NEON_GREEN}${BOLD}https://eplus.dev${RESET}"
echo
sleep 2

# ========================= USER INPUT SECTION =========================
echo "${ROYAL_BLUE}${BOLD}Enter Region & Zone Details${RESET}"
echo

read -p "Enter Region 1: " region1
read -p "Enter Zone 1: " zone1
read -p "Enter Region 2: " region2
read -p "Enter Zone 2: " zone2
read -p "Enter Region 3: " region3
read -p "Enter Zone 3: " zone3

if [[ -z "$region1" || -z "$zone1" || -z "$region2" || -z "$zone2" || -z "$region3" || -z "$zone3" ]]; then
    echo "${ORANGE}${BOLD}ERROR: All values required.${RESET}"
    exit 1
fi

echo "${NEON_GREEN}${BOLD}✔ Region & Zone captured successfully${RESET}"
echo

# ========================= AUTH INFO =========================
gcloud auth list
gcloud config list project

# ========================= ENABLE SERVICES =========================
echo "${ROYAL_BLUE}Enabling required services...${RESET}"
gcloud services enable compute.googleapis.com dns.googleapis.com >/dev/null 2>&1 &
spinner
echo "${NEON_GREEN}✔ Services Enabled${RESET}"
echo

# ========================= FIREWALL RULES =========================
echo "${ROYAL_BLUE}Creating firewall rules...${RESET}"
gcloud compute firewall-rules create fw-default-iapproxy \
--direction=INGRESS \
--priority=1000 \
--network=default \
--action=ALLOW \
--rules=tcp:22,icmp \
--source-ranges=35.235.240.0/20 >/dev/null 2>&1 &

spinner

gcloud compute firewall-rules create allow-http-traffic \
--direction=INGRESS \
--priority=1000 \
--network=default \
--action=ALLOW \
--rules=tcp:80 \
--source-ranges=0.0.0.0/0 \
--target-tags=http-server >/dev/null 2>&1 &

spinner
echo "${NEON_GREEN}✔ Firewall Rules Created${RESET}"
echo

# ========================= CLIENT VMs =========================
echo "${ROYAL_BLUE}Creating Client VMs...${RESET}"

gcloud compute instances create us-client-vm --machine-type e2-micro --zone $zone1 >/dev/null 2>&1 & spinner
gcloud compute instances create europe-client-vm --machine-type e2-micro --zone $zone2 >/dev/null 2>&1 & spinner
gcloud compute instances create asia-client-vm --machine-type e2-micro --zone $zone3 >/dev/null 2>&1 & spinner

echo "${NEON_GREEN}✔ Client VMs Created${RESET}"
echo

# ========================= WEB VMs =========================
echo "${ROYAL_BLUE}Creating Web VMs...${RESET}"

gcloud compute instances create us-web-vm \
--zone=$zone1 \
--machine-type=e2-micro \
--network=default \
--subnet=default \
--tags=http-server \
--metadata=startup-script="#! /bin/bash
apt-get update -y
apt-get install apache2 -y
echo 'Page served from: $region1 - Dr Abhishek' > /var/www/html/index.html
systemctl restart apache2" >/dev/null 2>&1 &

spinner

gcloud compute instances create europe-web-vm \
--zone=$zone2 \
--machine-type=e2-micro \
--network=default \
--subnet=default \
--tags=http-server \
--metadata=startup-script="#! /bin/bash
apt-get update -y
apt-get install apache2 -y
echo 'Page served from: $region2 - Dr Abhishek' > /var/www/html/index.html
systemctl restart apache2" >/dev/null 2>&1 &

spinner

echo "${NEON_GREEN}✔ Web VMs Created${RESET}"
echo

# ========================= DNS =========================
echo "${ROYAL_BLUE}Configuring Cloud DNS...${RESET}"

US_WEB_IP=$(gcloud compute instances describe us-web-vm --zone=$zone1 --format="value(networkInterfaces.networkIP)")
EUROPE_WEB_IP=$(gcloud compute instances describe europe-web-vm --zone=$zone2 --format="value(networkInterfaces.networkIP)")

gcloud dns managed-zones create example \
--description=test \
--dns-name=example.com \
--networks=default \
--visibility=private >/dev/null 2>&1 &

spinner

gcloud dns record-sets create geo.example.com \
--ttl=5 \
--type=A \
--zone=example \
--routing-policy-type=GEO \
--routing-policy-data="$region1=$US_WEB_IP;$region2=$EUROPE_WEB_IP" >/dev/null 2>&1 &

spinner

echo "${NEON_GREEN}✔ DNS Configured${RESET}"

# ========================= COMPLETION =========================
echo
echo "${ROYAL_BLUE}${BOLD}============================================================${RESET}"
echo "${NEON_GREEN}${BOLD}              🎉 LAB COMPLETED SUCCESSFULLY 🎉${RESET}"
echo "${ROYAL_BLUE}${BOLD}============================================================${RESET}"
echo
echo "${ORANGE}${BOLD}Subscribe for more Cloud Labs & Automation:${RESET}"
echo "${NEON_GREEN}${BOLD}https://eplus.dev${RESET}"
echo