#!/bin/bash

# ============================================================
# Google Cloud Skills Boost
# L7 Application Load Balancer Lab
# ePlus.DEV
# ============================================================

set -u

# ---------- Colors ----------
RED=$'\033[0;91m'
GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
BLUE=$'\033[0;94m'
MAGENTA=$'\033[0;95m'
CYAN=$'\033[0;96m'
WHITE=$'\033[0;97m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

clear

echo "${CYAN}${BOLD}"
echo "=============================================================="
echo "      L7 APPLICATION LOAD BALANCER - LAB AUTOMATION"
echo "                         ePlus.DEV"
echo "=============================================================="
echo "${RESET}"

# ============================================================
# Configuration
# ============================================================

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)
ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])" 2>/dev/null || true)

echo "${YELLOW}Project : ${WHITE}${PROJECT_ID}${RESET}"
echo "${YELLOW}Region  : ${WHITE}${REGION}${RESET}"
echo "${YELLOW}Zone    : ${WHITE}${ZONE}${RESET}"
echo

gcloud config set compute/region "$REGION" >/dev/null
gcloud config set compute/zone "$ZONE" >/dev/null

# ============================================================
# TASK 1
# Set default region and zone
# ============================================================

echo "${CYAN}${BOLD}=============================================================="
echo " TASK 1 - SET DEFAULT REGION AND ZONE"
echo "==============================================================${RESET}"

echo "${GREEN}✓ Region: $REGION${RESET}"
echo "${GREEN}✓ Zone  : $ZONE${RESET}"
echo


# ============================================================
# TASK 2
# Create multiple web servers
# ============================================================

echo "${CYAN}${BOLD}=============================================================="
echo " TASK 2 - CREATE WEB SERVERS"
echo "==============================================================${RESET}"

for VM in www1 www2 www3; do

    if gcloud compute instances describe "$VM" \
        --zone="$ZONE" >/dev/null 2>&1; then

        echo "${GREEN}✓ $VM already exists${RESET}"

    else
        echo "${YELLOW}Creating $VM...${RESET}"

        gcloud compute instances create "$VM" \
            --zone="$ZONE" \
            --tags=network-lb-tag \
            --machine-type=e2-small \
            --image-family=debian-12 \
            --image-project=debian-cloud \
            --metadata=startup-script="#!/bin/bash
apt-get update
apt-get install apache2 -y
systemctl enable apache2
systemctl restart apache2
echo '<h3>Web Server: $VM</h3>' > /var/www/html/index.html"

        if [ $? -ne 0 ]; then
            echo "${RED}✗ Failed to create $VM${RESET}"
            exit 1
        fi

        echo "${GREEN}✓ $VM created${RESET}"
    fi
done

echo

# ------------------------------------------------------------
# Firewall for www1 / www2 / www3
# ------------------------------------------------------------

if gcloud compute firewall-rules describe www-firewall-network-lb \
    >/dev/null 2>&1; then

    echo "${GREEN}✓ Firewall www-firewall-network-lb already exists${RESET}"

else
    echo "${YELLOW}Creating HTTP firewall rule...${RESET}"

    gcloud compute firewall-rules create www-firewall-network-lb \
        --network=default \
        --direction=INGRESS \
        --action=ALLOW \
        --rules=tcp:80 \
        --target-tags=network-lb-tag

    echo "${GREEN}✓ HTTP firewall created${RESET}"
fi

echo
echo "${BLUE}${BOLD}Web server instances:${RESET}"

gcloud compute instances list \
    --filter="name=(www1 www2 www3)" \
    --format="table(
        name,
        zone.basename(),
        status,
        networkInterfaces[0].accessConfigs[0].natIP:label=EXTERNAL_IP
    )"

echo

# ============================================================
# TASK 3
# Create Application Load Balancer
# ============================================================

echo "${CYAN}${BOLD}=============================================================="
echo " TASK 3 - CREATE APPLICATION LOAD BALANCER"
echo "==============================================================${RESET}"


# ------------------------------------------------------------
# Instance template
# ------------------------------------------------------------

if gcloud compute instance-templates describe lb-backend-template \
    >/dev/null 2>&1; then

    echo "${GREEN}✓ Instance template already exists${RESET}"

else
    echo "${YELLOW}Creating lb-backend-template...${RESET}"

    gcloud compute instance-templates create lb-backend-template \
        --region="$REGION" \
        --network=default \
        --subnet=default \
        --tags=allow-health-check \
        --machine-type=e2-medium \
        --image-family=debian-12 \
        --image-project=debian-cloud \
        --metadata=startup-script='#!/bin/bash
apt-get update
apt-get install apache2 -y
a2ensite default-ssl
a2enmod ssl

