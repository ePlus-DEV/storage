#!/bin/bash
# ===============================================================
#  © 2025 ePlus.DEV. All rights reserved.
#  GKE Cluster Resize & Pod Scheduling Lab Automation Script
# ===============================================================

# ---- COLOR SCHEME ----
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# ---- HEADER ----
echo "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════════════════════════════════╗"
echo "║                                                                                          ║"
echo "║        🚀 ePlus.DEV | Exploring Cost-optimization for GKE Virtual Machines - GSP767      ║"
echo "║                                                                                          ║"
echo "╚══════════════════════════════════════════════════════════════════════════════════════════╝"
echo "${RESET}"

# ---- AUTH & CONFIG ----
echo "${YELLOW}▶ Checking authentication...${RESET}"
gcloud auth list

echo "${YELLOW}▶ Setting environment variables...${RESET}"
export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export PROJECT_ID=$(gcloud config get-value project)

gcloud config set compute/zone "$ZONE"
gcloud config set compute/region "$REGION"

echo "${YELLOW}▶ Enabling required API...${RESET}"
gcloud services enable networkmanagement.googleapis.com

# ---- CLUSTER OPS ----
echo "${YELLOW}▶ Getting cluster credentials...${RESET}"
gcloud container clusters get-credentials hello-demo-cluster --zone "$ZONE"

echo "${YELLOW}▶ Scaling hello-server deployment...${RESET}"
kubectl scale deployment hello-server --replicas=2

echo "${YELLOW}▶ Resizing node pool...${RESET}"
gcloud container clusters resize hello-demo-cluster \
  --node-pool my-node-pool --num-nodes 3 --zone "$ZONE" --quiet

echo "${YELLOW}▶ Creating new node pool (larger-pool)...${RESET}"
gcloud container node-pools create larger-pool \
  --cluster=hello-demo-cluster --machine-type=e2-standard-2 \
  --num-nodes=1 --zone="$ZONE"

echo "${YELLOW}▶ Cordoning nodes in my-node-pool...${RESET}"
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool=my-node-pool -o=name); do
  kubectl cordon "$node"
done

echo "${YELLOW}▶ Draining nodes in my-node-pool...${RESET}"
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool=my-node-pool -o=name); do
  kubectl drain --force --ignore-daemonsets --delete-emptydir-data --grace-period=10 "$node"
done

kubectl get pods -o=wide

echo "${YELLOW}▶ Deleting old node pool (my-node-pool)...${RESET}"
gcloud container node-pools delete my-node-pool \
  --cluster hello-demo-cluster --zone "$ZONE" --quiet

# ---- REGIONAL CLUSTER ----
echo "${YELLOW}▶ Creating regional cluster...${RESET}"
gcloud container clusters create regional-demo --region=$REGION --num-nodes=1

# ---- PODS ----
echo "${YELLOW}▶ Creating pod-1...${RESET}"
cat << EOF > pod-1.yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-1
  labels:
    security: demo
spec:
  containers:
  - name: container-1
    image: wbitt/network-multitool
EOF
kubectl apply -f pod-1.yaml

echo "${YELLOW}▶ Creating pod-2 with anti-affinity...${RESET}"
cat << EOF > pod-2.yaml
apiVersion: v1
kind: Pod
metadata:
  name: pod-2
spec:
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
          - key: security
            operator: In
            values:
            - demo
        topologyKey: "kubernetes.io/hostname"
  containers:
  - name: container-2
    image: us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0
EOF
kubectl apply -f pod-2.yaml

sleep 20
kubectl get pod pod-1 pod-2 --output wide

echo
echo "${GREEN}▶ REGION:${RESET} ${CYAN}$REGION${RESET}"
echo
echo "${YELLOW}▶ VPC Flow Logs query:${RESET}"
echo "logName=\"projects/$PROJECT_ID/logs/compute.googleapis.com%2Fvpc_flows\""
echo

# ---- FOOTER ----
echo "${GREEN}${BOLD}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║   ✅ Script Completed | © 2025 ePlus.DEV                   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo "${RESET}"