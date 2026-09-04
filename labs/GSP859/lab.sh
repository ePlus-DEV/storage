#!/bin/bash

# ============================================================
# GSP859
# Migrating Amazon RDS for MySQL -> Cloud SQL for MySQL
# Database Migration Service
#
# ePlus.DEV Cloud Tutorial
# ============================================================

# IMPORTANT:
# - NO "set -e"
# - NO "exit"
# - Safe to paste directly into Cloud Shell
# - Errors return to terminal instead of closing terminal
# ============================================================

# ------------------------------------------------------------
# COLORS
# ------------------------------------------------------------

RED=$'\033[0;91m'
GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
BLUE=$'\033[0;94m'
MAGENTA=$'\033[0;95m'
CYAN=$'\033[0;96m'
WHITE=$'\033[0;97m'
RESET=$'\033[0m'
BOLD=$'\033[1m'

# ------------------------------------------------------------
# LAB CONSTANTS
# ------------------------------------------------------------

SOURCE_PROFILE="mysql-rds-source"
DEST_PROFILE="mysql-cloudsql-destination"

MIGRATION_JOB="rds-to-cloudsql"
DEST_INSTANCE="mysql-cloudsql"

SOURCE_DB_USER="admin"
SOURCE_DB_PASSWORD="changeme"
SOURCE_DB_PORT="3306"

DEST_DB_USER="root"
DEST_DB_PASSWORD="supersecret"

# ------------------------------------------------------------
# DISPLAY
# ------------------------------------------------------------

header() {

    clear

    echo
    echo "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════╗${RESET}"
    echo "${CYAN}${BOLD}        WELCOME TO ePlus.DEV CLOUD TUTORIAL                 ${RESET}"
    echo "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════╝${RESET}"
    echo
    echo "${MAGENTA}${BOLD} GSP859 - Amazon RDS MySQL → Cloud SQL MySQL${RESET}"
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

error() {
    echo "${RED}${BOLD}✗ $1${RESET}"
}

# ------------------------------------------------------------
# HELPERS
# ------------------------------------------------------------

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
        2>/dev/null
}

get_job_phase() {

    gcloud database-migration migration-jobs describe \
        "$MIGRATION_JOB" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format="value(phase)" \
        2>/dev/null
}

show_job_error() {

    echo

    gcloud database-migration migration-jobs describe \
        "$MIGRATION_JOB" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format="yaml(state,phase,error)" \
        2>/dev/null

    echo
}

# ------------------------------------------------------------
# WAIT DMS OPERATION
# ------------------------------------------------------------

wait_operation() {

    local OP="$1"
    local OP_ID
    local JSON
    local DONE
    local ERR
    local COUNT=0

    if [[ -z "$OP" ]]; then
        warn "Operation ID was not returned."
        sleep 5
        return 0
    fi

    OP_ID="${OP##*/}"

    info "Operation: $OP_ID"

    while true; do

        JSON=$(
            gcloud database-migration operations describe \
                "$OP_ID" \
                --region="$REGION" \
                --project="$PROJECT_ID" \
                --format=json \
                2>/dev/null
        )

        if [[ $? -ne 0 || -z "$JSON" ]]; then

            COUNT=$((COUNT + 1))

            if [[ "$COUNT" -gt 120 ]]; then
                error "Timed out waiting for operation."
                return 1
            fi

            printf "."
            sleep 5
            continue
        fi

        DONE=$(echo "$JSON" | jq -r '.done // false')

        if [[ "$DONE" == "true" ]]; then

            ERR=$(echo "$JSON" | jq -r '.error.message // empty')

            echo

            if [[ -n "$ERR" ]]; then

                error "$ERR"

                return 1
            fi

            ok "Operation completed."

            return 0
        fi

        printf "."

        sleep 5
    done
}

# ------------------------------------------------------------
# DMS ACTION
# ------------------------------------------------------------

run_dms_action() {

    local ACTION="$1"
    local OP

    info "Running DMS action: $ACTION"

    OP=$(
        gcloud database-migration migration-jobs "$ACTION" \
            "$MIGRATION_JOB" \
            --region="$REGION" \
            --project="$PROJECT_ID" \
            --quiet \
            --format="value(name)" \
            2>/tmp/dms_action_error.log
    )

    if [[ $? -ne 0 ]]; then

        echo
        cat /tmp/dms_action_error.log
        echo

        error "DMS action '$ACTION' failed."

        return 1
    fi

    wait_operation "$OP"

    return $?
}

