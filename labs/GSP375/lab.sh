#!/bin/bash

# ============================================================
# Share Data Using Google Data Cloud - Challenge Lab
#
# ONE TERMINAL • ONE SOURCE
# TASK 1 → TASK 4
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
# ============================================================

PARTNER_DATASET="demo_dataset"
PARTNER_VIEW="authorized_view_5805"

CUSTOMER_DATASET="customer_dataset"
CUSTOMER_INFO="customer_info"
CUSTOMER_VIEW="customer_authorized_view_e90o"

# Current lab username.
# Press ENTER to use it, or type another value if your lab changed.
DEFAULT_CUSTOMER_USER="student-04-06d62d8a1d0f@qwiklabs.net"

# ============================================================
# VARIABLES
# ============================================================

PARTNER_USER=""
PARTNER_PROJECT=""

CUSTOMER_USER=""
CUSTOMER_PROJECT=""

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
    if [[ -n "${ORIGINAL_ACCOUNT:-}" ]]; then
        gcloud config set account \
            "$ORIGINAL_ACCOUNT" \
            --quiet \
            >/dev/null 2>&1 || true
    fi

    # Restore Partner project
    if [[ -n "${ORIGINAL_PROJECT:-}" && "$ORIGINAL_PROJECT" != "(unset)" ]]; then
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
    echo "${CYAN}${BOLD}║            BIGQUERY BI-DIRECTIONAL DATA SHARING              ║${RESET}"
    echo "${CYAN}${BOLD}║                                                              ║${RESET}"
    echo "${CYAN}${BOLD}║                  ONE TERMINAL • ONE SOURCE                   ║${RESET}"
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
# INPUT
# ============================================================

colored_read_default() {

    local variable="$1"
    local label="$2"
    local default="$3"
    local value=""

    printf "%s%s%s%s %s[%s]%s %s>%s " \
        "$YELLOW" \
        "$BOLD" \
        "$label" \
        "$RESET" \
        "$WHITE" \
        "$default" \
        "$RESET" \
        "$GREEN" \
        "$CYAN"

    IFS= read -r value

    printf "%s" "$RESET"

    if [[ -z "$value" ]]; then
        value="$default"
    fi

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
# ASK CUSTOMER USER FIRST
# ============================================================

ask_customer_user() {

    step "ENTER CUSTOMER ACCOUNT"

    echo "${WHITE}Press ENTER to use the username shown in the lab.${RESET}"
    echo "${WHITE}If your lab instance changed, paste the new Customer username.${RESET}"
    echo

    while true; do

        colored_read_default \
            CUSTOMER_USER \
            "Customer user" \
            "$DEFAULT_CUSTOMER_USER"

        echo

        if valid_email "$CUSTOMER_USER"; then
            break
        fi

        warn "Invalid email address."
        echo
    done

    ok "Customer: ${CUSTOMER_USER}"
}

# ============================================================
# GCLOUD HELPERS
# ============================================================

get_active_account() {

    gcloud auth list \
        --filter=status:ACTIVE \
        --format='value(account)' \
        2>/dev/null |
    head -n1
}

get_config_project() {

    local project=""

    project="$(
        gcloud config get-value project \
            2>/dev/null || true
    )"

    [[ "$project" != "(unset)" ]] || project=""

    printf "%s" "$project"
}

# ============================================================
# BIGQUERY HELPERS
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

