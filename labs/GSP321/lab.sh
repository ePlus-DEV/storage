#!/bin/bash
set -e

# ==========================================
# Color setup
# ==========================================
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
RESET=$(tput sgr0)

step () {
  echo ""
  echo "${CYAN}========== [TASK $1] $2 ==========${RESET}"
}

success () {
  echo "${GREEN}✅ $1${RESET}"
}

warn () {
  echo "${YELLOW}⚠ $1${RESET}"
}

# ==========================================
# Config
# ==========================================
ZONE=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
REGION=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])")
PROJECT_ID=$(gcloud config get-value project)

echo "Using project: $PROJECT_ID, region: $REGION, zone: $ZONE"

# ==========================================
# Task 1 - Development VPC
# ==========================================
step 1 "Create Development VPC + Subnets"
gcloud compute networks create griffin-dev-vpc --subnet-mode=custom

gcloud compute networks subnets create griffin-dev-wp \
  --network=griffin-dev-vpc --region=$REGION --range=192.168.16.0/20

gcloud compute networks subnets create griffin-dev-mgmt \
  --network=griffin-dev-vpc --region=$REGION --range=192.168.32.0/20
success "Development VPC created"

# ==========================================
# Task 2 - Production VPC
# ==========================================
step 2 "Create Production VPC + Subnets"
gcloud compute networks create griffin-prod-vpc --subnet-mode=custom

gcloud compute networks subnets create griffin-prod-wp \
  --network=griffin-prod-vpc --region=$REGION --range=192.168.48.0/20

gcloud compute networks subnets create griffin-prod-mgmt \
  --network=griffin-prod-vpc --region=$REGION --range=192.168.64.0/20
success "Production VPC created"

# ==========================================
# Task 3 - Bastion host + Firewall rule
# ==========================================
step 3 "Create Firewall rule + Bastion host"
gcloud compute firewall-rules create griffin-dev-allow-ssh \
  --network=griffin-dev-vpc \
  --allow=tcp:22 \
  --direction=INGRESS \
  --priority=1000 \
  --source-ranges=0.0.0.0/0 \
  --target-tags=bastion

gcloud compute instances create griffin-bastion \
  --zone=$ZONE \
  --machine-type=e2-medium \
  --network-interface=subnet=griffin-dev-mgmt \
  --network-interface=subnet=griffin-prod-mgmt \
  --tags=bastion
success "Bastion host created (with SSH firewall rule)"

# ==========================================
# Task 4 - Cloud SQL Instance
# ==========================================
step 4 "Create Cloud SQL Instance + WordPress DB"
gcloud sql instances create griffin-dev-db \
  --database-version=MYSQL_8_0 \
  --tier=db-n1-standard-1 \
  --region=$REGION

gcloud sql databases create wordpress --instance=griffin-dev-db
gcloud sql users create wp_user --host=% --instance=griffin-dev-db \
  --password=stormwind_rules
success "Cloud SQL and wordpress DB ready"

# ==========================================
# Task 5 - Kubernetes cluster
# ==========================================
step 5 "Create Kubernetes Cluster"
gcloud container clusters create griffin-dev \
  --zone $ZONE \
  --num-nodes=2 \
  --machine-type=e2-standard-4 \
  --network=griffin-dev-vpc \
  --subnetwork=griffin-dev-wp

gcloud container clusters get-credentials griffin-dev --zone $ZONE
success "Kubernetes cluster ready"

# ==========================================
# Task 6 - Prepare cluster
# ==========================================
step 6 "Prepare cluster (secrets, Cloud SQL proxy key)"
gsutil cp -r gs://spls/gsp321/wp-k8s .
cd wp-k8s

kubectl create secret generic wp-db-secret \
  --from-literal=username=wp_user \
  --from-literal=password=stormwind_rules

gcloud iam service-accounts keys create key.json \
  --iam-account=cloud-sql-proxy@$PROJECT_ID.iam.gserviceaccount.com

kubectl create secret generic cloudsql-instance-credentials \
  --from-file=key.json
success "Secrets and Cloud SQL proxy key created"

# ==========================================
# Task 7 - WordPress Deployment
# ==========================================
step 7 "Deploy WordPress"
SQL_CONN=$(gcloud sql instances describe griffin-dev-db --format="value(connectionName)")
echo "SQL connection name: $SQL_CONN"

sed -i "s/YOUR_SQL_INSTANCE/$SQL_CONN/g" wp-deployment.yaml

kubectl apply -f wp-env.yaml
kubectl apply -f wp-deployment.yaml
kubectl apply -f wp-service.yaml

warn "Waiting for LoadBalancer external IP..."
echo "Run: kubectl get svc wordpress"
echo "Then open External IP in browser for WordPress installer."
success "WordPress deployment completed"