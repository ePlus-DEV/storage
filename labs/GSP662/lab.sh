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

echo "${BG_MAGENTA}${BOLD}Starting Execution - ePlus.DEV ${RESET}"



gcloud auth list

export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")

export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

export PROJECT_ID=$(gcloud config get-value project)

gcloud config set compute/zone "$ZONE"

gcloud config set compute/region "$REGION"

gcloud services enable compute.googleapis.com --project=$DEVSHELL_PROJECT_ID

gsutil mb gs://fancy-store-$DEVSHELL_PROJECT_ID

git clone https://github.com/googlecodelabs/monolith-to-microservices.git
cd ~/monolith-to-microservices
./setup.sh
nvm install --lts

curl -LO raw.githubusercontent.com/Techcps/GSP-Short-Trick/master/Hosting%20a%20Web%20App%20on%20Google%20Cloud%20Using%20Compute%20Engine/startup-script.sh

gsutil cp ~/monolith-to-microservices/startup-script.sh gs://fancy-store-$DEVSHELL_PROJECT_ID

cd ~
rm -rf monolith-to-microservices/*/node_modules
gsutil -m cp -r monolith-to-microservices gs://fancy-store-$DEVSHELL_PROJECT_ID/

gcloud compute instances create backend --zone=$ZONE --machine-type=e2-standard-2 --tags=backend --metadata=startup-script-url=https://storage.googleapis.com/fancy-store-$DEVSHELL_PROJECT_ID/startup-script.sh

gcloud compute instances list

cat > .env <<EOF_CP
REACT_APP_ORDERS_URL=http://$EXTERNAL_IP_BK:8081/api/orders
REACT_APP_PRODUCTS_URL=http://$EXTERNAL_IP_BK:8082/api/products
EOF_CP

cd ~/monolith-to-microservices/react-app
npm install && npm run-script build

cd ~
rm -rf monolith-to-microservices/*/node_modules
gsutil -m cp -r monolith-to-microservices gs://fancy-store-$DEVSHELL_PROJECT_ID/

gcloud compute instances create frontend --zone=$ZONE --machine-type=e2-standard-2 --tags=frontend --metadata=startup-script-url=https://storage.googleapis.com/fancy-store-$DEVSHELL_PROJECT_ID/startup-script.sh

gcloud compute firewall-rules create fw-fe --allow tcp:8080 --target-tags=frontend

gcloud compute firewall-rules create fw-be --allow tcp:8081-8082 --target-tags=backend

gcloud compute instances list

# Task 4 is completed & like share and subscribe to techcps

gcloud compute instances stop frontend --zone=$ZONE

gcloud compute instances stop backend --zone=$ZONE

gcloud compute instance-templates create fancy-fe --source-instance-zone=$ZONE --source-instance=frontend

gcloud compute instance-templates create fancy-be --source-instance-zone=$ZONE --source-instance=backend

gcloud compute instance-templates list

gcloud compute instances delete backend --zone=$ZONE --quiet

gcloud compute instance-groups managed create fancy-fe-mig --zone=$ZONE --base-instance-name fancy-fe --size 2 --template fancy-fe

gcloud compute instance-groups managed create fancy-be-mig --zone=$ZONE --base-instance-name fancy-be --size 2 --template fancy-be

gcloud compute instance-groups set-named-ports fancy-fe-mig --zone=$ZONE --named-ports frontend:8080

gcloud compute instance-groups set-named-ports fancy-be-mig --zone=$ZONE --named-ports orders:8081,products:8082

gcloud compute health-checks create http fancy-fe-hc --port 8080 --check-interval 30s --healthy-threshold 1 --timeout 10s --unhealthy-threshold 3

gcloud compute health-checks create http fancy-be-hc --port 8081 --request-path=/api/orders --check-interval 30s --healthy-threshold 1 --timeout 10s --unhealthy-threshold 3

gcloud compute firewall-rules create allow-health-check --allow tcp:8080-8081 --source-ranges 130.211.0.0/22,35.191.0.0/16 --network default

gcloud compute instance-groups managed update fancy-fe-mig --zone=$ZONE --health-check fancy-fe-hc --initial-delay 300

gcloud compute instance-groups managed update fancy-be-mig --zone=$ZONE --health-check fancy-be-hc --initial-delay 300

