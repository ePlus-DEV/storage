#!/usr/bin/env bash
set -u

# ============================================================
# GSP216 - Internal Load Balancer
# Full Automated Lab Script
# © ePlus.DEV
# ============================================================

# ========================= COLORS ============================
RED=$'\033[0;91m'
GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
BLUE=$'\033[0;94m'
MAGENTA=$'\033[0;95m'
CYAN=$'\033[0;96m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
RESET=$'\033[0m'

clear

echo "${CYAN}${BOLD}"
echo "=============================================================="
echo "              GSP216 - INTERNAL LOAD BALANCER"
echo "=============================================================="
echo "${MAGENTA}                    © ePlus.DEV${RESET}"
echo ""

section() {
    echo ""
    echo "${BLUE}${BOLD}==============================================================${RESET}"
    echo "${YELLOW}${BOLD}$1${RESET}"
    echo "${BLUE}${BOLD}==============================================================${RESET}"
}

ok()   { echo "${GREEN}${BOLD}✓ $1${RESET}"; }
info() { echo "${CYAN}➜ $1${RESET}"; }
warn() { echo "${YELLOW}⚠ $1${RESET}"; }
err()  { echo "${RED}${BOLD}✗ $1${RESET}"; }

die() {
    err "$1"
    exit 1
}

# ============================================================
# RETRY
# Handles temporary Google API 5xx / 502 errors
# ============================================================

retry() {

    local max=8
    local delay=8
    local i

    for ((i=1; i<=max; i++)); do

        if "$@"; then
            return 0
        fi

        warn "Command failed - retry $i/$max..."
        sleep "$delay"
    done

    return 1
}

# ============================================================
# CONFIG - EXACT CURRENT LAB VALUES
# ============================================================

NETWORK="my-internal-app"

SUBNET_A="subnet-a"
SUBNET_B="subnet-b"

REGION="us-west4"
ZONE1="us-west4-b"

FW_HTTP="app-allow-http"
FW_HEALTH="app-allow-health-check"

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
# [0/5] ENVIRONMENT
# ============================================================

section "[0/5] Detecting Lab Environment"

PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
    PROJECT_ID="${DEVSHELL_PROJECT_ID:-}"
fi

if [[ -z "$PROJECT_ID" ]]; then
    read -rp "Enter Project ID: " PROJECT_ID
fi

gcloud config set project "$PROJECT_ID" >/dev/null

info "Project : $PROJECT_ID"
info "Region  : $REGION"
info "Zone 1  : $ZONE1"

# ============================================================
# VERIFY NETWORK / SUBNETS
# ============================================================

gcloud compute networks describe "$NETWORK" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1 || die "Network $NETWORK not found"

gcloud compute networks subnets describe "$SUBNET_A" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    >/dev/null 2>&1 || die "$SUBNET_A not found in $REGION"

gcloud compute networks subnets describe "$SUBNET_B" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    >/dev/null 2>&1 || die "$SUBNET_B not found in $REGION"

SUBNET_A_CIDR="$(
    gcloud compute networks subnets describe "$SUBNET_A" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --format='value(ipCidrRange)'
)"

SUBNET_B_CIDR="$(
    gcloud compute networks subnets describe "$SUBNET_B" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --format='value(ipCidrRange)'
)"

ok "Network: $NETWORK"
ok "$SUBNET_A = $SUBNET_A_CIDR"
ok "$SUBNET_B = $SUBNET_B_CIDR"

# ============================================================
# VERIFY ZONE1 EXACT LAB ZONE
# ============================================================

gcloud compute zones describe "$ZONE1" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1 || die "$ZONE1 not available"

# ============================================================
# AUTO DETECT SECOND DIFFERENT ZONE
# ============================================================

ZONE2="$(
    gcloud compute zones list \
        --project="$PROJECT_ID" \
        --format='value(name,status)' \
    | awk -v R="$REGION" -v Z1="$ZONE1" '
        $1 ~ ("^" R "-") && $1 != Z1 && $2 == "UP" {
            print $1
            exit
        }
    '
)"

[[ -n "$ZONE2" ]] || die "Could not find another zone in $REGION"

info "Zone 2  : $ZONE2"

gcloud config set compute/region "$REGION" >/dev/null
gcloud config set compute/zone "$ZONE1" >/dev/null

gcloud services enable compute.googleapis.com \
    --project="$PROJECT_ID" \
    --quiet >/dev/null 2>&1 || true

