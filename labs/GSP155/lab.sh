#!/bin/bash

# ============================================================
# L7 APPLICATION LOAD BALANCER LAB
# Full Automation Script
# ePlus.DEV
# ============================================================

set +e

# ============================================================
# COLORS
# ============================================================

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
echo "        L7 APPLICATION LOAD BALANCER - ePlus.DEV"
echo "=============================================================="
echo "${RESET}"

# ============================================================
# PROJECT / REGION / ZONE AUTO DETECT
# ============================================================

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

REGION=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])" \
  2>/dev/null)

ZONE=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-zone])" \
  2>/dev/null)

# Fallback to gcloud configuration
if [ -z "$ZONE" ]; then
  ZONE=$(gcloud config get-value compute/zone 2>/dev/null)
fi

if [ -z "$REGION" ]; then
  REGION=$(gcloud config get-value compute/region 2>/dev/null)
fi

# Derive region from zone if needed
if [ -z "$REGION" ] && [ -n "$ZONE" ]; then
  REGION=$(gcloud compute zones describe "$ZONE" \
    --format="value(region.basename())" 2>/dev/null)
fi

# Last fallback: check existing VM
if [ -z "$ZONE" ]; then
  ZONE=$(gcloud compute instances list \
    --format="value(zone.basename())" \
    --limit=1 2>/dev/null)
fi

if [ -z "$REGION" ] && [ -n "$ZONE" ]; then
  REGION=$(gcloud compute zones describe "$ZONE" \
    --format="value(region.basename())" 2>/dev/null)
fi

if [ -z "$REGION" ] || [ -z "$ZONE" ]; then
  echo "${RED}Unable to detect REGION / ZONE.${RESET}"
  exit 1
fi

gcloud config set compute/region "$REGION" >/dev/null
gcloud config set compute/zone "$ZONE" >/dev/null

echo "${YELLOW}Project : ${WHITE}$PROJECT_ID${RESET}"
echo "${YELLOW}Region  : ${WHITE}$REGION${RESET}"
echo "${YELLOW}Zone    : ${WHITE}$ZONE${RESET}"

echo


# ============================================================
# TASK 1
# ============================================================

echo "${CYAN}${BOLD}=============================================================="
echo " TASK 1 - CONFIGURE REGION AND ZONE"
echo "==============================================================${RESET}"

echo "${GREEN}✓ Region configured: $REGION${RESET}"
echo "${GREEN}✓ Zone configured  : $ZONE${RESET}"

echo


# ============================================================
# TASK 2 - CREATE WWW INSTANCES
# ============================================================

echo "${CYAN}${BOLD}=============================================================="
echo " TASK 2 - CREATE WEB SERVER INSTANCES"
echo "==============================================================${RESET}"

for VM in www1 www2 www3
do

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

    if [ $? -eq 0 ]; then
      echo "${GREEN}✓ $VM created${RESET}"
    else
      echo "${RED}✗ Failed to create $VM${RESET}"
    fi

  fi

done

echo


# ============================================================
# FIREWALL FOR WWW SERVERS
# ============================================================

if gcloud compute firewall-rules describe \
  www-firewall-network-lb >/dev/null 2>&1; then

  echo "${GREEN}✓ www-firewall-network-lb already exists${RESET}"

else

  echo "${YELLOW}Creating www-firewall-network-lb...${RESET}"

  gcloud compute firewall-rules create \
    www-firewall-network-lb \
    --network=default \
    --target-tags=network-lb-tag \
    --allow=tcp:80

fi

echo


# ============================================================
# SHOW WWW INSTANCES
# ============================================================

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
# CREATE INSTANCE TEMPLATE
# ============================================================

echo "${CYAN}${BOLD}=============================================================="
echo " TASK 3 - CREATE APPLICATION LOAD BALANCER"
echo "==============================================================${RESET}"

if gcloud compute instance-templates describe \
  lb-backend-template >/dev/null 2>&1; then

  echo "${GREEN}✓ lb-backend-template already exists${RESET}"

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

echo "Page served from: ${vm_hostname}" \
> /var/www/html/index.html

systemctl enable apache2
systemctl restart apache2
'

fi

echo


# ============================================================
# FUNCTION: REMOVE MIG FROM BACKEND
# ============================================================

