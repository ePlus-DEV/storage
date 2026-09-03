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

die() {
    echo "${RED}${BOLD}✗ $1${RESET}"
    exit 1
}

trap 'echo ""; echo "${RED}${BOLD}✗ ERROR at line ${LINENO}${RESET}"; exit 1' ERR


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

# In the Console, Load Balancer name becomes backend service name.
BACKEND_SERVICE="my-ilb"

ADDRESS_NAME="my-ilb-ip"
ILB_IP="10.10.30.5"

FORWARDING_RULE="my-ilb-forwarding-rule"


# ============================================================
# [0/4] DETECT ENVIRONMENT
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
# CHECK NETWORK
# ============================================================

if ! gcloud compute networks describe "$NETWORK" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1; then

    die "Network '$NETWORK' was not found."
fi

ok "Network found: $NETWORK"


# ============================================================
# AUTO DETECT subnet-a
#
# Do NOT parse the raw network URL with awk.
# Use basename() so this works with current gcloud formats.
# ============================================================

SUBNET_A_INFO="$(
    gcloud compute networks subnets list \
        --project="$PROJECT_ID" \
        --filter="name=($SUBNET_A)" \
        --format="csv[no-heading](name,region.basename(),network.basename(),ipCidrRange)" \
        2>/dev/null \
        | head -n1
)"

if [[ -z "$SUBNET_A_INFO" ]]; then
    echo ""
    warn "Current subnets:"
    gcloud compute networks subnets list \
        --project="$PROJECT_ID" \
        --format="table(name,region.basename(),network.basename(),ipCidrRange)"
    echo ""
    die "Cannot find $SUBNET_A"
fi

IFS=',' read -r \
    FOUND_SUBNET_A \
    REGION \
    FOUND_NETWORK_A \
    SUBNET_A_CIDR \
    <<< "$SUBNET_A_INFO"

if [[ "$FOUND_NETWORK_A" != "$NETWORK" ]]; then
    die "$SUBNET_A belongs to '$FOUND_NETWORK_A', not '$NETWORK'"
fi

ok "Found $SUBNET_A"
info "Region   : $REGION"
info "Network  : $FOUND_NETWORK_A"
info "CIDR     : $SUBNET_A_CIDR"


# ============================================================
# AUTO DETECT subnet-b
# ============================================================

SUBNET_B_INFO="$(
    gcloud compute networks subnets list \
        --project="$PROJECT_ID" \
        --filter="name=($SUBNET_B)" \
        --format="csv[no-heading](name,region.basename(),network.basename(),ipCidrRange)" \
        2>/dev/null \
        | head -n1
)"

if [[ -z "$SUBNET_B_INFO" ]]; then
    die "Cannot find $SUBNET_B"
fi

IFS=',' read -r \
    FOUND_SUBNET_B \
    SUBNET_B_REGION \
    FOUND_NETWORK_B \
    SUBNET_B_CIDR \
    <<< "$SUBNET_B_INFO"

if [[ "$FOUND_NETWORK_B" != "$NETWORK" ]]; then
    die "$SUBNET_B belongs to '$FOUND_NETWORK_B', not '$NETWORK'"
fi

if [[ "$SUBNET_B_REGION" != "$REGION" ]]; then
    die "$SUBNET_A and $SUBNET_B are not in the same region."
fi

ok "Found $SUBNET_B"
info "Region   : $SUBNET_B_REGION"
info "Network  : $FOUND_NETWORK_B"
info "CIDR     : $SUBNET_B_CIDR"


# ============================================================
# AUTO DETECT ZONES
#
# Lab requires:
# MIG1 -> REGION-a
# MIG2 -> another zone in same region
#
# We verify REGION-a actually exists before using it.
# ============================================================

mapfile -t REGION_ZONES < <(
    gcloud compute zones list \
        --filter="region:($REGION) AND status=UP" \
        --format='value(name)' \
        2>/dev/null \
        | sort
)

