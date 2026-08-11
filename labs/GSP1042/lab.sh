#!/bin/bash

# ============================================================
# BigQuery Authorized Views + Looker Studio Lab
# ONE TERMINAL - ONE SOURCE
#
# Tasks 1 → 5 (BigQuery resources)
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
# CONSTANTS
# NO PROJECT ID HARD-CODED
# ============================================================

PARTNER_DATASET="demo_dataset"

VIEW_A="authorized_view_a"
VIEW_B="authorized_view_b"

CUSTOMER_A_DATASET="customer_a_dataset"
CUSTOMER_A_TABLE="customer_a_table"

CUSTOMER_B_DATASET="customer_b_dataset"
CUSTOMER_B_TABLE="customer_b_table"

CUSTOMER_INFO="customer_info"

# ============================================================
# VARIABLES
# ============================================================

CUSTOMER_A_USER=""
CUSTOMER_B_USER=""

PARTNER_ACCOUNT=""
PARTNER_PROJECT=""

CUSTOMER_A_PROJECT=""
CUSTOMER_B_PROJECT=""

ORIGINAL_ACCOUNT=""
ORIGINAL_PROJECT=""

TMP_FILES=()

# ============================================================
# CLEANUP
# ============================================================

cleanup() {
    if [[ ${#TMP_FILES[@]} -gt 0 ]]; then
        rm -f "${TMP_FILES[@]}" 2>/dev/null || true
    fi

    # Restore Partner account
    if [[ -n "$ORIGINAL_ACCOUNT" ]]; then
        gcloud config set account \
            "$ORIGINAL_ACCOUNT" \
            --quiet \
            >/dev/null 2>&1 || true
    fi

    # Restore Partner project
    if [[ -n "$ORIGINAL_PROJECT" && "$ORIGINAL_PROJECT" != "(unset)" ]]; then
        gcloud config set project \
            "$ORIGINAL_PROJECT" \
            --quiet \
            >/dev/null 2>&1 || true
    fi

    printf "%s" "$RESET" 2>/dev/null || true
}

trap cleanup EXIT
trap 'exit 130' INT TERM

# ============================================================
# UI
# ============================================================

banner() {
    echo
    echo "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo "${CYAN}${BOLD}║                                                              ║${RESET}"
    echo "${CYAN}${BOLD}║          BIGQUERY AUTHORIZED VIEWS CHALLENGE LAB             ║${RESET}"
    echo "${CYAN}${BOLD}║                                                              ║${RESET}"
    echo "${CYAN}${BOLD}║                ONE TERMINAL • TASK 1 → 5                     ║${RESET}"
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

valid_email() {
    [[ "$1" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]
}

valid_project() {
    [[ "$1" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || \
        fail "Required command not found: $1"
}

# ============================================================
# ASK CUSTOMER USERS IMMEDIATELY
# ============================================================

ask_users() {
    step "ENTER CUSTOMER ACCOUNTS"

    echo "${WHITE}Copy Customer A and Customer B usernames from the lab panel.${RESET}"
    echo
    echo "${WHITE}Example:${RESET}"
    echo "${CYAN}student-02-xxxxxxxxxxxx@qwiklabs.net${RESET}"
    echo

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
# CURRENT GCLOUD CONTEXT
# ============================================================

get_active_account() {
    gcloud auth list \
        --filter=status:ACTIVE \
        --format='value(account)' \
        2>/dev/null |
    head -n1
}

get_config_project() {
    local value

    value="$(
        gcloud config get-value project \
            2>/dev/null || true
    )"

    [[ "$value" != "(unset)" ]] || value=""

    printf "%s" "$value"
}

# ============================================================
# DATASET HELPERS
# ============================================================

dataset_exists() {
    local project="$1"
    local dataset="$2"

    timeout 20s \
    bq \
        --quiet \
        --project_id="$project" \
        show \
        "$project:$dataset" \
        >/dev/null 2>&1
}

get_location() {
    local project="$1"
    local dataset="$2"
    local location=""

    location="$(
        timeout 20s \
        bq \
            --quiet \
            --project_id="$project" \
            show \
            --format=prettyjson \
            "$project:$dataset" \
        2>/dev/null |
        jq -r '.location // empty' \
        || true
    )"

    [[ -n "$location" ]] || location="US"

    printf "%s" "$location"
}

# ============================================================
# SWITCH ACCOUNT / PROJECT
# ============================================================

switch_context() {
    local account="$1"
    local project="$2"

    info "Activating account: ${account}"

    gcloud config set account \
        "$account" \
        --quiet \
        >/dev/null

    info "Setting project: ${project}"

    gcloud config set project \
        "$project" \
        --quiet \
        >/dev/null

    ok "Account : ${account}"
    ok "Project : ${project}"
}

# ============================================================
# LOGIN CUSTOMER ACCOUNT IN SAME CLOUD SHELL
# ============================================================

ensure_login() {
    local account="$1"
    local label="$2"

    step "LOGIN - ${label}"

    if \
        gcloud auth list \
            --format='value(account)' \
            2>/dev/null |
        grep -Fxq "$account" \
        &&
        gcloud auth print-access-token \
            --account="$account" \
            >/dev/null 2>&1
    then
        ok "Existing credential found."
        ok "$account"
    else
        echo "${WHITE}Login required for:${RESET}"
        echo
        echo "${CYAN}${BOLD}${account}${RESET}"
        echo
        echo "${YELLOW}${BOLD}A Google authorization URL will appear below.${RESET}"
        echo
        echo "${WHITE}Open the URL → login with ${CYAN}${account}${RESET}"
        echo "${WHITE}using the temporary Qwiklabs password.${RESET}"
        echo

        gcloud auth login \
            "$account" \
            --no-launch-browser \
            --force \
            --quiet
    fi

    gcloud config set account \
        "$account" \
        --quiet \
        >/dev/null

    if [[ "$(get_active_account)" != "$account" ]]; then
        fail "Could not activate ${account}."
    fi

    echo
    ok "${label} authenticated."
}

# ============================================================
# FIND PROJECT CONTAINING DATASET
# ============================================================

find_project_with_dataset() {
    local account="$1"
    local dataset="$2"
    local variable="$3"
    local label="$4"

    local projects=""
    local project=""
    local found=""

    step "DETECT ${label} PROJECT"

    info "Searching projects available to ${account}..."

    projects="$(
        timeout 30s \
        gcloud projects list \
            --account="$account" \
            --format='value(projectId)' \
        2>/dev/null || true
    )"

    while IFS= read -r project; do
        [[ -n "$project" ]] || continue

        info "Checking ${project}..."

        if dataset_exists "$project" "$dataset"; then
            found="$project"
            break
        fi
    done <<< "$projects"

    if [[ -z "$found" ]]; then
        warn "Could not detect ${label} Project automatically."
        echo

        while true; do
            colored_read found "${label} Project ID"
            echo

            if ! valid_project "$found"; then
                warn "Invalid Project ID."
                echo
                continue
            fi

            if dataset_exists "$found" "$dataset"; then
                break
            fi

            warn "${dataset} not found in ${found}."
            echo
        done
    fi

    printf -v "$variable" '%s' "$found"

    ok "${label} Project: ${found}"
}

# ============================================================
# TASK 1
# CREATE AUTHORIZED VIEW A + B
# ============================================================

task1() {
    step "[1/5] TASK 1 - CREATE AUTHORIZED VIEWS"

    local location

    location="$(
        get_location \
            "$PARTNER_PROJECT" \
            "$PARTNER_DATASET"
    )"

    echo "${WHITE}Partner Project : ${CYAN}${PARTNER_PROJECT}${RESET}"
    echo "${WHITE}Dataset         : ${CYAN}${PARTNER_DATASET}${RESET}"
    echo "${WHITE}Location        : ${CYAN}${location}${RESET}"

    # --------------------------------------------------------
    # View A = Texas
    # --------------------------------------------------------

    echo
    info "Creating ${VIEW_A} - Texas..."

    timeout 120s \
    bq \
        --quiet \
        --project_id="$PARTNER_PROJECT" \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        "
        CREATE OR REPLACE VIEW
        \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_A}\`
        AS

        SELECT *
        FROM \`bigquery-public-data.geo_us_boundaries.zip_codes\`
        WHERE state_code = 'TX'
        LIMIT 4000
        "

    ok "${VIEW_A} created."

    # --------------------------------------------------------
    # View B = California
    # --------------------------------------------------------

    echo
    info "Creating ${VIEW_B} - California..."

    timeout 120s \
    bq \
        --quiet \
        --project_id="$PARTNER_PROJECT" \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        "
        CREATE OR REPLACE VIEW
        \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_B}\`
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
# AUTHORIZE VIEW A + B
# ============================================================

task2() {
    step "[2/5] TASK 2 - AUTHORIZE BOTH VIEWS"

    local before
    local after

    before="$(mktemp)"
    after="$(mktemp)"

    TMP_FILES+=("$before" "$after")

    info "Reading current ${PARTNER_DATASET} ACL..."

    timeout 30s \
    bq \
        --quiet \
        --project_id="$PARTNER_PROJECT" \
        show \
        --format=prettyjson \
        "$PARTNER_PROJECT:$PARTNER_DATASET" \
        > "$before"

    info "Adding Authorized View A + B..."

    jq \
        --arg project "$PARTNER_PROJECT" \
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
        "$before" \
        > "$after"

    timeout 60s \
    bq \
        --quiet \
        --project_id="$PARTNER_PROJECT" \
        update \
        --source="$after" \
        "$PARTNER_PROJECT:$PARTNER_DATASET" \
        >/dev/null

    ok "${VIEW_A} authorized."
    ok "${VIEW_B} authorized."

    echo
    ok "TASK 2 COMPLETED"
}

# ============================================================
# TASK 3
# GRANT CUSTOMER USERS BIGQUERY DATA VIEWER
# ============================================================

task3() {
    step "[3/5] TASK 3 - GRANT VIEW PERMISSIONS"

    echo "${WHITE}${BOLD}Customer A${RESET}"
    echo "${WHITE}User : ${CYAN}${CUSTOMER_A_USER}${RESET}"
    echo "${WHITE}View : ${GREEN}${VIEW_A}${RESET}"

    echo
    info "Granting BigQuery Data Viewer..."

    timeout 60s \
    bq \
        --quiet \
        --project_id="$PARTNER_PROJECT" \
        add-iam-policy-binding \
        --table=true \
        --member="user:${CUSTOMER_A_USER}" \
        --role="roles/bigquery.dataViewer" \
        "${PARTNER_PROJECT}:${PARTNER_DATASET}.${VIEW_A}" \
        >/dev/null

    ok "Customer A → ${VIEW_A}"

    echo
    echo "${WHITE}${BOLD}Customer B${RESET}"
    echo "${WHITE}User : ${MAGENTA}${CUSTOMER_B_USER}${RESET}"
    echo "${WHITE}View : ${GREEN}${VIEW_B}${RESET}"

    echo
    info "Granting BigQuery Data Viewer..."

    timeout 60s \
    bq \
        --quiet \
        --project_id="$PARTNER_PROJECT" \
        add-iam-policy-binding \
        --table=true \
        --member="user:${CUSTOMER_B_USER}" \
        --role="roles/bigquery.dataViewer" \
        "${PARTNER_PROJECT}:${PARTNER_DATASET}.${VIEW_B}" \
        >/dev/null

    ok "Customer B → ${VIEW_B}"

    echo
    ok "TASK 3 COMPLETED"
}

# ============================================================
# TASK 4
# CUSTOMER A
#
# IMPORTANT:
# customer_a_table MUST contain the JOIN query.
# ============================================================

task4_customer_a() {
    step "[4/5] TASK 4 - DISPLAY INSIGHTS FOR VIEW A"

    local location

    location="$(
        get_location \
            "$CUSTOMER_A_PROJECT" \
            "$CUSTOMER_A_DATASET"
    )"

    echo "${WHITE}Account          : ${CYAN}${CUSTOMER_A_USER}${RESET}"
    echo "${WHITE}Customer Project : ${CYAN}${CUSTOMER_A_PROJECT}${RESET}"
    echo "${WHITE}Partner Project  : ${MAGENTA}${PARTNER_PROJECT}${RESET}"

    # --------------------------------------------------------
    # Run JOIN query as required in lab
    # --------------------------------------------------------

    echo
    info "Running Customer A Texas JOIN..."

    timeout 120s \
    bq \
        --quiet \
        --project_id="$CUSTOMER_A_PROJECT" \
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
            \`${CUSTOMER_A_PROJECT}.${CUSTOMER_A_DATASET}.${CUSTOMER_INFO}\` AS cust
        JOIN
            \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_A}\` AS geos
        ON
            geos.zip_code = cust.postal_code;
        "

    ok "Customer A JOIN query successful."

    # --------------------------------------------------------
    # SAVE VIEW equivalent
    #
    # customer_a_table = JOIN QUERY
    # --------------------------------------------------------

    echo
    info "Saving JOIN as ${CUSTOMER_A_DATASET}.${CUSTOMER_A_TABLE}..."

    timeout 120s \
    bq \
        --quiet \
        --project_id="$CUSTOMER_A_PROJECT" \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        "
        CREATE OR REPLACE VIEW
        \`${CUSTOMER_A_PROJECT}.${CUSTOMER_A_DATASET}.${CUSTOMER_A_TABLE}\`
        AS

        SELECT
            geos.zip_code,
            geos.city,
            cust.last_name,
            cust.first_name
        FROM
            \`${CUSTOMER_A_PROJECT}.${CUSTOMER_A_DATASET}.${CUSTOMER_INFO}\` AS cust
        JOIN
            \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_A}\` AS geos
        ON
            geos.zip_code = cust.postal_code
        "

    # --------------------------------------------------------
    # Verify
    # --------------------------------------------------------

    timeout 30s \
    bq \
        --quiet \
        --project_id="$CUSTOMER_A_PROJECT" \
        show \
        "${CUSTOMER_A_PROJECT}:${CUSTOMER_A_DATASET}.${CUSTOMER_A_TABLE}" \
        >/dev/null

    ok "${CUSTOMER_A_TABLE} created."

    echo
    info "Testing saved view..."

    timeout 60s \
    bq \
        --quiet \
        --project_id="$CUSTOMER_A_PROJECT" \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        --max_rows=5 \
        "
        SELECT *
        FROM \`${CUSTOMER_A_PROJECT}.${CUSTOMER_A_DATASET}.${CUSTOMER_A_TABLE}\`
        LIMIT 5
        " \
        >/dev/null

    ok "${CUSTOMER_A_TABLE} query successful."

    echo
    ok "TASK 4 BIGQUERY SECTION COMPLETED"
}

# ============================================================
# TASK 5
# CUSTOMER B
#
# IMPORTANT:
# customer_b_table MUST contain the JOIN query.
# ============================================================

task5_customer_b() {
    step "[5/5] TASK 5 - DISPLAY INSIGHTS FOR VIEW B"

    local location

    location="$(
        get_location \
            "$CUSTOMER_B_PROJECT" \
            "$CUSTOMER_B_DATASET"
    )"

    echo "${WHITE}Account          : ${MAGENTA}${CUSTOMER_B_USER}${RESET}"
    echo "${WHITE}Customer Project : ${CYAN}${CUSTOMER_B_PROJECT}${RESET}"
    echo "${WHITE}Partner Project  : ${MAGENTA}${PARTNER_PROJECT}${RESET}"

    # --------------------------------------------------------
    # Run JOIN query required by lab
    # --------------------------------------------------------

    echo
    info "Running Customer B California JOIN..."

    timeout 120s \
    bq \
        --quiet \
        --project_id="$CUSTOMER_B_PROJECT" \
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
            \`${CUSTOMER_B_PROJECT}.${CUSTOMER_B_DATASET}.${CUSTOMER_INFO}\` AS cust
        JOIN
            \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_B}\` AS geos
        ON
            geos.zip_code = cust.postal_code;
        "

    ok "Customer B JOIN query successful."

    # --------------------------------------------------------
    # SAVE VIEW equivalent
    #
    # customer_b_table = JOIN QUERY
    # --------------------------------------------------------

    echo
    info "Saving JOIN as ${CUSTOMER_B_DATASET}.${CUSTOMER_B_TABLE}..."

    timeout 120s \
    bq \
        --quiet \
        --project_id="$CUSTOMER_B_PROJECT" \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        "
        CREATE OR REPLACE VIEW
        \`${CUSTOMER_B_PROJECT}.${CUSTOMER_B_DATASET}.${CUSTOMER_B_TABLE}\`
        AS

        SELECT
            geos.zip_code,
            geos.city,
            cust.last_name,
            cust.first_name
        FROM
            \`${CUSTOMER_B_PROJECT}.${CUSTOMER_B_DATASET}.${CUSTOMER_INFO}\` AS cust
        JOIN
            \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${VIEW_B}\` AS geos
        ON
            geos.zip_code = cust.postal_code
        "

    # --------------------------------------------------------
    # Verify
    # --------------------------------------------------------

    timeout 30s \
    bq \
        --quiet \
        --project_id="$CUSTOMER_B_PROJECT" \
        show \
        "${CUSTOMER_B_PROJECT}:${CUSTOMER_B_DATASET}.${CUSTOMER_B_TABLE}" \
        >/dev/null

    ok "${CUSTOMER_B_TABLE} created."

    echo
    info "Testing saved view..."

    timeout 60s \
    bq \
        --quiet \
        --project_id="$CUSTOMER_B_PROJECT" \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        --max_rows=5 \
        "
        SELECT *
        FROM \`${CUSTOMER_B_PROJECT}.${CUSTOMER_B_DATASET}.${CUSTOMER_B_TABLE}\`
        LIMIT 5
        " \
        >/dev/null

    ok "${CUSTOMER_B_TABLE} query successful."

    echo
    ok "TASK 5 BIGQUERY SECTION COMPLETED"
}

# ============================================================
# FINAL MANUAL LOOKER STUDIO INFO
# ============================================================

show_looker_steps() {
    echo
    echo "${YELLOW}${BOLD}LOOKER STUDIO STEPS STILL REQUIRED${RESET}"
    echo "${BLUE}${BOLD}==============================================================${RESET}"

    echo
    echo "${CYAN}${BOLD}TASK 4 - CUSTOMER A${RESET}"
    echo
    echo "${WHITE}Open:${RESET}"
    echo "${CYAN}https://lookerstudio.google.com/${RESET}"
    echo
    echo "${WHITE}Account     : ${CYAN}${CUSTOMER_A_USER}${RESET}"
    echo "${WHITE}Project     : ${CYAN}${CUSTOMER_A_PROJECT}${RESET}"
    echo "${WHITE}Dataset     : ${CYAN}${CUSTOMER_A_DATASET}${RESET}"
    echo "${WHITE}Data source : ${GREEN}${CUSTOMER_A_TABLE}${RESET}"
    echo "${WHITE}Report name : ${GREEN}Customer A Visualization${RESET}"
    echo "${WHITE}Chart       : ${GREEN}Pie chart${RESET}"
    echo "${WHITE}Dimension   : ${GREEN}city${RESET}"
    echo "${WHITE}Metric      : ${GREEN}Record Count${RESET}"

    echo
    echo "${MAGENTA}${BOLD}TASK 5 - CUSTOMER B${RESET}"
    echo
    echo "${WHITE}Account     : ${MAGENTA}${CUSTOMER_B_USER}${RESET}"
    echo "${WHITE}Project     : ${CYAN}${CUSTOMER_B_PROJECT}${RESET}"
    echo "${WHITE}Dataset     : ${CYAN}${CUSTOMER_B_DATASET}${RESET}"
    echo "${WHITE}Data source : ${GREEN}${CUSTOMER_B_TABLE}${RESET}"
    echo "${WHITE}Report name : ${GREEN}Customer B Visualization${RESET}"
    echo "${WHITE}Chart       : ${GREEN}Pie chart${RESET}"
    echo "${WHITE}Dimension   : ${GREEN}city${RESET}"
    echo "${WHITE}Metric      : ${GREEN}Record Count${RESET}"

    echo
    echo "${BLUE}${BOLD}==============================================================${RESET}"
}

# ============================================================
# MAIN
# ============================================================

main() {
    banner

    # --------------------------------------------------------
    # INPUT FIRST
    # --------------------------------------------------------

    ask_users

    require_cmd gcloud
    require_cmd bq
    require_cmd jq
    require_cmd grep
    require_cmd timeout

    # --------------------------------------------------------
    # Partner environment
    # --------------------------------------------------------

    ORIGINAL_ACCOUNT="$(get_active_account)"
    ORIGINAL_PROJECT="$(get_config_project)"

    [[ -n "$ORIGINAL_ACCOUNT" ]] || \
        fail "No active Partner account found."

    PARTNER_ACCOUNT="$ORIGINAL_ACCOUNT"
    PARTNER_PROJECT="${DEVSHELL_PROJECT_ID:-$ORIGINAL_PROJECT}"

    step "DATA SHARING PARTNER ENVIRONMENT"

    echo "${WHITE}Account : ${CYAN}${PARTNER_ACCOUNT}${RESET}"
    echo "${WHITE}Project : ${GREEN}${PARTNER_PROJECT:-not detected}${RESET}"

    # --------------------------------------------------------
    # Find Partner project if current one does not contain
    # demo_dataset
    # --------------------------------------------------------

    if \
        [[ -z "$PARTNER_PROJECT" ]] \
        ||
        ! dataset_exists "$PARTNER_PROJECT" "$PARTNER_DATASET"
    then

        find_project_with_dataset \
            "$PARTNER_ACCOUNT" \
            "$PARTNER_DATASET" \
            PARTNER_PROJECT \
            "Partner"
    fi

    switch_context \
        "$PARTNER_ACCOUNT" \
        "$PARTNER_PROJECT"

    # ========================================================
    # TASKS 1 - 3
    # ========================================================

    task1
    task2
    task3

    echo
    echo "${GREEN}${BOLD}✓ TASK 1 COMPLETE${RESET}"
    echo "${GREEN}${BOLD}✓ TASK 2 COMPLETE${RESET}"
    echo "${GREEN}${BOLD}✓ TASK 3 COMPLETE${RESET}"

    # ========================================================
    # CUSTOMER A LOGIN
    # ========================================================

    ensure_login \
        "$CUSTOMER_A_USER" \
        "CUSTOMER A"

    find_project_with_dataset \
        "$CUSTOMER_A_USER" \
        "$CUSTOMER_A_DATASET" \
        CUSTOMER_A_PROJECT \
        "Customer A"

    switch_context \
        "$CUSTOMER_A_USER" \
        "$CUSTOMER_A_PROJECT"

    # ========================================================
    # TASK 4
    # ========================================================

    task4_customer_a

    # ========================================================
    # CUSTOMER B LOGIN
    # ========================================================

    ensure_login \
        "$CUSTOMER_B_USER" \
        "CUSTOMER B"

    find_project_with_dataset \
        "$CUSTOMER_B_USER" \
        "$CUSTOMER_B_DATASET" \
        CUSTOMER_B_PROJECT \
        "Customer B"

    switch_context \
        "$CUSTOMER_B_USER" \
        "$CUSTOMER_B_PROJECT"

    # ========================================================
    # TASK 5
    # ========================================================

    task5_customer_b

    # ========================================================
    # RESULT
    # ========================================================

    echo
    echo "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║              BIGQUERY RESOURCES COMPLETE                     ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║                       TASK 1 ✓                               ║${RESET}"
    echo "${GREEN}${BOLD}║                       TASK 2 ✓                               ║${RESET}"
    echo "${GREEN}${BOLD}║                       TASK 3 ✓                               ║${RESET}"
    echo "${GREEN}${BOLD}║               TASK 4 BIGQUERY ✓                              ║${RESET}"
    echo "${GREEN}${BOLD}║               TASK 5 BIGQUERY ✓                              ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║                      © ePlus.DEV                             ║${RESET}"
    echo "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"

    show_looker_steps

    echo
    echo "${YELLOW}${BOLD}Complete the Looker Studio steps, then click Check my progress.${RESET}"
}

main "$@"

)