detach_mig_from_backend() {

  if ! gcloud compute backend-services describe \
    web-backend-service \
    --global >/dev/null 2>&1; then

    return
  fi

  BACKEND_GROUPS=$(gcloud compute backend-services describe \
    web-backend-service \
    --global \
    --format="value(backends[].group)" 2>/dev/null)

  for GROUP_URL in $BACKEND_GROUPS
  do

    if echo "$GROUP_URL" | grep -q "/instanceGroups/lb-backend-group$"; then

      BACKEND_ZONE=$(echo "$GROUP_URL" \
        | sed -n 's#.*zones/\([^/]*\)/instanceGroups/.*#\1#p')

      if [ -n "$BACKEND_ZONE" ]; then

        echo "${YELLOW}Detaching existing MIG from backend ($BACKEND_ZONE)...${RESET}"

        gcloud compute backend-services remove-backend \
          web-backend-service \
          --instance-group=lb-backend-group \
          --instance-group-zone="$BACKEND_ZONE" \
          --global \
          --quiet >/dev/null 2>&1

      fi

    fi

  done
}


# ============================================================
# CHECK EXISTING MIG
# ============================================================

MIG_ZONE=$(gcloud compute instance-groups managed list \
  --filter="name=lb-backend-group" \
  --format="value(zone.basename())" \
  2>/dev/null | head -1)

MIG_READY=0

if [ -n "$MIG_ZONE" ]; then

  echo "${YELLOW}Existing MIG found in: $MIG_ZONE${RESET}"

  MIG_OUTPUT=$(gcloud compute instance-groups managed list-instances \
    lb-backend-group \
    --zone="$MIG_ZONE" 2>&1)

  RUNNING_COUNT=$(echo "$MIG_OUTPUT" \
    | grep -c "STATUS: RUNNING")

  if [ "$RUNNING_COUNT" -ge 2 ]; then

    echo "${GREEN}✓ Existing MIG has 2 RUNNING instances${RESET}"

    ZONE="$MIG_ZONE"
    MIG_READY=1

  else

    echo "${YELLOW}Existing MIG is not healthy.${RESET}"

    echo "$MIG_OUTPUT"

    detach_mig_from_backend

    echo
    echo "${YELLOW}Deleting failed MIG...${RESET}"

    gcloud compute instance-groups managed delete \
      lb-backend-group \
      --zone="$MIG_ZONE" \
      --quiet

    sleep 5

  fi

fi

echo


# ============================================================
# CREATE MIG
# ============================================================

if [ "$MIG_READY" -eq 0 ]; then

  # Current/default zone is always tried first.
  ZONES="$ZONE"

  for Z in $(gcloud compute zones list \
    --filter="region:($REGION)" \
    --format="value(name)")
  do

    if [ "$Z" != "$ZONE" ]; then
      ZONES="$ZONES $Z"
    fi

  done

  echo "${CYAN}Candidate zones:${RESET}"
  echo "$ZONES"
  echo

  WORKING_ZONE=""

  for Z in $ZONES
  do

    echo
    echo "${BLUE}${BOLD}--------------------------------------------------------------"
    echo " Trying MIG in zone: $Z"
    echo "--------------------------------------------------------------${RESET}"

    # Clean a failed group with same name if present
    if gcloud compute instance-groups managed describe \
      lb-backend-group \
      --zone="$Z" >/dev/null 2>&1; then

      detach_mig_from_backend

      gcloud compute instance-groups managed delete \
        lb-backend-group \
        --zone="$Z" \
        --quiet

      sleep 3

    fi

    echo "${YELLOW}Creating lb-backend-group...${RESET}"

    gcloud compute instance-groups managed create \
      lb-backend-group \
      --template=lb-backend-template \
      --size=2 \
      --zone="$Z"

    if [ $? -ne 0 ]; then

      echo "${RED}✗ MIG creation failed in $Z${RESET}"
      continue

    fi

    gcloud compute instance-groups managed set-named-ports \
      lb-backend-group \
      --zone="$Z" \
      --named-ports=http:80 >/dev/null 2>&1

    echo "${YELLOW}Waiting for instances...${RESET}"

    MIG_SUCCESS=0

    for CHECK in {1..30}
    do

      sleep 10

      OUTPUT=$(gcloud compute instance-groups managed list-instances \
        lb-backend-group \
        --zone="$Z" 2>&1)

      RUNNING_COUNT=$(echo "$OUTPUT" \
        | grep -c "STATUS: RUNNING")

      echo "Check $CHECK/30 -> $RUNNING_COUNT/2 RUNNING"

      # Immediately detect zone capacity problem
      if echo "$OUTPUT" | grep -q "ZONE_RESOURCE_POOL_EXHAUSTED"; then

        echo "${RED}✗ ZONE_RESOURCE_POOL_EXHAUSTED in $Z${RESET}"
        break

      fi

      if [ "$RUNNING_COUNT" -ge 2 ]; then

        MIG_SUCCESS=1
        break

      fi

    done

    if [ "$MIG_SUCCESS" -eq 1 ]; then

      WORKING_ZONE="$Z"

      echo
      echo "${GREEN}${BOLD}✓ MIG successfully created in $Z${RESET}"

      break

    fi

    echo "${YELLOW}Deleting failed MIG from $Z...${RESET}"

    detach_mig_from_backend

    gcloud compute instance-groups managed delete \
      lb-backend-group \
      --zone="$Z" \
      --quiet >/dev/null 2>&1

    sleep 3

  done


  if [ -z "$WORKING_ZONE" ]; then

    echo
    echo "${RED}${BOLD}=============================================================="
    echo " MIG CREATION FAILED"
    echo "==============================================================${RESET}"
    echo
    echo "All zones in $REGION currently have insufficient capacity."
    exit 1

  fi

  # ZONE now means the actual zone used by the lab resources.
  ZONE="$WORKING_ZONE"

  gcloud config set compute/zone "$ZONE" >/dev/null