ok "Environment ready"

# ============================================================
# [1/5] CLEAN OLD LAB RESOURCES
# ============================================================

section "[1/5] Cleaning Existing Lab Resources"

# ============================================================
# Forwarding rule
# ============================================================

if gcloud compute forwarding-rules describe "$FORWARDING_RULE" \
    --project="$PROJECT_ID" \
    --region="$REGION" >/dev/null 2>&1; then

    info "Deleting $FORWARDING_RULE..."

    retry gcloud compute forwarding-rules delete "$FORWARDING_RULE" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --quiet || true
fi

# ============================================================
# Backend service
# ============================================================

if gcloud compute backend-services describe "$BACKEND_SERVICE" \
    --project="$PROJECT_ID" \
    --region="$REGION" >/dev/null 2>&1; then

    info "Deleting $BACKEND_SERVICE..."

    retry gcloud compute backend-services delete "$BACKEND_SERVICE" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --quiet || true
fi

# ============================================================
# Health check
# ============================================================

if gcloud compute health-checks describe "$HEALTH_CHECK" \
    --project="$PROJECT_ID" \
    --region="$REGION" >/dev/null 2>&1; then

    info "Deleting $HEALTH_CHECK..."

    retry gcloud compute health-checks delete "$HEALTH_CHECK" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --quiet || true
fi

# ============================================================
# ILB IP
# ============================================================

if gcloud compute addresses describe "$ADDRESS_NAME" \
    --project="$PROJECT_ID" \
    --region="$REGION" >/dev/null 2>&1; then

    info "Deleting $ADDRESS_NAME..."

    retry gcloud compute addresses delete "$ADDRESS_NAME" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --quiet || true
fi

# ============================================================
# Utility VM - find wherever it exists
# ============================================================

UTILITY_OLD_ZONE="$(
    gcloud compute instances list \
        --project="$PROJECT_ID" \
        --filter="name=$UTILITY_VM" \
        --format='value(zone)' \
        | head -n1
)"

if [[ -n "$UTILITY_OLD_ZONE" ]]; then

    UTILITY_OLD_ZONE="${UTILITY_OLD_ZONE##*/}"

    info "Deleting old $UTILITY_VM from $UTILITY_OLD_ZONE..."

    retry gcloud compute instances delete "$UTILITY_VM" \
        --project="$PROJECT_ID" \
        --zone="$UTILITY_OLD_ZONE" \
        --quiet || true
fi

# ============================================================
# DELETE MIGs wherever previous scripts may have created them
# ============================================================

delete_mig_anywhere() {

    local MIG="$1"

    local zones
    zones="$(
        gcloud compute instance-groups managed list \
            --project="$PROJECT_ID" \
            --filter="name=$MIG" \
            --format='value(zone)' 2>/dev/null
    )"

    while read -r zone_url; do

        [[ -z "$zone_url" ]] && continue

        local zone="${zone_url##*/}"

        info "Found $MIG in $zone"

        gcloud compute instance-groups managed stop-autoscaling "$MIG" \
            --project="$PROJECT_ID" \
            --zone="$zone" \
            --quiet >/dev/null 2>&1 || true

        info "Deleting $MIG..."

        if retry gcloud compute instance-groups managed delete "$MIG" \
            --project="$PROJECT_ID" \
            --zone="$zone" \
            --quiet; then

            ok "Deleted $MIG from $zone"

        else

            die "Could not delete $MIG from $zone"
        fi

    done <<< "$zones"
}

delete_mig_anywhere "$MIG1"
delete_mig_anywhere "$MIG2"

# ============================================================
# Delete templates
# ============================================================

for T in "$TEMPLATE1" "$TEMPLATE2"; do

    if gcloud compute instance-templates describe "$T" \
        --project="$PROJECT_ID" >/dev/null 2>&1; then

        info "Deleting $T..."

        retry gcloud compute instance-templates delete "$T" \
            --project="$PROJECT_ID" \
            --quiet || die "Cannot delete $T"

        ok "Deleted $T"
    fi

done

# ============================================================
# Firewall rules
# ============================================================

for FW in "$FW_HTTP" "$FW_HEALTH"; do

    if gcloud compute firewall-rules describe "$FW" \
        --project="$PROJECT_ID" >/dev/null 2>&1; then

        info "Deleting $FW..."

        retry gcloud compute firewall-rules delete "$FW" \
            --project="$PROJECT_ID" \
            --quiet || true
    fi

