#!/bin/bash

# ============================================================
# BigQuery Authorized Views Challenge Lab
# CHECK PROGRESS TASKS ONLY
#
# SOURCE SAFE
# © ePlus.DEV
# ============================================================

# ============================================================
# IMPORTANT:
# Everything runs inside a SUBSHELL.
#
# Therefore BOTH commands are safe:
#
#   source lab.sh
#   bash lab.sh
#
# set -e / trap / exit / variables will NOT affect Cloud Shell.
# ============================================================

(

set -Eeuo pipefail

# ============================================================
# COLORS - CLOUD SHELL SAFE
# ============================================================

if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && \
   tput colors >/dev/null 2>&1; then

    RED="$(tput setaf 1)"
    GREEN="$(tput setaf 2)"
    YELLOW="$(tput setaf 3)"
    BLUE="$(tput setaf 4)"
    MAGENTA="$(tput setaf 5)"
    CYAN="$(tput setaf 6)"
    WHITE="$(tput setaf 7)"

    BOLD="$(tput bold)"
    RESET="$(tput sgr0)"

else

    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    MAGENTA=""
    CYAN=""
    WHITE=""

    BOLD=""
    RESET=""

fi

# ============================================================
# LAB CONSTANTS
# NO PROJECT ID HARD-CODED
# ============================================================

PARTNER_DATASET="demo_dataset"

VIEW_A="authorized_view_a"
VIEW_B="authorized_view_b"

CUSTOMER_A_DATASET="customer_a_dataset"
CUSTOMER_A_VIEW="customer_a_table"

CUSTOMER_B_DATASET="customer_b_dataset"
CUSTOMER_B_VIEW="customer_b_table"

# ============================================================
# VARIABLES
# ============================================================

CUSTOMER_A_USER=""
CUSTOMER_B_USER=""

CURRENT_PROJECT=""
CURRENT_ACCOUNT=""

PROJECT_ROLE=""
PARTNER_PROJECT=""

TMP_FILES=()

# ============================================================
# CLEANUP
# ============================================================

cleanup() {

    if [[ ${#TMP_FILES[@]} -gt 0 ]]; then
        rm -f "${TMP_FILES[@]}" 2>/dev/null || true
    fi

    printf "%s" "$RESET" 2>/dev/null || true
}

trap cleanup EXIT

# ============================================================
# ERROR HANDLER
# ============================================================

on_error() {

    local line="$1"
    local code="$2"

    printf "%s" "$RESET"

    echo
    echo "${RED}${BOLD}✗ Script failed at line ${line}.${RESET}"
    echo "${RED}Exit code: ${code}${RESET}"
    echo
    echo "${CYAN}${BOLD}© ePlus.DEV${RESET}"
}

trap 'on_error "$LINENO" "$?"' ERR

# ============================================================
# UI
# ============================================================

banner() {

    echo
    echo "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo "${CYAN}${BOLD}║                                                              ║${RESET}"
    echo "${CYAN}${BOLD}║          BIGQUERY AUTHORIZED VIEWS CHALLENGE LAB             ║${RESET}"
    echo "${CYAN}${BOLD}║                                                              ║${RESET}"
    echo "${CYAN}${BOLD}║                  CHECK PROGRESS ONLY                         ║${RESET}"
    echo "${CYAN}${BOLD}║                                                              ║${RESET}"
    echo "${CYAN}${BOLD}║                      © ePlus.DEV                             ║${RESET}"
    echo "${CYAN}${BOLD}║                                                              ║${RESET}"
    echo "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo
}

step() {

    echo
    echo "${MAGENTA}${BOLD}$1${RESET}"
    echo "${BLUE}${BOLD}==============================================================${RESET}"
}

info() {
    echo "${CYAN}➜ $*${RESET}"
}

ok() {
    echo "${GREEN}${BOLD}✓ $*${RESET}"
}

warn() {
    echo "${YELLOW}${BOLD}⚠ $*${RESET}"
}

fail() {

    echo
    echo "${RED}${BOLD}✗ $*${RESET}"
    exit 1
}

# ============================================================
# COLORED INPUT
# ============================================================

colored_read() {

    local variable="$1"
    local label="$2"
    local value=""

    printf "%s%s%s%s %s>%s " \
        "$YELLOW" \
        "$BOLD" \
        "$label" \
        "$RESET" \
        "$GREEN" \
        "$CYAN"

    IFS= read -r value

    printf "%s" "$RESET"

    printf -v "$variable" '%s' "$value"
}

# ============================================================
# VALIDATION
# ============================================================

valid_email() {

    local email="$1"

    [[ "$email" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]
}

valid_project() {

    local project="$1"

    [[ "$project" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]
}

# ============================================================
# ASK USERS FIRST
#
# NO GCLOUD/BQ BEFORE THIS.
# ============================================================

ask_users() {

    step "ENTER CUSTOMER ACCOUNTS"

    echo "${WHITE}Copy Customer A and Customer B users from the lab panel.${RESET}"

    echo
    echo "${WHITE}Example:${RESET}"
    echo "${CYAN}student-02-xxxxxxxxxxxx@qwiklabs.net${RESET}"
    echo

    # --------------------------------------------------------
    # CUSTOMER A
    # --------------------------------------------------------

    while true; do

        colored_read \
            CUSTOMER_A_USER \
            "Customer A user"

        echo

        if valid_email "$CUSTOMER_A_USER"; then
            break
        fi

        warn "Invalid Customer A email."
        echo

    done

    echo

    # --------------------------------------------------------
    # CUSTOMER B
    # --------------------------------------------------------

    while true; do

        colored_read \
            CUSTOMER_B_USER \
            "Customer B user"

        echo

        if valid_email "$CUSTOMER_B_USER"; then
            break
        fi

        warn "Invalid Customer B email."
        echo

    done

    echo
    echo "${BLUE}--------------------------------------------------------------${RESET}"
    echo "${WHITE}${BOLD}INPUT SUMMARY${RESET}"
    echo "${BLUE}--------------------------------------------------------------${RESET}"

    echo "${WHITE}Customer A : ${CYAN}${BOLD}${CUSTOMER_A_USER}${RESET}"
    echo "${WHITE}Customer B : ${MAGENTA}${BOLD}${CUSTOMER_B_USER}${RESET}"

    echo "${BLUE}--------------------------------------------------------------${RESET}"
}

# ============================================================
# COMMAND CHECK
# ============================================================

require_cmd() {

    command -v "$1" >/dev/null 2>&1 || \
        fail "Required command not found: $1"
}

# ============================================================
# DETECT CURRENT PROJECT
# ============================================================

detect_current_project() {

    step "DETECT GOOGLE CLOUD ENVIRONMENT"

    info "Detecting current project..."

    # Cloud Shell normally provides this instantly.
    CURRENT_PROJECT="${DEVSHELL_PROJECT_ID:-}"

    # Fallback to gcloud config.
    if [[ -z "$CURRENT_PROJECT" ]]; then

        CURRENT_PROJECT="$(
            timeout 10s \
            gcloud config get-value project \
            2>/dev/null || true
        )"

    fi

    # Manual fallback.
    if [[ -z "$CURRENT_PROJECT" || "$CURRENT_PROJECT" == "(unset)" ]]; then

        warn "Unable to detect Project ID automatically."

        echo

        while true; do

            colored_read \
                CURRENT_PROJECT \
                "Current Project ID"

            echo

            if valid_project "$CURRENT_PROJECT"; then
                break
            fi

            warn "Invalid Google Cloud Project ID."
            echo

        done

    fi

    ok "Current project: ${CURRENT_PROJECT}"
}

# ============================================================
# DETECT ACCOUNT
# ============================================================

detect_current_account() {

    CURRENT_ACCOUNT="$(
        timeout 10s \
        gcloud auth list \
            --filter=status:ACTIVE \
            --format='value(account)' \
        2>/dev/null |
        head -n1 || true
    )"

    if [[ -z "$CURRENT_ACCOUNT" ]]; then
        CURRENT_ACCOUNT="unknown"
    fi
}

# ============================================================
# DETECT PROJECT ROLE
#
# ONE bq ls instead of multiple bq show calls.
# ============================================================

detect_project_role() {

    step "DETECT LAB ROLE"

    info "Reading datasets..."

    local datasets_json=""

    if ! datasets_json="$(
        timeout 25s \
        bq \
            --project_id="$CURRENT_PROJECT" \
            --quiet \
            ls \
            --format=prettyjson \
        2>/dev/null
    )"; then

        PROJECT_ROLE="UNKNOWN"

        warn "Unable to detect role automatically."

        return
    fi

    # --------------------------------------------------------
    # PARTNER
    # --------------------------------------------------------

    if jq -e \
        --arg dataset "$PARTNER_DATASET" \
        '
        any(
            .[]?;
            .datasetReference.datasetId == $dataset
        )
        ' \
        <<< "$datasets_json" \
        >/dev/null 2>&1; then

        PROJECT_ROLE="PARTNER"
        PARTNER_PROJECT="$CURRENT_PROJECT"

        ok "Detected Data Sharing Partner."

        return
    fi

    # --------------------------------------------------------
    # CUSTOMER A
    # --------------------------------------------------------

    if jq -e \
        --arg dataset "$CUSTOMER_A_DATASET" \
        '
        any(
            .[]?;
            .datasetReference.datasetId == $dataset
        )
        ' \
        <<< "$datasets_json" \
        >/dev/null 2>&1; then

        PROJECT_ROLE="CUSTOMER_A"

        ok "Detected Customer A."

        return
    fi

    # --------------------------------------------------------
    # CUSTOMER B
    # --------------------------------------------------------

    if jq -e \
        --arg dataset "$CUSTOMER_B_DATASET" \
        '
        any(
            .[]?;
            .datasetReference.datasetId == $dataset
        )
        ' \
        <<< "$datasets_json" \
        >/dev/null 2>&1; then

        PROJECT_ROLE="CUSTOMER_B"

        ok "Detected Customer B."

        return
    fi

    PROJECT_ROLE="UNKNOWN"

    warn "Unable to detect lab role automatically."
}

# ============================================================
# MANUAL ROLE FALLBACK
# ============================================================

ask_project_role() {

    step "SELECT CURRENT PROJECT TYPE"

    echo "${WHITE}Which lab console are you using?${RESET}"

    echo
    echo "  ${CYAN}${BOLD}1${RESET} - Data Sharing Partner"
    echo "  ${CYAN}${BOLD}2${RESET} - Customer A"
    echo "  ${CYAN}${BOLD}3${RESET} - Customer B"
    echo

    local choice=""

    while true; do

        colored_read choice "Select"

        echo

        case "$choice" in

            1)

                PROJECT_ROLE="PARTNER"
                PARTNER_PROJECT="$CURRENT_PROJECT"

                break
                ;;

            2)

                PROJECT_ROLE="CUSTOMER_A"

                break
                ;;

            3)

                PROJECT_ROLE="CUSTOMER_B"

                break
                ;;

            *)

                warn "Please enter 1, 2 or 3."
                echo
                ;;

        esac

    done
}