view_exists() {

    local project="$1"
    local dataset="$2"
    local view="$3"

    timeout 20s \
    bq \
        --quiet \
        --project_id="$project" \
        show \
        "$project:$dataset.$view" \
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
# LOGIN CUSTOMER IN SAME TERMINAL
# ============================================================

ensure_login() {

    local account="$1"
    local label="$2"

    step "LOGIN - ${label}"

    # Reuse credential if already stored
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

        echo "${WHITE}Authorization is required for:${RESET}"
        echo
        echo "${CYAN}${BOLD}${account}${RESET}"
        echo
        echo "${YELLOW}${BOLD}A Google login URL will appear below.${RESET}"
        echo
        echo "${WHITE}1. Open the URL.${RESET}"
        echo "${WHITE}2. Login with the Customer account.${RESET}"
        echo "${WHITE}3. Use the temporary lab password.${RESET}"
        echo "${WHITE}4. Copy the authorization code.${RESET}"
        echo "${WHITE}5. Paste it back into this terminal.${RESET}"
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
        fail "Unable to activate ${account}."
    fi

    echo
    ok "${label} authenticated."
}

# ============================================================
# SWITCH CONTEXT
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
# FIND PROJECT CONTAINING DATASET
# ============================================================

find_project_with_dataset() {

    local account="$1"
    local dataset="$2"
    local result_variable="$3"
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

    if [[ -n "$projects" ]]; then

        while IFS= read -r project; do

            [[ -n "$project" ]] || continue

            info "Checking ${project}..."

            if dataset_exists "$project" "$dataset"; then
                found="$project"
                break
            fi

        done <<< "$projects"
    fi

    # Manual fallback
    if [[ -z "$found" ]]; then

        warn "Could not auto-detect ${label} Project."
        echo

        while true; do

            printf "%s%s%s%s %s>%s " \
                "$YELLOW" \
                "$BOLD" \
                "${label} Project ID" \
                "$RESET" \
                "$GREEN" \
                "$CYAN"

            IFS= read -r found

            printf "%s" "$RESET"
            echo

            if ! valid_project "$found"; then
                warn "Invalid Project ID."
                echo
                continue
            fi

            if dataset_exists "$found" "$dataset"; then
                break
            fi

            warn "Dataset ${dataset} not found in ${found}."
            echo
        done
    fi

    printf -v "$result_variable" '%s' "$found"

    ok "${label} Project: ${found}"
}

# ============================================================
# AUTHORIZE VIEW IN DATASET ACL
# ============================================================

authorize_view() {

    local project="$1"
    local dataset="$2"
    local view_project="$3"
    local view_dataset="$4"
    local view_name="$5"

    local before=""
    local after=""

    before="$(mktemp)"
    after="$(mktemp)"

    TMP_FILES+=("$before" "$after")

    info "Reading ${project}.${dataset} ACL..."

    timeout 30s \
    bq \
        --quiet \
        --project_id="$project" \
        show \
        --format=prettyjson \
        "$project:$dataset" \
        > "$before"

    # Preserve all current ACL entries.
    # Remove an existing copy of this authorized-view entry
    # before appending the correct one.
    jq \
        --arg vp "$view_project" \
        --arg vd "$view_dataset" \
        --arg vn "$view_name" \
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

                        (.view.projectId != $vp)

                        or

                        (.view.datasetId != $vd)

                        or

                        (.view.tableId != $vn)
                    )
                ]

                +

                [
                    {
                        "view": {
                            "projectId": $vp,
                            "datasetId": $vd,
                            "tableId": $vn
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
        --project_id="$project" \
        update \
        --source="$after" \
        "$project:$dataset" \
        >/dev/null

    ok "Authorized View added."
}

# ============================================================
# VERIFY AUTHORIZED VIEW ACL
# ============================================================

verify_authorized_view() {

    local project="$1"
    local dataset="$2"
    local view_project="$3"
    local view_dataset="$4"
    local view_name="$5"

    local count=""

    count="$(
        timeout 30s \
        bq \
            --quiet \
            --project_id="$project" \
            show \
            --format=prettyjson \
            "$project:$dataset" |
        jq \
            --arg vp "$view_project" \
            --arg vd "$view_dataset" \
            --arg vn "$view_name" \
            '
            [
                .access[]?

                |

                select(
                    .view.projectId == $vp
                    and
                    .view.datasetId == $vd
                    and
                    .view.tableId == $vn
                )
            ]
            |
            length
            '
    )"

    if [[ "$count" -lt 1 ]]; then
        fail "Authorized View ACL verification failed."
    fi

    ok "Authorized View ACL verified."
}

# ============================================================
# GRANT BIGQUERY DATA VIEWER
# ============================================================

grant_data_viewer() {

    local project="$1"
    local dataset="$2"
    local view="$3"
    local user="$4"

    timeout 60s \
    bq \
        --quiet \
        --project_id="$project" \
        add-iam-policy-binding \
        --table=true \
        --member="user:${user}" \
        --role="roles/bigquery.dataViewer" \
        "${project}:${dataset}.${view}" \
        >/dev/null
}

# ============================================================
# VERIFY BIGQUERY DATA VIEWER
# ============================================================

verify_data_viewer() {

    local project="$1"
    local dataset="$2"
    local view="$3"
    local user="$4"

    local policy=""
    local matches=""

    policy="$(mktemp)"
    TMP_FILES+=("$policy")

    timeout 30s \
    bq \
        --quiet \
        --project_id="$project" \
        get-iam-policy \
        --table=true \
        "${project}:${dataset}.${view}" \
        > "$policy"

    matches="$(
        jq \
            --arg member "user:${user}" \
            '
            [
                .bindings[]?

                |

                select(
                    .role == "roles/bigquery.dataViewer"
                    and
                    (.members // [] | index($member))
                )
            ]
            |
            length
            ' \
            "$policy"
    )"

    if [[ "$matches" -lt 1 ]]; then
        fail "BigQuery Data Viewer verification failed for ${user}."
    fi

    ok "BigQuery Data Viewer verified."
}

# ============================================================
# TASK 1A
#
# CREATE PARTNER AUTHORIZED VIEW
# ============================================================

task1_create_partner_view() {

    step "[1/4] TASK 1 - CREATE PARTNER AUTHORIZED VIEW"

    local location=""

    location="$(
        get_location \
            "$PARTNER_PROJECT" \
            "$PARTNER_DATASET"
    )"

    echo "${WHITE}Project : ${CYAN}${BOLD}${PARTNER_PROJECT}${RESET}"
    echo "${WHITE}Dataset : ${CYAN}${PARTNER_DATASET}${RESET}"
    echo "${WHITE}View    : ${GREEN}${PARTNER_VIEW}${RESET}"
    echo "${WHITE}Location: ${CYAN}${location}${RESET}"

    echo
    info "Creating ${PARTNER_VIEW}..."

    timeout 120s \
    bq \
        --quiet \
        --project_id="$PARTNER_PROJECT" \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        "
        CREATE OR REPLACE VIEW
        \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${PARTNER_VIEW}\`
        AS

        SELECT
            *
        FROM
            \`bigquery-public-data.geo_us_boundaries.zip_codes\`
        "

    if ! view_exists \
        "$PARTNER_PROJECT" \
        "$PARTNER_DATASET" \
        "$PARTNER_VIEW"
    then
        fail "${PARTNER_VIEW} was not created."
    fi

    ok "${PARTNER_VIEW} created."

    echo
    echo "${GREEN}${BOLD}✓ CREATE THE PARTNER AUTHORIZED VIEW COMPLETE${RESET}"
}

# ============================================================
# TASK 1B
#
# AUTHORIZE VIEW + CUSTOMER IAM
# ============================================================

task1_authorize_partner_view() {

    step "[2/4] AUTHORIZE PARTNER VIEW + CUSTOMER IAM"

    info "Authorizing ${PARTNER_VIEW}..."

    authorize_view \
        "$PARTNER_PROJECT" \
        "$PARTNER_DATASET" \
        "$PARTNER_PROJECT" \
        "$PARTNER_DATASET" \
        "$PARTNER_VIEW"

    verify_authorized_view \
        "$PARTNER_PROJECT" \
        "$PARTNER_DATASET" \
        "$PARTNER_PROJECT" \
        "$PARTNER_DATASET" \
        "$PARTNER_VIEW"

    echo
    info "Granting Customer BigQuery Data Viewer..."

    grant_data_viewer \
        "$PARTNER_PROJECT" \
        "$PARTNER_DATASET" \
        "$PARTNER_VIEW" \
        "$CUSTOMER_USER"

    verify_data_viewer \
        "$PARTNER_PROJECT" \
        "$PARTNER_DATASET" \
        "$PARTNER_VIEW" \
        "$CUSTOMER_USER"

    ok "Customer → ${PARTNER_VIEW}"

    echo
    echo "${GREEN}${BOLD}✓ AUTHORIZE VIEW + CUSTOMER IAM COMPLETE${RESET}"
}

# ============================================================
# TASK 2
#
# UPDATE CUSTOMER DATA
# ============================================================

task2_update_customer() {

    step "[3/4] TASK 2 - UPDATE CUSTOMER DATA TABLE"

    local location=""

    location="$(
        get_location \
            "$CUSTOMER_PROJECT" \
            "$CUSTOMER_DATASET"
    )"

    echo "${WHITE}Customer Project : ${CYAN}${CUSTOMER_PROJECT}${RESET}"
    echo "${WHITE}Partner Project  : ${MAGENTA}${PARTNER_PROJECT}${RESET}"

    echo
    info "Updating county values from Partner authorized view..."

    timeout 120s \
    bq \
        --quiet \
        --project_id="$CUSTOMER_PROJECT" \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        "
        UPDATE
            \`${CUSTOMER_PROJECT}.${CUSTOMER_DATASET}.${CUSTOMER_INFO}\`
            AS cust

        SET
            cust.county = vw.county

        FROM
            \`${PARTNER_PROJECT}.${PARTNER_DATASET}.${PARTNER_VIEW}\`
            AS vw

        WHERE
            vw.zip_code = cust.postal_code;
        "

    ok "Customer county values updated."
}

# ============================================================
# TASK 3
#
# CUSTOMER AUTHORIZED VIEW
# ============================================================

task3_customer_view() {

    step "[4/4] TASK 3 - CREATE CUSTOMER AUTHORIZED VIEW"

    local location=""

    location="$(
        get_location \
            "$CUSTOMER_PROJECT" \
            "$CUSTOMER_DATASET"
    )"

    echo "${WHITE}Project : ${CYAN}${CUSTOMER_PROJECT}${RESET}"
    echo "${WHITE}Dataset : ${CYAN}${CUSTOMER_DATASET}${RESET}"
    echo "${WHITE}View    : ${GREEN}${CUSTOMER_VIEW}${RESET}"

    # --------------------------------------------------------
    # Create View
    # --------------------------------------------------------

    echo
    info "Creating ${CUSTOMER_VIEW}..."

    timeout 120s \
    bq \
        --quiet \
        --project_id="$CUSTOMER_PROJECT" \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        "
        CREATE OR REPLACE VIEW
        \`${CUSTOMER_PROJECT}.${CUSTOMER_DATASET}.${CUSTOMER_VIEW}\`
        AS

        SELECT
            county,
            COUNT(1) AS Count
        FROM
            \`${CUSTOMER_PROJECT}.${CUSTOMER_DATASET}.${CUSTOMER_INFO}\`
            AS cust
        GROUP BY
            county
        HAVING
            county IS NOT NULL
        "

    if ! view_exists \
        "$CUSTOMER_PROJECT" \
        "$CUSTOMER_DATASET" \
        "$CUSTOMER_VIEW"
    then
        fail "${CUSTOMER_VIEW} was not created."
    fi

    ok "${CUSTOMER_VIEW} created."

    echo
    echo "${GREEN}${BOLD}✓ CREATE THE CUSTOMER AUTHORIZED VIEW COMPLETE${RESET}"

    # --------------------------------------------------------
    # Authorize customer view
    # --------------------------------------------------------

    echo
    info "Authorizing ${CUSTOMER_VIEW}..."

    authorize_view \
        "$CUSTOMER_PROJECT" \
        "$CUSTOMER_DATASET" \
        "$CUSTOMER_PROJECT" \
        "$CUSTOMER_DATASET" \
        "$CUSTOMER_VIEW"

    verify_authorized_view \
        "$CUSTOMER_PROJECT" \
        "$CUSTOMER_DATASET" \
        "$CUSTOMER_PROJECT" \
        "$CUSTOMER_DATASET" \
        "$CUSTOMER_VIEW"

    # --------------------------------------------------------
    # Grant Partner IAM
    # --------------------------------------------------------

    echo
    info "Granting Partner BigQuery Data Viewer..."

    grant_data_viewer \
        "$CUSTOMER_PROJECT" \
        "$CUSTOMER_DATASET" \
        "$CUSTOMER_VIEW" \
        "$PARTNER_USER"

    verify_data_viewer \
        "$CUSTOMER_PROJECT" \
        "$CUSTOMER_DATASET" \
        "$CUSTOMER_VIEW" \
        "$PARTNER_USER"

    ok "Partner → ${CUSTOMER_VIEW}"

    echo
    echo "${GREEN}${BOLD}✓ AUTHORIZE CUSTOMER VIEW + PARTNER IAM COMPLETE${RESET}"
}

# ============================================================
# PREPARE TASK 4
#
# Switch back to Partner and verify it can consume
# customer_authorized_view_e90o.
# ============================================================

prepare_task4() {

    step "PREPARE TASK 4 - VERIFY CUSTOMER VIEW ACCESS"

    switch_context \
        "$PARTNER_USER" \
        "$PARTNER_PROJECT"

    local location=""

    location="$(
        get_location \
            "$PARTNER_PROJECT" \
            "$PARTNER_DATASET"
    )"

    info "Testing Customer Authorized View as Partner..."

    timeout 120s \
    bq \
        --quiet \
        --project_id="$PARTNER_PROJECT" \
        query \
        --location="$location" \
        --use_legacy_sql=false \
        --max_rows=10 \
        "
        SELECT
            county,
            Count
        FROM
            \`${CUSTOMER_PROJECT}.${CUSTOMER_DATASET}.${CUSTOMER_VIEW}\`
        ORDER BY
            Count DESC
        LIMIT 10
        "

    ok "Partner can query ${CUSTOMER_VIEW}."
    ok "BigQuery data source is ready for Looker Studio."
}

# ============================================================
# TASK 4 MANUAL INSTRUCTIONS
# ============================================================

show_looker_steps() {

    echo
    echo "${YELLOW}${BOLD}TASK 4 - LOOKER STUDIO STEPS${RESET}"
    echo "${BLUE}${BOLD}==============================================================${RESET}"

    echo
    echo "${WHITE}1. Open:${RESET}"
    echo "${CYAN}   https://lookerstudio.google.com/${RESET}"

    echo
    echo "${WHITE}2. Make sure you are logged in as Partner:${RESET}"
    echo "${CYAN}   ${PARTNER_USER}${RESET}"

    echo
    echo "${WHITE}3. Create a Blank Report.${RESET}"

    echo
    echo "${WHITE}4. Add BigQuery data:${RESET}"
    echo "${WHITE}   Project : ${CYAN}${CUSTOMER_PROJECT}${RESET}"
    echo "${WHITE}   Dataset : ${CYAN}${CUSTOMER_DATASET}${RESET}"
    echo "${WHITE}   View    : ${GREEN}${CUSTOMER_VIEW}${RESET}"

    echo
    echo "${WHITE}5. Add the data source to the report.${RESET}"

    echo
    echo "${WHITE}6. Rename report:${RESET}"
    echo "${GREEN}   Data Sharing Partner Vizualization${RESET}"

    echo
    echo "${WHITE}7. Insert a Vertical Bar Chart.${RESET}"

    echo
    echo "${WHITE}8. Configure:${RESET}"
    echo "${WHITE}   Dimension           : ${GREEN}county${RESET}"
    echo "${WHITE}   Breakdown Dimension : ${GREEN}Count${RESET}"
    echo "${WHITE}   Metric              : ${GREEN}Count${RESET}"

    echo
    echo "${WHITE}9. Click Check my progress for:${RESET}"
    echo "${YELLOW}   Connect BigQuery to Data Studio${RESET}"

    echo
    echo "${BLUE}${BOLD}==============================================================${RESET}"
}

# ============================================================
# MAIN
# ============================================================

main() {

    banner

    # ========================================================
    # INPUT FIRST
    # ========================================================

    ask_customer_user

    # ========================================================
    # REQUIREMENTS
    # ========================================================

    require_cmd gcloud
    require_cmd bq
    require_cmd jq
    require_cmd grep
    require_cmd timeout

    # ========================================================
    # DETECT PARTNER
    # ========================================================

    ORIGINAL_ACCOUNT="$(get_active_account)"
    ORIGINAL_PROJECT="$(get_config_project)"

    if [[ -z "$ORIGINAL_ACCOUNT" ]]; then
        fail "No active Data Sharing Partner account detected."
    fi

    PARTNER_USER="$ORIGINAL_ACCOUNT"
    PARTNER_PROJECT="${DEVSHELL_PROJECT_ID:-}"

    if [[ -z "$PARTNER_PROJECT" ]]; then
        PARTNER_PROJECT="$ORIGINAL_PROJECT"
    fi

    step "DATA SHARING PARTNER ENVIRONMENT"

    echo "${WHITE}Partner User    : ${CYAN}${BOLD}${PARTNER_USER}${RESET}"
    echo "${WHITE}Partner Project : ${GREEN}${BOLD}${PARTNER_PROJECT:-not detected}${RESET}"

    # --------------------------------------------------------
    # Fallback if current project is incorrect
    # --------------------------------------------------------

    if \
        [[ -z "$PARTNER_PROJECT" ]] \
        ||
        ! dataset_exists \
            "$PARTNER_PROJECT" \
            "$PARTNER_DATASET"
    then

        find_project_with_dataset \
            "$PARTNER_USER" \
            "$PARTNER_DATASET" \
            PARTNER_PROJECT \
            "Partner"
    fi

    switch_context \
        "$PARTNER_USER" \
        "$PARTNER_PROJECT"

    # ========================================================
    # TASK 1
    # ========================================================

    task1_create_partner_view
    task1_authorize_partner_view

    # ========================================================
    # LOGIN CUSTOMER
    # ========================================================

    ensure_login \
        "$CUSTOMER_USER" \
        "CUSTOMER"

    # ========================================================
    # DETECT CUSTOMER PROJECT
    # ========================================================

    find_project_with_dataset \
        "$CUSTOMER_USER" \
        "$CUSTOMER_DATASET" \
        CUSTOMER_PROJECT \
        "Customer"

    switch_context \
        "$CUSTOMER_USER" \
        "$CUSTOMER_PROJECT"

    # ========================================================
    # TASK 2
    # ========================================================

    task2_update_customer

    # ========================================================
    # TASK 3
    # ========================================================

    task3_customer_view

    # ========================================================
    # SWITCH BACK TO PARTNER + VERIFY TASK 4 SOURCE
    # ========================================================

    prepare_task4

    # ========================================================
    # FINAL
    # ========================================================

    echo
    echo "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║                    BIGQUERY TASKS COMPLETE                   ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║            Partner authorized view              ✓           ║${RESET}"
    echo "${GREEN}${BOLD}║            Partner view authorization + IAM     ✓           ║${RESET}"
    echo "${GREEN}${BOLD}║            Customer data update                 ✓           ║${RESET}"
    echo "${GREEN}${BOLD}║            Customer authorized view             ✓           ║${RESET}"
    echo "${GREEN}${BOLD}║            Customer view authorization + IAM    ✓           ║${RESET}"
    echo "${GREEN}${BOLD}║            Task 4 BigQuery source verified      ✓           ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║                      © ePlus.DEV                             ║${RESET}"
    echo "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"

    echo
    echo "${YELLOW}${BOLD}→ Check my progress: Create the partner authorized view${RESET}"
    echo "${YELLOW}${BOLD}→ Check my progress: Authorize the view and Assign IAM permissions${RESET}"
    echo "${YELLOW}${BOLD}→ Check my progress: Create the customer authorized view${RESET}"
    echo "${YELLOW}${BOLD}→ Check my progress: Authorize the view and Assign IAM permissions${RESET}"

    show_looker_steps
}

main "$@"

)