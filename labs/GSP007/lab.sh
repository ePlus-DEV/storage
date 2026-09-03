#!/bin/bash

# ============================================================
# GSP007 - External Passthrough Network Load Balancer
# © ePlus.DEV
# ============================================================

set -uo pipefail

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

RESET=$'\033[0m'
BOLD=$'\033[1m'
UNDERLINE=$'\033[4m'

# ============================================================
# FUNCTIONS
# ============================================================

line() {
  echo "${CYAN}============================================================${RESET}"
}

success() {
  echo "${GREEN}✓ $1${RESET}"
}

info() {
  echo "${CYAN}➜ $1${RESET}"
}

warn() {
  echo "${YELLOW}⚠ $1${RESET}"
}

error() {
  echo "${RED}✗ $1${RESET}"
}

section() {
  echo
  line
  echo "${GREEN}${BOLD}$1${RESET}"
  line
}

# ============================================================
# HEADER
# ============================================================

clear

echo "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║          GSP007 - NETWORK LOAD BALANCER                 ║"
echo "║                     © ePlus.DEV                         ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo "${RESET}"

echo "${MAGENTA}${BOLD}Google Cloud Skills Boost Automation${RESET}"
echo "${YELLOW}${UNDERLINE}https://eplus.dev${RESET}"
echo

# ============================================================
# PROJECT
# ============================================================

PROJECT_ID=$(gcloud config get-value project 2>/dev/null || true)

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  error "Google Cloud project was not detected."
  exit 1
fi

# ============================================================
# AUTO DETECT REGION / ZONE
# ============================================================

section "[1/5] DETECT REGION AND ZONE"

info "Detecting lab location automatically..."

# ------------------------------------------------------------
# 1. Try project metadata
# ------------------------------------------------------------

REGION=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])" \
  2>/dev/null || true)

ZONE=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-zone])" \
  2>/dev/null || true)

# ------------------------------------------------------------
# 2. Try current gcloud config
# ------------------------------------------------------------

if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  REGION=$(gcloud config get-value compute/region 2>/dev/null || true)
fi

if [[ -z "$ZONE" || "$ZONE" == "(unset)" ]]; then
  ZONE=$(gcloud config get-value compute/zone 2>/dev/null || true)
fi

# ------------------------------------------------------------
# 3. If zone exists but region doesn't, derive region
# ------------------------------------------------------------

if [[ (-z "$REGION" || "$REGION" == "(unset)") && \
      -n "$ZONE" && "$ZONE" != "(unset)" ]]; then

  REGION=$(gcloud compute zones describe "$ZONE" \
    --format="value(region.basename())" \
    2>/dev/null || true)
fi

# ------------------------------------------------------------
# 4. If region exists but zone doesn't, find a valid zone
# ------------------------------------------------------------

if [[ (-z "$ZONE" || "$ZONE" == "(unset)") && \
      -n "$REGION" && "$REGION" != "(unset)" ]]; then

  ZONE=$(gcloud compute zones list \
    --filter="region:($REGION) status:UP" \
    --format="value(name)" \
    --sort-by=name \
    --limit=1 \
    2>/dev/null || true)
fi

# ------------------------------------------------------------
# Final validation
# ------------------------------------------------------------

if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
  error "Unable to automatically detect REGION."
  exit 1
fi

if [[ -z "$ZONE" || "$ZONE" == "(unset)" ]]; then
  error "Unable to automatically detect ZONE."
  exit 1
fi

# ------------------------------------------------------------
# Configure gcloud defaults
# ------------------------------------------------------------

gcloud config set compute/region "$REGION" --quiet >/dev/null
gcloud config set compute/zone "$ZONE" --quiet >/dev/null

success "Project detected"
success "Region detected"
success "Zone detected"

echo
echo "${WHITE}${BOLD}Lab Configuration${RESET}"
echo "Project : ${GREEN}${PROJECT_ID}${RESET}"
echo "Region  : ${GREEN}${REGION}${RESET}"
echo "Zone    : ${GREEN}${ZONE}${RESET}"

# ============================================================
# TASK 2 - CREATE WEB SERVERS
# ============================================================

section "[2/5] CREATE WEB SERVER INSTANCES"

create_web_server() {

  local SERVER_NAME="$1"

  # ----------------------------------------------------------
  # Existing VM
  # ----------------------------------------------------------

  if gcloud compute instances describe "$SERVER_NAME" \
      --zone="$ZONE" \
      >/dev/null 2>&1; then

    success "$SERVER_NAME already exists"

    # Ensure required network tag exists
    gcloud compute instances add-tags "$SERVER_NAME" \
      --zone="$ZONE" \
      --tags=network-lb-tag \
      --quiet >/dev/null 2>&1 || true

    return
  fi

  # ----------------------------------------------------------
  # Startup script
  # ----------------------------------------------------------

  info "Creating $SERVER_NAME..."

  STARTUP_SCRIPT=$(cat <<EOF
#!/bin/bash

apt-get update
apt-get install apache2 -y

systemctl enable apache2
systemctl restart apache2

cat > /var/www/html/index.html <<HTML
<h3>Web Server: $SERVER_NAME</h3>
HTML
EOF
)

  # ----------------------------------------------------------
  # Create VM
  # ----------------------------------------------------------

  if gcloud compute instances create "$SERVER_NAME" \
      --zone="$ZONE" \
      --tags=network-lb-tag \
      --machine-type=e2-small \
      --image-family=debian-12 \
      --image-project=debian-cloud \
      --metadata=startup-script="$STARTUP_SCRIPT" \
      --quiet; then

    success "$SERVER_NAME created successfully"

  else

    error "Failed to create $SERVER_NAME"
    exit 1
  fi
}

