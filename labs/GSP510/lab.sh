#!/bin/bash
# ========================================================
# GKE Challenge Lab - Full Automation Script (Tasks 1→6)
# Copyright (c) 2025 ePlus.DEV
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

read -p "${CYAN}${BOLD}Enter Cluster Name (e.g., hello-world-xxxx): ${RESET}" CLUSTER
read -p "${CYAN}${BOLD}Enter Namespace (e.g., gmp-xxxx): ${RESET}" NAMESPACE
read -p "${CYAN}${BOLD}Enter Artifact Registry Repo (e.g., demo-repo): ${RESET}" REPO
read -p "${CYAN}${BOLD}Enter PodMonitoring interval (default 30s): ${RESET}" INTERVAL

if [[ -z "$CLUSTER" || -z "$NAMESPACE" || -z "$REPO" ]]; then
  echo "${RED}${BOLD}❌ You must provide CLUSTER, NAMESPACE, and REPO!${RESET}"
  exit 1
fi

if [[ -z "$INTERVAL" ]]; then
  INTERVAL="30s"
fi

# ===== Environment Variables =====
PROJECT_ID=$(gcloud config get-value project)
ZONE="us-east1-c"
REGION="us-east1"

echo "${YELLOW}==========================================${RESET}"
echo "${GREEN} Project ID : $PROJECT_ID${RESET}"
echo "${GREEN} Cluster    : $CLUSTER${RESET}"
echo "${GREEN} Namespace  : $NAMESPACE${RESET}"
echo "${GREEN} Repo       : $REPO${RESET}"
echo "${GREEN} Interval   : $INTERVAL${RESET}"
echo "${GREEN} Zone       : $ZONE${RESET}"
echo "${GREEN} Region     : $REGION${RESET}"
echo "${YELLOW}==========================================${RESET}"

# --------------------------------------------------------
# Task 1. Create GKE Cluster
# --------------------------------------------------------
echo "${BLUE}${BOLD}▶ Task 1: Creating GKE cluster...${RESET}"
VERSION=$(gcloud container get-server-config --zone $ZONE --format="value(validMasterVersions[0])")

gcloud container clusters create $CLUSTER \
  --zone $ZONE \
  --release-channel regular \
  --cluster-version $VERSION \
  --enable-autoscaling \
  --num-nodes 3 \
  --min-nodes 2 \
  --max-nodes 6

gcloud container clusters get-credentials $CLUSTER --zone $ZONE
kubectl get nodes

# --------------------------------------------------------
# Task 2. Enable Managed Prometheus
# --------------------------------------------------------
echo "${BLUE}${BOLD}▶ Task 2: Enabling Managed Prometheus...${RESET}"
gcloud container clusters update $CLUSTER --zone $ZONE --enable-managed-prometheus

kubectl delete namespace $NAMESPACE --ignore-not-found
kubectl create namespace $NAMESPACE

# Prometheus app
cat > prometheus-app.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus-test
  template:
    metadata:
      labels:
        app: prometheus-test
    spec:
      containers:
      - image: nilebox/prometheus-example-app:latest
        name: prometheus-test
        ports:
        - containerPort: 8080
          name: metrics
EOF

kubectl apply -f prometheus-app.yaml -n $NAMESPACE
kubectl rollout status deploy/prometheus-test -n $NAMESPACE --timeout=120s

# PodMonitoring
cat > pod-monitoring.yaml <<EOF
apiVersion: monitoring.googleapis.com/v1
kind: PodMonitoring
metadata:
  name: prometheus-test
  labels:
    app.kubernetes.io/name: prometheus-test
spec:
  selector:
    matchLabels:
      app: prometheus-test
  endpoints:
  - port: metrics
    interval: ${INTERVAL}
EOF

kubectl apply -f pod-monitoring.yaml -n $NAMESPACE

# --------------------------------------------------------
# Task 3. Deploy helloweb (invalid image expected)
# --------------------------------------------------------
echo "${BLUE}${BOLD}▶ Task 3: Deploying helloweb (with invalid image)...${RESET}"
gsutil cp -r gs://spls/gsp510/hello-app/ .
kubectl apply -f hello-app/manifests/helloweb-deployment.yaml -n $NAMESPACE

# --------------------------------------------------------
# Task 4. Logs-based metric & alert
# --------------------------------------------------------
echo "${YELLOW}${BOLD}▶ Task 4: Manual step required in Console!${RESET}"
echo "  1. Go to Logs Explorer → filter: resource.type=\"k8s_container\" severity=ERROR"
echo "  2. Create metric: ${BOLD}pod-image-errors${RESET} (Counter)."
echo "  3. Go to Monitoring → Alerting → Create policy."
echo "     Name: ${BOLD}Pod Error Alert${RESET}, Threshold >0, Window 10m, Sum aggregation."
echo "  4. Disable notification channel."
echo ">>> Then click 'Check my progress' in Qwiklabs."

# --------------------------------------------------------
# Task 5. Fix helloweb deployment
# --------------------------------------------------------
echo "${BLUE}${BOLD}▶ Task 5: Fixing deployment with correct image...${RESET}"
sed -i 's|image:.*|image: us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0|' hello-app/manifests/helloweb-deployment.yaml

kubectl delete deploy helloweb -n $NAMESPACE --ignore-not-found
kubectl apply -f hello-app/manifests/helloweb-deployment.yaml -n $NAMESPACE
kubectl rollout status deploy/helloweb -n $NAMESPACE --timeout=120s

# --------------------------------------------------------
# Task 6. Containerize v2 and deploy
# --------------------------------------------------------
echo "${BLUE}${BOLD}▶ Task 6: Building v2 image and deploying...${RESET}"
sed -i 's/Version:.*/Version: 2.0.0"/' hello-app/main.go

IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO/hello-app:v2"
gcloud auth configure-docker $REGION-docker.pkg.dev -q

docker build -t $IMAGE hello-app/
docker push $IMAGE

sed -i "s|image:.*|image: $IMAGE|" hello-app/manifests/helloweb-deployment.yaml
kubectl apply -f hello-app/manifests/helloweb-deployment.yaml -n $NAMESPACE
kubectl rollout status deploy/helloweb -n $NAMESPACE --timeout=120s

SVC_NAME="helloweb-service-$(openssl rand -hex 2)"
kubectl expose deploy helloweb \
  --name=$SVC_NAME \
  --type=LoadBalancer \
  --port 8080 --target-port 8080 \
  -n $NAMESPACE

echo "${GREEN}${BOLD}✅ All tasks completed (1→6). Check Qwiklabs progress!${RESET}"
kubectl get svc $SVC_NAME -n $NAMESPACE
