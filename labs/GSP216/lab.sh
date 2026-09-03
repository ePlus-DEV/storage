#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
#  GSP216 - Internal Load Balancer
#  Automated Lab Script
#  © ePlus.DEV
# ============================================================

# ========================= COLORS ============================
BLACK=$'\033[0;30m'
RED=$'\033[0;91m'
GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
BLUE=$'\033[0;94m'
MAGENTA=$'\033[0;95m'
CYAN=$'\033[0;96m'
WHITE=$'\033[0;97m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
RESET=$'\033[0m'

clear

echo "${CYAN}${BOLD}"
echo "=============================================================="
echo "               GSP216 - INTERNAL LOAD BALANCER"
echo "=============================================================="
echo "${MAGENTA}                    © ePlus.DEV${RESET}"
echo ""

trap 'echo ""; echo "${RED}${BOLD}✗ ERROR at line ${LINENO}${RESET}"; exit 1' ERR

section() {
    echo ""
    echo "${BLUE}${BOLD}==============================================================${RESET}"
    echo "${YELLOW}${BOLD}$1${RESET}"
    echo "${BLUE}${BOLD}==============================================================${RESET}"
}

ok() {
    echo "${GREEN}${BOLD}✓ $1${RESET}"
}

info() {
    echo "${CYAN}➜ $1${RESET}"
}

warn() {
    echo "${YELLOW}⚠ $1${RESET}"
}

die() {
    echo "${RED}${BOLD}✗ $1${RESET}"
    exit 1
}

# ============================================================
# CONFIG
# ============================================================

NETWORK="my-internal-app"

SUBNET_A="subnet-a"
SUBNET_B="subnet-b"

TEMPLATE1="instance-template-1"
TEMPLATE2="instance-template-2"

MIG1="instance-group-1"
MIG2="instance-group-2"

UTILITY_VM="utility-vm"
UTILITY_IP="10.10.20.50"

HEALTH_CHECK="my-ilb-health-check"
BACKEND_SERVICE="my-ilb"

ADDRESS_NAME="my-ilb-ip"
ILB_IP="10.10.30.5"

FORWARDING_RULE="my-ilb-forwarding-rule"

# ============================================================
# AUTO DETECT PROJECT
# ============================================================

section "[0/4] Detecting Lab Environment"

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
    PROJECT_ID="${DEVSHELL_PROJECT_ID:-}"
fi

if [[ -z "$PROJECT_ID" ]]; then
    read -rp "Enter Project ID: " PROJECT_ID
fi

gcloud config set project "$PROJECT_ID" >/dev/null

info "Project ID : $PROJECT_ID"

# ============================================================
# VERIFY PROVIDED NETWORK
# ============================================================

if ! gcloud compute networks describe "$NETWORK" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then
    die "Network '$NETWORK' was not found. Make sure the lab resources are ready."
fi

ok "Network found: $NETWORK"

# Find subnet-a and region automatically
SUBNET_A_ROW="$(
    gcloud compute networks subnets list \
        --project="$PROJECT_ID" \
        --format='value(name,region,network)' |
    awk -v s="$SUBNET_A" -v n="$NETWORK" \
        '$1==s && $3 ~ ("/" n "$") {print; exit}'
)"

if [[ -z "$SUBNET_A_ROW" ]]; then
    die "Cannot find $SUBNET_A in $NETWORK"
fi

read -r _ REGION_URL _ <<< "$SUBNET_A_ROW"
REGION="${REGION_URL##*/}"

SUBNET_B_REGION="$(
    gcloud compute networks subnets list \
        --project="$PROJECT_ID" \
        --format='value(name,region,network)' |
    awk -v s="$SUBNET_B" -v n="$NETWORK" \
        '$1==s && $3 ~ ("/" n "$") {print $2; exit}'
)"

if [[ -z "$SUBNET_B_REGION" ]]; then
    die "Cannot find $SUBNET_B in $NETWORK"
fi

SUBNET_B_REGION="${SUBNET_B_REGION##*/}"

if [[ "$SUBNET_B_REGION" != "$REGION" ]]; then
    die "$SUBNET_A and $SUBNET_B are not in the same region."
fi

