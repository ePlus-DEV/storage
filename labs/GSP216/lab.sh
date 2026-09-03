#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# GSP216 - Internal Load Balancer
# Automated Lab Script
# © ePlus.DEV
# ============================================================

# ========================= COLORS ============================
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
echo "           GSP216 - INTERNAL LOAD BALANCER"
echo "=============================================================="
echo "${MAGENTA}                    © ePlus.DEV${RESET}"
echo ""

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

error() {
    echo "${RED}${BOLD}✗ $1${RESET}"
}

die() {
    error "$1"
    exit 1
}


# ============================================================
# LAB CONFIG
# ============================================================

NETWORK="my-internal-app"

SUBNET_A="subnet-a"
SUBNET_B="subnet-b"

HTTP_FW="app-allow-http"
HC_FW="app-allow-health-check"

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
# [0/4] ENVIRONMENT
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
# NETWORK
# ============================================================

if ! gcloud compute networks describe "$NETWORK" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1; then

    die "Network '$NETWORK' was not found."
fi

ok "Network found: $NETWORK"


# ============================================================
# SUBNET A
#
# Use raw URLs then strip basename.
# This avoids the detection bug from the previous script.
# ============================================================

SUBNET_A_LINE="$(
    gcloud compute networks subnets list \
        --project="$PROJECT_ID" \
        --filter="name=$SUBNET_A" \
        --format='value(name,region,network,ipCidrRange)' \
        2>/dev/null \
        | head -n1
)"

if [[ -z "$SUBNET_A_LINE" ]]; then

    warn "Existing subnets:"

    gcloud compute networks subnets list \
        --project="$PROJECT_ID" \
        --format="table(name,region.basename(),network.basename(),ipCidrRange)"

    die "Cannot find $SUBNET_A"
fi


read -r \
    FOUND_SUBNET_A \
    REGION_URL \
    NETWORK_A_URL \
    SUBNET_A_CIDR \
    <<< "$SUBNET_A_LINE"

REGION="${REGION_URL##*/}"
FOUND_NETWORK_A="${NETWORK_A_URL##*/}"


if [[ "$FOUND_NETWORK_A" != "$NETWORK" ]]; then
    die "$SUBNET_A belongs to $FOUND_NETWORK_A, not $NETWORK"
fi

ok "Found $SUBNET_A"
info "Region  : $REGION"
info "Network : $FOUND_NETWORK_A"
info "CIDR    : $SUBNET_A_CIDR"


# ============================================================
# SUBNET B
# ============================================================

SUBNET_B_LINE="$(
    gcloud compute networks subnets list \
        --project="$PROJECT_ID" \
        --filter="name=$SUBNET_B" \
        --format='value(name,region,network,ipCidrRange)' \
        2>/dev/null \
        | head -n1
)"

if [[ -z "$SUBNET_B_LINE" ]]; then
    die "Cannot find $SUBNET_B"
fi


read -r \
    FOUND_SUBNET_B \
    REGION_B_URL \
    NETWORK_B_URL \
    SUBNET_B_CIDR \
    <<< "$SUBNET_B_LINE"

REGION_B="${REGION_B_URL##*/}"
FOUND_NETWORK_B="${NETWORK_B_URL##*/}"


if [[ "$FOUND_NETWORK_B" != "$NETWORK" ]]; then
    die "$SUBNET_B belongs to $FOUND_NETWORK_B, not $NETWORK"
fi

if [[ "$REGION_B" != "$REGION" ]]; then
    die "$SUBNET_A and $SUBNET_B are in different regions."
fi


ok "Found $SUBNET_B"
info "Region  : $REGION_B"
info "Network : $FOUND_NETWORK_B"
info "CIDR    : $SUBNET_B_CIDR"


# ============================================================
# AUTO DETECT ZONES
#
# Zone1:
# Prefer REGION-a because lab explicitly requires it.
#
# Zone2:
# Prefer REGION-b.
# Otherwise choose another UP zone.
# ============================================================