done

sleep 3

ok "Cleanup completed"

# ============================================================
# [2/5] TASK 1 - FIREWALL
# ============================================================

section "[2/5] TASK 1 - Firewall Rules"

gcloud compute firewall-rules create "$FW_HTTP" \
    --project="$PROJECT_ID" \
    --network="$NETWORK" \
    --direction=INGRESS \
    --priority=1000 \
    --action=ALLOW \
    --rules=tcp:80 \
    --source-ranges=10.10.0.0/16 \
    --target-tags=lb-backend \
    --quiet

ok "$FW_HTTP"

gcloud compute firewall-rules create "$FW_HEALTH" \
    --project="$PROJECT_ID" \
    --network="$NETWORK" \
    --direction=INGRESS \
    --priority=1000 \
    --action=ALLOW \
    --rules=tcp \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags=lb-backend \
    --quiet

ok "$FW_HEALTH"

# ============================================================
# [3/5] TASK 2
# ============================================================

section "[3/5] TASK 2 - Templates and Instance Groups"

# ============================================================
# STARTUP SCRIPT - EXACT LAB SCRIPT
# ============================================================

STARTUP="/tmp/gsp216-startup.sh"

cat > "$STARTUP" <<'STARTUP_SCRIPT'
#!/bin/bash
apt-get update
apt-get install -y apache2 php libapache2-mod-php
cat <<'EOF' > /var/www/html/index.php
<h1>Internal Load Balancing Lab</h1>
<h2>Client IP</h2>
Your IP address : <?php echo $_SERVER['REMOTE_ADDR']; ?>
<h2>Hostname</h2>
Server Hostname: <?php echo gethostname(); ?>
<h2>Server Location</h2>
Region and Zone: <?php
  $ch = curl_init();
  curl_setopt($ch, CURLOPT_URL, "http://metadata.google.internal/computeMetadata/v1/instance/zone");
  curl_setopt($ch, CURLOPT_HTTPHEADER, array('Metadata-Flavor: Google'));
  curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
  $zone = curl_exec($ch);
  $parts = explode('/', $zone);
  echo end($parts);
?>
EOF
rm -f /var/www/html/index.html
systemctl restart apache2
STARTUP_SCRIPT

# ============================================================
# TEMPLATE 1 - EXACT subnet-a
# ============================================================

info "Creating $TEMPLATE1..."

gcloud compute instance-templates create "$TEMPLATE1" \
    --project="$PROJECT_ID" \
    --machine-type=e2-micro \
    --network-interface="network=$NETWORK,subnet=$SUBNET_A,no-address" \
    --tags=lb-backend \
    --metadata-from-file=startup-script="$STARTUP" \
    --quiet

ok "$TEMPLATE1 created"

# ============================================================
# VERIFY TEMPLATE 1 BEFORE CONTINUE
# ============================================================

T1="$(
    gcloud compute instance-templates describe "$TEMPLATE1" \
        --project="$PROJECT_ID" \
        --format=json
)"

T1_MACHINE="$(jq -r '.properties.machineType // ""' <<< "$T1")"

T1_SUBNET="$(
    jq -r '.properties.networkInterfaces[0].subnetwork // ""' <<< "$T1"
)"

T1_NETWORK="$(
    jq -r '.properties.networkInterfaces[0].network // ""' <<< "$T1"
)"

T1_EXT="$(
    jq -r \
        '(.properties.networkInterfaces[0].accessConfigs // []) | length' \
        <<< "$T1"
)"

T1_TAG="$(
    jq -r '.properties.tags.items[]? // empty' <<< "$T1" \
    | grep -x lb-backend || true
)"

[[ "$T1_MACHINE" == "e2-micro" || "$T1_MACHINE" == */e2-micro ]] \
    || die "Wrong machine type: $T1_MACHINE"

[[ "$T1_SUBNET" == */subnetworks/subnet-a || "$T1_SUBNET" == "subnet-a" ]] \
    || die "Wrong template subnet: $T1_SUBNET"

[[ "$T1_NETWORK" == */networks/my-internal-app || "$T1_NETWORK" == "my-internal-app" ]] \
    || die "Wrong network: $T1_NETWORK"

[[ "$T1_EXT" == "0" ]] \
    || die "Template has external IPv4"

[[ "$T1_TAG" == "lb-backend" ]] \
    || die "lb-backend tag missing"