# ------------------------------------------------------------
# Create required VMs
# ------------------------------------------------------------

create_web_server "www1"
create_web_server "www2"
create_web_server "www3"

# ============================================================
# FIREWALL
# ============================================================

echo
info "Checking HTTP firewall rule..."

if gcloud compute firewall-rules describe www-firewall-network-lb \
    >/dev/null 2>&1; then

  success "www-firewall-network-lb already exists"

else

  info "Creating www-firewall-network-lb..."

  gcloud compute firewall-rules create www-firewall-network-lb \
    --target-tags=network-lb-tag \
    --allow=tcp:80 \
    --quiet

  success "Firewall rule created"
fi

# ============================================================
# SHOW INSTANCES
# ============================================================

echo
echo "${WHITE}${BOLD}Web Server Instances${RESET}"
echo

gcloud compute instances list \
  --filter="name=(www1 www2 www3)" \
  --format="table(
    name,
    zone.basename():label=ZONE,
    machineType.basename():label=MACHINE_TYPE,
    status,
    networkInterfaces[0].networkIP:label=INTERNAL_IP,
    networkInterfaces[0].accessConfigs[0].natIP:label=EXTERNAL_IP
  )"

# ============================================================
# WAIT FOR APACHE
# ============================================================

echo
info "Waiting for Apache startup..."

for SERVER in www1 www2 www3; do

  SERVER_IP=$(gcloud compute instances describe "$SERVER" \
    --zone="$ZONE" \
    --format="value(networkInterfaces[0].accessConfigs[0].natIP)" \
    2>/dev/null)

  echo
  info "Testing $SERVER → $SERVER_IP"

  READY=false

  for attempt in {1..24}; do

    RESPONSE=$(curl -s \
      --connect-timeout 3 \
      --max-time 5 \
      "http://${SERVER_IP}" \
      2>/dev/null || true)

    if [[ "$RESPONSE" == *"Web Server:"* ]]; then

      echo "   $RESPONSE"
      success "$SERVER is ready"

      READY=true
      break
    fi

    printf "${YELLOW}   Apache startup: %02d/24\r${RESET}" "$attempt"

    sleep 5
  done

  echo

  if [[ "$READY" != true ]]; then
    warn "$SERVER exists but Apache may still be initializing."
  fi
done

# ============================================================
# TASK 3 - LOAD BALANCING SERVICE
# ============================================================

section "[3/5] CONFIGURE LOAD BALANCING SERVICE"

# ============================================================
# STATIC REGIONAL EXTERNAL IP
# ============================================================

if gcloud compute addresses describe network-lb-ip-1 \
    --region="$REGION" \
    >/dev/null 2>&1; then

  success "network-lb-ip-1 already exists"

else

  info "Creating regional static external IP..."

  gcloud compute addresses create network-lb-ip-1 \
    --region="$REGION" \
    --quiet

  success "Static IP created"
fi

STATIC_IP=$(gcloud compute addresses describe network-lb-ip-1 \
  --region="$REGION" \
  --format="value(address)")

echo
echo "Static IP : ${GREEN}${BOLD}${STATIC_IP}${RESET}"

# ============================================================
# LEGACY HTTP HEALTH CHECK
# ============================================================

echo
info "Checking legacy health check..."

if gcloud compute http-health-checks describe basic-check \
    >/dev/null 2>&1; then

  success "basic-check already exists"

else

  info "Creating basic-check..."

  gcloud compute http-health-checks create basic-check \
    --quiet

  success "Health check created"
fi

# ============================================================
# TASK 4 - TARGET POOL
# ============================================================

section "[4/5] CREATE TARGET POOL AND FORWARDING RULE"

# ============================================================
# TARGET POOL
# ============================================================

if gcloud compute target-pools describe www-pool \
    --region="$REGION" \
    >/dev/null 2>&1; then

  success "www-pool already exists"

else

  info "Creating target pool..."

  gcloud compute target-pools create www-pool \
    --region="$REGION" \
    --http-health-check=basic-check \
    --quiet

  success "Target pool created"
fi

# ============================================================
# ENSURE HEALTH CHECK ATTACHED
# ============================================================

POOL_HEALTH=$(gcloud compute target-pools describe www-pool \
  --region="$REGION" \
  --format="value(healthChecks)" \
  2>/dev/null || true)

if [[ "$POOL_HEALTH" != *"basic-check"* ]]; then

  info "Attaching basic-check to www-pool..."

  gcloud compute target-pools add-health-checks www-pool \
    --region="$REGION" \
    --http-health-check=basic-check \
    --quiet >/dev/null 2>&1 || true