mapfile -t REGION_ZONES < <(
    gcloud compute zones list \
        --project="$PROJECT_ID" \
        --format='value(name,status)' \
        2>/dev/null \
    | awk -v PREFIX="${REGION}-" \
        '$1 ~ ("^" PREFIX) && $2=="UP" {print $1}' \
    | sort
)


if (( ${#REGION_ZONES[@]} < 2 )); then

    echo ""
    gcloud compute zones list \
        --project="$PROJECT_ID" \
        --format="table(name,region.basename(),status)"

    die "Less than two available zones in $REGION"
fi


PREFERRED_ZONE1="${REGION}-a"
PREFERRED_ZONE2="${REGION}-b"

ZONE1=""
ZONE2=""


# Zone 1
if printf '%s\n' "${REGION_ZONES[@]}" \
    | grep -qx "$PREFERRED_ZONE1"; then

    ZONE1="$PREFERRED_ZONE1"

else

    ZONE1="${REGION_ZONES[0]}"

    warn "$PREFERRED_ZONE1 unavailable. Using $ZONE1"
fi


# Zone 2
if [[ "$PREFERRED_ZONE2" != "$ZONE1" ]] && \
   printf '%s\n' "${REGION_ZONES[@]}" \
   | grep -qx "$PREFERRED_ZONE2"; then

    ZONE2="$PREFERRED_ZONE2"

else

    for z in "${REGION_ZONES[@]}"; do

        if [[ "$z" != "$ZONE1" ]]; then
            ZONE2="$z"
            break
        fi

    done

fi


[[ -n "$ZONE2" ]] || die "Cannot find second zone."


echo ""
info "Available zones:"
printf "   • %s\n" "${REGION_ZONES[@]}"

echo ""
info "Region : $REGION"
info "Zone 1 : $ZONE1"
info "Zone 2 : $ZONE2"


gcloud config set compute/region "$REGION" >/dev/null
gcloud config set compute/zone "$ZONE1" >/dev/null


# ============================================================
# COMPUTE API
# ============================================================

info "Checking Compute Engine API..."

gcloud services enable compute.googleapis.com \
    --project="$PROJECT_ID" \
    --quiet >/dev/null

ok "Environment ready"


# ============================================================
# TASK 1 - FIREWALL
# ============================================================

section "[1/4] TASK 1 - Firewall Rules"


# ------------------------------------------------------------
# app-allow-http
# ------------------------------------------------------------

if gcloud compute firewall-rules describe "$HTTP_FW" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1; then

    warn "$HTTP_FW already exists"

else

    gcloud compute firewall-rules create "$HTTP_FW" \
        --project="$PROJECT_ID" \
        --network="$NETWORK" \
        --direction=INGRESS \
        --priority=1000 \
        --action=ALLOW \
        --rules=tcp:80 \
        --source-ranges=10.10.0.0/16 \
        --target-tags=lb-backend \
        --quiet

    ok "Created $HTTP_FW"
fi


# ------------------------------------------------------------
# app-allow-health-check
# ------------------------------------------------------------

if gcloud compute firewall-rules describe "$HC_FW" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1; then

    warn "$HC_FW already exists"

else

    gcloud compute firewall-rules create "$HC_FW" \
        --project="$PROJECT_ID" \
        --network="$NETWORK" \
        --direction=INGRESS \
        --priority=1000 \
        --action=ALLOW \
        --rules=tcp \
        --source-ranges=130.211.0.0/22,35.191.0.0/16 \
        --target-tags=lb-backend \
        --quiet

    ok "Created $HC_FW"
fi


echo ""

gcloud compute firewall-rules list \
    --project="$PROJECT_ID" \
    --filter="name=($HTTP_FW $HC_FW)" \
    --format="table(
        name,
        network.basename(),
        sourceRanges.list():label=SOURCE_RANGES,
        allowed[].map().firewall_rule().list():label=ALLOW
    )"


ok "TASK 1 completed"


# ============================================================
# TASK 2 - INSTANCE TEMPLATES / MIG
# ============================================================

section "[2/4] TASK 2 - Templates, MIGs and Utility VM"


# ============================================================
# STARTUP SCRIPT
# ============================================================

STARTUP_FILE="/tmp/eplus-gsp216-startup.sh"

cat > "$STARTUP_FILE" <<'STARTUP'
#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

apt-get update

apt-get install -y \
    apache2 \
    php \
    libapache2-mod-php \
    php-curl \
    curl

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

curl_setopt(
    $ch,
    CURLOPT_RETURNTRANSFER,
    1
);

$zone = curl_exec($ch);

$parts = explode('/', $zone);

echo end($parts);

?>
PHP

rm -f /var/www/html/index.html

systemctl enable apache2
systemctl restart apache2
STARTUP


# ============================================================
# TEMPLATE 1
# ============================================================

if gcloud compute instance-templates describe "$TEMPLATE1" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1; then

    warn "$TEMPLATE1 already exists"

else

    info "Creating $TEMPLATE1 on $SUBNET_A"

    gcloud compute instance-templates create "$TEMPLATE1" \
        --project="$PROJECT_ID" \
        --machine-type=e2-micro \
        --image-family=debian-12 \
        --image-project=debian-cloud \
        --network-interface="network=$NETWORK,subnet=$SUBNET_A,no-address" \
        --tags=lb-backend \
        --metadata-from-file=startup-script="$STARTUP_FILE" \
        --quiet

    ok "Created $TEMPLATE1"
fi


# ============================================================
# TEMPLATE 2
# ============================================================

if gcloud compute instance-templates describe "$TEMPLATE2" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1; then

    warn "$TEMPLATE2 already exists"

else

    info "Creating $TEMPLATE2 on $SUBNET_B"

    gcloud compute instance-templates create "$TEMPLATE2" \
        --project="$PROJECT_ID" \
        --machine-type=e2-micro \
        --image-family=debian-12 \
        --image-project=debian-cloud \
        --network-interface="network=$NETWORK,subnet=$SUBNET_B,no-address" \
        --tags=lb-backend \
        --metadata-from-file=startup-script="$STARTUP_FILE" \
        --quiet

    ok "Created $TEMPLATE2"
fi


# ============================================================
# MIG 1
# ============================================================

if gcloud compute instance-groups managed describe "$MIG1" \
    --project="$PROJECT_ID" \
    --zone="$ZONE1" \
    >/dev/null 2>&1; then

    warn "$MIG1 already exists in $ZONE1"

else

    info "Creating $MIG1 in $ZONE1"

    gcloud compute instance-groups managed create "$MIG1" \
        --project="$PROJECT_ID" \
        --zone="$ZONE1" \
        --base-instance-name="$MIG1" \
        --template="$TEMPLATE1" \
        --size=1 \
        --quiet

    ok "Created $MIG1"
fi


# ============================================================
# MIG 1 AUTOSCALER
# Lab:
# Min = 1
# Max = 1
# CPU = 80%
# Initialization period = 45 sec
# ============================================================

gcloud compute instance-groups managed set-autoscaling "$MIG1" \
    --project="$PROJECT_ID" \
    --zone="$ZONE1" \
    --min-num-replicas=1 \
    --max-num-replicas=1 \
    --target-cpu-utilization=0.8 \
    --cool-down-period=45 \
    --mode=on \
    --quiet >/dev/null

ok "$MIG1 autoscaling configured"


# ============================================================
# MIG 2
# ============================================================

if gcloud compute instance-groups managed describe "$MIG2" \
    --project="$PROJECT_ID" \
    --zone="$ZONE2" \
    >/dev/null 2>&1; then

    warn "$MIG2 already exists in $ZONE2"

else

    info "Creating $MIG2 in $ZONE2"

    gcloud compute instance-groups managed create "$MIG2" \
        --project="$PROJECT_ID" \
        --zone="$ZONE2" \
        --base-instance-name="$MIG2" \
        --template="$TEMPLATE2" \
        --size=1 \
        --quiet

    ok "Created $MIG2"
fi


# ============================================================
# MIG 2 AUTOSCALER
# ============================================================

gcloud compute instance-groups managed set-autoscaling "$MIG2" \
    --project="$PROJECT_ID" \
    --zone="$ZONE2" \
    --min-num-replicas=1 \
    --max-num-replicas=1 \
    --target-cpu-utilization=0.8 \
    --cool-down-period=45 \
    --mode=on \
    --quiet >/dev/null

ok "$MIG2 autoscaling configured"


# ============================================================
# UTILITY VM
# ============================================================

UTILITY_EXISTING_ZONE="$(
    gcloud compute instances list \
        --project="$PROJECT_ID" \
        --filter="name=$UTILITY_VM" \
        --format='value(zone)' \
        2>/dev/null \
        | head -n1
)"

UTILITY_EXISTING_ZONE="${UTILITY_EXISTING_ZONE##*/}"


if [[ -n "$UTILITY_EXISTING_ZONE" ]]; then

    UTILITY_ZONE="$UTILITY_EXISTING_ZONE"

    warn "$UTILITY_VM already exists in $UTILITY_ZONE"

else

    UTILITY_ZONE="$ZONE1"

    info "Creating $UTILITY_VM"
    info "Zone        : $UTILITY_ZONE"
    info "Subnet      : $SUBNET_A"
    info "Internal IP : $UTILITY_IP"

    gcloud compute instances create "$UTILITY_VM" \
        --project="$PROJECT_ID" \
        --zone="$UTILITY_ZONE" \
        --machine-type=e2-micro \
        --image-family=debian-12 \
        --image-project=debian-cloud \
        --network-interface="network=$NETWORK,subnet=$SUBNET_A,private-network-ip=$UTILITY_IP" \
        --quiet

    ok "Created $UTILITY_VM"
fi


# ============================================================
# WAIT FOR MIG
#
# IMPORTANT:
# All progress output -> STDERR
# Only VM name -> STDOUT
#
# Therefore:
# VM1="$(wait_for_mig ...)"
# receives ONLY the VM name.
# ============================================================

wait_for_mig() {

    local GROUP="$1"
    local ZONE="$2"

    local DATA=""
    local NAME=""
    local STATUS=""
    local ACTION=""
    local ERROR_CODE=""
    local ERROR_MESSAGE=""
    local PREVIOUS_ERROR=""

    for ((i=1; i<=30; i++)); do

        DATA="$(
            gcloud compute instance-groups managed list-instances "$GROUP" \
                --project="$PROJECT_ID" \
                --zone="$ZONE" \
                --format=json \
                2>/dev/null \
                || echo '[]'
        )"


        NAME="$(
            jq -r '.[0].name // empty' <<< "$DATA" 2>/dev/null || true
        )"

        STATUS="$(
            jq -r '.[0].instanceStatus // empty' <<< "$DATA" 2>/dev/null || true
        )"

        ACTION="$(
            jq -r '.[0].currentAction // empty' <<< "$DATA" 2>/dev/null || true
        )"

        ERROR_CODE="$(
            jq -r \
                '.[0].lastAttempt.errors.errors[0].code // empty' \
                <<< "$DATA" \
                2>/dev/null \
                || true
        )"

        ERROR_MESSAGE="$(
            jq -r \
                '.[0].lastAttempt.errors.errors[0].message // empty' \
                <<< "$DATA" \
                2>/dev/null \
                || true
        )"


        if [[ -n "$NAME" ]]; then

            printf \
                "\r${DIM}   [%02d/30] %-18s STATUS=%-10s ACTION=%-10s${RESET}" \
                "$i" \
                "$GROUP" \
                "${STATUS:-PENDING}" \
                "${ACTION:-UNKNOWN}" \
                >&2

        else

            printf \
                "\r${DIM}   [%02d/30] %-18s waiting for instance allocation...${RESET}" \
                "$i" \
                "$GROUP" \
                >&2
        fi


        if [[ -n "$ERROR_CODE" && "$ERROR_CODE" != "$PREVIOUS_ERROR" ]]; then

            echo "" >&2

            echo \
                "${YELLOW}⚠ $GROUP provisioning error: $ERROR_CODE${RESET}" \
                >&2

            if [[ -n "$ERROR_MESSAGE" ]]; then
                echo "   $ERROR_MESSAGE" >&2
            fi

            PREVIOUS_ERROR="$ERROR_CODE"
        fi


        if [[ "$STATUS" == "RUNNING" ]] && \
           [[ "$ACTION" == "NONE" || -z "$ACTION" ]]; then

            echo "" >&2

            echo \
                "${GREEN}${BOLD}✓ $GROUP VM is RUNNING: $NAME${RESET}" \
                >&2

            echo "$NAME"

            return 0
        fi


        sleep 4

    done


    echo "" >&2

    echo \
        "${YELLOW}⚠ $GROUP did not become RUNNING yet.${RESET}" \
        >&2

    echo \
        "${YELLOW}  Script will continue creating the remaining lab resources.${RESET}" \
        >&2


    gcloud compute instance-groups managed list-instances "$GROUP" \
        --project="$PROJECT_ID" \
        --zone="$ZONE" \
        >&2 || true


    return 1
}


