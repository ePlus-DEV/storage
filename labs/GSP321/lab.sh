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
REGION="us-west1"
ZONE="us-west1-a"
PROJECT_ID=$(gcloud config get-value project)

# Require engineer email
read -p "👉 Enter the additional engineer email (e.g. student-04-xxxx@qwiklabs.net): " ENGINEER_EMAIL
if [[ -z "$ENGINEER_EMAIL" ]]; then
  echo "${RED}❌ You did not enter an email. Exiting.${RESET}"
  exit 1
fi

echo "Using project: $PROJECT_ID, region: $REGION, zone: $ZONE"
echo "Engineer email: $ENGINEER_EMAIL"

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
# Task 3 - Bastion host + Firewall rules
# ==========================================
step 3 "Create Firewall rules + Bastion host"
# Dev firewall rule
gcloud compute firewall-rules create griffin-dev-allow-ssh \
  --network=griffin-dev-vpc \
  --allow=tcp:22 \
  --direction=INGRESS \
  --priority=1000 \
  --source-ranges=0.0.0.0/0 \
  --target-tags=bastion || true

# Prod firewall rule
gcloud compute firewall-rules create griffin-prod-allow-ssh \
  --network=griffin-prod-vpc \
  --allow=tcp:22 \
  --direction=INGRESS \
  --priority=1000 \
  --source-ranges=0.0.0.0/0 \
  --target-tags=bastion || true

# Bastion host
gcloud compute instances create griffin-bastion \
  --zone=$ZONE \
  --machine-type=e2-medium \
  --network-interface=subnet=griffin-dev-mgmt \
  --network-interface=subnet=griffin-prod-mgmt \
  --tags=bastion
success "Bastion host created (with SSH firewall rules for dev + prod)"

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
success "Cloud SQL and WordPress DB ready"

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
step 6 "Prepare cluster (secrets, Cloud SQL proxy key, PVC)"
gsutil cp -r gs://spls/gsp321/wp-k8s .
cd wp-k8s

kubectl delete secret wp-db-secret --ignore-not-found
kubectl create secret generic wp-db-secret \
  --from-literal=username=wp_user \
  --from-literal=password=stormwind_rules

if gcloud iam service-accounts list | grep -q "cloud-sql-proxy"; then
  gcloud iam service-accounts keys create key.json \
    --iam-account=cloud-sql-proxy@$PROJECT_ID.iam.gserviceaccount.com
  kubectl delete secret cloudsql-instance-credentials --ignore-not-found
  kubectl create secret generic cloudsql-instance-credentials \
    --from-file=key.json
else
  echo "⚠️ Service account cloud-sql-proxy not found, lab may provide secret already."
fi

kubectl apply -f wp-env.yaml
success "Secrets and PVC applied"

# ==========================================
# Task 7 - WordPress Deployment
# ==========================================
step 7 "Deploy WordPress"
SQL_CONN=$(gcloud sql instances describe griffin-dev-db --format="value(connectionName)")
echo "SQL connection name: $SQL_CONN"

sed -i "s/YOUR_SQL_INSTANCE/$SQL_CONN/g" wp-deployment.yaml

kubectl apply -f wp-deployment.yaml
kubectl apply -f wp-service.yaml

warn "Waiting for LoadBalancer external IP..."
sleep 30
WP_IP=$(kubectl get svc wordpress -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "WordPress External IP: $WP_IP"
success "WordPress deployment completed"

# ==========================================
# Task 8 - Enable Monitoring (Uptime Check)
# ==========================================
step 8 "Enable Monitoring Uptime Check"
if [ -z "$WP_IP" ]; then
  WP_IP=$(kubectl get svc wordpress -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
fi

gcloud monitoring uptime create wordpress-uptime \
  --path="/" \
  --port=80 \
  --regions=usa-oregon,usa-iowa,usa-virginia \
  --request-method=get \
  --protocol=http \
  --resource-type=uptime-url \
  --resource-labels host=$WP_IP

success "Uptime check created for WordPress at $WP_IP"

# ==========================================
# Task 9 - Provide access for additional engineer
# ==========================================
step 9 "Provide Editor access for engineer"
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="user:$ENGINEER_EMAIL" \
  --role="roles/editor"
success "Editor role granted to $ENGINEER_EMAIL"

echo "=========================================="
echo "${GREEN}🎉 All tasks (1 → 9) completed successfully!${RESET}"
echo "=========================================="