SUBNET_A_CIDR="$(
    gcloud compute networks subnets describe "$SUBNET_A" \
        --region="$REGION" \
        --format='value(ipCidrRange)'
)"

SUBNET_B_CIDR="$(
    gcloud compute networks subnets describe "$SUBNET_B" \
        --region="$REGION" \
        --format='value(ipCidrRange)'
)"

info "Region   : $REGION"
info "Subnet A : $SUBNET_A ($SUBNET_A_CIDR)"
info "Subnet B : $SUBNET_B ($SUBNET_B_CIDR)"

# ============================================================
# AUTO SELECT TWO ZONES
# Prefer region-a and region-b because that matches lab layout.
# ============================================================

mapfile -t REGION_ZONES < <(
    gcloud compute zones list \
        --format='value(name,status)' |
    awk -v prefix="${REGION}-" \
        'index($1,prefix)==1 && $2=="UP" {print $1}' |
    sort
)

if (( ${#REGION_ZONES[@]} < 2 )); then
    die "Need at least two available zones in $REGION"
fi

ZONE1=""

for z in "${REGION_ZONES[@]}"; do
    if [[ "$z" == "${REGION}-a" ]]; then
        ZONE1="$z"
        break
    fi
done

ZONE1="${ZONE1:-${REGION_ZONES[0]}}"

ZONE2=""

# Prefer zone b
for z in "${REGION_ZONES[@]}"; do
    if [[ "$z" == "${REGION}-b" && "$z" != "$ZONE1" ]]; then
        ZONE2="$z"
        break
    fi
done

# Otherwise use any other zone
if [[ -z "$ZONE2" ]]; then
    for z in "${REGION_ZONES[@]}"; do
        if [[ "$z" != "$ZONE1" ]]; then
            ZONE2="$z"
            break
        fi
    done
fi

info "Zone 1   : $ZONE1"
info "Zone 2   : $ZONE2"

gcloud config set compute/region "$REGION" >/dev/null
gcloud config set compute/zone "$ZONE1" >/dev/null

# Compute API should normally already be enabled.
gcloud services enable compute.googleapis.com --quiet >/dev/null

ok "Environment detected successfully"

# ============================================================
# TASK 1
# Firewall Rules
# ============================================================

section "[1/4] TASK 1 - Firewall Rules"

# ------------------------------------------------------------
# app-allow-http
# ------------------------------------------------------------

if gcloud compute firewall-rules describe app-allow-http \
    >/dev/null 2>&1; then

    warn "app-allow-http already exists"

else

    gcloud compute firewall-rules create app-allow-http \
        --network="$NETWORK" \
        --direction=INGRESS \
        --priority=1000 \
        --action=ALLOW \
        --rules=tcp:80 \
        --source-ranges=10.10.0.0/16 \
        --target-tags=lb-backend \
        --quiet

    ok "Created app-allow-http"
fi

# ------------------------------------------------------------
# app-allow-health-check
# Lab requires TCP from Google health check ranges.
# No port was specified in the lab -> allow TCP.
# ------------------------------------------------------------

if gcloud compute firewall-rules describe app-allow-health-check \
    >/dev/null 2>&1; then

    warn "app-allow-health-check already exists"

else

    gcloud compute firewall-rules create app-allow-health-check \
        --network="$NETWORK" \
        --direction=INGRESS \
        --priority=1000 \
        --action=ALLOW \
        --rules=tcp \
        --source-ranges=130.211.0.0/22,35.191.0.0/16 \
        --target-tags=lb-backend \
        --quiet

    ok "Created app-allow-health-check"
fi

echo ""
gcloud compute firewall-rules list \
    --filter='name=(app-allow-http app-allow-health-check)' \
    --format='table(
        name,
        network.basename(),
        sourceRanges,
        allowed[].map().firewall_rule().list()
    )'

ok "TASK 1 resources completed"

# ============================================================
# TASK 2
# Instance Templates + MIGs + Utility VM
# ============================================================

section "[2/4] TASK 2 - Templates, MIGs and Utility VM"

STARTUP_SCRIPT="/tmp/eplus-ilb-startup.sh"

cat > "$STARTUP_SCRIPT" <<'STARTUP'
#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

apt-get update

apt-get install -y \
  apache2 \
  php \
  libapache2-mod-php \
  php-curl

cat <<'PHP' > /var/www/html/index.php
<h1>Internal Load Balancing Lab</h1>
<h2>Client IP</h2>
Your IP address : <?php echo $_SERVER['REMOTE_ADDR']; ?>

<h2>Hostname</h2>
Server Hostname: <?php echo gethostname(); ?>

<h2>Server Location</h2>
Region and Zone: <?php
  $ch = curl_init();
  curl_setopt(
      $ch,
      CURLOPT_URL,
      "http://metadata.google.internal/computeMetadata/v1/instance/zone"
  );
  curl_setopt(
      $ch,
      CURLOPT_HTTPHEADER,
      array('Metadata-Flavor: Google')
  );
  curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);

  $zone = curl_exec($ch);

  $parts = explode('/', $zone);

  echo end($parts);
?>
PHP

rm -f /var/www/html/index.html

systemctl enable apache2
systemctl restart apache2
STARTUP

# ------------------------------------------------------------
# Instance Template 1
# ------------------------------------------------------------

if gcloud compute instance-templates describe "$TEMPLATE1" \
    >/dev/null 2>&1; then

    warn "$TEMPLATE1 already exists"

else

    info "Creating $TEMPLATE1 on $SUBNET_A"

    gcloud compute instance-templates create "$TEMPLATE1" \
        --machine-type=e2-micro \
        --image-family=debian-12 \
        --image-project=debian-cloud \
        --network-interface="network=$NETWORK,subnet=$SUBNET_A,no-address" \
        --tags=lb-backend \
        --metadata-from-file=startup-script="$STARTUP_SCRIPT" \
        --quiet

    ok "Created $TEMPLATE1"
fi

# ------------------------------------------------------------
# Instance Template 2
# ------------------------------------------------------------

if gcloud compute instance-templates describe "$TEMPLATE2" \
    >/dev/null 2>&1; then

    warn "$TEMPLATE2 already exists"

else

    info "Creating $TEMPLATE2 on $SUBNET_B"

    gcloud compute instance-templates create "$TEMPLATE2" \
        --machine-type=e2-micro \
        --image-family=debian-12 \
        --image-project=debian-cloud \
        --network-interface="network=$NETWORK,subnet=$SUBNET_B,no-address" \
        --tags=lb-backend \
        --metadata-from-file=startup-script="$STARTUP_SCRIPT" \
        --quiet

    ok "Created $TEMPLATE2"
fi

# ------------------------------------------------------------
# MIG 1
# ------------------------------------------------------------

if gcloud compute instance-groups managed describe "$MIG1" \
    --zone="$ZONE1" >/dev/null 2>&1; then

    warn "$MIG1 already exists"

else

    gcloud compute instance-groups managed create "$MIG1" \
        --base-instance-name="$MIG1" \
        --template="$TEMPLATE1" \
        --size=1 \
        --zone="$ZONE1" \
        --quiet

    ok "Created $MIG1"
fi

# Exact CURRENT lab settings:
# Min 1 / Max 1 / CPU 80% / Initialization 45 seconds

gcloud compute instance-groups managed set-autoscaling "$MIG1" \
    --zone="$ZONE1" \
    --min-num-replicas=1 \
    --max-num-replicas=1 \
    --target-cpu-utilization=0.80 \
    --cool-down-period=45 \
    --mode=on \
    --quiet

ok "$MIG1 autoscaling: min=1 max=1 CPU=80% init=45"

# ------------------------------------------------------------
# MIG 2
# ------------------------------------------------------------

if gcloud compute instance-groups managed describe "$MIG2" \
    --zone="$ZONE2" >/dev/null 2>&1; then

    warn "$MIG2 already exists"

else

    gcloud compute instance-groups managed create "$MIG2" \
        --base-instance-name="$MIG2" \
        --template="$TEMPLATE2" \
        --size=1 \
        --zone="$ZONE2" \
        --quiet

    ok "Created $MIG2"
fi

gcloud compute instance-groups managed set-autoscaling "$MIG2" \
    --zone="$ZONE2" \
    --min-num-replicas=1 \
    --max-num-replicas=1 \
    --target-cpu-utilization=0.80 \
    --cool-down-period=45 \
    --mode=on \
    --quiet

ok "$MIG2 autoscaling: min=1 max=1 CPU=80% init=45"

# ------------------------------------------------------------
# Utility VM
# ------------------------------------------------------------

UTILITY_ZONE="$ZONE1"

EXISTING_UTILITY_ZONE="$(
    gcloud compute instances list \
        --filter="name=$UTILITY_VM" \
        --format='value(zone)' |
    head -n1 || true
)"

