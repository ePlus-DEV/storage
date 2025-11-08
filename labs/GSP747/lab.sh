#!/bin/bash
set -e

echo "----- TASK 1: MANUAL DEPLOYMENT -----"

echo "Installing Hugo..."
cd ~
/tmp/installhugo.sh

echo "Setting project variables..."
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

echo "Installing Git and GitHub CLI..."
sudo apt-get update
sudo apt-get install git -y
sudo apt-get install gh -y

echo "Configuring GitHub CLI..."
curl -sS https://webi.sh/gh | sh
gh auth login
gh api user -q ".login"
GITHUB_USERNAME=$(gh api user -q ".login")
git config --global user.name "${GITHUB_USERNAME}"
git config --global user.email "${USER_EMAIL}"
echo ${GITHUB_USERNAME}
echo ${USER_EMAIL}

echo "Creating GitHub Repository..."
cd ~
gh repo create my_hugo_site --private
gh repo clone my_hugo_site

echo "Creating Hugo Site..."
cd ~/my_hugo_site
/tmp/hugo new site my_hugo_site --force

echo "Installing Hugo Theme: hello-friend-ng..."
git clone https://github.com/rhazdon/hugo-theme-hello-friend-ng.git themes/hello-friend-ng
echo 'theme = "hello-friend-ng"' >> config.toml

echo "Removing theme git tracking..."
sudo rm -r themes/hello-friend-ng/.git
sudo rm themes/hello-friend-ng/.gitignore

echo "Installing Firebase CLI..."
curl -sL https://firebase.tools | bash

echo "Initializing Firebase..."
cd ~/my_hugo_site
firebase init

echo "Building with Hugo and deploying with Firebase..."
/tmp/hugo && firebase deploy


echo "----- TASK 2: AUTOMATION WITH CLOUD BUILD -----"

echo "Configuring Git..."
git config --global user.name "hugo"
git config --global user.email "hugo@blogger.com"

echo "Creating .gitignore..."
cd ~/my_hugo_site
echo "resources" >> .gitignore

echo "Initial Commit to GitHub..."
git add .
git commit -m "Add app to GitHub Repository"
git push -u origin main

echo "Copying cloudbuild.yaml file..."
cp /tmp/cloudbuild.yaml .

echo "Creating GitHub Connection..."
gcloud builds connections create github cloud-build-connection --project=$PROJECT_ID --region=$REGION
gcloud builds connections describe cloud-build-connection --region=$REGION

echo ">>> PLEASE OPEN THE actionUri ABOVE TO AUTHORIZE GITHUB ACCESS <<<"

echo "Creating Cloud Build Repository..."
gcloud builds repositories create hugo-website-build-repository \
  --remote-uri="https://github.com/${GITHUB_USERNAME}/my_hugo_site.git" \
  --connection="cloud-build-connection" --region=$REGION


echo "Creating Cloud Build Trigger..."
gcloud builds triggers create github --name="commit-to-main-branch1" \
  --repository=projects/$PROJECT_ID/locations/$REGION/connections/cloud-build-connection/repositories/hugo-website-build-repository \
  --build-config='cloudbuild.yaml' \
  --service-account=projects/$PROJECT_ID/serviceAccounts/$PROJECT_NUMBER-compute@developer.gserviceaccount.com \
  --region=$REGION \
  --branch-pattern='^main$'

echo "----- SCRIPT COMPLETE -----"
echo "Now edit config.toml, push changes, and test pipeline."