# ============================================================
# CHECK MIGs
# Do NOT kill script when provisioning is slow.
# ============================================================

echo ""
info "Checking managed instances..."

VM1="$(wait_for_mig "$MIG1" "$ZONE1" || true)"

echo ""

VM2="$(wait_for_mig "$MIG2" "$ZONE2" || true)"

echo ""


if [[ -n "$VM1" ]]; then
    ok "$MIG1 VM: $VM1"
else
    warn "$MIG1 VM is not RUNNING yet"
fi


if [[ -n "$VM2" ]]; then
    ok "$MIG2 VM: $VM2"
else
    warn "$MIG2 VM is not RUNNING yet"
fi


# ============================================================
# BACKEND INTERNAL IPs
# ============================================================

BACKEND_IP1=""
BACKEND_IP2=""


if [[ -n "$VM1" ]]; then

    BACKEND_IP1="$(
        gcloud compute instances describe "$VM1" \
            --project="$PROJECT_ID" \
            --zone="$ZONE1" \
            --format='value(networkInterfaces[0].networkIP)' \
            2>/dev/null \
            || true
    )"

    info "$VM1 -> $BACKEND_IP1"
fi


if [[ -n "$VM2" ]]; then

    BACKEND_IP2="$(
        gcloud compute instances describe "$VM2" \
            --project="$PROJECT_ID" \
            --zone="$ZONE2" \
            --format='value(networkInterfaces[0].networkIP)' \
            2>/dev/null \
            || true
    )"

    info "$VM2 -> $BACKEND_IP2"
