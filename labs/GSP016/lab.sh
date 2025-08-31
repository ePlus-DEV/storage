#!/bin/bash
# Define color variables
BLACK=`tput setaf 0`
RED=`tput setaf 1`
GREEN=`tput setaf 2`
YELLOW=`tput setaf 3`
BLUE=`tput setaf 4`
MAGENTA=`tput setaf 5`
CYAN=`tput setaf 6`
WHITE=`tput setaf 7`

BG_BLACK=`tput setab 0`
BG_RED=`tput setab 1`
BG_GREEN=`tput setab 2`
BG_YELLOW=`tput setab 3`
BG_BLUE=`tput setab 4`
BG_MAGENTA=`tput setab 5`
BG_CYAN=`tput setab 6`
BG_WHITE=`tput setab 7`

BOLD=`tput bold`
RESET=`tput sgr0`

# Function to display section headers
section_header() {
    echo
    echo "${BG_BLUE}${BOLD}${WHITE}╔══════════╗${RESET}"
    echo "${BG_BLUE}${BOLD}${WHITE}  ePlus.DEV  $1${RESET}"
    echo "${BG_BLUE}${BOLD}${WHITE}╚══════════╝${RESET}"
    echo
}

# Function to show progress spinner
spinner() {
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Welcome message
clear
section_header " Lab Setup"
echo "${GREEN}${BOLD}This script will configure a custom GCP network environment${RESET}"
echo "${CYAN}For more cloud tutorials, visit: https:/epluss.dev${RESET}"
echo

# Start execution
echo "${BG_MAGENTA}${BOLD}Starting Network Configuration${RESET}"

# Network Creation
section_header "Creating Custom Network"
echo "${BLUE}${BOLD}Creating taw-custom-network...${RESET}"
(gcloud compute networks create taw-custom-network --subnet-mode custom > /dev/null 2>&1) & spinner
echo "${GREEN}✓ Network created successfully${RESET}"

# Subnet Creation
section_header "Creating Subnets"
echo "${BLUE}${BOLD}Creating subnets in specified regions...${RESET}"

echo "${YELLOW}Creating subnet-$REGION_1...${RESET}"
(gcloud compute networks subnets create subnet-$REGION_1 \
   --network taw-custom-network \
   --region $REGION_1 \
   --range 10.0.0.0/16 > /dev/null 2>&1) & spinner
echo "${GREEN}✓ subnet-$REGION_1 created${RESET}"

echo "${YELLOW}Creating subnet-$REGION_2...${RESET}"
(gcloud compute networks subnets create subnet-$REGION_2 \
   --network taw-custom-network \
   --region $REGION_2 \
   --range 10.1.0.0/16 > /dev/null 2>&1) & spinner
echo "${GREEN}✓ subnet-$REGION_2 created${RESET}"

echo "${YELLOW}Creating subnet-$REGION_3...${RESET}"
(gcloud compute networks subnets create subnet-$REGION_3 \
   --network taw-custom-network \
   --region $REGION_3 \
   --range 10.2.0.0/16 > /dev/null 2>&1) & spinner
echo "${GREEN}✓ subnet-$REGION_3 created${RESET}"

# Firewall Rules
section_header "Configuring Firewall Rules"
echo "${BLUE}${BOLD}Setting up firewall rules...${RESET}"

echo "${YELLOW}Creating HTTP rule...${RESET}"
(gcloud compute firewall-rules create nw101-allow-http \
--allow tcp:80 --network taw-custom-network --source-ranges 0.0.0.0/0 \
--target-tags http > /dev/null 2>&1) & spinner
echo "${GREEN}✓ HTTP rule created${RESET}"

echo "${YELLOW}Creating ICMP rule...${RESET}"
(gcloud compute firewall-rules create "nw101-allow-icmp" \
--allow icmp --network "taw-custom-network" --source-ranges 0.0.0.0/0 \
--target-tags rules > /dev/null 2>&1) & spinner
echo "${GREEN}✓ ICMP rule created${RESET}"

echo "${YELLOW}Creating internal traffic rule...${RESET}"
(gcloud compute firewall-rules create "nw101-allow-internal" \
--allow tcp:0-65535,udp:0-65535,icmp --network "taw-custom-network" \
--source-ranges "10.0.0.0/16","10.2.0.0/16","10.1.0.0/16" > /dev/null 2>&1) & spinner
echo "${GREEN}✓ Internal traffic rule created${RESET}"

echo "${YELLOW}Creating SSH rule...${RESET}"
(gcloud compute firewall-rules create "nw101-allow-ssh" \
--allow tcp:22 --network "taw-custom-network" --target-tags "ssh" > /dev/null 2>&1) & spinner
echo "${GREEN}✓ SSH rule created${RESET}"

echo "${YELLOW}Creating RDP rule...${RESET}"
(gcloud compute firewall-rules create "nw101-allow-rdp" \
--allow tcp:3389 --network "taw-custom-network" > /dev/null 2>&1) & spinner
echo "${GREEN}✓ RDP rule created${RESET}"

# Completion message
section_header "Lab Completed Successfully!"
echo "${BG_GREEN}${BOLD}${BLACK}Congratulations on completing Lab!${RESET}"
echo
echo "${MAGENTA}${BOLD}For more cloud computing tutorials and labs:${RESET}"
echo