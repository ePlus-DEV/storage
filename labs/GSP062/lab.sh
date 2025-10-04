#!/bin/bash

# Define color variables
BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'

NO_COLOR=$'\033[0m'
RESET_FORMAT=$'\033[0m'

# Define text formatting variables
BOLD_TEXT=$'\033[1m'
UNDERLINE_TEXT=$'\033[4m'

clear

# Set text styles
YELLOW=$(tput setaf 3)
BOLD=$(tput bold)
RESET=$(tput sgr0)

echo "Please set the required values for the lab"
read -p "${YELLOW}${BOLD}Enter ZONE 1 (e.g., us-east1-b): ${RESET}" ZONE_1
read -p "${YELLOW}${BOLD}Enter ZONE 2 (e.g., us-central1-b): ${RESET}" ZONE_2
read -p "${YELLOW}${BOLD}Enter VPN Shared Secret: ${RESET}" VPN_SECRET

# Export variables after collecting input
export ZONE_1
export ZONE_2
export REGION_1="${ZONE_1%-*}"
export REGION="${ZONE_2%-*}"

echo
echo "${GREEN_TEXT}${BOLD_TEXT}Setting up environment...${RESET_FORMAT}"
echo "${BLUE_TEXT}ZONE 1: $ZONE_1${RESET_FORMAT}"
echo "${BLUE_TEXT}REGION 1: $REGION_1${RESET_FORMAT}"
echo "${BLUE_TEXT}ZONE 2: $ZONE_2${RESET_FORMAT}"
echo "${BLUE_TEXT}REGION 2: $REGION${RESET_FORMAT}"

# Check authentication and project
echo
echo "${YELLOW}${BOLD}Checking authentication and project...${RESET}"
gcloud auth list
export PROJECT_ID=$(gcloud config get-value project)
echo "${BLUE_TEXT}PROJECT_ID: $PROJECT_ID${RESET_FORMAT}"

echo
echo "${GREEN_TEXT}${BOLD_TEXT}Starting VPN Network Setup...${RESET_FORMAT}"
echo "${MAGENTA_TEXT}This lab is part of Dr. Abhishek Cloud Tutorials${RESET_FORMAT}"

# Create cloud network
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}Creating Cloud network...${RESET_FORMAT}"
gcloud compute networks create cloud --subnet-mode custom

# Create firewall rules for cloud
echo "${YELLOW_TEXT}${BOLD_TEXT}Creating firewall rules for cloud network...${RESET_FORMAT}"
gcloud compute firewall-rules create cloud-fw --network cloud --allow tcp:22,tcp:5001,udp:5001,icmp

# Create cloud subnet
echo "${YELLOW_TEXT}${BOLD_TEXT}Creating cloud-east subnet...${RESET_FORMAT}"
gcloud compute networks subnets create cloud-east --network cloud \
    --range 10.0.1.0/24 --region $REGION_1

# Create on-prem network
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}Creating On-prem network...${RESET_FORMAT}"
gcloud compute networks create on-prem --subnet-mode custom

# Create firewall rules for on-prem
echo "${YELLOW_TEXT}${BOLD_TEXT}Creating firewall rules for on-prem network...${RESET_FORMAT}"
gcloud compute firewall-rules create on-prem-fw --network on-prem --allow tcp:22,tcp:5001,udp:5001,icmp

# Create on-prem subnet
echo "${YELLOW_TEXT}${BOLD_TEXT}Creating on-prem-central subnet...${RESET_FORMAT}"
gcloud compute networks subnets create on-prem-central \
    --network on-prem --range 192.168.1.0/24 --region $REGION

# Create VPN gateways
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}Creating VPN Gateways...${RESET_FORMAT}"
gcloud compute target-vpn-gateways create on-prem-gw1 --network on-prem --region $REGION
gcloud compute target-vpn-gateways create cloud-gw1 --network cloud --region $REGION_1

# Create static IP addresses
echo "${YELLOW_TEXT}${BOLD_TEXT}Creating static IP addresses...${RESET_FORMAT}"
gcloud compute addresses create cloud-gw1 --region $REGION_1
gcloud compute addresses create on-prem-gw1 --region $REGION

# Get IP addresses
cloud_gw1_ip=$(gcloud compute addresses describe cloud-gw1 \
    --region $REGION_1 --format='value(address)')

on_prem_gw_ip=$(gcloud compute addresses describe on-prem-gw1 \
    --region $REGION --format='value(address)')

echo "${BLUE_TEXT}Cloud Gateway IP: $cloud_gw1_ip${RESET_FORMAT}"
echo "${BLUE_TEXT}On-prem Gateway IP: $on_prem_gw_ip${RESET_FORMAT}"

# Create forwarding rules for cloud gateway
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}Creating forwarding rules for Cloud Gateway...${RESET_FORMAT}"
gcloud compute forwarding-rules create cloud-1-fr-esp --ip-protocol ESP \
    --address $cloud_gw1_ip --target-vpn-gateway cloud-gw1 --region $REGION_1

