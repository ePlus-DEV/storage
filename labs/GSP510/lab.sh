#!/bin/bash
# ========================================================
# GKE Challenge Lab - Full Automation Script
# Copyright (c) 2025 ePlus.DEV. All rights reserved.
# ========================================================

# ===== Required Inputs =====
read -p "Enter Cluster Name (e.g., hello-world-3kxq): " CLUSTER
read -p "Enter Namespace (e.g., gmp-veiz): " NAMESPACE
read -p "Enter Artifact Registry Repo (e.g., sandbox-repo): " REPO

if [[ -z "$CLUSTER" || -z "$NAMESPACE" || -z "$REPO" ]]; then
  echo "❌ You must provide CLUSTER, NAMESPACE, and REPO!"
  exit 1
fi

# ===== Environment Variables =====
PROJECT_ID=$(gcloud config get-value project)
ZONE="europe-west4-a"
REGION="europe-west4"

echo "=========================================="
echo " Project ID : $PROJECT_ID"
echo " Cluster    : $CLUSTER"
echo " Namespace  : $NAMESPACE"
echo " Repo       : $REPO"
echo " Zone       : $ZONE"
echo " Region     : $REGION"
echo "=========================================="

# --------------------------------------------------------
# Task 1. Create GKE Cluster
# --------------------------------------------------------
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
gsutil cp -r gs://spls/gsp510/hello-app/ .
kubectl apply -f hello-app/manifests/helloweb-deployment.yaml -n $NAMESPACE

# --------------------------------------------------------
# Task 4. Logs-based metric & alert
# --------------------------------------------------------
echo "👉 Manual step required:"
echo "   1. Go to Logs Explorer."
echo "   2. Run query: resource.type=\"k8s_container\" severity>=ERROR"
echo "   3. Create log-based metric: pod-image-errors (Counter)."
echo "   4. Create Alerting Policy 'Pod Error Alert' with threshold >0."

# --------------------------------------------------------
# Task 5. Fix deployment
# --------------------------------------------------------
sed -i 's|image:.*|image: us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0|' hello-app/manifests/helloweb-deployment.yaml

kubectl delete deploy helloweb -n $NAMESPACE
kubectl apply -f hello-app/manifests/helloweb-deployment.yaml -n $NAMESPACE

# --------------------------------------------------------
# Task 6. Containerize v2 and deploy
# --------------------------------------------------------
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

echo "⏳ Waiting for external IP..."
kubectl get svc helloweb-service-2xml -n $NAMESPACE