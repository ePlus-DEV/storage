#!/bin/bash
#----------------------------------------------------
# Google Cloud L7 Load Balancer Setup Script
# Author: ePlus.dev (David)
#----------------------------------------------------

# Colors
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
RESET=$(tput sgr0)

log() { echo "${CYAN}==>${RESET} $1"; }
success() { echo "${GREEN}[OK]${RESET} $1"; }
error() { echo "${RED}[ERR]${RESET} $1"; }

#----------------------------------------------------
# 1. Detect Project ID
#----------------------------------------------------
PROJECT_ID=$(gcloud projects list --format="value(projectId)" --limit=1)
if [[ -z "$PROJECT_ID" ]]; then
  error "No Project ID found!"
  exit 1
fi
gcloud config set project $PROJECT_ID
success "Project ID set: $PROJECT_ID"

#----------------------------------------------------
# 2. Detect Region and Zone
#----------------------------------------------------
ZONE=$(gcloud compute zones list --format="value(name)" --limit=1)
REGION=${ZONE%-*}
gcloud config set compute/region $REGION
gcloud config set compute/zone $ZONE
success "Region: $REGION | Zone: $ZONE"

#----------------------------------------------------
# 3. Create 3 Web Server VMs
#----------------------------------------------------
for i in 1 2 3; do
  log "Creating VM www$i ..."
  gcloud compute instances create www$i \
    --zone=$ZONE \
    --tags=network-lb-tag \
    --machine-type=e2-small \
    --image-family=debian-11 \
    --image-project=debian-cloud \
    --metadata=startup-script="#!/bin/bash
      apt-get update
      apt-get install apache2 -y
      service apache2 restart
      echo '<h3>Web Server: www$i</h3>' > /var/www/html/index.html"
done
success "Created 3 web server VMs"

# Firewall rule for HTTP
gcloud compute firewall-rules create www-firewall-network-lb \
  --target-tags network-lb-tag --allow tcp:80 --quiet
success "Firewall rule created for HTTP"

#----------------------------------------------------
# 4. Create Template + Managed Instance Group (MIG)
#----------------------------------------------------
gcloud compute instance-templates create lb-backend-template \
   --region=$REGION \
   --network=default \
   --subnet=default \
   --tags=allow-health-check \
   --machine-type=e2-medium \
   --image-family=debian-11 \
   --image-project=debian-cloud \
   --metadata=startup-script="#!/bin/bash
     apt-get update
     apt-get install apache2 -y
     a2ensite default-ssl
     a2enmod ssl
     vm_hostname=\$(curl -H 'Metadata-Flavor:Google' \
     http://169.254.169.254/computeMetadata/v1/instance/name)
     echo 'Page served from: \$vm_hostname' > /var/www/html/index.html
     systemctl restart apache2"

gcloud compute instance-groups managed create lb-backend-group \
   --template=lb-backend-template --size=2 --zone=$ZONE
success "Template + MIG created"

# Firewall rule for health check
gcloud compute firewall-rules create fw-allow-health-check \
  --network=default --action=allow --direction=ingress \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-tags=allow-health-check --rules=tcp:80 --quiet
success "Firewall rule created for health check"

#----------------------------------------------------
# 5. Global IP + Backend Service
#----------------------------------------------------
gcloud compute addresses create lb-ipv4-1 --ip-version=IPV4 --global
LB_IP=$(gcloud compute addresses describe lb-ipv4-1 \
  --format="get(address)" --global)
success "Global IP created: $LB_IP"

gcloud compute health-checks create http http-basic-check --port 80

gcloud compute backend-services create web-backend-service \
  --protocol=HTTP --port-name=http --health-checks=http-basic-check --global

gcloud compute backend-services add-backend web-backend-service \
  --instance-group=lb-backend-group --instance-group-zone=$ZONE --global
success "Backend service created and MIG attached"

#----------------------------------------------------
# 6. URL Map + Proxy + Forwarding Rule
#----------------------------------------------------
gcloud compute url-maps create web-map-http \
    --default-service web-backend-service

gcloud compute target-http-proxies create http-lb-proxy \
    --url-map web-map-http

gcloud compute forwarding-rules create http-content-rule \
   --address=lb-ipv4-1 --global --target-http-proxy=http-lb-proxy --ports=80
success "URL map, proxy, and forwarding rule created"

#----------------------------------------------------
# Done
#----------------------------------------------------
echo
echo "${YELLOW}============================================================${RESET}"
echo "🎉 Setup completed! Test the load balancer at:"
echo "👉 http://$LB_IP"
echo "${YELLOW}============================================================${RESET}"
