#!/bin/bash
set -euo pipefail

# Define color variables
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

echo "${BG_MAGENTA}${BOLD}Starting Execution - ePlus.DEV${RESET}"

ZONE=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
REGION=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])")
PROJECT_ID=$(gcloud config get-value project)



cd continuous-deployment-on-kubernetes/sample-app

git checkout -b new-feature
rm Jenkinsfile html.go main.go

wget https://raw.githubusercontent.com/quiccklabs/Labs_solutions/refs/heads/master/Continuous%20Delivery%20with%20Jenkins%20in%20Kubernetes%20Engine/Jenkinsfile
wget https://raw.githubusercontent.com/quiccklabs/Labs_solutions/refs/heads/master/Continuous%20Delivery%20with%20Jenkins%20in%20Kubernetes%20Engine/html.go
wget https://raw.githubusercontent.com/quiccklabs/Labs_solutions/refs/heads/master/Continuous%20Delivery%20with%20Jenkins%20in%20Kubernetes%20Engine/main.go


sed -i "s/qwiklabs-gcp-01-2848c53eb4b6/$PROJECT_ID/g" Jenkinsfile

sed -i "s/us-central1-c/$ZONE/g" Jenkinsfile

git add Jenkinsfile html.go main.go

git commit -m "Version 2.0.0"

git push origin new-feature

git checkout -b canary

git push origin canary

git checkout master

git merge canary

git push origin master


echo "${BG_RED}${BOLD}Congratulations For Completing The Lab !!! - ePlus.DEV${RESET}"