fi

# ============================================================
# ADD INSTANCES
# ============================================================

echo
info "Checking target pool instances..."

POOL_INFO=$(gcloud compute target-pools describe www-pool \
  --region="$REGION" \
  --format="value(instances)" \
  2>/dev/null || true)

for SERVER in www1 www2 www3; do

  if echo "$POOL_INFO" | grep -q "/instances/${SERVER}"; then

    success "$SERVER already in www-pool"

  else

    info "Adding $SERVER to www-pool..."

    if gcloud compute target-pools add-instances www-pool \
      --region="$REGION" \
      --instances="$SERVER" \
      --instances-zone="$ZONE" \
      --quiet; then

      success "$SERVER added"

    else

      error "Failed to add $SERVER to target pool"
      exit 1
    fi
  fi

done

# ============================================================
# FORWARDING RULE
# ============================================================

echo
info "Checking forwarding rule..."

if gcloud compute forwarding-rules describe www-rule \
    --region="$REGION" \
    >/dev/null 2>&1; then

  success "www-rule already exists"

else

  info "Creating forwarding rule..."

  gcloud compute forwarding-rules create www-rule \
    --region="$REGION" \
    --ports=80 \
    --address=network-lb-ip-1 \
    --target-pool=www-pool \
    --quiet

  success "Forwarding rule created"
fi

# ============================================================
# TASK 5 - TEST LOAD BALANCER
# ============================================================

section "[5/5] TEST NETWORK LOAD BALANCER"

IPADDRESS=$(gcloud compute forwarding-rules describe www-rule \
  --region="$REGION" \
  --format="value(IPAddress)" \
  2>/dev/null)

echo
echo "${WHITE}${BOLD}Load Balancer IP${RESET}"
echo
echo "    ${GREEN}${BOLD}${IPADDRESS}${RESET}"
echo

# ============================================================
# WAIT UNTIL NLB RESPONDS
# ============================================================

info "Waiting for healthy load balancer backends..."

LB_READY=false

for attempt in {1..24}; do

  RESPONSE=$(curl -s \
    --connect-timeout 3 \
    --max-time 5 \
    "http://${IPADDRESS}" \
    2>/dev/null || true)

  if [[ "$RESPONSE" == *"Web Server:"* ]]; then

    echo
    success "Network Load Balancer is responding"
    echo "   $RESPONSE"

    LB_READY=true
    break
  fi

  printf "${YELLOW}Health check propagation: %02d/24\r${RESET}" "$attempt"

  sleep 5
done

echo

# ============================================================
# TRAFFIC DISTRIBUTION TEST
# ============================================================

if [[ "$LB_READY" == true ]]; then

  echo
  echo "${WHITE}${BOLD}Traffic Distribution Test${RESET}"
  echo

  for i in {1..12}; do

    RESPONSE=$(curl -s \
      --connect-timeout 3 \
      --max-time 5 \
      "http://${IPADDRESS}" \
      2>/dev/null || true)

    printf "Request %02d → %s\n" "$i" "$RESPONSE"

    sleep 1
  done

else

  warn "Load balancer resources are ready."
  warn "Google Cloud health checks may still be propagating."
fi

# ============================================================
# FINAL CHECK
# ============================================================

section "FINAL RESOURCE STATUS"

echo "${WHITE}${BOLD}VM INSTANCES${RESET}"
echo

gcloud compute instances list \
  --filter="name=(www1 www2 www3)" \
  --format="table(
    name,
    zone.basename():label=ZONE,
    machineType.basename():label=MACHINE,
    status
  )"

echo
echo "${WHITE}${BOLD}NETWORK LOAD BALANCER${RESET}"
echo

echo "Project         : ${GREEN}$PROJECT_ID${RESET}"
echo "Region          : ${GREEN}$REGION${RESET}"
echo "Zone            : ${GREEN}$ZONE${RESET}"
echo "Static IP       : ${GREEN}$STATIC_IP${RESET}"
echo "Health Check    : ${GREEN}basic-check${RESET}"
echo "Target Pool     : ${GREEN}www-pool${RESET}"
echo "Forwarding Rule : ${GREEN}www-rule${RESET}"
echo "Load Balancer IP: ${GREEN}${BOLD}$IPADDRESS${RESET}"

# ============================================================
# TARGET POOL HEALTH
# ============================================================

echo
echo "${WHITE}${BOLD}Target Pool Health${RESET}"
echo

gcloud compute target-pools get-health www-pool \
  --region="$REGION" \
  2>/dev/null || true

# ============================================================
# COMPLETE
# ============================================================

echo
echo "${GREEN}${BOLD}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                 GSP007 COMPLETED                        ║"
echo "║                     © ePlus.DEV                         ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo "${RESET}"

echo "${CYAN}Load Balancer:${RESET}"
echo "${BLUE}${UNDERLINE}http://${IPADDRESS}${RESET}"
echo
echo "${YELLOW}${BOLD}Click \"Check my progress\" in Google Cloud Skills Boost.${RESET}"
echo