vm_hostname="$(curl -s \
-H "Metadata-Flavor: Google" \
http://169.254.169.254/computeMetadata/v1/instance/name)"

echo "Page served from: ${vm_hostname}" > /var/www/html/index.html

systemctl enable apache2
systemctl restart apache2'

    echo "${GREEN}✓ Instance template created${RESET}"
fi

echo

# ------------------------------------------------------------
# Managed Instance Group
# ------------------------------------------------------------

if gcloud compute instance-groups managed describe lb-backend-group \
    --zone="$ZONE" >/dev/null 2>&1; then

    echo "${GREEN}✓ Managed instance group already exists${RESET}"

else
    echo "${YELLOW}Creating lb-backend-group...${RESET}"

    gcloud compute instance-groups managed create lb-backend-group \
        --template=lb-backend-template \
        --size=2 \
        --zone="$ZONE"

    echo "${GREEN}✓ Managed instance group created${RESET}"
fi


# Set named port
echo "${YELLOW}Configuring named port http:80...${RESET}"

gcloud compute instance-groups managed set-named-ports \
    lb-backend-group \
    --zone="$ZONE" \
    --named-ports=http:80 >/dev/null 2>&1 || true

echo "${GREEN}✓ Named port configured${RESET}"

echo


# ------------------------------------------------------------
# Health check firewall
# ------------------------------------------------------------

if gcloud compute firewall-rules describe fw-allow-health-check \
    >/dev/null 2>&1; then

    echo "${GREEN}✓ Health-check firewall already exists${RESET}"

else
    echo "${YELLOW}Creating health-check firewall...${RESET}"

    gcloud compute firewall-rules create fw-allow-health-check \
        --network=default \
        --action=allow \
        --direction=ingress \
        --source-ranges=130.211.0.0/22,35.191.0.0/16 \
        --target-tags=allow-health-check \
        --rules=tcp:80

    echo "${GREEN}✓ Health-check firewall created${RESET}"
fi

echo


# ------------------------------------------------------------
# Global IP address
# ------------------------------------------------------------

if gcloud compute addresses describe lb-ipv4-1 \
    --global >/dev/null 2>&1; then

    echo "${GREEN}✓ Global IP lb-ipv4-1 already exists${RESET}"

else
    echo "${YELLOW}Reserving global IPv4 address...${RESET}"

    gcloud compute addresses create lb-ipv4-1 \
        --ip-version=IPV4 \
        --global

    echo "${GREEN}✓ Global IPv4 address reserved${RESET}"
fi

LB_IP=$(gcloud compute addresses describe lb-ipv4-1 \
    --global \
    --format="value(address)")

echo
echo "${MAGENTA}${BOLD}Load Balancer IP: $LB_IP${RESET}"
echo


# ------------------------------------------------------------
# Health check
# ------------------------------------------------------------

if gcloud compute health-checks describe http-basic-check \
    >/dev/null 2>&1; then

    echo "${GREEN}✓ Health check already exists${RESET}"

else
    echo "${YELLOW}Creating HTTP health check...${RESET}"

    gcloud compute health-checks create http http-basic-check \
        --port=80

    echo "${GREEN}✓ Health check created${RESET}"
fi

echo


# ------------------------------------------------------------
# Backend service
# ------------------------------------------------------------

if gcloud compute backend-services describe web-backend-service \
    --global >/dev/null 2>&1; then

    echo "${GREEN}✓ Backend service already exists${RESET}"

else
    echo "${YELLOW}Creating backend service...${RESET}"

    gcloud compute backend-services create web-backend-service \
        --protocol=HTTP \
        --port-name=http \
        --health-checks=http-basic-check \
        --global

    echo "${GREEN}✓ Backend service created${RESET}"
fi

echo


# ------------------------------------------------------------
# Add MIG backend
# ------------------------------------------------------------

BACKENDS=$(gcloud compute backend-services describe \
    web-backend-service \
    --global \
    --format="value(backends.group)" 2>/dev/null)

if echo "$BACKENDS" | grep -q "instanceGroups/lb-backend-group"; then

    echo "${GREEN}✓ lb-backend-group already attached to backend service${RESET}"

else
    echo "${YELLOW}Adding instance group to backend service...${RESET}"

    gcloud compute backend-services add-backend \
        web-backend-service \
        --instance-group=lb-backend-group \
        --instance-group-zone="$ZONE" \
        --global

    echo "${GREEN}✓ Backend added${RESET}"
fi

echo


# ------------------------------------------------------------
# URL Map
# ------------------------------------------------------------

if gcloud compute url-maps describe web-map-http \
    >/dev/null 2>&1; then

    echo "${GREEN}✓ URL map already exists${RESET}"

else
    echo "${YELLOW}Creating URL map...${RESET}"

    gcloud compute url-maps create web-map-http \
        --default-service=web-backend-service

    echo "${GREEN}✓ URL map created${RESET}"
