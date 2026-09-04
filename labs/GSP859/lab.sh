#!/bin/bash

# ============================================================
# GSP859 - Migrating to Cloud SQL from Amazon RDS for MySQL
# Using Database Migration Service
#
# ePlus.DEV Cloud Tutorial
# ============================================================

set -Eeuo pipefail

# ============================================================
# COLORS
# ============================================================

BLACK=$'\033[0;90m'
RED=$'\033[0;91m'
GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
BLUE=$'\033[0;94m'
MAGENTA=$'\033[0;95m'
CYAN=$'\033[0;96m'
WHITE=$'\033[0;97m'

RESET=$'\033[0m'
BOLD=$'\033[1m'

# ============================================================
# FIXED LAB VALUES
# ============================================================

SOURCE_PROFILE="mysql-rds-source"
DEST_PROFILE="mysql-cloudsql-destination"

MIGRATION_JOB="rds-to-cloudsql"
DEST_INSTANCE="mysql-cloudsql"

SOURCE_DB_USER="admin"
SOURCE_DB_PASSWORD="changeme"
SOURCE_DB_PORT="3306"

DEST_DB_USER="root"
DEST_DB_PASSWORD="supersecret"

# ============================================================
# FUNCTIONS
# ============================================================

header() {
    clear

    echo
    echo "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════╗${RESET}"
    echo "${CYAN}${BOLD}        WELCOME TO ePlus.DEV CLOUD TUTORIAL                 ${RESET}"
    echo "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════╝${RESET}"
    echo
    echo "${MAGENTA}${BOLD} GSP859 - Amazon RDS MySQL → Cloud SQL MySQL${RESET}"
    echo "${MAGENTA}${BOLD} Database Migration Service${RESET}"
    echo
}

step() {
    echo
    echo "${BLUE}${BOLD}============================================================${RESET}"
    echo "${YELLOW}${BOLD}$1${RESET}"
    echo "${BLUE}${BOLD}============================================================${RESET}"
}

info() {
    echo "${CYAN}➜ $1${RESET}"
}

ok() {
    echo "${GREEN}${BOLD}✓ $1${RESET}"
}

warn() {
    echo "${YELLOW}${BOLD}⚠ $1${RESET}"
}

fail() {
    echo
    echo "${RED}${BOLD}✗ ERROR: $1${RESET}"
    echo
    exit 1
}

trim() {
    local value="$1"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    printf '%s' "$value"
}

get_job_state() {

    gcloud database-migration migration-jobs describe \
        "$MIGRATION_JOB" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format="value(state)" \
        2>/dev/null || true
}

get_job_phase() {

    gcloud database-migration migration-jobs describe \
        "$MIGRATION_JOB" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format="value(phase)" \
        2>/dev/null || true
}

get_job_error() {

    gcloud database-migration migration-jobs describe \
        "$MIGRATION_JOB" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format="value(error.message)" \
        2>/dev/null || true
}

# ------------------------------------------------------------
# Run async DMS action and wait for its operation
#
# Examples:
#   run_dms_action demote-destination
#   run_dms_action verify
#   run_dms_action start
#   run_dms_action restart
# ------------------------------------------------------------

run_dms_action() {

    local ACTION="$1"
    local ACTION_JSON
    local OP_NAME
    local OP_ID
    local OP_JSON
    local OP_DONE
    local OP_ERROR

    info "Running: $ACTION"

    if ! ACTION_JSON=$(
        gcloud database-migration migration-jobs "$ACTION" \
            "$MIGRATION_JOB" \
            --region="$REGION" \
            --project="$PROJECT_ID" \
            --quiet \
            --format=json
    ); then

        fail "Unable to execute DMS action: $ACTION"
    fi

    OP_NAME=$(
        echo "$ACTION_JSON" |
        jq -r '.name // empty'
    )

    if [[ -z "$OP_NAME" ]]; then

        warn "No operation ID returned."
        warn "Checking migration job state instead."

        sleep 10
        return 0
    fi

    OP_ID="${OP_NAME##*/}"

    info "Operation: $OP_ID"

    while true; do

        if ! OP_JSON=$(
            gcloud database-migration operations describe \
                "$OP_ID" \
                --region="$REGION" \
                --project="$PROJECT_ID" \
                --format=json \
                2>/dev/null
        ); then

            printf "."
            sleep 5
            continue
        fi

        OP_DONE=$(
            echo "$OP_JSON" |
            jq -r '.done // false'
        )

        if [[ "$OP_DONE" == "true" ]]; then

            OP_ERROR=$(
                echo "$OP_JSON" |
                jq -r '.error.message // empty'
            )

            echo

            if [[ -n "$OP_ERROR" ]]; then

                echo
                echo "${RED}${BOLD}Operation failed:${RESET}"
                echo "$OP_ERROR"
                echo

                return 1
            fi

            ok "$ACTION completed."
            return 0
        fi

        printf "."
        sleep 5
    done
}