# Fallback because some gcloud filter versions return region URL
if (( ${#REGION_ZONES[@]} < 2 )); then

    mapfile -t REGION_ZONES < <(
        gcloud compute zones list \
            --format='value(name,status)' \
        | awk -v PREFIX="${REGION}-" \
            '$1 ~ ("^" PREFIX) && $2=="UP" {print $1}' \
        | sort
    )
fi

if (( ${#REGION_ZONES[@]} < 2 )); then

    echo ""
    gcloud compute zones list \
        --format="table(name,region.basename(),status)"

    die "Need at least 2 available zones in $REGION"
fi


# ------------------------------------------------------------
# ZONE 1
# Prefer REGION-a because the lab explicitly asks for it.
# ------------------------------------------------------------

PREFERRED_ZONE1="${REGION}-a"

if printf '%s\n' "${REGION_ZONES[@]}" \
    | grep -qx "$PREFERRED_ZONE1"; then

    ZONE1="$PREFERRED_ZONE1"

else

    ZONE1="${REGION_ZONES[0]}"

    warn "$PREFERRED_ZONE1 not available. Using $ZONE1"
fi


# ------------------------------------------------------------
# ZONE 2
# Prefer REGION-b; otherwise any other available zone.
# ------------------------------------------------------------

PREFERRED_ZONE2="${REGION}-b"
ZONE2=""

if [[ "$PREFERRED_ZONE2" != "$ZONE1" ]] && \
   printf '%s\n' "${REGION_ZONES[@]}" \
   | grep -qx "$PREFERRED_ZONE2"; then

    ZONE2="$PREFERRED_ZONE2"
fi

if [[ -z "$ZONE2" ]]; then

    for zone in "${REGION_ZONES[@]}"; do

        if [[ "$zone" != "$ZONE1" ]]; then

            ZONE2="$zone"
            break

        fi

    done
fi

[[ -n "$ZONE2" ]] || die "Cannot determine second zone."

echo ""
info "Available zones:"
printf '   %s\n' "${REGION_ZONES[@]}"

echo ""
info "Selected Region : $REGION"
info "Selected Zone 1 : $ZONE1"
info "Selected Zone 2 : $ZONE2"


gcloud config set compute/region "$REGION" >/dev/null
gcloud config set compute/zone "$ZONE1" >/dev/null


# ============================================================
# ENABLE API
# ============================================================

info "Ensuring Compute Engine API is enabled..."

gcloud services enable compute.googleapis.com \
    --project="$PROJECT_ID" \
    --quiet

ok "Environment detected successfully"


# ============================================================
# TASK 1
# FIREWALL RULES
# ============================================================

section "[1/4] TASK 1 - Firewall Rules"


# ============================================================
# app-allow-http
# ============================================================

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


# ============================================================
# app-allow-health-check
# ============================================================

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
# TASK 2
# TEMPLATES + MIGs + UTILITY VM
# ============================================================

section "[2/4] TASK 2 - Templates, MIGs and Utility VM"


# ============================================================
# STARTUP SCRIPT
# ============================================================

STARTUP_SCRIPT="/tmp/eplus-gsp216-startup.sh"

cat > "$STARTUP_SCRIPT" <<'STARTUP'
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
# INSTANCE TEMPLATE 1
# subnet-a
# ============================================================

if gcloud compute instance-templates describe "$TEMPLATE1" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1; then

    warn "$TEMPLATE1 already exists"

else

    info "Creating $TEMPLATE1"
    info "Subnet: $SUBNET_A"

    gcloud compute instance-templates create "$TEMPLATE1" \
        --project="$PROJECT_ID" \
        --machine-type=e2-micro \
        --image-family=debian-12 \
        --image-project=debian-cloud \
        --network-interface="network=$NETWORK,subnet=$SUBNET_A,no-address" \
        --tags=lb-backend \
        --metadata-from-file=startup-script="$STARTUP_SCRIPT" \
        --quiet

    ok "Created $TEMPLATE1"

fi


# ============================================================
# INSTANCE TEMPLATE 2
# subnet-b
# ============================================================

if gcloud compute instance-templates describe "$TEMPLATE2" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1; then

    warn "$TEMPLATE2 already exists"

else

    info "Creating $TEMPLATE2"
    info "Subnet: $SUBNET_B"

    gcloud compute instance-templates create "$TEMPLATE2" \
        --project="$PROJECT_ID" \
        --machine-type=e2-micro \
        --image-family=debian-12 \
        --image-project=debian-cloud \
        --network-interface="network=$NETWORK,subnet=$SUBNET_B,no-address" \
        --tags=lb-backend \
        --metadata-from-file=startup-script="$STARTUP_SCRIPT" \
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
# AUTOSCALING MIG 1
#
# Lab:
# Min = 1
# Max = 1
# CPU = 80%
# Initialization = 45 seconds
# ============================================================

gcloud compute instance-groups managed set-autoscaling "$MIG1" \
    --project="$PROJECT_ID" \
    --zone="$ZONE1" \
    --min-num-replicas=1 \
    --max-num-replicas=1 \
    --target-cpu-utilization=0.80 \
    --cool-down-period=45 \
    --mode=on \
    --quiet

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
# AUTOSCALING MIG 2
# ============================================================

gcloud compute instance-groups managed set-autoscaling "$MIG2" \
    --project="$PROJECT_ID" \
    --zone="$ZONE2" \
    --min-num-replicas=1 \
    --max-num-replicas=1 \
    --target-cpu-utilization=0.80 \
    --cool-down-period=45 \
    --mode=on \
    --quiet

ok "$MIG2 autoscaling configured"


# ============================================================
# UTILITY VM
# ============================================================

UTILITY_EXISTING_ZONE="$(
    gcloud compute instances list \
        --project="$PROJECT_ID" \
        --filter="name=($UTILITY_VM)" \
        --format='value(zone.basename())' \
        2>/dev/null \
        | head -n1
)"

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
# WAIT MIG VMs
# ============================================================

wait_for_mig() {

    local GROUP="$1"
    local ZONE="$2"

    local INSTANCE_URL=""
    local INSTANCE=""
    local STATUS=""

    for ((i=1; i<=40; i++)); do

        INSTANCE_URL="$(
            gcloud compute instance-groups managed list-instances "$GROUP" \
                --project="$PROJECT_ID" \
                --zone="$ZONE" \
                --format='value(instance)' \
                2>/dev/null \
                | head -n1
        )"

        if [[ -n "$INSTANCE_URL" ]]; then

            INSTANCE="${INSTANCE_URL##*/}"

            STATUS="$(
                gcloud compute instances describe "$INSTANCE" \
                    --project="$PROJECT_ID" \
                    --zone="$ZONE" \
                    --format='value(status)' \
                    2>/dev/null \
                    || true
            )"

            if [[ "$STATUS" == "RUNNING" ]]; then

                echo "$INSTANCE"
                return 0

            fi

        fi

        printf "${DIM}   [%02d/40] %-20s %s${RESET}\r" \
            "$i" \
            "$GROUP" \
            "${STATUS:-CREATING}" >&2

        sleep 5

    done

    echo "" >&2
    return 1
}


echo ""
info "Waiting for managed instances..."

VM1="$(wait_for_mig "$MIG1" "$ZONE1")"
echo ""

VM2="$(wait_for_mig "$MIG2" "$ZONE2")"
echo ""

ok "$MIG1 VM: $VM1"
ok "$MIG2 VM: $VM2"


# ============================================================
# DETECT BACKEND INTERNAL IPs
# ============================================================

BACKEND_IP1="$(
    gcloud compute instances describe "$VM1" \
        --project="$PROJECT_ID" \
        --zone="$ZONE1" \
        --format='value(networkInterfaces[0].networkIP)'
)"

BACKEND_IP2="$(
    gcloud compute instances describe "$VM2" \
        --project="$PROJECT_ID" \
        --zone="$ZONE2" \
        --format='value(networkInterfaces[0].networkIP)'
)"

info "$VM1 -> $BACKEND_IP1"
info "$VM2 -> $BACKEND_IP2"


# ============================================================
# WAIT UTILITY VM RUNNING
# ============================================================

info "Waiting for $UTILITY_VM..."

for ((i=1; i<=30; i++)); do

    STATUS="$(
        gcloud compute instances describe "$UTILITY_VM" \
            --project="$PROJECT_ID" \
            --zone="$UTILITY_ZONE" \
            --format='value(status)' \
            2>/dev/null \
            || true
    )"

    if [[ "$STATUS" == "RUNNING" ]]; then

        ok "$UTILITY_VM is RUNNING"
        break

    fi

    printf "${DIM}   [%02d/30] utility-vm status: %s${RESET}\r" \
        "$i" "${STATUS:-CREATING}"

    sleep 5

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
# WAIT SSH
# ============================================================