if [[ -n "$EXISTING_UTILITY_ZONE" ]]; then

    UTILITY_ZONE="${EXISTING_UTILITY_ZONE##*/}"
    warn "$UTILITY_VM already exists in $UTILITY_ZONE"

else

    info "Creating utility-vm with internal IP $UTILITY_IP"

    gcloud compute instances create "$UTILITY_VM" \
        --zone="$ZONE1" \
        --machine-type=e2-micro \
        --image-family=debian-12 \
        --image-project=debian-cloud \
        --network-interface="network=$NETWORK,subnet=$SUBNET_A,private-network-ip=$UTILITY_IP" \
        --quiet

    ok "Created $UTILITY_VM"
fi

# ============================================================
# Wait until MIG instances exist and are RUNNING
# ============================================================

wait_for_mig_vm() {

    local GROUP="$1"
    local ZONE="$2"

    local INSTANCE_URL=""
    local INSTANCE=""
    local STATUS=""

    for ((i=1; i<=40; i++)); do

        INSTANCE_URL="$(
            gcloud compute instance-groups managed list-instances "$GROUP" \
                --zone="$ZONE" \
                --format='value(instance)' |
            head -n1 || true
        )"

        if [[ -n "$INSTANCE_URL" ]]; then

            INSTANCE="${INSTANCE_URL##*/}"

            STATUS="$(
                gcloud compute instances describe "$INSTANCE" \
                    --zone="$ZONE" \
                    --format='value(status)' \
                    2>/dev/null || true
            )"

            if [[ "$STATUS" == "RUNNING" ]]; then
                echo "$INSTANCE"
                return 0
            fi
        fi

        printf "${DIM}   [%02d/40] %s VM status: %s${RESET}\r" \
            "$i" "$GROUP" "${STATUS:-CREATING}" >&2

        sleep 5
    done

    echo "" >&2
    return 1
}