# ============================================================
# START
# ============================================================

header

# ============================================================
# INPUT LAB VALUES FIRST
# ============================================================

step "STEP 1 - Enter Lab Details"

echo
echo "${YELLOW}Copy these values from the Lab setup panel on the right.${RESET}"
echo
echo "${WHITE}Required:${RESET}"
echo "  • AWS RDS Database - Source"
echo "  • AWS RDS Database Security Group"
echo "  • AWS Access Key ID"
echo "  • AWS Secret Access Key"
echo
echo "${YELLOW}AWS Username and AWS Password are NOT required.${RESET}"
echo

read -rp "AWS RDS Database - Source        : " RDS_HOST
read -rp "AWS RDS Database Security Group : " AWS_SECURITY_GROUP
read -rp "AWS Access Key ID               : " AWS_ACCESS_KEY_ID
read -rsp "AWS Secret Access Key           : " AWS_SECRET_ACCESS_KEY

echo
echo

RDS_HOST=$(trim "$RDS_HOST")
AWS_SECURITY_GROUP=$(trim "$AWS_SECURITY_GROUP")
AWS_ACCESS_KEY_ID=$(trim "$AWS_ACCESS_KEY_ID")
AWS_SECRET_ACCESS_KEY=$(trim "$AWS_SECRET_ACCESS_KEY")

RDS_HOST="${RDS_HOST%.}"

[[ -z "$RDS_HOST" ]] &&
    fail "AWS RDS Database - Source cannot be empty."

[[ -z "$AWS_SECURITY_GROUP" ]] &&
    fail "AWS RDS Security Group cannot be empty."

[[ -z "$AWS_ACCESS_KEY_ID" ]] &&
    fail "AWS Access Key ID cannot be empty."

[[ -z "$AWS_SECRET_ACCESS_KEY" ]] &&
    fail "AWS Secret Access Key cannot be empty."

if [[ "$AWS_SECURITY_GROUP" != sg-* ]]; then
    warn "Security Group normally begins with sg-"
fi

export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY

# Do NOT reuse credentials from previous aws configure
unset AWS_SESSION_TOKEN 2>/dev/null || true

ok "Lab information received."

echo
info "RDS Source     : $RDS_HOST"
info "Security Group : $AWS_SECURITY_GROUP"
info "Access Key     : ${AWS_ACCESS_KEY_ID:0:5}********"

# ============================================================
# GOOGLE CLOUD PROJECT
# ============================================================

step "STEP 2 - Detect Google Cloud environment"

PROJECT_ID=$(
    gcloud config get-value project 2>/dev/null || true
)

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then

    PROJECT_ID=$(
        gcloud projects list \
            --filter="lifecycleState=ACTIVE" \
            --format="value(projectId)" \
            --limit=1
    )

    [[ -z "$PROJECT_ID" ]] &&
        fail "Unable to detect Google Cloud Project ID."

    gcloud config set project "$PROJECT_ID" >/dev/null
fi

ok "Project: $PROJECT_ID"

# ============================================================
# FIND CLOUD SQL
# ============================================================

step "STEP 3 - Detect Cloud SQL destination"