ok "Machine type  : e2-micro"
ok "Network       : my-internal-app"
ok "Subnetwork    : subnet-a"
ok "External IPv4 : None"
ok "Tag           : lb-backend"

# ============================================================
# TEMPLATE 2 - Copy equivalent configuration, subnet-b
# ============================================================

info "Creating $TEMPLATE2..."

gcloud compute instance-templates create "$TEMPLATE2" \
    --project="$PROJECT_ID" \
    --machine-type=e2-micro \
    --network-interface="network=$NETWORK,subnet=$SUBNET_B,no-address" \
    --tags=lb-backend \
    --metadata-from-file=startup-script="$STARTUP" \
    --quiet

ok "$TEMPLATE2 created"

# ============================================================
# MIG 1 - EXACT LAB ZONE us-west4-b
# ============================================================

info "Creating $MIG1 in $ZONE1..."

gcloud compute instance-groups managed create "$MIG1" \
    --project="$PROJECT_ID" \
    --zone="$ZONE1" \
    --base-instance-name="$MIG1" \
    --template="$TEMPLATE1" \
    --size=1 \
    --quiet

ok "$MIG1 created in $ZONE1"

gcloud compute instance-groups managed set-autoscaling "$MIG1" \
    --project="$PROJECT_ID" \
    --zone="$ZONE1" \
    --min-num-replicas=1 \
    --max-num-replicas=1 \
    --target-cpu-utilization=0.80 \
    --cool-down-period=45 \
    --mode=on \
    --quiet >/dev/null

ok "$MIG1 autoscaling = min 1 / max 1 / CPU 80% / init 45s"

# ============================================================
# MIG 2 - DIFFERENT ZONE
# ============================================================

info "Creating $MIG2 in $ZONE2..."

gcloud compute instance-groups managed create "$MIG2" \
    --project="$PROJECT_ID" \
    --zone="$ZONE2" \
    --base-instance-name="$MIG2" \
    --template="$TEMPLATE2" \
    --size=1 \
    --quiet

ok "$MIG2 created in $ZONE2"

gcloud compute instance-groups managed set-autoscaling "$MIG2" \
    --project="$PROJECT_ID" \
    --zone="$ZONE2" \
    --min-num-replicas=1 \
    --max-num-replicas=1 \
    --target-cpu-utilization=0.80 \
    --cool-down-period=45 \
    --mode=on \
    --quiet >/dev/null

ok "$MIG2 autoscaling = min 1 / max 1 / CPU 80% / init 45s"

# ============================================================
# UTILITY VM - EXACT us-west4-b
# ============================================================

info "Creating utility-vm..."

gcloud compute instances create "$UTILITY_VM" \
    --project="$PROJECT_ID" \
    --zone="$ZONE1" \
    --machine-type=e2-micro \
    --network-interface="network=$NETWORK,subnet=$SUBNET_A,private-network-ip=$UTILITY_IP" \
    --quiet

ok "$UTILITY_VM created in $ZONE1"
ok "Internal IP = $UTILITY_IP"

# ============================================================
# MIG WAIT
# ============================================================

wait_mig() {

    local GROUP="$1"
    local ZONE="$2"

    local JSON
    local INSTANCE_URL
    local INSTANCE
    local STATUS
    local ACTION
    local ERROR_MSG

    for ((i=1; i<=30; i++)); do

        JSON="$(
            gcloud compute instance-groups managed list-instances "$GROUP" \
                --project="$PROJECT_ID" \
                --zone="$ZONE" \
                --format=json \
                2>/dev/null || echo '[]'
        )"

        INSTANCE_URL="$(
            jq -r '.[0].instance // empty' <<< "$JSON"
        )"

        INSTANCE="${INSTANCE_URL##*/}"

        STATUS="$(
            jq -r '.[0].instanceStatus // empty' <<< "$JSON"
        )"

        ACTION="$(
            jq -r '.[0].currentAction // empty' <<< "$JSON"
        )"

        ERROR_MSG="$(
            jq -r \
                '.[0].lastAttempt.errors.errors[0].message // empty' \
                <<< "$JSON"
        )"

        printf \
            "\r${DIM}[%02d/30] %-18s STATUS=%-10s ACTION=%-10s${RESET}" \
            "$i" \
            "$GROUP" \
            "${STATUS:-PENDING}" \
            "${ACTION:-CREATING}" >&2

        if [[ -n "$ERROR_MSG" ]]; then
            echo "" >&2
            echo "${YELLOW}⚠ $ERROR_MSG${RESET}" >&2
        fi

        if [[ -n "$INSTANCE" && "$STATUS" == "RUNNING" ]]; then

            echo "" >&2
            echo "${GREEN}✓ $GROUP VM: $INSTANCE${RESET}" >&2

            echo "$INSTANCE"
            return 0
        fi

        sleep 4
    done

    echo "" >&2
    warn "$GROUP VM not ready yet" >&2

    return 1
}

