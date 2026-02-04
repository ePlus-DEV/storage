#!/bin/bash
# Dr. Abhishek's Jenkins on GKE Deployment Script

# Modern Color Definitions
BLACK=$(tput setaf 0)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)

BG_BLACK=$(tput setab 0)
BG_RED=$(tput setab 1)
BG_GREEN=$(tput setab 2)
BG_YELLOW=$(tput setab 3)
BG_BLUE=$(tput setab 4)
BG_MAGENTA=$(tput setab 5)
BG_CYAN=$(tput setab 6)
BG_WHITE=$(tput setab 7)

BOLD=$(tput bold)
RESET=$(tput sgr0)

# Modern Box Drawing Characters
BOX_TOP="╔══════════════════════════════════════╗"
BOX_MID="║              EPLUS.DEV               ║"
BOX_BOT="╚══════════════════════════════════════╝"

#----------------------------------------------------start--------------------------------------------------#

# Header with Dr. Abhishek branding
clear
echo "${CYAN}${BOLD}${BOX_TOP}"
echo "${BOX_MID}"
echo "  🚀 Dr. Abhishek's Jenkins CD on GKE Setup  "
echo "${BOX_MID}"
echo "${BOX_BOT}${RESET}"
echo
echo "${WHITE}📺 YouTube: ${BLUE}https://eplus.dev${RESET}"
echo "${WHITE}⭐ Please Subscribe for More Cloud Tutorials! ⭐${RESET}"
echo

# Function to set and export zone
set_zone() {
    echo "${BLUE}${BOLD}🌍 Zone Configuration${RESET}"
    
    # Try to get default zone
    export ZONE=$(gcloud config get-value compute/zone 2>/dev/null)
    
    if [ -z "$ZONE" ]; then
        echo "${YELLOW}No default zone configured.${RESET}"
        echo "${CYAN}Available zones in your project:${RESET}"
        gcloud compute zones list --format="value(name)" | sort | pr -3 -t
        
        while true; do
            read -p "${BOLD}Enter your preferred zone (e.g., us-central1-a): ${RESET}" ZONE
            if gcloud compute zones describe $ZONE &>/dev/null; then
                break
            else
                echo "${RED}Invalid zone. Please try again.${RESET}"
            fi
        done
        
        # Set zone in gcloud config
        gcloud config set compute/zone $ZONE
    fi
    
    echo "${GREEN}Using zone: ${BOLD}$ZONE${RESET}"
    export ZONE
}

# Set and export zone
set_zone

# Main execution
echo
echo "${MAGENTA}${BOLD}${BOX_TOP}"
echo "  Starting Jenkins CD Deployment  "
echo "${BOX_BOT}${RESET}"

echo "${CYAN}${BOLD}🔧 Step 1: Cloning CD on Kubernetes repository...${RESET}"
git clone https://github.com/GoogleCloudPlatform/continuous-deployment-on-kubernetes.git
cd continuous-deployment-on-kubernetes || exit

echo "${CYAN}${BOLD}⚙️ Step 2: Creating GKE cluster for Jenkins...${RESET}"
gcloud container clusters create jenkins-cd \
--num-nodes 2 \
--scopes "https://www.googleapis.com/auth/projecthosting,cloud-platform" \
--zone $ZONE

echo "${CYAN}${BOLD}🔗 Step 3: Configuring kubectl credentials...${RESET}"
gcloud container clusters get-credentials jenkins-cd --zone $ZONE

echo "${CYAN}${BOLD}📦 Step 4: Setting up Helm charts...${RESET}"
helm repo add jenkins https://charts.jenkins.io
helm repo update

echo "${CYAN}${BOLD}🚀 Step 5: Deploying Jenkins...${RESET}"
helm upgrade --install -f jenkins/values.yaml myjenkins jenkins/jenkins

# Completion message
echo
echo "${GREEN}${BOLD}${BOX_TOP}"
echo "  🎉 Jenkins Deployment Completed Successfully!  "
echo "${BOX_BOT}${RESET}"
echo
echo "${YELLOW}Don't forget to subscribe: ${BLUE}https://eplus.dev${RESET}"
echo

#-----------------------------------------------------end----------------------------------------------------------#