if ! gcloud sql instances describe "$DEST_INSTANCE" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

    warn "$DEST_INSTANCE not found."

    mapfile -t SQL_INSTANCES < <(
        gcloud sql instances list \
            --project="$PROJECT_ID" \
            --format="value(name)"
    )

    if [[ "${#SQL_INSTANCES[@]}" -eq 1 ]]; then

        DEST_INSTANCE="${SQL_INSTANCES[0]}"

        warn "Using detected Cloud SQL instance: $DEST_INSTANCE"

    else

        echo
        gcloud sql instances list \
            --project="$PROJECT_ID" \
            --format="table(name,region,databaseVersion)"
        echo

        fail "Unable to automatically identify mysql-cloudsql."
    fi
fi

REGION=$(
    gcloud sql instances describe \
        "$DEST_INSTANCE" \
        --project="$PROJECT_ID" \
        --format="value(region)"
)

[[ -z "$REGION" ]] &&
    fail "Unable to determine Cloud SQL region."

ok "Destination : $DEST_INSTANCE"
ok "Region      : $REGION"

# ============================================================
# ENABLE APIs
# ============================================================

step "STEP 4 - Enable required APIs"

gcloud services enable \
    datamigration.googleapis.com \
    sqladmin.googleapis.com \
    compute.googleapis.com \
    --project="$PROJECT_ID" \
    --quiet

ok "Required APIs enabled."

# Give API a few seconds to propagate
sleep 5

# ============================================================
# INSTALL REQUIRED UTILITIES
# ============================================================

step "STEP 5 - Check required utilities"

if ! command -v jq >/dev/null 2>&1; then

    info "Installing jq..."

    sudo apt-get update -qq
    sudo apt-get install -y jq

fi

ok "jq ready."

if ! command -v dig >/dev/null 2>&1; then

    info "Installing dnsutils..."

    sudo apt-get update -qq
    sudo apt-get install -y dnsutils

fi

ok "dig ready."

# ============================================================
# INSTALL AWS CLI
# ============================================================

step "STEP 6 - Prepare AWS CLI"

if ! command -v aws >/dev/null 2>&1; then

    info "AWS CLI not found."
    info "Installing AWS CLI v2..."

    if ! command -v unzip >/dev/null 2>&1; then
        sudo apt-get update -qq
        sudo apt-get install -y unzip
    fi

    rm -rf /tmp/aws /tmp/awscliv2.zip

    curl -sS \
        "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
        -o /tmp/awscliv2.zip

    unzip -q /tmp/awscliv2.zip -d /tmp

    sudo /tmp/aws/install --update

    rm -rf /tmp/aws /tmp/awscliv2.zip

fi

ok "AWS CLI ready."

aws --version

# ============================================================
# DETECT AWS REGION
# ============================================================

step "STEP 7 - Detect AWS RDS region"

AWS_REGION=$(
    echo "$RDS_HOST" |
    sed -nE \
        's/.*\.([a-z]{2}(-gov)?-[a-z0-9-]+-[0-9]+)\.rds\.amazonaws\.com$/\1/p'
)

if [[ -z "$AWS_REGION" ]]; then

    # GSP859 currently provisions the RDS database in us-east-1.
    AWS_REGION="us-east-1"

    warn "Could not determine AWS region from hostname."
    warn "Using lab region: $AWS_REGION"
fi

export AWS_DEFAULT_REGION="$AWS_REGION"

ok "AWS Region: $AWS_REGION"

# ============================================================
# TEST AWS CREDENTIALS
# ============================================================

step "STEP 8 - Test AWS credentials"

if ! AWS_ACCOUNT=$(
    aws sts get-caller-identity \
        --region="$AWS_REGION" \
        --query="Account" \
        --output=text \
        2>/dev/null
); then

    fail "AWS credentials are invalid."
fi

ok "AWS authentication successful."
info "AWS Account: $AWS_ACCOUNT"

# ============================================================
# CHECK SECURITY GROUP
# ============================================================

step "STEP 9 - Verify AWS Security Group"

if ! aws ec2 describe-security-groups \
    --region="$AWS_REGION" \
    --group-ids="$AWS_SECURITY_GROUP" \
    >/dev/null 2>&1; then

    fail "Security Group $AWS_SECURITY_GROUP was not found in $AWS_REGION."
