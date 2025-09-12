#!/bin/bash
set -euo pipefail

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

#----------------------------------------------------start--------------------------------------------------#
echo "${BG_MAGENTA}${BOLD}Starting Execution - ePlus.DEV ${RESET}"

if [[ -z "${REPO_NAME:-}" ]]; then
  read -rp "Enter REPO_NAME: " REPO_NAME
fi

if [[ -z "${DOCKER_IMAGE:-}" ]]; then
  read -rp "Enter DOCKER_IMAGE: " DOCKER_IMAGE
fi

if [[ -z "${TAG_NAME:-}" ]]; then
  read -rp "Enter TAG_NAME: " TAG_NAME
fi

export ZONE=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-zone])")

export REGION="${ZONE%-*}"

gcloud auth list
source <(gsutil cat gs://cloud-training/gsp318/marking/setup_marking_v2.sh)
gsutil cp gs://spls/gsp318/valkyrie-app.tgz .
tar -xzf valkyrie-app.tgz
cd valkyrie-app
cat > Dockerfile <<EOF
FROM golang:1.10
WORKDIR /go/src/app
COPY source .  
RUN go install -v
ENTRYPOINT ["app","-single=true","-port=8080"]
EOF

docker build -t "$DOCKER_IMAGE:$TAG_NAME" .
bash ~/marking/step1_v2.sh
docker run -p 8080:8080 "$DOCKER_IMAGE:$TAG_NAME" &
bash ~/marking/step2_v2.sh

gcloud artifacts repositories create "$REPO_NAME" \
    --repository-format=docker \
    --location="$REGION" \
    --description="subscribe to quicklab" \
    --async 

gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet

sleep 30

Image_ID=$(docker images --format='{{.ID}}' | head -n 1)

docker tag "$Image_ID" "$REGION-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$REPO_NAME/$DOCKER_IMAGE:$TAG_NAME"
docker push "$REGION-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$REPO_NAME/$DOCKER_IMAGE:$TAG_NAME"

sed -i "s#IMAGE_HERE#$REGION-docker.pkg.dev/$DEVSHELL_PROJECT_ID/$REPO_NAME/$DOCKER_IMAGE:$TAG_NAME#g" k8s/deployment.yaml

gcloud container clusters get-credentials valkyrie-dev --zone "$ZONE"
kubectl create -f k8s/deployment.yaml
kubectl create -f k8s/service.yaml

bash ~/marking/step2_v2.sh

echo "${BG_RED}${BOLD}Congratulations For Completing!!! - ePlus.DEV ${RESET}"
#-----------------------------------------------------end----------------------------------------------------------#