fi


# ============================================================
# UTILITY VM STATUS
# ============================================================

info "Checking $UTILITY_VM..."

for ((i=1; i<=20; i++)); do

    UTILITY_STATUS="$(
        gcloud compute instances describe "$UTILITY_VM" \
            --project="$PROJECT_ID" \
            --zone="$UTILITY_ZONE" \
            --format='value(status)' \
            2>/dev/null \
            || true
    )"


    if [[ "$UTILITY_STATUS" == "RUNNING" ]]; then

        ok "$UTILITY_VM is RUNNING"
        break
    fi


    printf \
        "${DIM}   [%02d/20] utility-vm = %s${RESET}\r" \
        "$i" \
        "${UTILITY_STATUS:-CREATING}"

    sleep 3
done

echo ""


# ============================================================
# SSH HELPER
# ============================================================

ssh_utility() {

    gcloud compute ssh "$UTILITY_VM" \
        --project="$PROJECT_ID" \
        --zone="$UTILITY_ZONE" \
        --quiet \
        --command="$1"
}


# ============================================================
# SSH CHECK
# ============================================================

SSH_READY=0

info "Checking SSH access..."

for ((i=1; i<=15; i++)); do

    if ssh_utility "echo eplus-ready" >/dev/null 2>&1; then

        SSH_READY=1
        break
    fi


    printf \
        "${DIM}   [%02d/15] Waiting for SSH...${RESET}\r" \
        "$i"

    sleep 4