fi

ok "Security Group found: $AWS_SECURITY_GROUP"

# ============================================================
# RESOLVE RDS IP
# ============================================================

step "STEP 10 - Resolve RDS hostname to IPv4"

RDS_IP=""

for ATTEMPT in $(seq 1 60); do

    RDS_IP=$(
        dig +short A "$RDS_HOST" |
        grep -E \
            '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' |
        tail -n1 ||
        true
    )

    if [[ -n "$RDS_IP" ]]; then
        break
    fi

    info "Waiting for RDS DNS... attempt $ATTEMPT/60"

    sleep 10
done

[[ -z "$RDS_IP" ]] &&
    fail "Unable to resolve RDS hostname after 10 minutes."

ok "RDS Host : $RDS_HOST"
ok "RDS IP   : $RDS_IP"

# ============================================================
# CREATE SOURCE CONNECTION PROFILE
# ============================================================

step "STEP 11 - Create MySQL RDS source connection profile"

if gcloud database-migration connection-profiles describe \
    "$SOURCE_PROFILE" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1; then

    ok "Source profile already exists: $SOURCE_PROFILE"

else

    gcloud database-migration connection-profiles create mysql \
        "$SOURCE_PROFILE" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --display-name="$SOURCE_PROFILE" \
        --host="$RDS_IP" \
        --port="$SOURCE_DB_PORT" \
        --username="$SOURCE_DB_USER" \
        --password="$SOURCE_DB_PASSWORD" \
        --provider=RDS \
        --role=SOURCE \
        --ssl-type=NONE \
        --no-async \
        --quiet

    ok "Created source profile: $SOURCE_PROFILE"
fi

# Display source profile
echo

gcloud database-migration connection-profiles describe \
    "$SOURCE_PROFILE" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format="yaml(name,displayName,state,mysql.host,mysql.port,mysql.username,provider,role)" \
    2>/dev/null || true

# ============================================================
# DESTINATION CONNECTION PROFILE
# ============================================================

step "STEP 12 - Create destination connection profile"

if gcloud database-migration connection-profiles describe \
    "$DEST_PROFILE" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1; then

    ok "Destination profile already exists: $DEST_PROFILE"

else

    gcloud database-migration connection-profiles create mysql \
        "$DEST_PROFILE" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --display-name="$DEST_PROFILE" \
        --cloudsql-instance="$DEST_INSTANCE" \
        --provider=CLOUDSQL \
        --role=DESTINATION \
        --no-async \
        --quiet

    ok "Created destination profile: $DEST_PROFILE"
fi

# ============================================================
# CREATE MIGRATION JOB
# ============================================================

step "STEP 13 - Create one-time migration job"

if gcloud database-migration migration-jobs describe \
    "$MIGRATION_JOB" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1; then

    ok "Migration job already exists: $MIGRATION_JOB"

else

    gcloud database-migration migration-jobs create \
        "$MIGRATION_JOB" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --display-name="$MIGRATION_JOB" \
        --source="$SOURCE_PROFILE" \
        --destination="$DEST_PROFILE" \
        --type=ONE_TIME \
        --static-ip \
        --all-databases \
        --no-async \
        --quiet

    ok "Created migration job: $MIGRATION_JOB"
fi

CURRENT_STATE=$(get_job_state)

info "Migration job state: ${CURRENT_STATE:-UNKNOWN}"

# ============================================================
# FETCH OUTGOING STATIC IPS
# ============================================================

step "STEP 14 - Get Destination outgoing IP addresses"

STATIC_IPS=()

