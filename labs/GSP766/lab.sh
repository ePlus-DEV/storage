#!/bin/bash
# ===============================================================
#  © 2025 ePlus.DEV. All rights reserved.
#  GKE Multi-Tenant Lab Automation Script
# ===============================================================

# ---- COLOR SCHEME ----
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
BOLD=$(tput bold)
RESET=$(tput sgr0)

echo "${CYAN}${BOLD}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║         🚀 ePlus.DEV | GKE Multi-Tenant Lab Script         ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo "${RESET}"

export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")

# ---- LAB STEPS ----
echo "${YELLOW}▶ Copying qwiklab files...${RESET}"
gsutil -m cp -r gs://spls/gsp766/gke-qwiklab ~
cd ~/gke-qwiklab

echo "${YELLOW}▶ Setting cluster credentials...${RESET}"
gcloud config set compute/zone ${ZONE} && gcloud container clusters get-credentials multi-tenant-cluster

echo "${YELLOW}▶ Creating namespaces...${RESET}"
kubectl create namespace team-a && \
kubectl create namespace team-b

echo "${YELLOW}▶ Creating pods for team-a and team-b...${RESET}"
kubectl run app-server --image=centos --namespace=team-a -- sleep infinity && \
kubectl run app-server --image=centos --namespace=team-b -- sleep infinity

kubectl describe pod app-server --namespace=team-a
kubectl config set-context --current --namespace=team-a

echo "${YELLOW}▶ Assigning IAM policy binding...${RESET}"
gcloud projects add-iam-policy-binding ${GOOGLE_CLOUD_PROJECT} \
--member=serviceAccount:team-a-dev@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com  \
--role=roles/container.clusterViewer

kubectl create role pod-reader \
--resource=pods --verb=watch --verb=get --verb=list

kubectl create -f developer-role.yaml

kubectl create rolebinding team-a-developers \
--role=developer --user=team-a-dev@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com

echo "${YELLOW}▶ Creating IAM service account key...${RESET}"
gcloud iam service-accounts keys create /tmp/key.json \
--iam-account team-a-dev@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com

gcloud container clusters get-credentials multi-tenant-cluster --zone ${ZONE} --project ${GOOGLE_CLOUD_PROJECT}

echo "${YELLOW}▶ Creating resource quota for team-a...${RESET}"
kubectl create quota test-quota \
--hard=count/pods=2,count/services.loadbalancers=1 --namespace=team-a

kubectl run app-server-2 --image=centos --namespace=team-a -- sleep infinity
kubectl run app-server-3 --image=centos --namespace=team-a -- sleep infinity

sleep 20

kubectl get quota test-quota --namespace=team-a -o yaml | \
  sed 's/count\/pods: "2"/count\/pods: "6"/' | \
  kubectl apply -f -

kubectl create -f cpu-mem-quota.yaml
kubectl create -f cpu-mem-demo-pod.yaml --namespace=team-a
kubectl describe quota cpu-mem-quota --namespace=team-a

echo "${YELLOW}▶ Enabling GKE Usage Metering...${RESET}"
gcloud container clusters \
  update multi-tenant-cluster --zone ${ZONE} \
  --resource-usage-bigquery-dataset cluster_dataset

export GCP_BILLING_EXPORT_TABLE_FULL_PATH=${GOOGLE_CLOUD_PROJECT}.billing_dataset.gcp_billing_export_v1_xxxx
export USAGE_METERING_DATASET_ID=cluster_dataset
export COST_BREAKDOWN_TABLE_ID=usage_metering_cost_breakdown

export USAGE_METERING_QUERY_TEMPLATE=~/gke-qwiklab/usage_metering_query_template.sql
export USAGE_METERING_QUERY=cost_breakdown_query.sql
export USAGE_METERING_START_DATE=2020-10-26

sed \
-e "s/\${fullGCPBillingExportTableID}/$GCP_BILLING_EXPORT_TABLE_FULL_PATH/" \
-e "s/\${projectID}/$GOOGLE_CLOUD_PROJECT/" \
-e "s/\${datasetID}/$USAGE_METERING_DATASET_ID/" \
-e "s/\${startDate}/$USAGE_METERING_START_DATE/" \
"$USAGE_METERING_QUERY_TEMPLATE" \
> "$USAGE_METERING_QUERY"

bq query \
--project_id=$GOOGLE_CLOUD_PROJECT \
--use_legacy_sql=false \
--destination_table=$USAGE_METERING_DATASET_ID.$COST_BREAKDOWN_TABLE_ID \
--schedule='every 24 hours' \
--display_name="GKE Usage Metering Cost Breakdown Scheduled Query" \
--replace=true \
"$(cat $USAGE_METERING_QUERY)"

# ---- FOOTER ----
echo "${GREEN}${BOLD}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║   ✅ GKE Multi-Tenant Lab Completed | © 2025 ePlus.DEV      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo "${RESET}"