fi


# ============================================================
# VERIFY MIG
# ============================================================

echo
echo "${CYAN}${BOLD}=============================================================="
echo " MANAGED INSTANCE GROUP"
echo "==============================================================${RESET}"

gcloud compute instance-groups managed describe \
  lb-backend-group \
  --zone="$ZONE" \
  --format="yaml(
name,
zone,
targetSize,
instanceTemplate
)"

echo

gcloud compute instance-groups managed list-instances \
  lb-backend-group \
  --zone="$ZONE"

echo


# ============================================================
# HEALTH CHECK FIREWALL
# ============================================================

if gcloud compute firewall-rules describe \
  fw-allow-health-check >/dev/null 2>&1; then

  echo "${GREEN}✓ fw-allow-health-check already exists${RESET}"

else

  echo "${YELLOW}Creating fw-allow-health-check...${RESET}"

  gcloud compute firewall-rules create fw-allow-health-check \
    --network=default \
    --action=allow \
    --direction=ingress \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags=allow-health-check \
    --rules=tcp:80

fi

echo


# ============================================================
# GLOBAL IP
# ============================================================

if gcloud compute addresses describe \
  lb-ipv4-1 \
  --global >/dev/null 2>&1; then

  echo "${GREEN}✓ lb-ipv4-1 already exists${RESET}"

else

  echo "${YELLOW}Creating lb-ipv4-1...${RESET}"

  gcloud compute addresses create lb-ipv4-1 \
    --ip-version=IPV4 \
    --global

fi

LB_IP=$(gcloud compute addresses describe \
  lb-ipv4-1 \
  --global \
  --format="value(address)")

echo "${MAGENTA}${BOLD}Load Balancer IP: $LB_IP${RESET}"

echo


# ============================================================
# HEALTH CHECK
# ============================================================

if gcloud compute health-checks describe \
  http-basic-check >/dev/null 2>&1; then

  echo "${GREEN}✓ http-basic-check already exists${RESET}"

else

  echo "${YELLOW}Creating http-basic-check...${RESET}"

  gcloud compute health-checks create http \
    http-basic-check \
    --port=80

fi

echo


# ============================================================
# BACKEND SERVICE
# ============================================================

if gcloud compute backend-services describe \
  web-backend-service \
  --global >/dev/null 2>&1; then

  echo "${GREEN}✓ web-backend-service already exists${RESET}"

else

  echo "${YELLOW}Creating web-backend-service...${RESET}"

  gcloud compute backend-services create \
    web-backend-service \
    --protocol=HTTP \
    --port-name=http \
    --health-checks=http-basic-check \
    --global

fi

echo


# ============================================================
# MAKE SURE ONLY CURRENT MIG IS ATTACHED
# ============================================================

detach_mig_from_backend

echo "${YELLOW}Attaching lb-backend-group from $ZONE...${RESET}"

gcloud compute backend-services add-backend \
  web-backend-service \
  --instance-group=lb-backend-group \
  --instance-group-zone="$ZONE" \
  --global

echo "${GREEN}✓ Backend attached${RESET}"

echo


# ============================================================
# URL MAP
# ============================================================

if gcloud compute url-maps describe \
  web-map-http >/dev/null 2>&1; then

  echo "${GREEN}✓ web-map-http already exists${RESET}"