for ATTEMPT in $(seq 1 20); do

    STATIC_JSON=$(
        gcloud database-migration connection-profiles \
            fetch-static-ips "$REGION" \
            --project="$PROJECT_ID" \
            --format=json \
            2>/dev/null ||
        true
    )

    mapfile -t STATIC_IPS < <(
        echo "$STATIC_JSON" |
        jq -r '
            if type == "array" then
                .[]
                | if type == "string"
                  then .
                  else (.staticIp // .ipAddress // .ip // empty)
                  end
            elif .staticIps then
                .staticIps[]
                | if type == "string"
                  then .
                  else (.staticIp // .ipAddress // .ip // empty)
                  end
            else
                empty
            end
        ' 2>/dev/null |
        grep -E \
            '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' |
        sort -u
    )

    if [[ "${#STATIC_IPS[@]}" -gt 0 ]]; then
        break
    fi

    info "Waiting for DMS outgoing IPs... $ATTEMPT/20"

    sleep 5
done

if [[ "${#STATIC_IPS[@]}" -eq 0 ]]; then

    # REST API fallback
    warn "gcloud did not return the static IP list."
    info "Trying Database Migration API..."

    ACCESS_TOKEN=$(gcloud auth print-access-token)

    STATIC_JSON=$(
        curl -sS \
            -H "Authorization: Bearer $ACCESS_TOKEN" \
            "https://datamigration.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}:fetchStaticIps?pageSize=100"
    )

    mapfile -t STATIC_IPS < <(
        echo "$STATIC_JSON" |
        jq -r '.staticIps[]?'
    )
fi

[[ "${#STATIC_IPS[@]}" -eq 0 ]] &&
    fail "Unable to obtain DMS outgoing IP addresses."

echo
echo "${GREEN}${BOLD}Destination outgoing IP addresses:${RESET}"

for IP in "${STATIC_IPS[@]}"; do
    echo "  → $IP"
done

# ============================================================
# ADD IPS TO AWS SECURITY GROUP
# ============================================================

step "STEP 15 - Configure AWS RDS IP allowlist"

for IP in "${STATIC_IPS[@]}"; do

    info "Allow TCP 3306 from $IP/32"

    set +e

    AWS_OUTPUT=$(
        aws ec2 authorize-security-group-ingress \
            --region="$AWS_REGION" \
            --group-id="$AWS_SECURITY_GROUP" \
            --protocol=tcp \
            --port=3306 \
            --cidr="${IP}/32" \
            2>&1
    )

    AWS_RC=$?

    set -e

    if [[ "$AWS_RC" -eq 0 ]]; then

        ok "$IP/32 added."

    elif echo "$AWS_OUTPUT" |
        grep -q "InvalidPermission.Duplicate"; then

        ok "$IP/32 already exists."

    else

        echo
        echo "$AWS_OUTPUT"
        echo

        fail "Failed to update AWS Security Group."
    fi

done

# ============================================================
# VERIFY SECURITY GROUP RULES
# ============================================================

step "STEP 16 - Verify RDS MySQL ingress rules"

aws ec2 describe-security-groups \
    --region="$AWS_REGION" \
    --group-ids="$AWS_SECURITY_GROUP" \
    --query \
    'SecurityGroups[0].IpPermissions[?IpProtocol==`tcp` && FromPort==`3306`].[FromPort,ToPort,IpRanges[].CidrIp]' \
    --output=table || true

ok "AWS RDS IP allowlist configured."

# ============================================================
# DEMOTE DESTINATION
# ============================================================

step "STEP 17 - Prepare existing Cloud SQL destination"

CURRENT_STATE=$(get_job_state)

info "Current state: ${CURRENT_STATE:-UNKNOWN}"

case "$CURRENT_STATE" in

    DRAFT)

        info "Demoting existing Cloud SQL destination..."

        if ! run_dms_action "demote-destination"; then
            fail "Destination demotion failed."
        fi

        ;;

    NOT_STARTED)

        ok "Destination is already prepared."

        ;;

    STARTING|RUNNING|COMPLETED)

        ok "Destination was already prepared."

        ;;

    FAILED)

        warn "Migration job is already in FAILED state."
        warn "$(get_job_error)"

        ;;

    *)

        warn "Unexpected current state: $CURRENT_STATE"

        ;;
esac

# Wait for DMS state to settle
for ATTEMPT in $(seq 1 60); do

    CURRENT_STATE=$(get_job_state)

    case "$CURRENT_STATE" in
        NOT_STARTED|STARTING|RUNNING|COMPLETED|FAILED)
            break
            ;;
    esac

    info "Waiting for destination preparation... state=$CURRENT_STATE"

    sleep 5