echo ""
info "Checking managed instances..."

VM1="$(wait_for_mig_vm "$MIG1" "$ZONE1")"
echo ""

VM2="$(wait_for_mig_vm "$MIG2" "$ZONE2")"
echo ""

ok "$MIG1 VM: $VM1"
ok "$MIG2 VM: $VM2"

BACKEND_IP1="$(
    gcloud compute instances describe "$VM1" \
        --zone="$ZONE1" \
        --format='value(networkInterfaces[0].networkIP)'
)"

BACKEND_IP2="$(
    gcloud compute instances describe "$VM2" \
        --zone="$ZONE2" \
        --format='value(networkInterfaces[0].networkIP)'
)"

info "$VM1 -> $BACKEND_IP1"
info "$VM2 -> $BACKEND_IP2"

# ------------------------------------------------------------
# Test SSH access to utility VM
# ------------------------------------------------------------

ssh_utility() {
    gcloud compute ssh "$UTILITY_VM" \
        --zone="$UTILITY_ZONE" \
        --quiet \
        --command="$1"
}

SSH_READY=0

info "Checking utility-vm SSH..."

for ((i=1; i<=20; i++)); do

    if ssh_utility "echo eplus-ready" >/dev/null 2>&1; then
        SSH_READY=1
        break
    fi

    printf "${DIM}   [%02d/20] Checking SSH...${RESET}\r" "$i"
    sleep 5
done

echo ""

if [[ "$SSH_READY" == "1" ]]; then

    ok "utility-vm SSH ready"

    info "Testing backend $BACKEND_IP1"

    ssh_utility "
        for i in \$(seq 1 30); do
            if curl -fsS --max-time 4 http://$BACKEND_IP1/; then
                exit 0
            fi
            sleep 5
        done
        exit 1
    " || warn "Backend 1 web server is still initializing"

    echo ""

    info "Testing backend $BACKEND_IP2"

    ssh_utility "
        for i in \$(seq 1 30); do
            if curl -fsS --max-time 4 http://$BACKEND_IP2/; then
                exit 0
            fi
            sleep 5
        done
        exit 1
    " || warn "Backend 2 web server is still initializing"

    echo ""