SSH_READY=0

info "Checking SSH access to utility-vm..."

for ((i=1; i<=20; i++)); do

    if ssh_utility "echo eplus-ready" >/dev/null 2>&1; then

        SSH_READY=1
        break

    fi

    printf "${DIM}   [%02d/20] Waiting for SSH...${RESET}\r" "$i"

    sleep 5

done

echo ""

if [[ "$SSH_READY" == "1" ]]; then

    ok "utility-vm SSH ready"

else

    warn "SSH not ready yet. Continuing with lab resources."

fi


# ============================================================
# TEST BACKENDS
# Task 2 related verification
# ============================================================

if [[ "$SSH_READY" == "1" ]]; then

    echo ""
    info "Testing backend 1: $BACKEND_IP1"

    ssh_utility "
        for i in \$(seq 1 30); do

            if curl -fsS --max-time 5 http://$BACKEND_IP1/; then
                exit 0
            fi

            sleep 5

        done

        exit 1
    " || warn "Backend 1 Apache is still starting."

    echo ""
    echo ""

    info "Testing backend 2: $BACKEND_IP2"

    ssh_utility "
        for i in \$(seq 1 30); do

            if curl -fsS --max-time 5 http://$BACKEND_IP2/; then
                exit 0
            fi

            sleep 5

        done

        exit 1
    " || warn "Backend 2 Apache is still starting."

    echo ""