done

CURRENT_STATE=$(get_job_state)

ok "Migration job state: $CURRENT_STATE"

# ============================================================
# VERIFY MIGRATION JOB
# ============================================================

step "STEP 18 - Test migration job"

CURRENT_STATE=$(get_job_state)

case "$CURRENT_STATE" in

    NOT_STARTED)

        if ! run_dms_action "verify"; then

            echo
            echo "${RED}${BOLD}Migration verification failed.${RESET}"
            echo
            echo "${YELLOW}Migration Job:${RESET}"
            echo

            gcloud database-migration migration-jobs describe \
                "$MIGRATION_JOB" \
                --region="$REGION" \
                --project="$PROJECT_ID" \
                --format="yaml(state,phase,error)" || true

            exit 1
        fi

        ok "Migration test successful."

        ;;

    STARTING|RUNNING|COMPLETED)

        ok "Migration job has already passed verification."

        ;;

    FAILED)

        warn "Job is FAILED from a previous run."
        warn "The script will try restart after checking connectivity."

        ;;

    *)

        warn "State is $CURRENT_STATE"

        ;;
esac

# ============================================================
# START / RESTART MIGRATION
# ============================================================

step "STEP 19 - Start one-time migration job"

CURRENT_STATE=$(get_job_state)

case "$CURRENT_STATE" in

    COMPLETED)

        ok "Migration already completed."

        ;;

    STARTING|RUNNING)

        ok "Migration is already running."

        ;;

    NOT_STARTED)

        if ! run_dms_action "start"; then
            fail "Unable to start migration job."
        fi

        ok "Migration started."

        ;;

    FAILED)

        warn "Restarting failed migration job..."

        if ! run_dms_action "restart"; then

            fail "Unable to restart migration job."
        fi

        ok "Migration restarted."

        ;;

    *)

        fail "Cannot start migration from state: $CURRENT_STATE"

        ;;
esac

# ============================================================
# WAIT UNTIL COMPLETED
# ============================================================

step "STEP 20 - Wait for migration to complete"

MAX_WAIT=180
WAIT_COUNT=0

while true; do

    CURRENT_STATE=$(get_job_state)
    CURRENT_PHASE=$(get_job_phase)

    printf "${CYAN}➜ State: %-15s Phase: %-20s${RESET}\n" \
        "${CURRENT_STATE:-UNKNOWN}" \
        "${CURRENT_PHASE:-N/A}"

    case "$CURRENT_STATE" in

        COMPLETED)

            echo
            ok "Migration completed successfully!"
            break

            ;;

        FAILED)

            echo
            echo "${RED}${BOLD}Migration FAILED.${RESET}"
            echo

            gcloud database-migration migration-jobs describe \
                "$MIGRATION_JOB" \
                --region="$REGION" \
                --project="$PROJECT_ID" \
                --format="yaml(state,phase,error)"

            exit 1

            ;;
    esac

    WAIT_COUNT=$((WAIT_COUNT + 1))

    if [[ "$WAIT_COUNT" -ge "$MAX_WAIT" ]]; then

        warn "Migration is taking longer than expected."
        warn "Current state: $CURRENT_STATE"
        warn "The migration may still be running."

        break
    fi

    sleep 10
done

# ============================================================
# VERIFY DATABASES
# ============================================================

step "STEP 21 - Verify migrated Cloud SQL databases"

echo

gcloud sql databases list \
    --instance="$DEST_INSTANCE" \
    --project="$PROJECT_ID" \
    --format="table(name)"

echo

DATABASES=$(
    gcloud sql databases list \
        --instance="$DEST_INSTANCE" \
        --project="$PROJECT_ID" \
        --format="value(name)"
)

if echo "$DATABASES" |
    grep -qx "customers_data"; then

    ok "customers_data found."

else

    warn "customers_data has not appeared yet."
fi

if echo "$DATABASES" |
    grep -qx "sales_data"; then

    ok "sales_data found."

