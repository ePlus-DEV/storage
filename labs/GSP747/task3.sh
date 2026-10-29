#!/usr/bin/env bash

# ePlus.DEV console banner. Presentation only; see repository LICENSE (Unlicense).
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then
  _eplus_cyan=$'\033[1;36m'
  _eplus_yellow=$'\033[0;33m'
  _eplus_reset=$'\033[0m'
else
  _eplus_cyan='' _eplus_yellow='' _eplus_reset=''
fi
printf '%s\n' "${_eplus_cyan}==========================================================${_eplus_reset}"
printf '%s\n' "${_eplus_cyan} ePlus.DEV - Starting Execution | GSP747 - Task 3${_eplus_reset}"
printf '%s\n' "${_eplus_yellow} Copyright (c) 2026 ePlus.DEV | Unlicense${_eplus_reset}"
printf '%s\n' "${_eplus_cyan}==========================================================${_eplus_reset}"
unset _eplus_cyan _eplus_yellow _eplus_reset


gcloud builds repositories create hugo-website-build-repository \
  --remote-uri="https://github.com/${GITHUB_USERNAME}/my_hugo_site.git" \
  --connection="cloud-build-connection" --region=$REGION



gcloud builds triggers create github --name="commit-to-master-branch1" \
   --repository=projects/$PROJECT_ID/locations/$REGION/connections/cloud-build-connection/repositories/hugo-website-build-repository \
   --build-config='cloudbuild.yaml' \
   --service-account=projects/$PROJECT_ID/serviceAccounts/$PROJECT_NUMBER-compute@developer.gserviceaccount.com \
   --region=$REGION \
   --branch-pattern='^master$'


cd ~/my_hugo_site

sed -i "3c\title = 'Blogging with Hugo and Cloud Build'" config.toml



git add .
git commit -m "I updated the site title"
git push -u origin master

gcloud builds submit --region=$REGION


sleep 20

LATEST_BUILD_ID=$(gcloud builds list --region=$REGION --format="value(ID)" --limit=1)
gcloud builds log $LATEST_BUILD_ID --region=$REGION


gcloud builds log "$(gcloud builds list --region=$REGION --format='value(ID)' --limit=1)" --region=$REGION | grep "Hosting URL"
LATEST_BUILD_ID=$(gcloud builds list --region=$REGION --format="value(ID)" --limit=1)
gcloud builds log $LATEST_BUILD_ID --region=$REGION


gcloud builds log "$(gcloud builds list --region=$REGION --format='value(ID)' --limit=1)" --region=$REGION | grep "Hosting URL"