fi

ok "TASK 2 completed"


# ============================================================
# TASK 3
# INTERNAL PASSTHROUGH NETWORK LOAD BALANCER
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

    info "Creating regional TCP health check"

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
#
# Internal Passthrough Network Load Balancer
# ============================================================

if gcloud compute backend-services describe "$BACKEND_SERVICE" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    >/dev/null 2>&1; then

    warn "$BACKEND_SERVICE already exists"

else

    info "Creating backend service: $BACKEND_SERVICE"

    gcloud compute backend-services create "$BACKEND_SERVICE" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --load-balancing-scheme=INTERNAL \
        --protocol=TCP \
        --health-checks="$HEALTH_CHECK" \
        --health-checks-region="$REGION" \
        --quiet

    ok "Created backend service $BACKEND_SERVICE"

fi


# ============================================================
# ADD MIG 1 BACKEND
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
    | grep -q "/instanceGroups/$MIG1$"; then

    warn "$MIG1 already attached"

else

    gcloud compute backend-services add-backend "$BACKEND_SERVICE" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --instance-group="$MIG1" \
        --instance-group-zone="$ZONE1" \
        --quiet

    ok "Attached $MIG1"

fi


# ============================================================
# ADD MIG 2 BACKEND
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
    | grep -q "/instanceGroups/$MIG2$"; then

    warn "$MIG2 already attached"

else

    gcloud compute backend-services add-backend "$BACKEND_SERVICE" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --instance-group="$MIG2" \
        --instance-group-zone="$ZONE2" \
        --quiet

    ok "Attached $MIG2"

fi


# ============================================================
# RESERVE INTERNAL STATIC IP
# ============================================================

if gcloud compute addresses describe "$ADDRESS_NAME" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    >/dev/null 2>&1; then

    warn "$ADDRESS_NAME already exists"

else

    info "Reserving internal IP $ILB_IP"

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

info "$ADDRESS_NAME -> $RESERVED_IP"

if [[ "$RESERVED_IP" != "$ILB_IP" ]]; then

    die "$ADDRESS_NAME is $RESERVED_IP but lab requires $ILB_IP"

fi


# ============================================================
# FORWARDING RULE
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


# ============================================================
# DISPLAY LOAD BALANCER
# ============================================================

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

ok "TASK 3 completed"


# ============================================================
# TASK 4
# TEST INTERNAL LOAD BALANCER
# No separate Check my progress, but do it because it is related.
# ============================================================

section "[4/4] TASK 4 - Test Internal Load Balancer"


