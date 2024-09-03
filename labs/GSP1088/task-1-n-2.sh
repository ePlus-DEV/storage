#!/bin/bash
# Define color variables

BLACK=`tput setaf 0`
RED=`tput setaf 1`
GREEN=`tput setaf 2`
YELLOW=`tput setaf 3`
BLUE=`tput setaf 4`
MAGENTA=`tput setaf 5`
CYAN=`tput setaf 6`
WHITE=`tput setaf 7`

BG_BLACK=`tput setab 0`
BG_RED=`tput setab 1`
BG_GREEN=`tput setab 2`
BG_YELLOW=`tput setab 3`
BG_BLUE=`tput setab 4`
BG_MAGENTA=`tput setab 5`
BG_CYAN=`tput setab 6`
BG_WHITE=`tput setab 7`

BOLD=`tput bold`
RESET=`tput sgr0`
#----------------------------------------------------start--------------------------------------------------#

echo "${BG_MAGENTA}${BOLD}Starting Execution - ePus.DEV ${RESET}"

gcloud config set compute/zone "$ZONE"
gcloud container clusters list
gcloud container clusters get-credentials day2-ops --region "$REGION"

kubectl get nodes

git clone https://github.com/GoogleCloudPlatform/microservices-demo.git
cd microservices-demo

kubectl apply -f release/kubernetes-manifests.yaml

#!/bin/bash

check_all_pods_until_done() {
  while true; do
    # Get the list of all pods and their status across all namespaces
    pod_status=$(kubectl get pods --all-namespaces --no-headers | awk '{print $4}')

    # Check if all pods are in Running or Completed state
    if echo "$pod_status" | grep -qvE "Running|Completed"; then
      echo "Waiting for all pods to complete..."
      sleep 5  # Wait for 5 seconds before checking again
    else
      echo "All pods have completed."
      break
    fi
  done
}

# Call the function to check all pods across all namespaces
check_all_pods_until_done

export EXTERNAL_IP=$(kubectl get service frontend-external -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
echo $EXTERNAL_IP

curl -o /dev/null -s -w "%{http_code}\n"  http://${EXTERNAL_IP}

echo "${BG_RED}${BOLD}Congratulations For Completing Task 1 & 2 !!! - ePus.DEV ${RESET}"

#-----------------------------------------------------end----------------------------------------------------------#