done

echo ""


if [[ "$SSH_READY" == "1" ]]; then
    ok "utility-vm SSH ready"
else
    warn "utility-vm SSH not ready; continuing."
fi


# ============================================================
# BACKEND HTTP TEST
# ============================================================

if [[ "$SSH_READY" == "1" && -n "$BACKEND_IP1" ]]; then

    echo ""
    info "Testing backend 1: $BACKEND_IP1"

    ssh_utility "
        for i in \$(seq 1 20); do

            if curl -fsS \
                --max-time 5 \
                http://$BACKEND_IP1/; then

                exit 0
            fi

            sleep 4

        done

        exit 1
    " || warn "Backend 1 Apache is still initializing."

    echo ""
fi


if [[ "$SSH_READY" == "1" && -n "$BACKEND_IP2" ]]; then

    echo ""
    info "Testing backend 2: $BACKEND_IP2"

    ssh_utility "
        for i in \$(seq 1 20); do

            if curl -fsS \
                --max-time 5 \
                http://$BACKEND_IP2/; then

                exit 0
            fi

            sleep 4

        done

        exit 1
    " || warn "Backend 2 Apache is still initializing."

    echo ""
fi


ok "TASK 2 resources configured"


# ============================================================
# TASK 3 - INTERNAL LOAD BALANCER
# ============================================================