if [[ "$SSH_READY" == "1" ]]; then

    info "Waiting for backend health and ILB response..."

    ILB_READY=0

    for ((i=1; i<=40; i++)); do

        if ssh_utility \
            "curl -fsS --max-time 5 http://$ILB_IP/ >/dev/null" \
            >/dev/null 2>&1; then

            ILB_READY=1
            break

        fi

        printf "${DIM}   [%02d/40] Waiting for ILB $ILB_IP...${RESET}\r" \
            "$i"

        sleep 5

    done

    echo ""

    if [[ "$ILB_READY" == "1" ]]; then

        ok "Internal Load Balancer is responding"

        echo ""
        echo "${MAGENTA}${BOLD}==============================================================${RESET}"
        echo "${MAGENTA}${BOLD}             TESTING LOAD DISTRIBUTION${RESET}"
        echo "${MAGENTA}${BOLD}==============================================================${RESET}"

        ssh_utility "
            for i in \$(seq 1 10); do

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

        warn "ILB resources exist but health checks may still be initializing."

    fi

else

    warn "Skipping curl test because utility-vm SSH was unavailable."

fi


# ============================================================
# FINAL HEALTH CHECK
# ============================================================

section "FINAL CHECK"


echo "${CYAN}${BOLD}Project ID${RESET}      : $PROJECT_ID"
echo "${CYAN}${BOLD}Network${RESET}         : $NETWORK"
echo "${CYAN}${BOLD}Region${RESET}          : $REGION"
echo "${CYAN}${BOLD}Subnet A${RESET}        : $SUBNET_A ($SUBNET_A_CIDR)"
echo "${CYAN}${BOLD}Subnet B${RESET}        : $SUBNET_B ($SUBNET_B_CIDR)"
echo "${CYAN}${BOLD}Zone 1${RESET}          : $ZONE1"
echo "${CYAN}${BOLD}Zone 2${RESET}          : $ZONE2"
echo "${CYAN}${BOLD}Backend 1${RESET}       : $BACKEND_IP1"
echo "${CYAN}${BOLD}Backend 2${RESET}       : $BACKEND_IP2"
echo "${CYAN}${BOLD}Utility VM IP${RESET}   : $UTILITY_IP"
echo "${CYAN}${BOLD}ILB IP${RESET}          : $ILB_IP"


echo ""
echo "${YELLOW}${BOLD}Backend health:${RESET}"
echo ""

gcloud compute backend-services get-health "$BACKEND_SERVICE" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    || true


echo ""
echo "${YELLOW}${BOLD}Managed instance groups:${RESET}"
echo ""

gcloud compute instance-groups managed list \
    --project="$PROJECT_ID" \
    --filter="name=($MIG1 $MIG2)" \
    --format="table(
        name,
        location(),
        targetSize,
        instanceTemplate.basename()
    )"


echo ""
echo "${YELLOW}${BOLD}Important resources:${RESET}"
echo ""

printf "%-30s %s\n" "Firewall HTTP" "$HTTP_FW"
printf "%-30s %s\n" "Firewall Health Check" "$HC_FW"
printf "%-30s %s\n" "Instance Template 1" "$TEMPLATE1"
printf "%-30s %s\n" "Instance Template 2" "$TEMPLATE2"
printf "%-30s %s\n" "Managed Instance Group 1" "$MIG1"
printf "%-30s %s\n" "Managed Instance Group 2" "$MIG2"
printf "%-30s %s\n" "Utility VM" "$UTILITY_VM"
printf "%-30s %s\n" "Health Check" "$HEALTH_CHECK"
printf "%-30s %s\n" "Backend Service" "$BACKEND_SERVICE"
printf "%-30s %s\n" "Reserved IP" "$ADDRESS_NAME"
printf "%-30s %s\n" "Forwarding Rule" "$FORWARDING_RULE"


echo ""
echo "${GREEN}${BOLD}=============================================================="
echo "               GSP216 LAB COMPLETED"
echo "==============================================================${RESET}"
echo ""
echo "${MAGENTA}${BOLD}                    © ePlus.DEV${RESET}"
echo ""

echo "${YELLOW}${BOLD}Click Check my progress:${RESET}"
echo ""
echo "${GREEN}✓ Task 1 - Configure HTTP and health check firewall rules${RESET}"
echo "${GREEN}✓ Task 2 - Configure instance templates and create instance groups${RESET}"
echo "${GREEN}✓ Task 3 - Configure the Internal Load Balancer${RESET}"
echo ""
echo "${CYAN}Task 4 has no separate Check my progress, but the script tested it.${RESET}"
echo ""