else

    warn "Could not SSH utility-vm yet. Continuing with grader resources."
fi

ok "TASK 2 resources completed"

# ============================================================
# TASK 3
# Internal Load Balancer
# ============================================================

section "[3/4] TASK 3 - Internal Load Balancer"

# ------------------------------------------------------------
# Regional TCP health check
# ------------------------------------------------------------

if gcloud compute health-checks describe "$HEALTH_CHECK" \
    --region="$REGION" >/dev/null 2>&1; then

    warn "$HEALTH_CHECK already exists"

else

    gcloud compute health-checks create tcp "$HEALTH_CHECK" \
        --region="$REGION" \
        --port=80 \
        --check-interval=5s \
        --timeout=5s \
        --healthy-threshold=2 \
        --unhealthy-threshold=2 \
        --quiet

    ok "Created regional TCP health check"
fi

# ------------------------------------------------------------
# Regional Internal Backend Service
# Name = my-ilb
# ------------------------------------------------------------

if gcloud compute backend-services describe "$BACKEND_SERVICE" \
    --region="$REGION" >/dev/null 2>&1; then

    warn "$BACKEND_SERVICE backend service already exists"

else

    gcloud compute backend-services create "$BACKEND_SERVICE" \
        --region="$REGION" \
        --load-balancing-scheme=INTERNAL \
        --protocol=TCP \
        --network="$NETWORK" \
        --health-checks="$HEALTH_CHECK" \
        --health-checks-region="$REGION" \
        --quiet

    ok "Created backend service: $BACKEND_SERVICE"
fi

# ------------------------------------------------------------
# Add MIG 1 backend
# ------------------------------------------------------------

BACKENDS="$(
    gcloud compute backend-services describe "$BACKEND_SERVICE" \
        --region="$REGION" \
        --format='value(backends[].group)' || true
)"

if echo "$BACKENDS" | grep -q "/instanceGroups/$MIG1$"; then

    warn "$MIG1 already attached to $BACKEND_SERVICE"

else

    gcloud compute backend-services add-backend "$BACKEND_SERVICE" \
        --region="$REGION" \
        --instance-group="$MIG1" \
        --instance-group-zone="$ZONE1" \
        --quiet

    ok "Attached $MIG1"
fi

# ------------------------------------------------------------
# Add MIG 2 backend
# ------------------------------------------------------------

BACKENDS="$(
    gcloud compute backend-services describe "$BACKEND_SERVICE" \
        --region="$REGION" \
        --format='value(backends[].group)' || true
)"

if echo "$BACKENDS" | grep -q "/instanceGroups/$MIG2$"; then

    warn "$MIG2 already attached to $BACKEND_SERVICE"

else

    gcloud compute backend-services add-backend "$BACKEND_SERVICE" \
        --region="$REGION" \
        --instance-group="$MIG2" \
        --instance-group-zone="$ZONE2" \
        --quiet

    ok "Attached $MIG2"
fi

# ------------------------------------------------------------
# Reserve my-ilb-ip
# ------------------------------------------------------------

if gcloud compute addresses describe "$ADDRESS_NAME" \
    --region="$REGION" >/dev/null 2>&1; then

    warn "$ADDRESS_NAME already exists"

else

    gcloud compute addresses create "$ADDRESS_NAME" \
        --region="$REGION" \
        --subnet="$SUBNET_B" \
        --addresses="$ILB_IP" \
        --quiet

    ok "Reserved $ADDRESS_NAME -> $ILB_IP"
fi

RESERVED_IP="$(
    gcloud compute addresses describe "$ADDRESS_NAME" \
        --region="$REGION" \
        --format='value(address)'
)"

if [[ "$RESERVED_IP" != "$ILB_IP" ]]; then
    die "$ADDRESS_NAME is $RESERVED_IP but the lab requires $ILB_IP"
fi