section "[3/4] TASK 3 - Internal Load Balancer"


# ============================================================
# REGIONAL TCP HEALTH CHECK
# ============================================================

if gcloud compute health-checks describe "$HEALTH_CHECK" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    >/dev/null 2>&1; then

    warn "$HEALTH_CHECK already exists"

else

    info "Creating $HEALTH_CHECK"

    gcloud compute health-checks create tcp "$HEALTH_CHECK" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --port=80 \
        --check-interval=5s \
        --timeout=5s \
        --healthy-threshold=2 \
        --unhealthy-threshold=2 \
        --quiet

    ok "Created $HEALTH_CHECK"
fi


# ============================================================
# REGIONAL BACKEND SERVICE
# ============================================================

if gcloud compute backend-services describe "$BACKEND_SERVICE" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    >/dev/null 2>&1; then

    warn "$BACKEND_SERVICE already exists"

else

    info "Creating backend service $BACKEND_SERVICE"

    gcloud compute backend-services create "$BACKEND_SERVICE" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --load-balancing-scheme=INTERNAL \
        --protocol=TCP \
        --health-checks="$HEALTH_CHECK" \
        --health-checks-region="$REGION" \
        --quiet

    ok "Created $BACKEND_SERVICE"
fi


# ============================================================
# ADD MIG 1
# ============================================================

CURRENT_BACKENDS="$(
    gcloud compute backend-services describe "$BACKEND_SERVICE" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --format='value(backends[].group)' \
        2>/dev/null \
        || true
)"


if echo "$CURRENT_BACKENDS" \
    | grep -q "/instanceGroups/$MIG1"; then

    warn "$MIG1 already attached"

else

    info "Adding $MIG1 to $BACKEND_SERVICE"

    gcloud compute backend-services add-backend "$BACKEND_SERVICE" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --instance-group="$MIG1" \
        --instance-group-zone="$ZONE1" \
        --quiet

    ok "Attached $MIG1"
fi


# ============================================================
# ADD MIG 2
# ============================================================

CURRENT_BACKENDS="$(
    gcloud compute backend-services describe "$BACKEND_SERVICE" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --format='value(backends[].group)' \
        2>/dev/null \
        || true
)"


if echo "$CURRENT_BACKENDS" \
    | grep -q "/instanceGroups/$MIG2"; then

    warn "$MIG2 already attached"

else

    info "Adding $MIG2 to $BACKEND_SERVICE"

    gcloud compute backend-services add-backend "$BACKEND_SERVICE" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --instance-group="$MIG2" \
        --instance-group-zone="$ZONE2" \
        --quiet

    ok "Attached $MIG2"
fi


# ============================================================
# STATIC INTERNAL IP
# ============================================================

if gcloud compute addresses describe "$ADDRESS_NAME" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    >/dev/null 2>&1; then

    warn "$ADDRESS_NAME already exists"

else

    info "Reserving $ILB_IP"

    gcloud compute addresses create "$ADDRESS_NAME" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --subnet="$SUBNET_B" \
        --addresses="$ILB_IP" \
        --quiet

    ok "Reserved $ADDRESS_NAME"
