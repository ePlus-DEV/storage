#!/bin/bash
set -e

# ==========================================
# Config
# ==========================================
ZONE=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
REGION=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])")
PROJECT_ID=$(gcloud projects list --format="value(projectId)" --limit=1)

echo "Using project: $PROJECT_ID, region: $REGION, zone: $ZONE"

# ==========================================
# Task 1 - Development VPC
# ==========================================
echo "Creating Development VPC..."
gcloud compute networks create griffin-dev-vpc --subnet-mode=custom

gcloud compute networks subnets create griffin-dev-wp \
  --network=griffin-dev-vpc --region=$REGION --range=192.168.16.0/20

gcloud compute networks subnets create griffin-dev-mgmt \
  --network=griffin-dev-vpc --region=$REGION --range=192.168.32.0/20

# ==========================================
# Task 2 - Production VPC
# ==========================================
echo "Creating Production VPC..."
gcloud compute networks create griffin-prod-vpc --subnet-mode=custom

gcloud compute networks subnets create griffin-prod-wp \
  --network=griffin-prod-vpc --region=$REGION --range=192.168.48.0/20

gcloud compute networks subnets create griffin-prod-mgmt \
  --network=griffin-prod-vpc --region=$REGION --range=192.168.64.0/20

# ==========================================
# Task 3 - Bastion host + Firewall rule
# ==========================================
echo "Creating Firewall rule for SSH on griffin-dev-vpc..."
gcloud compute firewall-rules create griffin-dev-allow-ssh \
  --network=griffin-dev-vpc \
  --allow=tcp:22 \
  --direction=INGRESS \
  --priority=1000 \
  --source-ranges=0.0.0.0/0 \
  --target-tags=bastion

echo "Creating Bastion host..."
gcloud compute instances create griffin-bastion \
  --zone=$ZONE \
  --machine-type=e2-medium \
  --network-interface=subnet=griffin-dev-mgmt \
  --network-interface=subnet=griffin-prod-mgmt \
  --tags=bastion

# ==========================================
# Task 4 - Cloud SQL Instance
# ==========================================
echo "Creating Cloud SQL Instance..."
gcloud sql instances create griffin-dev-db \
  --database-version=MYSQL_8_0 \
  --tier=db-n1-standard-1 \
  --region=$REGION

echo "Creating DB and user..."
gcloud sql databases create wordpress --instance=griffin-dev-db
gcloud sql users create wp_user --host=% --instance=griffin-dev-db \
  --password=stormwind_rules

# ==========================================
# Task 5 - Kubernetes cluster
# ==========================================
echo "Creating Kubernetes Cluster..."
gcloud container clusters create griffin-dev \
  --zone $ZONE \
  --num-nodes=2 \
  --machine-type=e2-standard-4 \
  --network=griffin-dev-vpc \
  --subnetwork=griffin-dev-wp

gcloud container clusters get-credentials griffin-dev --zone $ZONE

# ==========================================
# Task 6 - Prepare cluster
# ==========================================
echo "Preparing Kubernetes cluster..."
gsutil cp -r gs://spls/gsp321/wp-k8s .
cd wp-k8s

kubectl create secret generic wp-db-secret \
  --from-literal=username=wp_user \
  --from-literal=password=stormwind_rules

gcloud iam service-accounts keys create key.json \
  --iam-account=cloud-sql-proxy@$PROJECT_ID.iam.gserviceaccount.com

kubectl create secret generic cloudsql-instance-credentials \
  --from-file=key.json

# ==========================================
# Task 7 - WordPress Deployment
# ==========================================
echo "Deploying WordPress..."

SQL_CONN=$(gcloud sql instances describe griffin-dev-db --format="value(connectionName)")
echo "SQL connection name: $SQL_CONN"

# replace YOUR_SQL_INSTANCE with actual connection name
sed -i "s/YOUR_SQL_INSTANCE/$SQL_CONN/g" wp-deployment.yaml

kubectl apply -f wp-env.yaml
kubectl apply -f wp-deployment.yaml
kubectl apply -f wp-service.yaml

echo "=========================================="
echo "Deployment complete!"
echo "Run: kubectl get svc wordpress"
echo "Wait for External IP, then open in browser to see WordPress installer."
echo "=========================================="