else

  echo "${YELLOW}Creating web-map-http...${RESET}"

  gcloud compute url-maps create web-map-http \
    --default-service=web-backend-service

fi

echo


# ============================================================
# TARGET HTTP PROXY
# ============================================================

if gcloud compute target-http-proxies describe \
  http-lb-proxy >/dev/null 2>&1; then

  echo "${GREEN}✓ http-lb-proxy already exists${RESET}"

else

  echo "${YELLOW}Creating http-lb-proxy...${RESET}"

  gcloud compute target-http-proxies create \
    http-lb-proxy \
    --url-map=web-map-http

fi

echo


# ============================================================
# FORWARDING RULE
# ============================================================

if gcloud compute forwarding-rules describe \
  http-content-rule \
  --global >/dev/null 2>&1; then

  echo "${GREEN}✓ http-content-rule already exists${RESET}"

else

  echo "${YELLOW}Creating http-content-rule...${RESET}"

  gcloud compute forwarding-rules create \
    http-content-rule \
    --address=lb-ipv4-1 \
    --global \
    --target-http-proxy=http-lb-proxy \
    --ports=80

fi


# ============================================================
# TASK 4 - WAIT FOR HEALTHY BACKENDS
# ============================================================

echo
echo "${CYAN}${BOLD}=============================================================="
echo " TASK 4 - WAIT FOR HEALTHY BACKENDS"
echo "==============================================================${RESET}"

BACKEND_HEALTHY=0

for CHECK in {1..40}
do

  HEALTH=$(gcloud compute backend-services get-health \
    web-backend-service \
    --global 2>/dev/null)

  HEALTHY_COUNT=$(echo "$HEALTH" \
    | grep -c "healthState: HEALTHY")

  echo "Health check $CHECK/40 -> $HEALTHY_COUNT/2 HEALTHY"

  if [ "$HEALTHY_COUNT" -ge 2 ]; then

    BACKEND_HEALTHY=1
    break

  fi

  sleep 10

done

echo

if [ "$BACKEND_HEALTHY" -eq 1 ]; then

  echo "${GREEN}${BOLD}✓ Both backend instances are HEALTHY${RESET}"

else

  echo "${YELLOW}Backend is still initializing.${RESET}"

  gcloud compute backend-services get-health \
    web-backend-service \
    --global

fi


# ============================================================
# TEST LOAD BALANCER
# ============================================================

echo
echo "${CYAN}${BOLD}=============================================================="
echo " TEST LOAD BALANCER"
echo "==============================================================${RESET}"

LB_READY=0

for CHECK in {1..30}
do

  RESPONSE=$(curl -s \
    --connect-timeout 5 \
    --max-time 10 \
    "http://${LB_IP}/" 2>/dev/null)

  if echo "$RESPONSE" | grep -q "Page served from:"; then

    LB_READY=1

    echo "${GREEN}✓ Load Balancer is responding${RESET}"
    echo
    echo "$RESPONSE"

    break

  fi

  echo "Frontend check $CHECK/30..."

  sleep 10

done


# ============================================================
# FINAL STATUS
# ============================================================

echo
echo "${CYAN}${BOLD}=============================================================="
echo "                       FINAL STATUS"
echo "==============================================================${RESET}"

echo
echo "${GREEN}✓ Task 1 - Region / Zone configured${RESET}"
echo "${GREEN}✓ Task 2 - www1 / www2 / www3 created${RESET}"
echo "${GREEN}✓ Task 3 - lb-backend-group created from lb-backend-template${RESET}"
echo "${GREEN}✓ Task 3 - Application Load Balancer configured${RESET}"

if [ "$LB_READY" -eq 1 ]; then
  echo "${GREEN}✓ Task 4 - Traffic test successful${RESET}"
else
  echo "${YELLOW}! Task 4 - Frontend may still be propagating${RESET}"
fi

echo
echo "${WHITE}${BOLD}Project:${RESET} $PROJECT_ID"
echo "${WHITE}${BOLD}Region :${RESET} $REGION"
echo "${WHITE}${BOLD}Zone   :${RESET} $ZONE"

echo
echo "${WHITE}${BOLD}Load Balancer URL:${RESET}"
echo
echo "${CYAN}${BOLD}http://${LB_IP}/${RESET}"

echo
echo "${MAGENTA}${BOLD}=============================================================="
echo "                         ePlus.DEV"
echo "==============================================================${RESET}"