fi

echo


# ------------------------------------------------------------
# HTTP Proxy
# ------------------------------------------------------------

if gcloud compute target-http-proxies describe http-lb-proxy \
    >/dev/null 2>&1; then

    echo "${GREEN}✓ HTTP proxy already exists${RESET}"

else
    echo "${YELLOW}Creating target HTTP proxy...${RESET}"

    gcloud compute target-http-proxies create http-lb-proxy \
        --url-map=web-map-http

    echo "${GREEN}✓ HTTP proxy created${RESET}"
fi

echo


# ------------------------------------------------------------
# Forwarding rule
# ------------------------------------------------------------

if gcloud compute forwarding-rules describe http-content-rule \
    --global >/dev/null 2>&1; then

    echo "${GREEN}✓ Forwarding rule already exists${RESET}"

else
    echo "${YELLOW}Creating global forwarding rule...${RESET}"

    gcloud compute forwarding-rules create http-content-rule \
        --address=lb-ipv4-1 \
        --global \
        --target-http-proxy=http-lb-proxy \
        --ports=80

    echo "${GREEN}✓ Forwarding rule created${RESET}"
fi


# ============================================================
# TASK 4
# Wait for healthy backend
# ============================================================

echo
echo "${CYAN}${BOLD}=============================================================="
echo " TASK 4 - CHECK BACKEND HEALTH"
echo "==============================================================${RESET}"

echo "${YELLOW}Waiting for backend instances to become HEALTHY...${RESET}"
echo

HEALTHY=0

for i in {1..60}; do

    HEALTH_OUTPUT=$(gcloud compute backend-services get-health \
        web-backend-service \
        --global 2>/dev/null)

    HEALTHY_COUNT=$(echo "$HEALTH_OUTPUT" \
        | grep -c "healthState: HEALTHY" || true)

    echo "Health check ${i}/60 : ${HEALTHY_COUNT}/2 healthy"

    if [ "$HEALTHY_COUNT" -ge 2 ]; then
        HEALTHY=1
        break
    fi

    sleep 10
done

echo

if [ "$HEALTHY" -eq 1 ]; then
    echo "${GREEN}${BOLD}✓ All backend instances are HEALTHY${RESET}"
else
    echo "${YELLOW}Backend may still be initializing.${RESET}"
    echo "${YELLOW}Current status:${RESET}"

    gcloud compute backend-services get-health \
        web-backend-service \
        --global || true
fi


# ============================================================
# Test Load Balancer
# ============================================================

echo
echo "${CYAN}${BOLD}=============================================================="
echo " TEST LOAD BALANCER"
echo "==============================================================${RESET}"

echo "${MAGENTA}${BOLD}URL: http://${LB_IP}/${RESET}"
echo

SUCCESS=0

for i in {1..30}; do

    RESPONSE=$(curl -s \
        --connect-timeout 5 \
        --max-time 10 \
        "http://${LB_IP}/" 2>/dev/null || true)

    if echo "$RESPONSE" | grep -q "Page served from:"; then

        echo "${GREEN}✓ Load Balancer is responding${RESET}"
        SUCCESS=1
        break

    fi

    echo "Waiting for frontend propagation... ($i/30)"
    sleep 10
done

echo

if [ "$SUCCESS" -eq 1 ]; then

    echo "${GREEN}${BOLD}Traffic test:${RESET}"
    echo

    for i in {1..10}; do
        printf "Request %-2s -> " "$i"

        curl -s \
            --connect-timeout 5 \
            --max-time 10 \
            "http://${LB_IP}/"

        echo
        sleep 1
    done

else
    echo "${YELLOW}Load Balancer frontend has not responded yet.${RESET}"
fi


# ============================================================
# Final summary
# ============================================================

echo
echo "${CYAN}${BOLD}=============================================================="
echo "                       FINAL STATUS"
echo "==============================================================${RESET}"

echo
echo "${GREEN}✓ Task 1 - Region / Zone configured${RESET}"
echo "${GREEN}✓ Task 2 - www1, www2, www3 created${RESET}"
echo "${GREEN}✓ Task 3 - Application Load Balancer created${RESET}"

if [ "$SUCCESS" -eq 1 ]; then
    echo "${GREEN}✓ Task 4 - Load Balancer traffic verified${RESET}"
else
    echo "${YELLOW}! Task 4 - Retry URL after backend/frontend finishes initializing${RESET}"
fi

echo
echo "${WHITE}${BOLD}Load Balancer URL:${RESET}"
echo
echo "${CYAN}${BOLD}http://${LB_IP}/${RESET}"
echo

echo "${MAGENTA}${BOLD}=============================================================="
echo "                         ePlus.DEV"
echo "==============================================================${RESET}"