echo ""
info "Checking managed instances..."

VM1="$(wait_mig "$MIG1" "$ZONE1" || true)"

echo ""

VM2="$(wait_mig "$MIG2" "$ZONE2" || true)"

echo ""

BACKEND_IP1=""
BACKEND_IP2=""

if [[ -n "$VM1" ]]; then

    BACKEND_IP1="$(
        gcloud compute instances describe "$VM1" \
            --project="$PROJECT_ID" \
            --zone="$ZONE1" \
            --format='value(networkInterfaces[0].networkIP)'
    )"

    info "$VM1 = $BACKEND_IP1"
fi

if [[ -n "$VM2" ]]; then

    BACKEND_IP2="$(
        gcloud compute instances describe "$VM2" \
            --project="$PROJECT_ID" \
            --zone="$ZONE2" \
            --format='value(networkInterfaces[0].networkIP)'
    )"

    info "$VM2 = $BACKEND_IP2"
fi

# ============================================================
# [4/5] TASK 3 - ILB
# ============================================================

section "[4/5] TASK 3 - Internal Load Balancer"

# ============================================================
# Regional TCP Health Check
# ============================================================

gcloud compute health-checks create tcp "$HEALTH_CHECK" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --port=80 \
    --check-interval=5s \
    --timeout=5s \
    --healthy-threshold=2 \
    --unhealthy-threshold=2 \
    --quiet

ok "$HEALTH_CHECK"

# ============================================================
# Backend service
# ============================================================

gcloud compute backend-services create "$BACKEND_SERVICE" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --load-balancing-scheme=INTERNAL \
    --protocol=TCP \
    --health-checks="$HEALTH_CHECK" \
    --health-checks-region="$REGION" \
    --quiet

ok "$BACKEND_SERVICE"

# ============================================================
# Backend 1
# ============================================================

gcloud compute backend-services add-backend "$BACKEND_SERVICE" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --instance-group="$MIG1" \
    --instance-group-zone="$ZONE1" \
    --quiet

ok "Added $MIG1"

# ============================================================
# Backend 2
# ============================================================

gcloud compute backend-services add-backend "$BACKEND_SERVICE" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --instance-group="$MIG2" \
    --instance-group-zone="$ZONE2" \
    --quiet

ok "Added $MIG2"

# ============================================================
# Reserve Static Internal IP
# ============================================================

gcloud compute addresses create "$ADDRESS_NAME" \
    --project="$PROJECT_ID" \
    --region="$REGION" \
    --subnet="$SUBNET_B" \
    --addresses="$ILB_IP" \
    --quiet

ok "$ADDRESS_NAME = $ILB_IP"

# ============================================================
# Frontend / Forwarding Rule
# ============================================================

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

ok "Internal Load Balancer created"

# ============================================================
# [5/5] TASK 4 - TEST
# ============================================================

section "[5/5] TASK 4 - Test Internal Load Balancer"

ssh_utility() {

    gcloud compute ssh "$UTILITY_VM" \
        --project="$PROJECT_ID" \
        --zone="$ZONE1" \
        --quiet \
        --command="$1"
}

SSH_READY=0

info "Waiting for utility-vm SSH..."

for ((i=1; i<=15; i++)); do

    if ssh_utility "echo ready" >/dev/null 2>&1; then
        SSH_READY=1
        break
    fi

    printf \
        "\r${DIM}[%02d/15] Waiting for SSH...${RESET}" \
        "$i"

    sleep 4
done

echo ""