# ============================================================
# MAIN
# ============================================================

main() {

    header

    # ========================================================
    # STEP 1 - USER INPUT
    # ========================================================

    step "STEP 1 - Enter Lab Details"

    echo
    echo "${YELLOW}Copy from the Lab Details panel:${RESET}"
    echo
    echo "  AWS RDS Database - Source"
    echo "  AWS RDS Database Security Group"
    echo "  AWS Access Key ID"
    echo "  AWS Secret Access Key"
    echo
    echo "${GREEN}All pasted values will be VISIBLE.${RESET}"
    echo

    read -r -p "AWS RDS Database - Source        : " RDS_HOST

    read -r -p "AWS RDS Database Security Group : " AWS_SECURITY_GROUP

    read -r -p "AWS Access Key ID               : " AWS_ACCESS_KEY_ID

    read -r -p "AWS Secret Access Key           : " AWS_SECRET_ACCESS_KEY

    echo

    RDS_HOST=$(trim "$RDS_HOST")
    AWS_SECURITY_GROUP=$(trim "$AWS_SECURITY_GROUP")
    AWS_ACCESS_KEY_ID=$(trim "$AWS_ACCESS_KEY_ID")
    AWS_SECRET_ACCESS_KEY=$(trim "$AWS_SECRET_ACCESS_KEY")

    RDS_HOST="${RDS_HOST%.}"

    if [[ -z "$RDS_HOST" ]]; then
        error "RDS Source cannot be empty."
        return 1
    fi

    if [[ -z "$AWS_SECURITY_GROUP" ]]; then
        error "Security Group cannot be empty."
        return 1
    fi

    if [[ -z "$AWS_ACCESS_KEY_ID" ]]; then
        error "AWS Access Key ID cannot be empty."
        return 1
    fi

    if [[ -z "$AWS_SECRET_ACCESS_KEY" ]]; then
        error "AWS Secret Access Key cannot be empty."
        return 1
    fi

    if [[ "$AWS_SECURITY_GROUP" != sg-* ]]; then
        warn "Security Group normally starts with sg-"
    fi

    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY

    unset AWS_SESSION_TOKEN

    echo
    ok "Input received."

    info "RDS Source     : $RDS_HOST"
    info "Security Group : $AWS_SECURITY_GROUP"
    info "Access Key     : $AWS_ACCESS_KEY_ID"
    info "Secret Key     : $AWS_SECRET_ACCESS_KEY"

    # ========================================================
    # STEP 2 - PROJECT
    # ========================================================

    step "STEP 2 - Detect Google Cloud project"

    PROJECT_ID=$(
        gcloud config get-value project 2>/dev/null
    )

    if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then

        PROJECT_ID=$(
            gcloud projects list \
                --filter="lifecycleState=ACTIVE" \
                --format="value(projectId)" \
                --limit=1 \
                2>/dev/null
        )

        if [[ -z "$PROJECT_ID" ]]; then

            error "Unable to detect Project ID."

            return 1
        fi

        gcloud config set project "$PROJECT_ID" >/dev/null 2>&1
    fi

    ok "Project: $PROJECT_ID"

    # ========================================================
    # STEP 3 - CLOUD SQL
    # ========================================================

    step "STEP 3 - Detect Cloud SQL instance"

    gcloud sql instances describe \
        "$DEST_INSTANCE" \
        --project="$PROJECT_ID" \
        >/dev/null 2>&1

    if [[ $? -ne 0 ]]; then

        warn "mysql-cloudsql not found by exact name."

        mapfile -t SQL_INSTANCES < <(
            gcloud sql instances list \
                --project="$PROJECT_ID" \
                --format="value(name)" \
                2>/dev/null
        )

        if [[ "${#SQL_INSTANCES[@]}" -eq 1 ]]; then

            DEST_INSTANCE="${SQL_INSTANCES[0]}"

            warn "Using detected instance: $DEST_INSTANCE"

        else

            echo

            gcloud sql instances list \
                --project="$PROJECT_ID" \
                --format="table(name,region,databaseVersion)"

            echo

            error "Cannot automatically identify Cloud SQL instance."

            return 1
        fi
    fi

    REGION=$(
        gcloud sql instances describe \
            "$DEST_INSTANCE" \
            --project="$PROJECT_ID" \
            --format="value(region)" \
            2>/dev/null
    )

    if [[ -z "$REGION" ]]; then

        error "Unable to detect Cloud SQL region."

        return 1
    fi

    ok "Cloud SQL : $DEST_INSTANCE"
    ok "Region    : $REGION"

    # ========================================================
    # STEP 4 - API
    # ========================================================

    step "STEP 4 - Enable required APIs"

    gcloud services enable \
        datamigration.googleapis.com \
        sqladmin.googleapis.com \
        compute.googleapis.com \
        --project="$PROJECT_ID" \
        --quiet

    if [[ $? -ne 0 ]]; then

        warn "One or more APIs may already be enabled."

    else

        ok "APIs enabled."
    fi

    sleep 5

    # ========================================================
    # STEP 5 - TOOLS
    # ========================================================

    step "STEP 5 - Prepare utilities"

    if ! command -v jq >/dev/null 2>&1; then

        info "Installing jq..."

        sudo apt-get update -qq
        sudo apt-get install -y jq

        if [[ $? -ne 0 ]]; then

            error "Unable to install jq."

            return 1
        fi
    fi

    ok "jq ready."

    if ! command -v dig >/dev/null 2>&1; then

        info "Installing dnsutils..."

        sudo apt-get update -qq
        sudo apt-get install -y dnsutils

        if [[ $? -ne 0 ]]; then

            error "Unable to install dnsutils."

            return 1
        fi
    fi

    ok "dig ready."

    # ========================================================
    # STEP 6 - AWS CLI
    # ========================================================

    step "STEP 6 - Prepare AWS CLI"

    if ! command -v aws >/dev/null 2>&1; then

        info "Installing AWS CLI v2..."

        rm -rf /tmp/aws /tmp/awscliv2.zip

        curl -sS \
            "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
            -o /tmp/awscliv2.zip

        if [[ $? -ne 0 ]]; then

            error "Unable to download AWS CLI."

            return 1
        fi

        if ! command -v unzip >/dev/null 2>&1; then

            sudo apt-get update -qq
            sudo apt-get install -y unzip
        fi

        unzip -q /tmp/awscliv2.zip -d /tmp

        sudo /tmp/aws/install --update

        if [[ $? -ne 0 ]]; then

            error "Unable to install AWS CLI."

            return 1
        fi

        rm -rf /tmp/aws /tmp/awscliv2.zip
    fi

    ok "AWS CLI ready."

    # ========================================================
    # STEP 7 - AWS REGION
    # ========================================================

    step "STEP 7 - Detect AWS region"

    AWS_REGION=$(
        echo "$RDS_HOST" |
        grep -oE \
            '[a-z]{2}-[a-z]+-[0-9]+\.rds\.amazonaws\.com' |
        head -n1 |
        cut -d. -f1
    )

    if [[ -z "$AWS_REGION" ]]; then

        AWS_REGION="us-east-1"

        warn "Cannot detect AWS region from hostname."
        warn "Using lab default: $AWS_REGION"
    fi

    export AWS_DEFAULT_REGION="$AWS_REGION"

    ok "AWS Region: $AWS_REGION"

    # ========================================================
    # STEP 8 - AWS AUTH
    # ========================================================

    step "STEP 8 - Verify AWS credentials"

    AWS_IDENTITY=$(
        aws sts get-caller-identity \
            --region="$AWS_REGION" \
            --query="Account" \
            --output=text \
            2>/tmp/aws_error.log
    )

    if [[ $? -ne 0 ]]; then

        echo
        cat /tmp/aws_error.log
        echo

        error "AWS credential verification failed."
        echo
        warn "Terminal remains open."
        warn "Run the script again and paste the credentials again."

        return 1
    fi

    ok "AWS authentication successful."
    info "AWS Account: $AWS_IDENTITY"

    # ========================================================
    # STEP 9 - SECURITY GROUP
    # ========================================================

    step "STEP 9 - Verify AWS Security Group"

    aws ec2 describe-security-groups \
        --region="$AWS_REGION" \
        --group-ids="$AWS_SECURITY_GROUP" \
        >/dev/null 2>/tmp/sg_error.log

    if [[ $? -ne 0 ]]; then

        echo
        cat /tmp/sg_error.log
        echo

        error "Security Group not found."

        return 1
    fi

    ok "Security Group: $AWS_SECURITY_GROUP"

    # ========================================================
    # STEP 10 - RDS IP
    # ========================================================

    step "STEP 10 - Resolve Amazon RDS IP"

    RDS_IP=""

    for i in $(seq 1 60); do

        RDS_IP=$(
            dig +short A "$RDS_HOST" |
            grep -E \
                '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' |
            tail -n1
        )

        if [[ -n "$RDS_IP" ]]; then
            break
        fi

        info "Waiting for RDS DNS... $i/60"

        sleep 10
    done

    if [[ -z "$RDS_IP" ]]; then

        error "Unable to resolve RDS IP."

        return 1
    fi

    ok "RDS Host : $RDS_HOST"
    ok "RDS IP   : $RDS_IP"

    # ========================================================
    # STEP 11 - SOURCE PROFILE
    # ========================================================

    step "STEP 11 - Create source connection profile"

    gcloud database-migration connection-profiles describe \
        "$SOURCE_PROFILE" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        >/dev/null 2>&1

    if [[ $? -eq 0 ]]; then

        ok "$SOURCE_PROFILE already exists."

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
            --static-ip-connectivity \
            --no-async \
            --quiet

        if [[ $? -ne 0 ]]; then

            error "Failed to create source connection profile."

            return 1
        fi

        ok "Created $SOURCE_PROFILE"
    fi

    # ========================================================
    # STEP 12 - DEST PROFILE
    # ========================================================

    step "STEP 12 - Create destination connection profile"

    gcloud database-migration connection-profiles describe \
        "$DEST_PROFILE" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        >/dev/null 2>&1

    if [[ $? -eq 0 ]]; then

        ok "$DEST_PROFILE already exists."

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

        if [[ $? -ne 0 ]]; then

            error "Failed to create destination profile."

            return 1
        fi

        ok "Created $DEST_PROFILE"
    fi

    # ========================================================
    # STEP 13 - MIGRATION JOB
    # ========================================================

    step "STEP 13 - Create one-time migration job"

    gcloud database-migration migration-jobs describe \
        "$MIGRATION_JOB" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        >/dev/null 2>&1

    if [[ $? -eq 0 ]]; then

        ok "$MIGRATION_JOB already exists."

    else

        gcloud database-migration migration-jobs create \
            "$MIGRATION_JOB" \
            --project="$PROJECT_ID" \
            --region="$REGION" \
            --display-name="$MIGRATION_JOB" \
            --source="$SOURCE_PROFILE" \
            --destination="$DEST_PROFILE" \
            --type=ONE_TIME \
            --no-async \
            --quiet

        if [[ $? -ne 0 ]]; then

            error "Failed to create migration job."

            return 1
        fi

        ok "Created $MIGRATION_JOB"
    fi

    # ========================================================
    # STEP 14 - STATIC IPS
    # ========================================================

    step "STEP 14 - Fetch Destination outgoing IP addresses"

    STATIC_OUTPUT=$(
        gcloud database-migration connection-profiles \
            fetch-static-ips "$REGION" \
            --project="$PROJECT_ID" \
            --format="value(staticIps)" \
            2>/dev/null
    )

    mapfile -t STATIC_IPS < <(
        echo "$STATIC_OUTPUT" |
        tr ';,' '\n' |
        grep -oE \
            '[0-9]{1,3}(\.[0-9]{1,3}){3}' |
        sort -u
    )

    if [[ "${#STATIC_IPS[@]}" -eq 0 ]]; then

        # JSON fallback

        STATIC_JSON=$(
            gcloud database-migration connection-profiles \
                fetch-static-ips "$REGION" \
                --project="$PROJECT_ID" \
                --format=json \
                2>/dev/null
        )

        mapfile -t STATIC_IPS < <(
            echo "$STATIC_JSON" |
            grep -oE \
                '[0-9]{1,3}(\.[0-9]{1,3}){3}' |
            sort -u
        )
    fi

    if [[ "${#STATIC_IPS[@]}" -eq 0 ]]; then

        error "No DMS outgoing IP addresses found."

        return 1
    fi

    echo

    for IP in "${STATIC_IPS[@]}"; do
        echo "${GREEN}  → $IP${RESET}"
    done

    # ========================================================
    # STEP 15 - AWS ALLOWLIST
    # ========================================================

    step "STEP 15 - Configure AWS RDS IP allowlist"

    for IP in "${STATIC_IPS[@]}"; do

        info "TCP 3306 <- $IP/32"

        AWS_RESULT=$(
            aws ec2 authorize-security-group-ingress \
                --region="$AWS_REGION" \
                --group-id="$AWS_SECURITY_GROUP" \
                --protocol=tcp \
                --port=3306 \
                --cidr="${IP}/32" \
                2>&1
        )

        AWS_RC=$?

        if [[ "$AWS_RC" -eq 0 ]]; then

            ok "$IP/32 added."

        elif echo "$AWS_RESULT" |
            grep -q "InvalidPermission.Duplicate"; then

            ok "$IP/32 already exists."

        else

            echo "$AWS_RESULT"

            error "Failed to allow $IP"

            return 1
        fi
    done

    echo

    aws ec2 describe-security-groups \
        --region="$AWS_REGION" \
        --group-ids="$AWS_SECURITY_GROUP" \
        --query \
        'SecurityGroups[0].IpPermissions[?FromPort==`3306`].[FromPort,ToPort,IpRanges[].CidrIp]' \
        --output=table

    # ========================================================
    # STEP 16 - DEMOTE DESTINATION
    # ========================================================

    step "STEP 16 - Prepare existing Cloud SQL destination"

    STATE=$(get_job_state)

    info "Current state: $STATE"

    if [[ "$STATE" == "DRAFT" ]]; then

        info "Demoting Cloud SQL destination..."

        run_dms_action "demote-destination"

        if [[ $? -ne 0 ]]; then

            error "Destination demotion failed."

            return 1
        fi
    else

        ok "Demotion not required for current state: $STATE"
    fi

    # Existing destination must be demoted before starting. Google
    # documents this requirement explicitly. :contentReference[oaicite:1]{index=1}

    # ========================================================
    # STEP 17 - WAIT DESTINATION
    # ========================================================

    step "STEP 17 - Wait for destination preparation"

    for i in $(seq 1 120); do

        STATE=$(get_job_state)

        info "State: $STATE"

        case "$STATE" in

            NOT_STARTED|STARTING|RUNNING|COMPLETED|FAILED)
                break
                ;;
        esac

        sleep 5
    done

    # ========================================================
    # STEP 18 - VERIFY
    # ========================================================

    step "STEP 18 - Test migration job"

    STATE=$(get_job_state)

    if [[ "$STATE" == "NOT_STARTED" ]]; then

        run_dms_action "verify"

        if [[ $? -ne 0 ]]; then

            show_job_error

            error "Migration job verification failed."

            return 1
        fi

        ok "Migration verification passed."

    elif [[ "$STATE" == "RUNNING" ||
            "$STATE" == "STARTING" ||
            "$STATE" == "COMPLETED" ]]; then

        ok "Verification already passed."

    elif [[ "$STATE" == "FAILED" ]]; then

        warn "Job already FAILED."

        show_job_error

    else

        warn "Current state: $STATE"
    fi

    # ========================================================
    # STEP 19 - START
    # ========================================================

    step "STEP 19 - Start migration job"

    STATE=$(get_job_state)

    case "$STATE" in

        NOT_STARTED)

            run_dms_action "start"

            if [[ $? -ne 0 ]]; then

                show_job_error

                error "Failed to start migration."

                return 1
            fi
            ;;

        STARTING|RUNNING)

            ok "Migration already running."
            ;;

        COMPLETED)

            ok "Migration already completed."
            ;;

        FAILED)

            warn "Trying restart..."

            run_dms_action "restart"

            if [[ $? -ne 0 ]]; then

                show_job_error

                error "Migration restart failed."

                return 1
            fi
            ;;

        *)

            error "Unexpected job state: $STATE"

            return 1
            ;;
    esac

    # ========================================================
    # STEP 20 - WAIT COMPLETED
    # ========================================================

    step "STEP 20 - Wait for migration"

    for i in $(seq 1 240); do

        STATE=$(get_job_state)
        PHASE=$(get_job_phase)

        printf "${CYAN}➜ State: %-15s Phase: %s${RESET}\n" \
            "$STATE" \
            "${PHASE:-N/A}"

        if [[ "$STATE" == "COMPLETED" ]]; then

            echo
            ok "Migration completed successfully!"

            break
        fi

        if [[ "$STATE" == "FAILED" ]]; then

            show_job_error

            error "Migration failed."

            return 1
        fi

        sleep 10
    done

    # ========================================================
    # STEP 21 - DATABASES
    # ========================================================

    step "STEP 21 - Check migrated databases"

    gcloud sql databases list \
        --instance="$DEST_INSTANCE" \
        --project="$PROJECT_ID" \
        --format="table(name)"

    DB_LIST=$(
        gcloud sql databases list \
            --instance="$DEST_INSTANCE" \
            --project="$PROJECT_ID" \
            --format="value(name)" \
            2>/dev/null
    )

    if echo "$DB_LIST" | grep -qx "customers_data"; then
        ok "customers_data found."
    else
        warn "customers_data not found yet."
    fi

    if echo "$DB_LIST" | grep -qx "sales_data"; then
        ok "sales_data found."
    else
        warn "sales_data not found yet."
    fi

    # ========================================================
    # STEP 22 - RECORD COUNT
    # ========================================================

    step "STEP 22 - Check customers count"

    SQL_PUBLIC_IP=$(
        gcloud sql instances describe \
            "$DEST_INSTANCE" \
            --project="$PROJECT_ID" \
            --format=json |
        jq -r '
            .ipAddresses[]?
            | select(.type=="PRIMARY")
            | .ipAddress
        ' |
        head -n1
    )

    if [[ -z "$SQL_PUBLIC_IP" ||
          "$SQL_PUBLIC_IP" == "null" ]]; then

        warn "Cloud SQL public IP not found."

    else

        info "Cloud SQL IP: $SQL_PUBLIC_IP"

        if ! command -v mysql >/dev/null 2>&1; then

            info "Installing MySQL client..."

            sudo apt-get update -qq

            sudo apt-get install \
                -y default-mysql-client \
                >/dev/null 2>&1
        fi

        CUSTOMER_COUNT=$(
            MYSQL_PWD="$DEST_DB_PASSWORD" \
            mysql \
                --connect-timeout=10 \
                --get-server-public-key \
                -h "$SQL_PUBLIC_IP" \
                -u "$DEST_DB_USER" \
                -Nse \
                "SELECT COUNT(*) FROM customers_data.customers;" \
                2>/dev/null
        )

        if [[ $? -eq 0 ]]; then

            info "Customer records: $CUSTOMER_COUNT"

            if [[ "$CUSTOMER_COUNT" == "5030" ]]; then

                ok "Correct: 5,030 records."

            else

                warn "Expected: 5,030"
                warn "Actual  : $CUSTOMER_COUNT"
            fi

        else

            warn "Direct MySQL connection failed."
            warn "Migration status is still checked separately."
        fi
    fi

    # ========================================================
    # FINAL
    # ========================================================

    step "FINAL STATUS"

    FINAL_STATE=$(get_job_state)

    echo
    echo "${WHITE}Project        : ${CYAN}$PROJECT_ID${RESET}"
    echo "${WHITE}GCP Region     : ${CYAN}$REGION${RESET}"
    echo "${WHITE}AWS Region     : ${CYAN}$AWS_REGION${RESET}"
    echo "${WHITE}RDS IP         : ${CYAN}$RDS_IP${RESET}"
    echo "${WHITE}Security Group : ${CYAN}$AWS_SECURITY_GROUP${RESET}"
    echo "${WHITE}Source Profile : ${CYAN}$SOURCE_PROFILE${RESET}"
    echo "${WHITE}Destination    : ${CYAN}$DEST_INSTANCE${RESET}"
    echo "${WHITE}Migration Job  : ${CYAN}$MIGRATION_JOB${RESET}"
    echo "${WHITE}State          : ${CYAN}$FINAL_STATE${RESET}"
    echo

    if [[ "$FINAL_STATE" == "COMPLETED" ]]; then

        echo "${GREEN}${BOLD}"
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "               ✓ GSP859 MIGRATION COMPLETE                 "
        echo "                       ePlus.DEV                            "
        echo "╚════════════════════════════════════════════════════════════╝"
        echo "${RESET}"

    else

        warn "Migration has not reached COMPLETED."
    fi

    return 0
}

# ============================================================
# RUN
# ============================================================

main

MAIN_RC=$?

echo

if [[ "$MAIN_RC" -ne 0 ]]; then

    echo "${YELLOW}${BOLD}Script stopped because a step failed.${RESET}"
    echo "${GREEN}${BOLD}Cloud Shell terminal remains open.${RESET}"
    echo
    echo "Fix the value/error above and run the script again."
    echo

else

    echo "${GREEN}${BOLD}Script finished. Terminal remains open.${RESET}"
    echo
fi

# DO NOT EXIT