fi


RESERVED_IP="$(
    gcloud compute addresses describe "$ADDRESS_NAME" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --format='value(address)'
)"


info "$ADDRESS_NAME = $RESERVED_IP"


if [[ "$RESERVED_IP" != "$ILB_IP" ]]; then

    error "$ADDRESS_NAME has IP $RESERVED_IP"
    error "Lab expects $ILB_IP"
    exit 1
fi


# ============================================================
# FORWARDING RULE
#
# Google documented pattern:
# INTERNAL + TCP + regional backend service
# ============================================================

if gcloud compute forwarding-rules describe "$FORWARDING_RULE" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    >/dev/null 2>&1; then

    warn "$FORWARDING_RULE already exists"

else

    info "Creating Internal Load Balancer frontend"

    gcloud compute forwarding-rules create "$FORWARDING_RULE" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --load-balancing-scheme=INTERNAL \
        --network="$NETWORK" \
        --subnet="$SUBNET_B" \
        --address="$ILB_IP" \
        --ip-protocol=TCP \
        --ports=80 \
        --backend-service="$BACKEND_SERVICE" \
        --backend-service-region="$REGION" \
        --quiet

    ok "Created $FORWARDING_RULE"
fi


echo ""
info "Internal Load Balancer"

gcloud compute forwarding-rules describe "$FORWARDING_RULE" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --format="table(
        name,
        IPAddress,
        IPProtocol,
        ports,
        loadBalancingScheme,
        backendService.basename()
    )"


ok "TASK 3 configured"


# ============================================================
# TASK 4 - TEST
# ============================================================

section "[4/4] TASK 4 - Test Internal Load Balancer"


# ============================================================
# BACKEND HEALTH
# ============================================================

info "Checking backend health..."

BACKEND_HEALTHY=0

for ((i=1; i<=30; i++)); do

    HEALTH_OUTPUT="$(
        gcloud compute backend-services get-health "$BACKEND_SERVICE" \
            --project="$PROJECT_ID" \
            --region="$REGION" \
            --format=json \
            2>/dev/null \
            || echo '[]'
    )"


    HEALTHY_COUNT="$(
        jq \
            '[.. | objects |
              select(.healthState? == "HEALTHY")] |
              length' \
            <<< "$HEALTH_OUTPUT" \
            2>/dev/null \
            || echo 0
    )"


    printf \
        "${DIM}   [%02d/30] Healthy endpoints: %s${RESET}\r" \
        "$i" \
        "$HEALTHY_COUNT"


    if (( HEALTHY_COUNT >= 1 )); then

        BACKEND_HEALTHY=1
        break
    fi


    sleep 5
done

echo ""


if [[ "$BACKEND_HEALTHY" == "1" ]]; then
    ok "At least one ILB backend is HEALTHY"
else
    warn "Backends are not HEALTHY yet."
fi


# ============================================================
# CURL LOAD BALANCER
# ============================================================

if [[ "$SSH_READY" == "1" ]]; then

    info "Testing ILB $ILB_IP from utility-vm..."

    ILB_READY=0


    for ((i=1; i<=25; i++)); do

        if ssh_utility \
            "curl -fsS --max-time 5 http://$ILB_IP/ >/dev/null" \
            >/dev/null 2>&1; then

            ILB_READY=1
            break
        fi


        printf \
            "${DIM}   [%02d/25] Waiting for $ILB_IP...${RESET}\r" \
            "$i"

        sleep 4
    done

    echo ""


    if [[ "$ILB_READY" == "1" ]]; then

        ok "Internal Load Balancer is responding"

        echo ""
        echo "${MAGENTA}${BOLD}==============================================================${RESET}"
        echo "${MAGENTA}${BOLD}                 LOAD BALANCER TEST${RESET}"
        echo "${MAGENTA}${BOLD}==============================================================${RESET}"


        ssh_utility "
            for i in \$(seq 1 8); do

                echo
                echo '---------------- REQUEST '\$i' ----------------'

                curl -sS \
                    --max-time 5 \
                    http://$ILB_IP/

                echo
                sleep 1

            done
        "

    else

        warn "ILB did not answer yet."
    fi