else

    warn "sales_data has not appeared yet."
fi

# ============================================================
# CHECK RECORD COUNT
# ============================================================

step "STEP 22 - Verify customers table record count"

SQL_PUBLIC_IP=$(
    gcloud sql instances describe \
        "$DEST_INSTANCE" \
        --project="$PROJECT_ID" \
        --format=json |
    jq -r '
        .ipAddresses[]?
        | select(.type == "PRIMARY")
        | .ipAddress
    ' |
    head -n1
)

if [[ -z "$SQL_PUBLIC_IP" || "$SQL_PUBLIC_IP" == "null" ]]; then

    warn "Cloud SQL Public IP not found."
    warn "Skipping direct MySQL record count check."

else

    ok "Cloud SQL Public IP: $SQL_PUBLIC_IP"

    if ! command -v mysql >/dev/null 2>&1; then

        info "Installing MySQL client..."

        sudo apt-get update -qq

        sudo apt-get install \
            -y default-mysql-client \
            >/dev/null
    fi

    info "Checking customers_data.customers..."

    set +e

    CUSTOMER_COUNT=$(
        MYSQL_PWD="$DEST_DB_PASSWORD" \
        mysql \
            --connect-timeout=15 \
            --get-server-public-key \
            -h "$SQL_PUBLIC_IP" \
            -u "$DEST_DB_USER" \
            -Nse \
            "SELECT COUNT(*) FROM customers_data.customers;" \
            2>/dev/null
    )

    MYSQL_RC=$?

    set -e

    if [[ "$MYSQL_RC" -eq 0 ]]; then

        echo
        info "customers_data.customers = $CUSTOMER_COUNT records"

        if [[ "$CUSTOMER_COUNT" == "5030" ]]; then

            ok "Correct! Expected record count = 5,030."

        else

            warn "Lab expects 5,030 records."
            warn "Current result: $CUSTOMER_COUNT"
        fi

    else

        warn "Direct MySQL connection from Cloud Shell failed."
        warn "This does not necessarily mean the migration failed."
        warn "Database existence was checked in the previous step."
    fi
fi

# ============================================================
# FINAL SUMMARY
# ============================================================

step "FINAL STATUS"

FINAL_STATE=$(get_job_state)

echo
echo "${WHITE}${BOLD}Project${RESET}"
echo "  $PROJECT_ID"
echo
echo "${WHITE}${BOLD}Google Cloud Region${RESET}"
echo "  $REGION"
echo
echo "${WHITE}${BOLD}AWS Region${RESET}"
echo "  $AWS_REGION"
echo
echo "${WHITE}${BOLD}RDS Source${RESET}"
echo "  $RDS_HOST"
echo
echo "${WHITE}${BOLD}RDS IP${RESET}"
echo "  $RDS_IP"
echo
echo "${WHITE}${BOLD}AWS Security Group${RESET}"
echo "  $AWS_SECURITY_GROUP"
echo
echo "${WHITE}${BOLD}Source Profile${RESET}"
echo "  $SOURCE_PROFILE"
echo
echo "${WHITE}${BOLD}Cloud SQL Destination${RESET}"
echo "  $DEST_INSTANCE"
echo
echo "${WHITE}${BOLD}Migration Job${RESET}"
echo "  $MIGRATION_JOB"
echo
echo "${WHITE}${BOLD}Migration State${RESET}"
echo "  $FINAL_STATE"
echo

if [[ "$FINAL_STATE" == "COMPLETED" ]]; then

    echo "${GREEN}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "                                                            "
    echo "               ✓ GSP859 MIGRATION COMPLETE                 "
    echo "                                                            "
    echo "                       ePlus.DEV                            "
    echo "                                                            "
    echo "╚════════════════════════════════════════════════════════════╝"
    echo "${RESET}"

    echo "${GREEN}${BOLD}You can now click all Check my progress buttons.${RESET}"
    echo

else

    echo "${YELLOW}${BOLD}"
    echo "Migration has not reached COMPLETED yet."
    echo "Current state: $FINAL_STATE"
    echo "${RESET}"
fi