# ============================================================
# ASK PARTNER PROJECT
# ============================================================

ask_partner_project() {

    step "ENTER DATA SHARING PARTNER PROJECT"

    echo "${WHITE}Copy the Partner Project ID from the lab panel.${RESET}"
    echo

    while true; do

        colored_read \
            PARTNER_PROJECT \
            "Partner Project ID"

        echo

        if valid_project "$PARTNER_PROJECT"; then
            break
        fi

        warn "Invalid Partner Project ID."
        echo

    done

    ok "Partner project: ${PARTNER_PROJECT}"
}

# ============================================================
# GET DATASET LOCATION
# ============================================================

get_dataset_location() {

    local project="$1"
    local dataset="$2"

    local location=""

    location="$(
        timeout 20s \
        bq \
            --project_id="$project" \
            --quiet \
            show \
            --format=prettyjson \
            "$project:$dataset" \
        2>/dev/null |
        jq -r '.location // empty' || true
    )"

    if [[ -z "$location" ]]; then
        location="US"
    fi

    printf "%s" "$location"
}

# ============================================================
# TASK 1
# CREATE AUTHORIZED VIEWS
# ============================================================

task1_create_views() {

    step "[1/4] TASK 1 - CREATE AUTHORIZED VIEWS"

    local location

    location="$(
        get_dataset_location \
            "$CURRENT_PROJECT" \
            "$PARTNER_DATASET"
    )"

    echo "${WHITE}Project  : ${CYAN}${BOLD}${CURRENT_PROJECT}${RESET}"
    echo "${WHITE}Dataset  : ${CYAN}${PARTNER_DATASET}${RESET}"
    echo "${WHITE}Location : ${CYAN}${location}${RESET}"

    # ========================================================
    # VIEW A - TEXAS
    # ========================================================

    echo
    info "Creating ${VIEW_A} for Texas..."

    timeout 120s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        "
        CREATE OR REPLACE VIEW
        \`${CURRENT_PROJECT}.${PARTNER_DATASET}.${VIEW_A}\`
        AS

        SELECT *
        FROM \`bigquery-public-data.geo_us_boundaries.zip_codes\`
        WHERE state_code = 'TX'
        LIMIT 4000
        "

    ok "${VIEW_A} created."

    # ========================================================
    # VIEW B - CALIFORNIA
    # ========================================================

    echo
    info "Creating ${VIEW_B} for California..."

    timeout 120s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        "
        CREATE OR REPLACE VIEW
        \`${CURRENT_PROJECT}.${PARTNER_DATASET}.${VIEW_B}\`
        AS

        SELECT *
        FROM \`bigquery-public-data.geo_us_boundaries.zip_codes\`
        WHERE state_code = 'CA'
        LIMIT 4000
        "

    ok "${VIEW_B} created."

    echo
    ok "TASK 1 COMPLETED"
}

# ============================================================
# TASK 2
# AUTHORIZE VIEW A + VIEW B
# ============================================================

task2_authorize_views() {

    step "[2/4] TASK 2 - AUTHORIZE BOTH VIEWS"

    local current_json
    local updated_json

    current_json="$(mktemp)"
    updated_json="$(mktemp)"

    TMP_FILES+=("$current_json")
    TMP_FILES+=("$updated_json")

    # --------------------------------------------------------
    # READ DATASET ACCESS
    # --------------------------------------------------------

    info "Reading ${PARTNER_DATASET} access list..."

    timeout 30s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        show \
        --format=prettyjson \
        "$CURRENT_PROJECT:$PARTNER_DATASET" \
        > "$current_json"

    # --------------------------------------------------------
    # ADD AUTHORIZED VIEW A/B
    # --------------------------------------------------------

    info "Adding ${VIEW_A} and ${VIEW_B}..."

    jq \
        --arg project "$CURRENT_PROJECT" \
        --arg dataset "$PARTNER_DATASET" \
        --arg view_a "$VIEW_A" \
        --arg view_b "$VIEW_B" \
        '
        .access = (

            [
                (.access // [])[]

                |

                select(

                    (.view == null)

                    or

                    (.view.projectId != $project)

                    or

                    (.view.datasetId != $dataset)

                    or

                    (
                        (.view.tableId != $view_a)
                        and
                        (.view.tableId != $view_b)
                    )
                )
            ]

            +

            [
                {
                    "view": {
                        "projectId": $project,
                        "datasetId": $dataset,
                        "tableId": $view_a
                    }
                },

                {
                    "view": {
                        "projectId": $project,
                        "datasetId": $dataset,
                        "tableId": $view_b
                    }
                }
            ]
        )
        ' \
        "$current_json" \
        > "$updated_json"

    timeout 60s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        update \
        --source="$updated_json" \
        "$CURRENT_PROJECT:$PARTNER_DATASET" \
        >/dev/null

    ok "${VIEW_A} authorized."
    ok "${VIEW_B} authorized."

    echo
    ok "TASK 2 COMPLETED"
}

# ============================================================
# TASK 3
#
# Customer A -> View A
# Customer B -> View B
# ============================================================

task3_grant_users() {

    step "[3/4] TASK 3 - GRANT USERS ACCESS TO VIEWS"

    # ========================================================
    # CUSTOMER A
    # ========================================================

    echo "${WHITE}${BOLD}Customer A${RESET}"
    echo "${WHITE}User : ${CYAN}${BOLD}${CUSTOMER_A_USER}${RESET}"
    echo "${WHITE}View : ${GREEN}${VIEW_A}${RESET}"

    echo
    info "Granting BigQuery Data Viewer..."

    timeout 60s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        add-iam-policy-binding \
        --table=true \
        --member="user:${CUSTOMER_A_USER}" \
        --role="roles/bigquery.dataViewer" \
        "${CURRENT_PROJECT}:${PARTNER_DATASET}.${VIEW_A}" \
        >/dev/null

    ok "Customer A → ${VIEW_A}"

    # ========================================================
    # CUSTOMER B
    # ========================================================

    echo
    echo "${WHITE}${BOLD}Customer B${RESET}"
    echo "${WHITE}User : ${MAGENTA}${BOLD}${CUSTOMER_B_USER}${RESET}"
    echo "${WHITE}View : ${GREEN}${VIEW_B}${RESET}"

    echo
    info "Granting BigQuery Data Viewer..."

    timeout 60s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        add-iam-policy-binding \
        --table=true \
        --member="user:${CUSTOMER_B_USER}" \
        --role="roles/bigquery.dataViewer" \
        "${CURRENT_PROJECT}:${PARTNER_DATASET}.${VIEW_B}" \
        >/dev/null

    ok "Customer B → ${VIEW_B}"

    echo
    ok "TASK 3 COMPLETED"
}

# ============================================================
# VERIFY PARTNER
# ============================================================

verify_partner_tasks() {

    step "VERIFY TASKS 1 - 3"

    # --------------------------------------------------------
    # VIEW A
    # --------------------------------------------------------

    info "Checking ${VIEW_A}..."

    timeout 20s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        show \
        "${CURRENT_PROJECT}:${PARTNER_DATASET}.${VIEW_A}" \
        >/dev/null

    ok "${VIEW_A} exists."

    # --------------------------------------------------------
    # VIEW B
    # --------------------------------------------------------

    info "Checking ${VIEW_B}..."

    timeout 20s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        show \
        "${CURRENT_PROJECT}:${PARTNER_DATASET}.${VIEW_B}" \
        >/dev/null

    ok "${VIEW_B} exists."

    # --------------------------------------------------------
    # ACL
    # --------------------------------------------------------

    info "Checking Authorized View ACL..."

    local count

    count="$(
        timeout 20s \
        bq \
            --project_id="$CURRENT_PROJECT" \
            --quiet \
            show \
            --format=prettyjson \
            "${CURRENT_PROJECT}:${PARTNER_DATASET}" |
        jq \
            --arg project "$CURRENT_PROJECT" \
            --arg dataset "$PARTNER_DATASET" \
            --arg view_a "$VIEW_A" \
            --arg view_b "$VIEW_B" \
            '
            [
                .access[]?

                |

                select(
                    .view.projectId == $project
                    and
                    .view.datasetId == $dataset
                    and
                    (
                        .view.tableId == $view_a
                        or
                        .view.tableId == $view_b
                    )
                )
            ]
            |
            length
            '
    )"

    if [[ "$count" -lt 2 ]]; then
        fail "Authorized View ACL is incomplete."
    fi

    ok "Both Authorized Views verified."

    echo
    echo "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║                    PARTNER COMPLETE                          ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║                       TASK 1 ✓                               ║${RESET}"
    echo "${GREEN}${BOLD}║                       TASK 2 ✓                               ║${RESET}"
    echo "${GREEN}${BOLD}║                       TASK 3 ✓                               ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"

    echo
    echo "${YELLOW}${BOLD}→ Check my progress: Task 1${RESET}"
    echo "${YELLOW}${BOLD}→ Check my progress: Task 2${RESET}"
    echo "${YELLOW}${BOLD}→ Check my progress: Task 3${RESET}"

    echo
    echo "${WHITE}${BOLD}PARTNER PROJECT ID:${RESET}"
    echo "${CYAN}${BOLD}${CURRENT_PROJECT}${RESET}"
}

# ============================================================
# PARTNER
# ============================================================

run_partner() {

    echo
    echo "${GREEN}${BOLD}MODE: DATA SHARING PARTNER${RESET}"

    task1_create_views
    task2_authorize_views
    task3_grant_users
    verify_partner_tasks
}

# ============================================================
# CUSTOMER A
# TASK 4
# ============================================================

run_customer_a() {

    step "[4/4] VERIFY AUTHORIZED VIEW SHARING - CUSTOMER A"

    local location

    location="$(
        get_dataset_location \
            "$CURRENT_PROJECT" \
            "$CUSTOMER_A_DATASET"
    )"

    echo "${WHITE}Customer Project : ${CYAN}${BOLD}${CURRENT_PROJECT}${RESET}"
    echo "${WHITE}Partner Project  : ${MAGENTA}${BOLD}${PARTNER_PROJECT}${RESET}"

    # --------------------------------------------------------
    # ACCESS VIEW A
    # --------------------------------------------------------

    echo
    info "Verifying access to ${VIEW_A}..."

    timeout 120s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        --max_rows=1 \
        "
        SELECT *
        FROM \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_A}\`
        LIMIT 1
        " \
        >/dev/null

    ok "Customer A can query ${VIEW_A}."

    # --------------------------------------------------------
    # CREATE CUSTOMER A VIEW
    # --------------------------------------------------------

    echo
    info "Creating ${CUSTOMER_A_DATASET}.${CUSTOMER_A_VIEW}..."

    timeout 120s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        "
        CREATE OR REPLACE VIEW
        \`${CURRENT_PROJECT}.${CUSTOMER_A_DATASET}.${CUSTOMER_A_VIEW}\`
        AS

        SELECT *
        FROM \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_A}\`
        "

    ok "${CUSTOMER_A_VIEW} created."

    # --------------------------------------------------------
    # VERIFY RESOURCE
    # --------------------------------------------------------

    echo
    info "Verifying ${CUSTOMER_A_VIEW}..."

    timeout 30s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        show \
        "${CURRENT_PROJECT}:${CUSTOMER_A_DATASET}.${CUSTOMER_A_VIEW}" \
        >/dev/null

    ok "${CUSTOMER_A_VIEW} exists."

    # --------------------------------------------------------
    # VIEW B SHOULD BE DENIED
    # --------------------------------------------------------

    echo
    info "Checking Customer A cannot access ${VIEW_B}..."

    local denied_log
    denied_log="$(mktemp)"

    TMP_FILES+=("$denied_log")

    if timeout 60s \
        bq \
            --project_id="$CURRENT_PROJECT" \
            --quiet \
            query \
            --location="$location" \
            --use_legacy_sql=false \
            --max_rows=1 \
            "
            SELECT *
            FROM \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_B}\`
            LIMIT 1
            " \
            >"$denied_log" 2>&1
    then

        warn "Customer A unexpectedly has access to ${VIEW_B}."

    else

        ok "Customer A cannot access ${VIEW_B} as expected."

    fi

    echo
    echo "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo "${GREEN}${BOLD}║                  CUSTOMER A COMPLETE                         ║${RESET}"
    echo "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"

    echo
    echo "${CYAN}${BOLD}NEXT:${RESET}"
    echo "${WHITE}Open Customer B Console and source this script again.${RESET}"
}

# ============================================================
# CUSTOMER B
# TASK 4
# ============================================================

run_customer_b() {

    step "[4/4] VERIFY AUTHORIZED VIEW SHARING - CUSTOMER B"

    local location

    location="$(
        get_dataset_location \
            "$CURRENT_PROJECT" \
            "$CUSTOMER_B_DATASET"
    )"

    echo "${WHITE}Customer Project : ${CYAN}${BOLD}${CURRENT_PROJECT}${RESET}"
    echo "${WHITE}Partner Project  : ${MAGENTA}${BOLD}${PARTNER_PROJECT}${RESET}"

    # --------------------------------------------------------
    # ACCESS VIEW B
    # --------------------------------------------------------

    echo
    info "Verifying access to ${VIEW_B}..."

    timeout 120s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        --max_rows=1 \
        "
        SELECT *
        FROM \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_B}\`
        LIMIT 1
        " \
        >/dev/null

    ok "Customer B can query ${VIEW_B}."

    # --------------------------------------------------------
    # CREATE CUSTOMER B VIEW
    # --------------------------------------------------------

    echo
    info "Creating ${CUSTOMER_B_DATASET}.${CUSTOMER_B_VIEW}..."

    timeout 120s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        "
        CREATE OR REPLACE VIEW
        \`${CURRENT_PROJECT}.${CUSTOMER_B_DATASET}.${CUSTOMER_B_VIEW}\`
        AS

        SELECT *
        FROM \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_B}\`
        "

    ok "${CUSTOMER_B_VIEW} created."

    # --------------------------------------------------------
    # VERIFY RESOURCE
    # --------------------------------------------------------

    echo
    info "Verifying ${CUSTOMER_B_VIEW}..."

    timeout 30s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        show \
        "${CURRENT_PROJECT}:${CUSTOMER_B_DATASET}.${CUSTOMER_B_VIEW}" \
        >/dev/null

    ok "${CUSTOMER_B_VIEW} exists."

    # --------------------------------------------------------
    # VIEW A SHOULD BE DENIED
    # --------------------------------------------------------

    echo
    info "Checking Customer B cannot access ${VIEW_A}..."

    local denied_log
    denied_log="$(mktemp)"

    TMP_FILES+=("$denied_log")

    if timeout 60s \
        bq \
            --project_id="$CURRENT_PROJECT" \
            --quiet \
            query \
            --location="$location" \
            --use_legacy_sql=false \
            --max_rows=1 \
            "
            SELECT *
            FROM \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_A}\`
            LIMIT 1
            " \
            >"$denied_log" 2>&1
    then

        warn "Customer B unexpectedly has access to ${VIEW_A}."

    else

        ok "Customer B cannot access ${VIEW_A} as expected."

    fi

    echo
    echo "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║                  CUSTOMER B COMPLETE                         ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║                       TASK 4 ✓                               ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║                    LAB COMPLETE                              ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"

    echo
    echo "${YELLOW}${BOLD}→ Check my progress: Task 4${RESET}"
}

# ============================================================
# MAIN
# ============================================================

main() {

    banner

    # ========================================================
    # ASK A/B IMMEDIATELY
    # ========================================================

    ask_users

    # ========================================================
    # LOCAL COMMANDS
    # ========================================================

    require_cmd gcloud
    require_cmd bq
    require_cmd jq
    require_cmd timeout

    # ========================================================
    # CLOUD ENVIRONMENT
    # ========================================================

    detect_current_project
    detect_current_account

    echo
    echo "${BLUE}--------------------------------------------------------------${RESET}"
    echo "${WHITE}${BOLD}GOOGLE CLOUD ENVIRONMENT${RESET}"
    echo "${BLUE}--------------------------------------------------------------${RESET}"

    echo "${WHITE}Account : ${CYAN}${BOLD}${CURRENT_ACCOUNT}${RESET}"
    echo "${WHITE}Project : ${GREEN}${BOLD}${CURRENT_PROJECT}${RESET}"

    echo "${BLUE}--------------------------------------------------------------${RESET}"

    # ========================================================
    # ROLE
    # ========================================================

    detect_project_role

    if [[ "$PROJECT_ROLE" == "UNKNOWN" ]]; then
        ask_project_role
    fi

    # ========================================================
    # EXECUTION
    # ========================================================

    case "$PROJECT_ROLE" in

        PARTNER)

            PARTNER_PROJECT="$CURRENT_PROJECT"

            run_partner
            ;;

        CUSTOMER_A)

            echo
            echo "${GREEN}${BOLD}MODE: CUSTOMER A${RESET}"

            ask_partner_project

            run_customer_a
            ;;

        CUSTOMER_B)

            echo
            echo "${GREEN}${BOLD}MODE: CUSTOMER B${RESET}"

            ask_partner_project

            run_customer_b
            ;;

        *)

            fail "Unknown lab project type."
            ;;

    esac

    echo
    echo "${CYAN}${BOLD}==============================================================${RESET}"
    echo "${CYAN}${BOLD}                       © ePlus.DEV                            ${RESET}"
    echo "${CYAN}${BOLD}==============================================================${RESET}"
}

main "$@"

# ============================================================
# END SUBSHELL
# ============================================================

)