else

    warn "Skipping HTTP test because utility-vm SSH is unavailable."
fi


# ============================================================
# FINAL REPORT
# ============================================================

section "FINAL LAB STATUS"


echo "${CYAN}${BOLD}Project${RESET}       : $PROJECT_ID"
echo "${CYAN}${BOLD}Network${RESET}       : $NETWORK"
echo "${CYAN}${BOLD}Region${RESET}        : $REGION"
echo "${CYAN}${BOLD}Zone 1${RESET}        : $ZONE1"
echo "${CYAN}${BOLD}Zone 2${RESET}        : $ZONE2"

echo ""

echo "${CYAN}${BOLD}Subnet A${RESET}      : $SUBNET_A"
echo "${CYAN}${BOLD}CIDR A${RESET}        : $SUBNET_A_CIDR"

echo "${CYAN}${BOLD}Subnet B${RESET}      : $SUBNET_B"
echo "${CYAN}${BOLD}CIDR B${RESET}        : $SUBNET_B_CIDR"

echo ""

echo "${CYAN}${BOLD}MIG 1${RESET}         : $MIG1"
echo "${CYAN}${BOLD}MIG 2${RESET}         : $MIG2"

echo "${CYAN}${BOLD}VM 1${RESET}          : ${VM1:-NOT READY}"
echo "${CYAN}${BOLD}VM 2${RESET}          : ${VM2:-NOT READY}"

echo "${CYAN}${BOLD}Backend IP 1${RESET}  : ${BACKEND_IP1:-NOT READY}"
echo "${CYAN}${BOLD}Backend IP 2${RESET}  : ${BACKEND_IP2:-NOT READY}"

echo ""

echo "${CYAN}${BOLD}Utility VM${RESET}    : $UTILITY_VM"
echo "${CYAN}${BOLD}Utility IP${RESET}    : $UTILITY_IP"

echo ""

echo "${CYAN}${BOLD}Health Check${RESET}  : $HEALTH_CHECK"
echo "${CYAN}${BOLD}Backend Svc${RESET}   : $BACKEND_SERVICE"
echo "${CYAN}${BOLD}ILB IP${RESET}        : $ILB_IP"
echo "${CYAN}${BOLD}Forward Rule${RESET}  : $FORWARDING_RULE"


echo ""
echo "${YELLOW}${BOLD}Managed instances:${RESET}"
echo ""

gcloud compute instance-groups managed list-instances "$MIG1" \
    --project="$PROJECT_ID" \
    --zone="$ZONE1" \
    || true

echo ""

gcloud compute instance-groups managed list-instances "$MIG2" \
    --project="$PROJECT_ID" \
    --zone="$ZONE2" \
    || true


echo ""
echo "${YELLOW}${BOLD}Backend health:${RESET}"
echo ""

gcloud compute backend-services get-health "$BACKEND_SERVICE" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    || true


echo ""
echo "${GREEN}${BOLD}=============================================================="
echo "               GSP216 SCRIPT COMPLETED"
echo "==============================================================${RESET}"

echo ""
echo "${MAGENTA}${BOLD}                    © ePlus.DEV${RESET}"
echo ""

echo "${YELLOW}${BOLD}Check my progress:${RESET}"
echo ""
echo "${GREEN}✓ Task 1 - Firewall rules${RESET}"
echo "${GREEN}✓ Task 2 - Templates and managed instance groups${RESET}"
echo "${GREEN}✓ Task 3 - Internal Load Balancer${RESET}"
echo ""
echo "${CYAN}Task 4 has no separate Check my progress; script tests it automatically.${RESET}"
echo ""

if [[ -z "$VM1" || -z "$VM2" ]]; then

    echo "${YELLOW}${BOLD}NOTE:${RESET}"
    echo "${YELLOW}One or more MIG instances are still provisioning.${RESET}"
    echo "${YELLOW}Look at LAST_ERROR above. You can safely run ./lab.sh again.${RESET}"
    echo ""
fi