gcloud compute forwarding-rules create cloud-1-fr-udp500 --ip-protocol UDP \
    --ports 500 --address $cloud_gw1_ip --target-vpn-gateway cloud-gw1 --region $REGION_1

gcloud compute forwarding-rules create cloud-fr-1-udp4500 --ip-protocol UDP \
    --ports 4500 --address $cloud_gw1_ip --target-vpn-gateway cloud-gw1 --region $REGION_1

# Create forwarding rules for on-prem gateway
echo "${YELLOW_TEXT}${BOLD_TEXT}Creating forwarding rules for On-prem Gateway...${RESET_FORMAT}"
gcloud compute forwarding-rules create on-prem-fr-esp --ip-protocol ESP \
    --address $on_prem_gw_ip --target-vpn-gateway on-prem-gw1 --region $REGION

gcloud compute forwarding-rules create on-prem-fr-udp500 --ip-protocol UDP --ports 500 \
    --address $on_prem_gw_ip --target-vpn-gateway on-prem-gw1 --region $REGION

gcloud compute forwarding-rules create on-prem-fr-udp4500 --ip-protocol UDP --ports 4500 \
    --address $on_prem_gw_ip --target-vpn-gateway on-prem-gw1 --region $REGION

# Create VPN tunnels
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}Creating VPN Tunnels...${RESET_FORMAT}"
gcloud compute vpn-tunnels create on-prem-tunnel1 --peer-address $cloud_gw1_ip \
    --target-vpn-gateway on-prem-gw1 --ike-version 2 --local-traffic-selector 0.0.0.0/0 \
    --remote-traffic-selector 0.0.0.0/0 --shared-secret=$VPN_SECRET --region $REGION

gcloud compute vpn-tunnels create cloud-tunnel1 --peer-address $on_prem_gw_ip \
    --target-vpn-gateway cloud-gw1 --ike-version 2 --local-traffic-selector 0.0.0.0/0 \
    --remote-traffic-selector 0.0.0.0/0 --shared-secret=$VPN_SECRET --region $REGION_1

# Create routes
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}Creating Network Routes...${RESET_FORMAT}"
gcloud compute routes create on-prem-route1 --destination-range 10.0.1.0/24 \
    --network on-prem --next-hop-vpn-tunnel on-prem-tunnel1 \
    --next-hop-vpn-tunnel-region $REGION

gcloud compute routes create cloud-route1 --destination-range 192.168.1.0/24 \
    --network cloud --next-hop-vpn-tunnel cloud-tunnel1 --next-hop-vpn-tunnel-region $REGION_1

# Create test instances
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}Creating Test Instances...${RESET_FORMAT}"
gcloud compute instances create "cloud-loadtest" --zone $ZONE_1 \
    --machine-type "e2-standard-4" --subnet "cloud-east" \
    --image-family "debian-11" --image-project "debian-cloud" --boot-disk-size "10" \
    --boot-disk-type "pd-standard" --boot-disk-device-name "cloud-loadtest"

gcloud compute instances create "on-prem-loadtest" --zone $ZONE_2 \
    --machine-type "e2-standard-4" --subnet "on-prem-central" \
    --image-family "debian-11" --image-project "debian-cloud" --boot-disk-size "10" \
    --boot-disk-type "pd-standard" --boot-disk-device-name "on-prem-loadtest"

echo
echo "${GREEN_TEXT}${BOLD_TEXT}Waiting for instances to be ready...${RESET_FORMAT}"
sleep 60

# Run network performance test
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}Starting Network Performance Test...${RESET_FORMAT}"
echo "${MAGENTA_TEXT}Testing VPN connectivity between cloud and on-prem networks${RESET_FORMAT}"

# Start iperf server on on-prem instance
echo "${BLUE_TEXT}Starting iperf server on on-prem instance...${RESET_FORMAT}"
gcloud compute ssh --zone "$ZONE_2" "on-prem-loadtest" --project "$PROJECT_ID" --quiet --command "sudo apt-get update && sudo apt-get install -y iperf && iperf -s -i 5" &

echo "${BLUE_TEXT}Waiting for server to start...${RESET_FORMAT}"
sleep 10

# Run iperf client from cloud instance
echo "${BLUE_TEXT}Running iperf client from cloud instance...${RESET_FORMAT}"
gcloud compute ssh --zone "$ZONE_1" "cloud-loadtest" --project "$PROJECT_ID" --quiet --command "sudo apt-get update && sudo apt-get install -y iperf && iperf -c 192.168.1.2 -P 20 -x C"

# Final message with Dr. Abhishek references
echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}        VPN NETWORKING LAB COMPLETED SUCCESSFULLY!     ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo
echo "${BLUE_TEXT}${BOLD_TEXT}https://eplus.dev${RESET_FORMAT}"