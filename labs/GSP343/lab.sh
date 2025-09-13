#!/bin/bash
# © 2025 ePlus.DEV. All rights reserved.
# Optimize Costs GKE Challenge Lab Automation Script

# ========== COLOR SCHEME ==========
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# ========== BANNER ==========
echo "${CYAN}${BOLD}"
echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║                                                                    ║"
echo "║         🚀 ePlus.DEV | GKE Optimize Costs Challenge Script         ║"
echo "║                                                                    ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo "${RESET}"

# ========== INPUT ==========
read -p "👉 Enter Cluster Name (e.g. onlineboutique-cluster-631): " CLUSTER_NAME
read -p "👉 Enter Node Pool Name (e.g. optimized-pool-3260): " POOL_NAME
read -p "👉 Enter Max Replicas for Frontend (default: 10): " MAX_REPLICAS
MAX_REPLICAS=${MAX_REPLICAS:-10}

PROJECT_ID=$DEVSHELL_PROJECT_ID
export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")

echo
echo "${YELLOW}▶ Project:${RESET} ${CYAN}${PROJECT_ID}${RESET}"
echo "${YELLOW}▶ Zone:${RESET} ${CYAN}${ZONE}${RESET}"
echo "${YELLOW}▶ Cluster:${RESET} ${CYAN}${CLUSTER_NAME}${RESET}"
echo "${YELLOW}▶ NodePool:${RESET} ${CYAN}${POOL_NAME}${RESET}"
echo "${YELLOW}▶ Max Replicas:${RESET} ${CYAN}${MAX_REPLICAS}${RESET}"
echo

# ========== TASK 1 ==========
echo "${GREEN}${BOLD}=== Task 1: Create cluster & deploy app ===${RESET}"
gcloud container clusters create $CLUSTER_NAME \
  --project=$PROJECT_ID \
  --zone=$ZONE \
  --machine-type=e2-standard-2 \
  --num-nodes=2 \
  --release-channel=rapid

kubectl create namespace dev
kubectl create namespace prod

git clone https://github.com/GoogleCloudPlatform/microservices-demo.git
cd microservices-demo
kubectl apply -f ./release/kubernetes-manifests.yaml --namespace dev
cd ..

# ========== TASK 2 ==========
echo "${GREEN}${BOLD}=== Task 2: Create optimized node pool & migrate workloads ===${RESET}"
gcloud container node-pools create $POOL_NAME \
  --cluster=$CLUSTER_NAME \
  --machine-type=custom-2-3584 \
  --num-nodes=2 \
  --zone=$ZONE

# Cordone + Drain default-pool
for node in $(kubectl get nodes -l cloud.google.com/gke-nodepool=default-pool -o=name); do
  echo "${YELLOW}Cordoning $node...${RESET}"
  kubectl cordon "$node"
  echo "${RED}Draining $node...${RESET}"
  kubectl drain "$node" --force --ignore-daemonsets --delete-local-data --grace-period=10
done

# Delete default-pool
gcloud container node-pools delete default-pool \
  --cluster $CLUSTER_NAME \
  --zone $ZONE \
  --quiet

# ========== TASK 3 ==========
echo "${GREEN}${BOLD}=== Task 3: Apply frontend update ===${RESET}"
kubectl create poddisruptionbudget onlineboutique-frontend-pdb \
  --selector app=frontend \
  --min-available=1 \
  --namespace dev

kubectl patch deployment frontend -n dev --type=json -p '[
  { "op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "gcr.io/qwiklabs-resources/onlineboutique-frontend:v2.1" },
  { "op": "replace", "path": "/spec/template/spec/containers/0/imagePullPolicy", "value": "Always" }
]'

# ========== TASK 4 ==========
echo "${GREEN}${BOLD}=== Task 4: Autoscale frontend & enable cluster autoscaler ===${RESET}"
kubectl autoscale deployment frontend \
  --cpu-percent=50 \
  --min=1 \
  --max=$MAX_REPLICAS \
  --namespace dev

kubectl get hpa --namespace dev

gcloud container clusters update $CLUSTER_NAME \
  --enable-autoscaling \
  --min-nodes=1 \
  --max-nodes=6 \
  --zone=$ZONE

# Autoscale recommendationservice
kubectl autoscale deployment recommendationservice \
  --cpu-percent=50 \
  --min=1 \
  --max=5 \
  --namespace dev

# ========== COMPLETION ==========
echo "${CYAN}${BOLD}"
echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║                      ✅ Script Completed!                           ║"
echo "║   Now run load test manually to simulate traffic surge.              ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo "${RESET}"

echo "${YELLOW}Run these commands to start load test:${RESET}"
echo
echo "FRONTEND_IP=\$(kubectl get svc frontend-external -n dev -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo 'kubectl exec $(kubectl get pod -n dev | grep loadgenerator | awk "{print \$1}") -it -n dev -- bash -c "export USERS=8000; locust --host=http://$FRONTEND_IP --headless -u 8000"'