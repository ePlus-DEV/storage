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

echo "${BG_MAGENTA}${BOLD}Starting Execution${RESET}"

ask_required() {
  local var_name="$1"
  local label="$2"
  local value=""

  while [ -z "$value" ]; do
    echo -ne "${CYAN}${BOLD}${label}: ${RESET}"
    read value

    if [ -z "$value" ]; then
      echo "${RED}${BOLD}This field is required. Please enter a value.${RESET}"
    fi
  done

  export "$var_name=$value"
}

echo "${YELLOW}${BOLD}Please enter required lab values:${RESET}"

ask_required VPC_NAME "Enter VPC_NAME"
ask_required SUBNET_A "Enter SUBNET_A"
ask_required SUBNET_B "Enter SUBNET_B"
ask_required FWL_1 "Enter FWL_1"
ask_required FWL_2 "Enter FWL_2"
ask_required FWL_3 "Enter FWL_3"
ask_required ZONE_1 "Enter ZONE_1"
ask_required ZONE_2 "Enter ZONE_2"

export REGION_1=${ZONE_1%-*}
export REGION_2=${ZONE_2%-*}
export VM_1=us-test-01
export VM_2=us-test-02

echo "${GREEN}${BOLD}Using values:${RESET}"
echo "VPC_NAME=$VPC_NAME"
echo "SUBNET_A=$SUBNET_A"
echo "SUBNET_B=$SUBNET_B"
echo "FWL_1=$FWL_1"
echo "FWL_2=$FWL_2"
echo "FWL_3=$FWL_3"
echo "ZONE_1=$ZONE_1"
echo "ZONE_2=$ZONE_2"
echo "REGION_1=$REGION_1"
echo "REGION_2=$REGION_2"

gcloud compute networks create $VPC_NAME \
    --project=$DEVSHELL_PROJECT_ID \
    --subnet-mode=custom \
    --mtu=1460 \
    --bgp-routing-mode=regional

gcloud compute networks subnets create $SUBNET_A \
    --project=$DEVSHELL_PROJECT_ID \
    --region=$REGION_1 \
    --network=$VPC_NAME \
    --range=10.10.10.0/24 \
    --stack-type=IPV4_ONLY

gcloud compute networks subnets create $SUBNET_B \
    --project=$DEVSHELL_PROJECT_ID \
    --region=$REGION_2 \
    --network=$VPC_NAME \
    --range=10.10.20.0/24 \
    --stack-type=IPV4_ONLY

gcloud compute firewall-rules create $FWL_1 \
    --project=$DEVSHELL_PROJECT_ID \
    --network=$VPC_NAME \
    --direction=INGRESS \
    --priority=1000 \
    --action=ALLOW \
    --rules=tcp:22 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=all

gcloud compute firewall-rules create $FWL_2 \
    --project=$DEVSHELL_PROJECT_ID \
    --network=$VPC_NAME \
    --direction=INGRESS \
    --priority=65535 \
    --action=ALLOW \
    --rules=tcp:3389 \
    --source-ranges=0.0.0.0/24 \
    --target-tags=all

gcloud compute firewall-rules create $FWL_3 \
    --project=$DEVSHELL_PROJECT_ID \
    --network=$VPC_NAME \
    --direction=INGRESS \
    --priority=1000 \
    --action=ALLOW \
    --rules=icmp \
    --source-ranges=0.0.0.0/24 \
    --target-tags=all

gcloud compute instances create $VM_1 \
    --project=$DEVSHELL_PROJECT_ID \
    --zone=$ZONE_1 \
    --subnet=$SUBNET_A \
    --tags=all,allow-icmp

gcloud compute instances create $VM_2 \
    --project=$DEVSHELL_PROJECT_ID \
    --zone=$ZONE_2 \
    --subnet=$SUBNET_B \
    --tags=all,allow-icmp

sleep 10

export EXTERNAL_IP2=$(gcloud compute instances describe $VM_2 \
    --zone=$ZONE_2 \
    --project=$DEVSHELL_PROJECT_ID \
    --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

echo "${GREEN}${BOLD}VM_2 External IP:${RESET} $EXTERNAL_IP2"

gcloud compute ssh $VM_1 \
    --zone=$ZONE_1 \
    --project=$DEVSHELL_PROJECT_ID \
    --quiet \
    --command="ping -c 3 $EXTERNAL_IP2 && ping -c 3 $VM_2.$ZONE_2"

echo "${BG_RED}${BOLD}Congratulations For Completing The Lab !!!${RESET}"

#-----------------------------------------------------end----------------------------------------------------------#