while true; do
    echo -ne "\e[1;93mDo you Want to proceed? (Y/n): \e[0m"
    read confirm
    case "$confirm" in
        [Yy]) 
            echo -e "\e[34mRunning the command...\e[0m"
            break
            ;;
        [Nn]|"") 
            echo "Operation canceled."
            break
            ;;
        *) 
            echo -e "\e[31mInvalid input. Please enter Y or N.\e[0m" 
            ;;
    esac
done


gcloud compute http-health-checks create fancy-fe-frontend-hc \
  --request-path / \
  --port 8080

gcloud compute http-health-checks create fancy-be-orders-hc \
--request-path /api/orders \
--port 8081


gcloud compute http-health-checks create fancy-be-products-hc \
--request-path /api/products \
--port 8082

gcloud compute backend-services create fancy-fe-frontend --http-health-checks fancy-fe-frontend-hc --port-name frontend --global

gcloud compute backend-services create fancy-be-orders --http-health-checks fancy-be-orders-hc --port-name orders --global

gcloud compute backend-services create fancy-be-products --http-health-checks fancy-be-products-hc --port-name products --global

gcloud compute backend-services add-backend fancy-fe-frontend --instance-group-zone=$ZONE --instance-group fancy-fe-mig --global

gcloud compute backend-services add-backend fancy-be-orders --instance-group-zone=$ZONE --instance-group fancy-be-mig --global

gcloud compute backend-services add-backend fancy-be-products --instance-group-zone=$ZONE --instance-group fancy-be-mig --global

gcloud compute url-maps create fancy-map --default-service fancy-fe-frontend

gcloud compute url-maps add-path-matcher fancy-map --default-service fancy-fe-frontend --path-matcher-name orders --path-rules "/api/orders=fancy-be-orders,/api/products=fancy-be-products"

gcloud compute target-http-proxies create fancy-proxy --url-map fancy-map

gcloud compute forwarding-rules create fancy-http-rule --global --target-http-proxy fancy-proxy --ports 80

cd ~/monolith-to-microservices/react-app/

gcloud compute forwarding-rules list --global

cat > .env <<EOF
REACT_APP_ORDERS_URL=http://$EXTERNAL_IP_BK:8081/api/orders
REACT_APP_PRODUCTS_URL=http://$EXTERNAL_IP_BK:8082/api/products

REACT_APP_ORDERS_URL=http://$EXTERNAL_IP/api/orders
REACT_APP_PRODUCTS_URL=http://$EXTERNAL_IP/api/products
EOF

cd ~

cd ~/monolith-to-microservices/react-app
npm install && npm run-script build

cd ~
rm -rf monolith-to-microservices/*/node_modules
gsutil -m cp -r monolith-to-microservices gs://fancy-store-$DEVSHELL_PROJECT_ID/

gcloud compute instance-groups managed rolling-action replace fancy-fe-mig --zone=$ZONE --max-unavailable 100%

gcloud compute instance-groups managed set-autoscaling \
fancy-fe-mig \
--zone=$ZONE --max-num-replicas 2 --target-load-balancing-utilization 0.60

gcloud compute instance-groups managed set-autoscaling \
fancy-be-mig \
--zone=$ZONE --max-num-replicas 2 --target-load-balancing-utilization 0.60

gcloud compute backend-services update fancy-fe-frontend --enable-cdn --global

gcloud compute instances set-machine-type frontend --zone=$ZONE --machine-type e2-small

gcloud compute instance-templates create fancy-fe-new --region=$REGION --source-instance=frontend --source-instance-zone=$ZONE

gcloud compute instance-groups managed rolling-action start-update fancy-fe-mig --zone=$ZONE --version template=fancy-fe-new

cd ~/monolith-to-microservices/react-app/src/pages/Home
mv index.js.new index.js

cat ~/monolith-to-microservices/react-app/src/pages/Home/index.js

cd ~/monolith-to-microservices/react-app
npm install && npm run-script build

cd ~
rm -rf monolith-to-microservices/*/node_modules
gsutil -m cp -r monolith-to-microservices gs://fancy-store-$DEVSHELL_PROJECT_ID/

gcloud compute instance-groups managed rolling-action replace fancy-fe-mig --zone=$ZONE --max-unavailable=100%

  
echo "${BG_RED}${BOLD}Congratulations For Completing!!! - ePlus.DEV ${RESET}"

#-----------------------------------------------------end----------------------------------------------------------#