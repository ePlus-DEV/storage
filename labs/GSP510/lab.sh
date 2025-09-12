#!/bin/bash
# ========================================================
# GKE Challenge Lab - Full Automation Script
# Copyright (c) 2025 ePlus.DEV. All rights reserved.
# ========================================================

# ===== Color Variables =====
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# ===== Required Inputs =====
echo "${MAGENTA}${BOLD}>>> Please provide required inputs <<<${RESET}"

read -p "${CYAN}${BOLD}Enter Cluster Name (e.g., hello-world-3kxq): ${RESET}" CLUSTER
read -p "${CYAN}${BOLD}Enter Namespace (e.g., gmp-veiz): ${RESET}" NAMESPACE
read -p "${CYAN}${BOLD}Enter Artifact Registry Repo (e.g., sandbox-repo): ${RESET}" REPO

if [[ -z "$CLUSTER" || -z "$NAMESPACE" || -z "$REPO" ]]; then
  echo "${RED}${BOLD}❌ You must provide CLUSTER, NAMESPACE, and REPO!${RESET}"
  exit 1
fi

# ===== Environment Variables =====
PROJECT_ID=$(gcloud config get-value project)
ZONE="europe-west4-a"
REGION="europe-west4"

echo "${YELLOW}==========================================${RESET}"
echo "${GREEN} Project ID : $PROJECT_ID${RESET}"
echo "${GREEN} Cluster    : $CLUSTER${RESET}"
echo "${GREEN} Namespace  : $NAMESPACE${RESET}"
echo "${GREEN} Repo       : $REPO${RESET}"
echo "${GREEN} Zone       : $ZONE${RESET}"
echo "${GREEN} Region     : $REGION${RESET}"
echo "${YELLOW}==========================================${RESET}"

# --------------------------------------------------------
# Task 1. Create GKE Cluster
# --------------------------------------------------------
echo "${BLUE}${BOLD}▶ Task 1: Creating GKE cluster...${RESET}"
gcloud container clusters create $CLUSTER \
  --zone $ZONE \
  --release-channel regular \
  --cluster-version 1.27.8-gke.1066000 \
  --enable-autoscaling \
  --num-nodes 3 \
  --min-nodes 2 \
  --max-nodes 6

gcloud container clusters get-credentials $CLUSTER --zone $ZONE

# --------------------------------------------------------
# Task 2. Enable Managed Prometheus
# --------------------------------------------------------
echo "${BLUE}${BOLD}▶ Task 2: Enabling Managed Prometheus...${RESET}"
gcloud container clusters update $CLUSTER \
  --zone $ZONE \
  --enable-managed-prometheus

kubectl create namespace $NAMESPACE

gsutil cp gs://spls/gsp510/prometheus-app.yaml .

# Patch Prometheus sample
sed -i 's|<todo>|prometheus-test|' prometheus-app.yaml
sed -i 's|containers.image:.*|containers.image: nilebox/prometheus-example-app:latest|' prometheus-app.yaml
sed -i 's|containers.name:.*|containers.name: prometheus-test|' prometheus-app.yaml
sed -i 's|ports.name:.*|ports.name: metrics|' prometheus-app.yaml

kubectl apply -f prometheus-app.yaml -n $NAMESPACE

# Pod monitoring
gsutil cp gs://spls/gsp510/pod-monitoring.yaml .

sed -i 's|<todo>|prometheus-test|' pod-monitoring.yaml
sed -i 's|labels.app.kubernetes.io/name:.*|labels.app.kubernetes.io/name: prometheus-test|' pod-monitoring.yaml
sed -i 's|matchLabels.app:.*|matchLabels.app: prometheus-test|' pod-monitoring.yaml
sed -i 's|endpoints.interval:.*|endpoints.interval: 50s|' pod-monitoring.yaml

kubectl apply -f pod-monitoring.yaml -n $NAMESPACE

# --------------------------------------------------------
# Task 3. Deploy helloweb (expected error)
# --------------------------------------------------------
echo "${BLUE}${BOLD}▶ Task 3: Deploying helloweb (with invalid image)...${RESET}"
gsutil cp -r gs://spls/gsp510/hello-app/ .
kubectl apply -f hello-app/manifests/helloweb-deployment.yaml -n $NAMESPACE

# --------------------------------------------------------
# Task 4. Logs-based metric & alert
# --------------------------------------------------------
echo "${YELLOW}${BOLD}▶ Task 4: Manual step required in Cloud Console!${RESET}"
echo "  1. Go to Logs Explorer."
echo "  2. Run query: ${CYAN}resource.type=\"k8s_container\" severity>=ERROR${RESET}"
echo "  3. Create log-based metric: ${BOLD}pod-image-errors${RESET} (Counter)."
echo "  4. Create Alerting Policy '${BOLD}Pod Error Alert${RESET}' with threshold >0."

# --------------------------------------------------------
# Task 5. Fix deployment
# --------------------------------------------------------
echo "${BLUE}${BOLD}▶ Task 5: Fixing deployment with correct image...${RESET}"
sed -i 's|image:.*|image: us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0|' hello-app/manifests/helloweb-deployment.yaml

kubectl delete deploy helloweb -n $NAMESPACE
kubectl apply -f hello-app/manifests/helloweb-deployment.yaml -n $NAMESPACE

# --------------------------------------------------------
# Task 6. Containerize v2 and deploy
# --------------------------------------------------------
echo "${BLUE}${BOLD}▶ Task 6: Building v2 image and deploying...${RESET}"
# Update main.go manually (line 49 → Version: 2.0.0)
sed -i 's/Version:.*/Version: 2.0.0"/' hello-app/main.go

IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO/hello-app:v2"

gcloud auth configure-docker $REGION-docker.pkg.dev -q
docker build -t $IMAGE hello-app/
docker push $IMAGE

sed -i "s|image:.*|image: $IMAGE|" hello-app/manifests/helloweb-deployment.yaml

kubectl apply -f hello-app/manifests/helloweb-deployment.yaml -n $NAMESPACE

kubectl expose deploy helloweb \
  --name=helloweb-service-2xml \
  --type=LoadBalancer \
  --port 8080 --target-port 8080 \
  -n $NAMESPACE

echo "${GREEN}${BOLD}✅ Script finished. Check service external IP:${RESET}"
kubectl get svc helloweb-service-2xml -n $NAMESPACE