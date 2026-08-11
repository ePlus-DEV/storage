#!/bin/bash

# ============================================================
# BigQuery Authorized Views Challenge Lab
# CHECK PROGRESS TASKS ONLY
# SOURCE SAFE
#
# © ePlus.DEV
# ============================================================

(
set -Eeuo pipefail

# ============================================================
# COLORS
# ============================================================

if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    RED="$(tput setaf 1 2>/dev/null || true)"
    GREEN="$(tput setaf 2 2>/dev/null || true)"
    YELLOW="$(tput setaf 3 2>/dev/null || true)"
    BLUE="$(tput setaf 4 2>/dev/null || true)"
    MAGENTA="$(tput setaf 5 2>/dev/null || true)"
    CYAN="$(tput setaf 6 2>/dev/null || true)"
    WHITE="$(tput setaf 7 2>/dev/null || true)"
    BOLD="$(tput bold 2>/dev/null || true)"
    RESET="$(tput sgr0 2>/dev/null || true)"
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
# NO PROJECT IDS ARE HARD-CODED
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
    [[ "$1" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]
}

valid_project() {
    [[ "$1" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]
}

# ============================================================
# REQUIRE COMMAND
# ============================================================

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || \
        fail "Required command not found: $1"
}

# ============================================================
# ASK CUSTOMER USERS FIRST
#
# NO GCLOUD / BQ COMMANDS RUN BEFORE THIS.
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
        colored_read CUSTOMER_A_USER "Customer A user"
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
        colored_read CUSTOMER_B_USER "Customer B user"
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
# DETECT CURRENT PROJECT
# ============================================================

detect_current_project() {
    step "DETECT GOOGLE CLOUD ENVIRONMENT"

    info "Detecting current project..."

    # Cloud Shell normally has this variable.
    CURRENT_PROJECT="${DEVSHELL_PROJECT_ID:-}"

    # Fallback to gcloud configuration.
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
            colored_read CURRENT_PROJECT "Current Project ID"
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

    [[ -n "$CURRENT_ACCOUNT" ]] || CURRENT_ACCOUNT="unknown"
}

# ============================================================
# DETECT LAB ROLE
#
# demo_dataset       = Partner
# customer_a_dataset = Customer A
# customer_b_dataset = Customer B
# ============================================================

detect_project_role() {
    step "DETECT LAB ROLE"

    info "Reading BigQuery datasets..."

    local datasets=""

    if ! datasets="$(
        timeout 25s \
        bq \
            --project_id="$CURRENT_PROJECT" \
            --quiet \
            ls \
            --format=prettyjson \
        2>/dev/null
    )"; then
        PROJECT_ROLE="UNKNOWN"

        warn "Unable to detect lab role automatically."
        return
    fi

    # --------------------------------------------------------
    # PARTNER
    # --------------------------------------------------------

    if jq -e \
        --arg dataset "$PARTNER_DATASET" \
        'any(.[]?; .datasetReference.datasetId == $dataset)' \
        <<< "$datasets" \
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
        'any(.[]?; .datasetReference.datasetId == $dataset)' \
        <<< "$datasets" \
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
        'any(.[]?; .datasetReference.datasetId == $dataset)' \
        <<< "$datasets" \
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

    echo "${WHITE}Which project are you currently using?${RESET}"
    echo
    echo "  ${CYAN}${BOLD}1${RESET}) Data Sharing Partner"
    echo "  ${CYAN}${BOLD}2${RESET}) Customer A"
    echo "  ${CYAN}${BOLD}3${RESET}) Customer B"
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
# PARTNER PROJECT FOR CUSTOMER CONSOLES
#
# Customer A/B accounts cannot reliably discover the separate
# Partner project automatically, so ask for it.
# ============================================================

ask_partner_project() {
    step "ENTER DATA SHARING PARTNER PROJECT"

    echo "${WHITE}Copy the Data Sharing Partner Project ID from the lab panel.${RESET}"
    echo

    while true; do
        colored_read PARTNER_PROJECT "Partner Project ID"
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

get_location() {
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

task1() {
    step "[1/4] TASK 1 - CREATE AUTHORIZED VIEWS"

    local location
    location="$(get_location "$CURRENT_PROJECT" "$PARTNER_DATASET")"

    echo "${WHITE}Project  : ${CYAN}${BOLD}${CURRENT_PROJECT}${RESET}"
    echo "${WHITE}Dataset  : ${CYAN}${PARTNER_DATASET}${RESET}"
    echo "${WHITE}Location : ${CYAN}${location}${RESET}"

    # ========================================================
    # AUTHORIZED VIEW A - TEXAS
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
    # AUTHORIZED VIEW B - CALIFORNIA
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
# AUTHORIZE BOTH VIEWS IN demo_dataset
# ============================================================

task2() {
    step "[2/4] TASK 2 - AUTHORIZE BOTH VIEWS"

    local source_json
    local update_json

    source_json="$(mktemp)"
    update_json="$(mktemp)"

    TMP_FILES+=("$source_json" "$update_json")

    # --------------------------------------------------------
    # READ CURRENT ACL
    # --------------------------------------------------------

    info "Reading ${PARTNER_DATASET} access list..."

    timeout 30s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        show \
        --format=prettyjson \
        "$CURRENT_PROJECT:$PARTNER_DATASET" \
        > "$source_json"

    # --------------------------------------------------------
    # BUILD MINIMAL UPDATE JSON
    #
    # Preserve existing access entries, remove duplicate
    # View A/B entries, then add the correct ones.
    # --------------------------------------------------------

    info "Adding ${VIEW_A} and ${VIEW_B} as Authorized Views..."

    jq \
        --arg project "$CURRENT_PROJECT" \
        --arg dataset "$PARTNER_DATASET" \
        --arg view_a "$VIEW_A" \
        --arg view_b "$VIEW_B" \
        '
        {
            "access":
            (
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
                            .view.tableId != $view_a
                            and
                            .view.tableId != $view_b
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
        }
        ' \
        "$source_json" \
        > "$update_json"

    # --------------------------------------------------------
    # UPDATE DATASET ACL
    # --------------------------------------------------------

    timeout 60s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        update \
        --source="$update_json" \
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
# Customer A -> authorized_view_a
# Customer B -> authorized_view_b
# ============================================================

task3() {
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
# VERIFY TASKS 1 - 3
# ============================================================

verify_partner() {
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
    # AUTHORIZED VIEW ACL
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
            "$CURRENT_PROJECT:$PARTNER_DATASET" |
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
    echo "${GREEN}${BOLD}║                   PARTNER COMPLETE                           ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║                     TASK 1 ✓                                 ║${RESET}"
    echo "${GREEN}${BOLD}║                     TASK 2 ✓                                 ║${RESET}"
    echo "${GREEN}${BOLD}║                     TASK 3 ✓                                 ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"

    echo
    echo "${YELLOW}${BOLD}→ Check my progress: Task 1${RESET}"
    echo "${YELLOW}${BOLD}→ Check my progress: Task 2${RESET}"
    echo "${YELLOW}${BOLD}→ Check my progress: Task 3${RESET}"

    echo
    echo "${WHITE}${BOLD}SAVE PARTNER PROJECT ID:${RESET}"
    echo "${CYAN}${BOLD}${CURRENT_PROJECT}${RESET}"

    echo
    echo "${WHITE}Customer A/B will ask for this Project ID.${RESET}"
}

# ============================================================
# RUN PARTNER
# ============================================================

run_partner() {
    echo
    echo "${GREEN}${BOLD}MODE: DATA SHARING PARTNER${RESET}"

    task1
    task2
    task3
    verify_partner
}

# ============================================================
# TASK 4 - CUSTOMER A
#
# 1. Query authorized_view_a
# 2. Save as customer_a_table
# 3. JOIN customer_info with authorized_view_a
# 4. Confirm authorized_view_b gives Access Denied
# ============================================================

run_customer_a() {
    step "[4/4] VERIFY AUTHORIZED VIEW SHARING - CUSTOMER A"

    local location
    local denied_log

    location="$(
        get_location \
            "$CURRENT_PROJECT" \
            "$CUSTOMER_A_DATASET"
    )"

    echo "${WHITE}Customer Project : ${CYAN}${BOLD}${CURRENT_PROJECT}${RESET}"
    echo "${WHITE}Partner Project  : ${MAGENTA}${BOLD}${PARTNER_PROJECT}${RESET}"
    echo "${WHITE}Dataset          : ${CYAN}${CUSTOMER_A_DATASET}${RESET}"

    # ========================================================
    # TASK 4 - CUSTOMER A - STEP 3
    #
    # SELECT * FROM Partner.demo_dataset.authorized_view_a
    # ========================================================

    echo
    info "[A-1/4] Querying ${VIEW_A}..."

    timeout 120s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        --max_rows=5 \
        "
        SELECT *
        FROM \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_A}\`
        LIMIT 5
        "

    ok "Customer A can query ${VIEW_A}."

    # ========================================================
    # TASK 4 - CUSTOMER A - STEPS 4-7
    #
    # Save > Save View
    #
    # Dataset = customer_a_dataset
    # Table   = customer_a_table
    # ========================================================

    echo
    info "[A-2/4] Creating ${CUSTOMER_A_DATASET}.${CUSTOMER_A_VIEW}..."

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

    ok "${CUSTOMER_A_DATASET}.${CUSTOMER_A_VIEW} created."

    # --------------------------------------------------------
    # VERIFY VIEW EXISTS
    # --------------------------------------------------------

    info "Verifying ${CUSTOMER_A_VIEW}..."

    timeout 30s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        show \
        "${CURRENT_PROJECT}:${CUSTOMER_A_DATASET}.${CUSTOMER_A_VIEW}" \
        >/dev/null

    ok "${CUSTOMER_A_VIEW} verified."

    # ========================================================
    # TASK 4 - CUSTOMER A - STEP 8
    #
    # JOIN customer_info + authorized_view_a
    # ========================================================

    echo
    info "[A-3/4] Joining Customer A data with Texas geographic data..."

    timeout 120s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        --max_rows=10 \
        "
        SELECT
            geos.zip_code,
            geos.city,
            cust.last_name,
            cust.first_name
        FROM
            \`${CURRENT_PROJECT}.${CUSTOMER_A_DATASET}.customer_info\` AS cust
        JOIN
            \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_A}\` AS geos
        ON
            geos.zip_code = cust.postal_code
        "

    ok "Customer A JOIN query completed."

    # ========================================================
    # TASK 4 - CUSTOMER A - STEP 9
    #
    # authorized_view_b MUST return Access Denied
    # ========================================================

    echo
    info "[A-4/4] Confirming Customer A cannot query ${VIEW_B}..."

    denied_log="$(mktemp)"
    TMP_FILES+=("$denied_log")

    if timeout 60s \
        bq \
            --project_id="$CURRENT_PROJECT" \
            --quiet \
            query \
            --location="$location" \
            --use_legacy_sql=false \
            "
            SELECT *
            FROM \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_B}\`
            " \
            >"$denied_log" 2>&1
    then
        fail "Customer A unexpectedly CAN query ${VIEW_B}."
    else
        ok "Access Denied received as expected."
        ok "Customer A can only access ${VIEW_A}."
    fi

    echo
    echo "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║                  CUSTOMER A COMPLETE ✓                       ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"

    echo
    echo "${CYAN}${BOLD}NEXT STEP:${RESET}"
    echo "${WHITE}Close Customer A Console.${RESET}"
    echo "${WHITE}Open Customer B Console and run:${RESET}"
    echo
    echo "${GREEN}${BOLD}source lab.sh${RESET}"
}

# ============================================================
# TASK 4 - CUSTOMER B
#
# 1. Query authorized_view_b
# 2. Save as customer_b_table
# 3. JOIN customer_info with authorized_view_b
# 4. Confirm authorized_view_a gives Access Denied
# ============================================================

run_customer_b() {
    step "[4/4] VERIFY AUTHORIZED VIEW SHARING - CUSTOMER B"

    local location
    local denied_log

    location="$(
        get_location \
            "$CURRENT_PROJECT" \
            "$CUSTOMER_B_DATASET"
    )"

    echo "${WHITE}Customer Project : ${CYAN}${BOLD}${CURRENT_PROJECT}${RESET}"
    echo "${WHITE}Partner Project  : ${MAGENTA}${BOLD}${PARTNER_PROJECT}${RESET}"
    echo "${WHITE}Dataset          : ${CYAN}${CUSTOMER_B_DATASET}${RESET}"

    # ========================================================
    # TASK 4 - CUSTOMER B - STEP 3
    #
    # SELECT * FROM Partner.demo_dataset.authorized_view_b
    # ========================================================

    echo
    info "[B-1/4] Querying ${VIEW_B}..."

    timeout 120s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        --max_rows=5 \
        "
        SELECT *
        FROM \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_B}\`
        LIMIT 5
        "

    ok "Customer B can query ${VIEW_B}."

    # ========================================================
    # TASK 4 - CUSTOMER B - STEPS 4-7
    #
    # Save > Save View
    #
    # Dataset = customer_b_dataset
    # Table   = customer_b_table
    # ========================================================

    echo
    info "[B-2/4] Creating ${CUSTOMER_B_DATASET}.${CUSTOMER_B_VIEW}..."

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

    ok "${CUSTOMER_B_DATASET}.${CUSTOMER_B_VIEW} created."

    # --------------------------------------------------------
    # VERIFY VIEW EXISTS
    # --------------------------------------------------------

    info "Verifying ${CUSTOMER_B_VIEW}..."

    timeout 30s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        show \
        "${CURRENT_PROJECT}:${CUSTOMER_B_DATASET}.${CUSTOMER_B_VIEW}" \
        >/dev/null

    ok "${CUSTOMER_B_VIEW} verified."

    # ========================================================
    # TASK 4 - CUSTOMER B - STEP 8
    #
    # JOIN customer_info + authorized_view_b
    # ========================================================

    echo
    info "[B-3/4] Joining Customer B data with California geographic data..."

    timeout 120s \
    bq \
        --project_id="$CURRENT_PROJECT" \
        --quiet \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        --max_rows=10 \
        "
        SELECT
            geos.zip_code,
            geos.city,
            cust.last_name,
            cust.first_name
        FROM
            \`${CURRENT_PROJECT}.${CUSTOMER_B_DATASET}.customer_info\` AS cust
        JOIN
            \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_B}\` AS geos
        ON
            geos.zip_code = cust.postal_code
        "

    ok "Customer B JOIN query completed."

    # ========================================================
    # TASK 4 - CUSTOMER B - STEP 9
    #
    # authorized_view_a MUST return Access Denied
    # ========================================================

    echo
    info "[B-4/4] Confirming Customer B cannot query ${VIEW_A}..."

    denied_log="$(mktemp)"
    TMP_FILES+=("$denied_log")

    if timeout 60s \
        bq \
            --project_id="$CURRENT_PROJECT" \
            --quiet \
            query \
            --location="$location" \
            --use_legacy_sql=false \
            "
            SELECT *
            FROM \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_A}\`
            " \
            >"$denied_log" 2>&1
    then
        fail "Customer B unexpectedly CAN query ${VIEW_A}."
    else
        ok "Access Denied received as expected."
        ok "Customer B can only access ${VIEW_B}."
    fi

    echo
    echo "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║                  CUSTOMER B COMPLETE ✓                       ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║                       TASK 4 ✓                               ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║                    LAB COMPLETE                              ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"

    echo
    echo "${YELLOW}${BOLD}→ Click Check my progress: Task 4${RESET}"
}

# ============================================================
# MAIN
# ============================================================

main() {
    banner

    # ========================================================
    # USER INPUT FIRST
    #
    # NO NETWORK CALLS BEFORE THIS.
    # ========================================================

    ask_users

    # ========================================================
    # CHECK LOCAL COMMANDS
    # ========================================================

    require_cmd gcloud
    require_cmd bq
    require_cmd jq
    require_cmd timeout

    # ========================================================
    # DETECT CLOUD ENVIRONMENT
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
    # DETECT LAB ROLE
    # ========================================================

    detect_project_role

    if [[ "$PROJECT_ROLE" == "UNKNOWN" ]]; then
        ask_project_role
    fi

    # ========================================================
    # RUN CORRECT TASKS
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

)