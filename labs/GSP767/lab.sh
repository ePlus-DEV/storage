#!/bin/bash
# =================================================================
#  © 2025 ePlus.DEV. All rights reserved.
#  Lab: Optimize Costs in GKE - Full Automation Script
# =================================================================

# ---- COLOR ----
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# ---- HEADER ----
echo "${CYAN}${BOLD}"
echo "╔════════════════════════════════════════════════════╗"
echo "║   🚀 ePlus.DEV | Optimize Costs in GKE Script      ║"
echo "╚════════════════════════════════════════════════════╝"
echo "${RESET}"

# ---- SETUP ----
echo "${YELLOW}▶ Setting environment...${RESET}"
export PROJECT_ID=$(gcloud config get-value project)
export ZONE=us-east1-d
export REGION=us-east1
gcloud config set compute/zone "$ZONE"
gcloud config set compute/region "$REGION"

# =====================================================
# TASK 2. Scale Up Hello App
# =====================================================
echo "${CYAN}${BOLD}▶ Task 2: Scale Up Hello App${RESET}"
gcloud container clusters get-credentials hello-demo-cluster --zone "$ZONE"

echo "${YELLOW}Scaling hello-server to 2 replicas...${RESET}"
kubectl scale deployment hello-server --replicas=2

echo "${YELLOW}Resizing node pool if needed...${RESET}"
gcloud container clusters resize hello-demo-cluster \
  --node-pool my-node-pool \
  --num-nodes 3 \
  --zone "$ZONE" --quiet

# =====================================================
# TASK 3. Migrate to optimized node pool
# =====================================================
echo "${CYAN}${BOLD}▶ Task 3: Migrate to optimized node pool${RESET}"

echo "${YELLOW}Creating optimized node pool (e2-standard-2)...${RESET}"
gcloud container node-pools create larger-pool \
  --cluster=hello-demo-cluster \
  --machine-type=e2-standard-2 \
  --num-nodes=1 \
  --zone="$ZONE"

echo "${YELLOW}Cordoning nodes in my-node-pool...${RESET}"
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool=my-node-pool -o=name); do
  kubectl cordon "$node"
done

echo "${YELLOW}Draining pods from my-node-pool...${RESET}"
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool=my-node-pool -o=name); do
  kubectl drain --force --ignore-daemonsets --delete-emptydir-data --grace-period=10 "$node"
done

echo "${YELLOW}Checking pods migration...${RESET}"
kubectl get pods -o wide

echo "${YELLOW}Deleting old node pool...${RESET}"
gcloud container node-pools delete my-node-pool \
  --cluster hello-demo-cluster \
  --zone "$ZONE" --quiet

# =====================================================
# TASK 4. Managing a regional cluster
# =====================================================
echo "${CYAN}${BOLD}▶ Task 4: Create Regional Cluster${RESET}"
gcloud container clusters create regional-demo \
  --region=$REGION --num-nodes=1

echo "${YELLOW}Creating pod-1...${RESET}"
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

echo "${YELLOW}Creating pod-2 (anti-affinity)...${RESET}"
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
kubectl get pod pod-1 pod-2 -o wide

# =====================================================
# TASK 5. Optimize cross-zonal traffic
# =====================================================
echo "${CYAN}${BOLD}▶ Task 5: Optimize cross-zonal traffic${RESET}"

echo "${YELLOW}Updating pod-2 to use podAffinity (same node)...${RESET}"
sed -i 's/podAntiAffinity/podAffinity/g' pod-2.yaml
kubectl delete pod pod-2
kubectl apply -f pod-2.yaml

sleep 15
kubectl get pod pod-1 pod-2 -o wide

echo
echo $REGION
echo
echo 
echo "logName="projects/$PROJECT_ID/logs/compute.googleapis.com%2Fvpc_flows""
echo
echo 
# echo -e "\033[1;33mExamine flow logs\033[0m \033[1;34mhttps://console.cloud.google.com/networking/networks/details/default?project=$DEVSHELL_PROJECT_ID&inv=1&invt=AbzSCA&pageTab=SUBNETS\033[0m"
echo

# ---- FOOTER ----
echo "${GREEN}${BOLD}"
echo "╔════════════════════════════════════════════════════╗"
echo "║   ✅ Lab Completed | Optimize Costs in GKE         ║"
echo "║   © 2025 ePlus.DEV                                 ║"
echo "╚════════════════════════════════════════════════════╝"
echo "${RESET}"