# ------------------------------------------------------------
# Forwarding rule
# Console-created ILB normally results in this forwarding rule.
# ------------------------------------------------------------

if gcloud compute forwarding-rules describe "$FORWARDING_RULE" \
    --region="$REGION" >/dev/null 2>&1; then

    warn "$FORWARDING_RULE already exists"

else

    gcloud compute forwarding-rules create "$FORWARDING_RULE" \
        --region="$REGION" \
        --load-balancing-scheme=INTERNAL \
        --network="$NETWORK" \
        --subnet="$SUBNET_B" \
        --address="$ADDRESS_NAME" \
        --ip-protocol=TCP \
        --ports=80 \
        --backend-service="$BACKEND_SERVICE" \
        --backend-service-region="$REGION" \
        --quiet

    ok "Created forwarding rule: $FORWARDING_RULE"
fi

echo ""
info "Load Balancer information"

gcloud compute forwarding-rules describe "$FORWARDING_RULE" \
    --region="$REGION" \
    --format='table(
        name,
        IPAddress,
        IPProtocol,
        ports,
        loadBalancingScheme,
        backendService.basename()
    )'

ok "TASK 3 resources completed"

# ============================================================
# TASK 4
# Related test - no separate Check my progress
# ============================================================

section "[4/4] TASK 4 - Test Internal Load Balancer"

if [[ "$SSH_READY" == "1" ]]; then

    info "Checking ILB VIP: $ILB_IP"

    ILB_READY=0

    for ((i=1; i<=36; i++)); do

        if ssh_utility \
            "curl -fsS --max-time 5 http://$ILB_IP/ >/tmp/eplus-ilb-test.html" \
            >/dev/null 2>&1; then

            ILB_READY=1
            break
        fi

        printf "${DIM}   [%02d/36] Health checks/backend initialization...${RESET}\r" "$i"

        sleep 5
    done

    echo ""

    if [[ "$ILB_READY" == "1" ]]; then

        ok "Internal Load Balancer is responding"

        echo ""
        echo "${MAGENTA}${BOLD}Responses through $ILB_IP:${RESET}"
        echo ""

        ssh_utility "
            for i in \$(seq 1 8); do
                echo
                echo '---------------- REQUEST '\$i' ----------------'
                curl -sS --max-time 5 http://$ILB_IP/
                echo
            done
        "

    else

        warn "ILB resources exist but backend health is not ready yet."

    fi

else

    warn "Skipping curl test because utility-vm SSH was unavailable."
fi

# ============================================================
# FINAL RESOURCE CHECK
# ============================================================

section "FINAL RESOURCE SUMMARY"

echo "${CYAN}${BOLD}Project${RESET}       : $PROJECT_ID"
echo "${CYAN}${BOLD}Region${RESET}        : $REGION"
echo "${CYAN}${BOLD}MIG 1 Zone${RESET}    : $ZONE1"
echo "${CYAN}${BOLD}MIG 2 Zone${RESET}    : $ZONE2"
echo "${CYAN}${BOLD}Backend 1${RESET}     : $BACKEND_IP1"
echo "${CYAN}${BOLD}Backend 2${RESET}     : $BACKEND_IP2"
echo "${CYAN}${BOLD}Utility VM IP${RESET} : $UTILITY_IP"
echo "${CYAN}${BOLD}ILB IP${RESET}        : $ILB_IP"

echo ""
echo "${YELLOW}${BOLD}Backend health:${RESET}"

gcloud compute backend-services get-health "$BACKEND_SERVICE" \
    --region="$REGION" || true

echo ""
echo "${GREEN}${BOLD}=============================================================="
echo "             GSP216 AUTOMATION COMPLETED"
echo "==============================================================${RESET}"
echo ""
echo "${MAGENTA}${BOLD}                    © ePlus.DEV${RESET}"
echo ""
echo "${YELLOW}${BOLD}Now click Check my progress for:${RESET}"
echo "  ${GREEN}✓ Task 1 - Configure HTTP and health check firewall rules${RESET}"
echo "  ${GREEN}✓ Task 2 - Configure instance templates and create instance groups${RESET}"
echo "  ${GREEN}✓ Task 3 - Configure the Internal Load Balancer${RESET}"
echo ""