if [[ "$SSH_READY" == "1" ]]; then

    ok "utility-vm SSH ready"

    # ========================================================
    # Direct Backend Tests
    # ========================================================

    if [[ -n "$BACKEND_IP1" ]]; then

        info "Testing backend 1: $BACKEND_IP1"

        ssh_utility "
            for i in \$(seq 1 20); do

                if curl -fsS --max-time 5 http://$BACKEND_IP1/; then
                    exit 0
                fi

                sleep 4
            done

            exit 1
        " || warn "Backend 1 still initializing"

        echo ""
    fi

    if [[ -n "$BACKEND_IP2" ]]; then

        info "Testing backend 2: $BACKEND_IP2"

        ssh_utility "
            for i in \$(seq 1 20); do

                if curl -fsS --max-time 5 http://$BACKEND_IP2/; then
                    exit 0
                fi

                sleep 4
            done

            exit 1
        " || warn "Backend 2 still initializing"

        echo ""
    fi

    # ========================================================
    # ILB Test
    # ========================================================

    ILB_READY=0

    info "Waiting for ILB $ILB_IP..."

    for ((i=1; i<=30; i++)); do

        if ssh_utility \
            "curl -fsS --max-time 5 http://$ILB_IP/ >/dev/null" \
            >/dev/null 2>&1; then

            ILB_READY=1
            break
        fi

        printf \
            "\r${DIM}[%02d/30] Waiting for ILB health...${RESET}" \
            "$i"

        sleep 5
    done

    echo ""

    if [[ "$ILB_READY" == "1" ]]; then

        ok "ILB responding"

        echo ""
        echo "${MAGENTA}${BOLD}=============================================================="
        echo "                  LOAD BALANCER TEST"
        echo "==============================================================${RESET}"

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

        warn "ILB health still initializing"
    fi

else

    warn "SSH unavailable; Task 4 test skipped"
fi

# ============================================================
# FINAL CHECK
# ============================================================

section "FINAL RESOURCE CHECK"

echo "${CYAN}Project       :${RESET} $PROJECT_ID"
echo "${CYAN}Region        :${RESET} $REGION"
echo "${CYAN}MIG1 Zone     :${RESET} $ZONE1"
echo "${CYAN}MIG2 Zone     :${RESET} $ZONE2"
echo ""
echo "${CYAN}Template 1    :${RESET} $TEMPLATE1"
echo "${CYAN}Template 2    :${RESET} $TEMPLATE2"
echo "${CYAN}MIG 1         :${RESET} $MIG1"
echo "${CYAN}MIG 2         :${RESET} $MIG2"
echo ""
echo "${CYAN}Utility VM    :${RESET} $UTILITY_VM"
echo "${CYAN}Utility IP    :${RESET} $UTILITY_IP"
echo "${CYAN}ILB IP        :${RESET} $ILB_IP"

# ============================================================
# TEMPLATE 1 FINAL GRADER CHECK
# ============================================================

echo ""
echo "${YELLOW}${BOLD}instance-template-1:${RESET}"

gcloud compute instance-templates describe "$TEMPLATE1" \
    --project="$PROJECT_ID" \
    --format="yaml(
        name,
        properties.machineType,
        properties.networkInterfaces,
        properties.tags
    )"

# ============================================================
# MIG STATUS
# ============================================================

echo ""
echo "${YELLOW}${BOLD}instance-group-1:${RESET}"

gcloud compute instance-groups managed list-instances "$MIG1" \
    --project="$PROJECT_ID" \
    --zone="$ZONE1" || true

echo ""
echo "${YELLOW}${BOLD}instance-group-2:${RESET}"

gcloud compute instance-groups managed list-instances "$MIG2" \
    --project="$PROJECT_ID" \
    --zone="$ZONE2" || true

# ============================================================
# BACKEND HEALTH
# ============================================================

echo ""
echo "${YELLOW}${BOLD}Backend health:${RESET}"

gcloud compute backend-services get-health "$BACKEND_SERVICE" \
    --project="$PROJECT_ID" \
    --region="$REGION" || true

# ============================================================
# DONE
# ============================================================

echo ""
echo "${GREEN}${BOLD}=============================================================="
echo "                  GSP216 COMPLETED"
echo "==============================================================${RESET}"

echo ""
echo "${MAGENTA}${BOLD}                    © ePlus.DEV${RESET}"
echo ""

echo "${YELLOW}${BOLD}Click Check my progress:${RESET}"
echo ""
echo "${GREEN}✓ Task 1 - Firewall rules${RESET}"
echo "${GREEN}✓ Task 2 - Instance templates and instance groups${RESET}"
echo "${GREEN}✓ Task 3 - Internal Load Balancer${RESET}"
echo ""
echo "${CYAN}Task 4 has no separate Check my progress.${RESET}"
echo ""