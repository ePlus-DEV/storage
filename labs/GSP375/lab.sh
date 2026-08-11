#!/bin/bash

# ============================================================
# Share Data Using Google Data Cloud - Challenge Lab
#
# ONE TERMINAL • ONE SOURCE
#
# Dynamic values:
#   - Customer user
#   - Partner Authorized View
#   - Customer Authorized View
#
# Project IDs are automatically detected.
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
# FIXED LAB RESOURCE NAMES
# ============================================================

PARTNER_DATASET="demo_dataset"

CUSTOMER_DATASET="customer_dataset"
CUSTOMER_INFO="customer_info"

# ============================================================
# DYNAMIC VALUES
# ============================================================

CUSTOMER_USER=""
PARTNER_VIEW=""
CUSTOMER_VIEW=""

# ============================================================
# AUTO-DETECTED VALUES
# ============================================================

PARTNER_USER=""
PARTNER_PROJECT=""

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

valid_bq_name() {
    [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

require_cmd() {

    command -v "$1" >/dev/null 2>&1 || \
        fail "Required command not found: $1"
}

# ============================================================
# ASK ALL INSTANCE-SPECIFIC VALUES FIRST
# ============================================================

ask_lab_inputs() {

    step "ENTER LAB PARAMETERS"

    echo "${WHITE}Copy the values exactly from the lab instructions.${RESET}"
    echo

    # --------------------------------------------------------
    # Customer user
    # --------------------------------------------------------

    while true; do

        colored_read \
            CUSTOMER_USER \
            "Customer user"

        echo

        if valid_email "$CUSTOMER_USER"; then
            break
        fi

        warn "Invalid Customer email."
        echo
    done

    echo

    # --------------------------------------------------------
    # Partner Authorized View
    #
    # Example:
    # authorized_view_5805
    # --------------------------------------------------------

    while true; do

        colored_read \
            PARTNER_VIEW \
            "Partner Authorized View name"

        echo

        if valid_bq_name "$PARTNER_VIEW"; then
            break
        fi

        warn "Invalid BigQuery view name."
        echo
    done

    echo

    # --------------------------------------------------------
    # Customer Authorized View
    #
    # Example:
    # customer_authorized_view_e90o
    # --------------------------------------------------------

    while true; do

        colored_read \
            CUSTOMER_VIEW \
            "Customer Authorized View name"

        echo

        if valid_bq_name "$CUSTOMER_VIEW"; then
            break
        fi

        warn "Invalid BigQuery view name."
        echo
    done

    echo
    echo "${BLUE}--------------------------------------------------------------${RESET}"
    echo "${WHITE}${BOLD}INPUT SUMMARY${RESET}"
    echo "${BLUE}--------------------------------------------------------------${RESET}"

    echo "${WHITE}Customer user            : ${CYAN}${BOLD}${CUSTOMER_USER}${RESET}"
    echo "${WHITE}Partner Authorized View  : ${GREEN}${BOLD}${PARTNER_VIEW}${RESET}"
    echo "${WHITE}Customer Authorized View : ${MAGENTA}${BOLD}${CUSTOMER_VIEW}${RESET}"

    echo "${BLUE}--------------------------------------------------------------${RESET}"
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

resource_exists() {

    local project="$1"
    local dataset="$2"
    local resource="$3"

    timeout 20s \
    bq \
        --quiet \
        --project_id="$project" \
        show \
        "$project:$dataset.$resource" \
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
# SWITCH ACCOUNT + PROJECT
# ============================================================

switch_context() {

    local account="$1"
    local project="$2"

    echo

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

    local active_account=""
    local active_project=""

    active_account="$(get_active_account)"
    active_project="$(get_config_project)"

    if [[ "$active_account" != "$account" ]]; then
        fail "Failed to activate account ${account}."
    fi

    if [[ "$active_project" != "$project" ]]; then
        fail "Failed to activate project ${project}."
    fi

    ok "Account : ${account}"
    ok "Project : ${project}"
}

# ============================================================
# LOGIN CUSTOMER
# ============================================================

ensure_login() {

    local account="$1"
    local label="$2"

    step "LOGIN - ${label}"

    # --------------------------------------------------------
    # Reuse credential if already stored
    # --------------------------------------------------------

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

        echo "${YELLOW}${BOLD}A Google authorization URL will appear below.${RESET}"
        echo

        echo "${WHITE}1. Open the URL in an Incognito window.${RESET}"
        echo "${WHITE}2. Login using the Customer account.${RESET}"
        echo "${WHITE}3. Use the temporary lab password.${RESET}"
        echo "${WHITE}4. Copy the authorization code.${RESET}"
        echo "${WHITE}5. Paste it back into this terminal.${RESET}"
        echo

        # No timeout here because browser login needs time.
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

    # --------------------------------------------------------
    # Manual fallback
    # --------------------------------------------------------

    if [[ -z "$found" ]]; then

        warn "Could not automatically detect ${label} Project."
        echo

        while true; do

            colored_read \
                found \
                "${label} Project ID"

            echo

            if ! valid_project "$found"; then
                warn "Invalid Google Cloud Project ID."
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
# AUTHORIZE BIGQUERY VIEW
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

    # --------------------------------------------------------
    # Read current dataset ACL
    # --------------------------------------------------------

    info "Reading ${project}.${dataset} ACL..."

    timeout 30s \
    bq \
        --quiet \
        --project_id="$project" \
        show \
        --format=prettyjson \
        "$project:$dataset" \
        > "$before"

    # --------------------------------------------------------
    # Preserve all current ACL entries.
    # Remove duplicate entry for this view.
    # Append correct Authorized View entry.
    # --------------------------------------------------------

    info "Adding Authorized View..."

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
# VERIFY AUTHORIZED VIEW
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
    local count=""

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

    count="$(
        jq \
            --arg member "user:${user}" \
            '
            [
                .bindings[]?

                |

                select(
                    .role == "roles/bigquery.dataViewer"
                    and
                    (
                        (.members // [])
                        |
                        index($member)
                    )
                )
            ]
            |
            length
            ' \
            "$policy"
    )"

    if [[ "$count" -lt 1 ]]; then
        fail "BigQuery Data Viewer verification failed for ${user}."
    fi

    ok "BigQuery Data Viewer verified."
}

# ============================================================
# RETRY QUERY FOR IAM PROPAGATION
# ============================================================

run_query_retry() {

    local project="$1"
    local location="$2"
    local sql="$3"
    local label="$4"

    local attempt=""
    local max_attempts=6
    local logfile=""

    logfile="$(mktemp)"
    TMP_FILES+=("$logfile")

    for attempt in $(seq 1 "$max_attempts"); do

        info "${label} - attempt ${attempt}/${max_attempts}..."

        if timeout 120s \
            bq \
                --quiet \
                --project_id="$project" \
                query \
                --location="$location" \
                --use_legacy_sql=false \
                "$sql" \
                >"$logfile" 2>&1
        then

            cat "$logfile"
            return 0
        fi

        if grep -Eqi \
            'Access Denied|Permission denied|PERMISSION_DENIED|does not have permission' \
            "$logfile"
        then

            if [[ "$attempt" -lt "$max_attempts" ]]; then
                warn "IAM permission may still be propagating."
                warn "Waiting 10 seconds..."
                sleep 10
                continue
            fi
        fi

        echo
        cat "$logfile"
        echo

        fail "${label} failed."
    done

    echo
    cat "$logfile"
    echo

    fail "${label} failed after retries."
}

# ============================================================
# TASK 1A
# CREATE PARTNER AUTHORIZED VIEW
# ============================================================

task1_create_partner_view() {

    step "[1/4] CREATE PARTNER AUTHORIZED VIEW"

    local location=""

    location="$(
        get_location \
            "$PARTNER_PROJECT" \
            "$PARTNER_DATASET"
    )"

    echo "${WHITE}Partner Project : ${CYAN}${BOLD}${PARTNER_PROJECT}${RESET}"
    echo "${WHITE}Dataset         : ${CYAN}${PARTNER_DATASET}${RESET}"
    echo "${WHITE}View            : ${GREEN}${BOLD}${PARTNER_VIEW}${RESET}"
    echo "${WHITE}Location        : ${CYAN}${location}${RESET}"

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

    if ! resource_exists \
        "$PARTNER_PROJECT" \
        "$PARTNER_DATASET" \
        "$PARTNER_VIEW"
    then
        fail "${PARTNER_VIEW} was not created."
    fi

    ok "${PARTNER_VIEW} created successfully."

    echo
    echo "${GREEN}${BOLD}✓ CREATE THE PARTNER AUTHORIZED VIEW COMPLETE${RESET}"
}

# ============================================================
# TASK 1B
# AUTHORIZE PARTNER VIEW + CUSTOMER IAM
# ============================================================

task1_authorize_partner_view() {

    step "[2/4] AUTHORIZE PARTNER VIEW + CUSTOMER IAM"

    # --------------------------------------------------------
    # Authorized View
    # --------------------------------------------------------

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

    # --------------------------------------------------------
    # Customer → BigQuery Data Viewer
    # --------------------------------------------------------

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

    echo
    ok "Customer : ${CUSTOMER_USER}"
    ok "View     : ${PARTNER_VIEW}"

    echo
    echo "${GREEN}${BOLD}✓ PARTNER VIEW AUTHORIZATION + IAM COMPLETE${RESET}"
}

# ============================================================
# TASK 2
# UPDATE CUSTOMER TABLE
# ============================================================

task2_update_customer() {

    step "[3/4] TASK 2 - UPDATE CUSTOMER DATA TABLE"

    local location=""

    location="$(
        get_location \
            "$CUSTOMER_PROJECT" \
            "$CUSTOMER_DATASET"
    )"

    echo "${WHITE}Customer Project : ${CYAN}${BOLD}${CUSTOMER_PROJECT}${RESET}"
    echo "${WHITE}Partner Project  : ${MAGENTA}${BOLD}${PARTNER_PROJECT}${RESET}"
    echo "${WHITE}Partner View     : ${GREEN}${PARTNER_VIEW}${RESET}"

    echo

    run_query_retry \
        "$CUSTOMER_PROJECT" \
        "$location" \
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
        " \
        "Updating customer county values"

    echo
    ok "Customer data table updated successfully."
}

# ============================================================
# TASK 3
# CREATE CUSTOMER AUTHORIZED VIEW
# ============================================================

task3_customer_view() {

    step "[4/4] TASK 3 - CREATE CUSTOMER AUTHORIZED VIEW"

    local location=""

    location="$(
        get_location \
            "$CUSTOMER_PROJECT" \
            "$CUSTOMER_DATASET"
    )"

    echo "${WHITE}Customer Project : ${CYAN}${BOLD}${CUSTOMER_PROJECT}${RESET}"
    echo "${WHITE}Dataset          : ${CYAN}${CUSTOMER_DATASET}${RESET}"
    echo "${WHITE}Customer View    : ${GREEN}${BOLD}${CUSTOMER_VIEW}${RESET}"

    # ========================================================
    # CREATE CUSTOMER VIEW
    # ========================================================

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

    if ! resource_exists \
        "$CUSTOMER_PROJECT" \
        "$CUSTOMER_DATASET" \
        "$CUSTOMER_VIEW"
    then
        fail "${CUSTOMER_VIEW} was not created."
    fi

    ok "${CUSTOMER_VIEW} created successfully."

    echo
    echo "${GREEN}${BOLD}✓ CREATE CUSTOMER AUTHORIZED VIEW COMPLETE${RESET}"

    # ========================================================
    # AUTHORIZE CUSTOMER VIEW
    # ========================================================

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

    # ========================================================
    # PARTNER → BIGQUERY DATA VIEWER
    # ========================================================

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

    echo
    ok "Partner : ${PARTNER_USER}"
    ok "View    : ${CUSTOMER_VIEW}"

    echo
    echo "${GREEN}${BOLD}✓ CUSTOMER VIEW AUTHORIZATION + IAM COMPLETE${RESET}"
}

# ============================================================
# TASK 4 PREPARATION
#
# IMPORTANT:
#
# The Looker Studio source MUST be:
#
# CUSTOMER_PROJECT
#   → customer_dataset
#   → CUSTOMER_VIEW
#
# NOT:
#
# PARTNER_PROJECT
#   → demo_dataset
#   → PARTNER_VIEW
# ============================================================

prepare_task4() {

    step "PREPARE TASK 4 - VERIFY CUSTOMER VIEW"

    switch_context \
        "$PARTNER_USER" \
        "$PARTNER_PROJECT"

    local location=""

    location="$(
        get_location \
            "$PARTNER_PROJECT" \
            "$PARTNER_DATASET"
    )"

    echo
    echo "${WHITE}${BOLD}Correct Looker Studio source:${RESET}"
    echo
    echo "${CYAN}${CUSTOMER_PROJECT}${RESET}"
    echo "${WHITE}  → ${CUSTOMER_DATASET}${RESET}"
    echo "${GREEN}  → ${CUSTOMER_VIEW}${RESET}"
    echo

    run_query_retry \
        "$PARTNER_PROJECT" \
        "$location" \
        "
        SELECT
            county,
            Count
        FROM
            \`${CUSTOMER_PROJECT}.${CUSTOMER_DATASET}.${CUSTOMER_VIEW}\`
        ORDER BY
            Count DESC
        LIMIT 10
        " \
        "Testing Customer Authorized View as Partner"

    echo
    ok "Partner can query Customer Authorized View."
    ok "Task 4 BigQuery source is ready."
}

# ============================================================
# LOOKER STUDIO INSTRUCTIONS
# ============================================================

show_looker_steps() {

    echo
    echo "${YELLOW}${BOLD}TASK 4 - LOOKER STUDIO${RESET}"
    echo "${BLUE}${BOLD}==============================================================${RESET}"

    echo
    echo "${RED}${BOLD}DO NOT SELECT:${RESET}"
    echo "${WHITE}   ${PARTNER_PROJECT}${RESET}"
    echo "${WHITE}   → ${PARTNER_DATASET}${RESET}"
    echo "${RED}   → ${PARTNER_VIEW}${RESET}"

    echo
    echo "${GREEN}${BOLD}SELECT THIS CUSTOMER VIEW:${RESET}"
    echo "${WHITE}   Project : ${CYAN}${CUSTOMER_PROJECT}${RESET}"
    echo "${WHITE}   Dataset : ${CYAN}${CUSTOMER_DATASET}${RESET}"
    echo "${WHITE}   View    : ${GREEN}${CUSTOMER_VIEW}${RESET}"

    echo
    echo "${BLUE}${BOLD}==============================================================${RESET}"

    echo
    echo "${WHITE}1. Open:${RESET}"
    echo "${CYAN}   https://lookerstudio.google.com/${RESET}"

    echo
    echo "${WHITE}2. Login as Data Sharing Partner:${RESET}"
    echo "${CYAN}   ${PARTNER_USER}${RESET}"

    echo
    echo "${WHITE}3. Create a Blank Report.${RESET}"

    echo
    echo "${WHITE}4. Select BigQuery.${RESET}"

    echo
    echo "${WHITE}5. If the Customer Project is not listed:${RESET}"
    echo "${YELLOW}   Click Enter Project Id manually${RESET}"

    echo
    echo "${WHITE}6. Enter:${RESET}"
    echo "${CYAN}   ${CUSTOMER_PROJECT}${RESET}"

    echo
    echo "${WHITE}7. Select:${RESET}"
    echo "${CYAN}   ${CUSTOMER_DATASET}${RESET}"
    echo "${GREEN}   ${CUSTOMER_VIEW}${RESET}"

    echo
    echo "${WHITE}8. Click Add → Add to Report.${RESET}"

    echo
    echo "${WHITE}9. Report name:${RESET}"
    echo "${GREEN}   Data Sharing Partner Vizualization${RESET}"

    echo
    echo "${WHITE}10. Insert a Vertical Bar Chart.${RESET}"

    echo
    echo "${WHITE}11. Configure:${RESET}"
    echo "${WHITE}    Dimension           : ${GREEN}county${RESET}"
    echo "${WHITE}    Breakdown Dimension : ${GREEN}Count${RESET}"
    echo "${WHITE}    Metric              : ${GREEN}Count${RESET}"

    echo
    echo "${WHITE}12. Click Check my progress:${RESET}"
    echo "${YELLOW}    Connect BigQuery to Data Studio${RESET}"

    echo
    echo "${BLUE}${BOLD}==============================================================${RESET}"
    echo "${CYAN}${BOLD}© ePlus.DEV${RESET}"
}

# ============================================================
# MAIN
# ============================================================

main() {

    banner

    # ========================================================
    # INPUT VALUES FIRST
    # ========================================================

    ask_lab_inputs

    # ========================================================
    # REQUIRED COMMANDS
    # ========================================================

    require_cmd gcloud
    require_cmd bq
    require_cmd jq
    require_cmd grep
    require_cmd timeout
    require_cmd seq

    # ========================================================
    # DETECT DATA SHARING PARTNER
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
    echo "${WHITE}Partner View    : ${GREEN}${BOLD}${PARTNER_VIEW}${RESET}"

    # --------------------------------------------------------
    # If current project is not the lab Partner project,
    # search for demo_dataset.
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
            "Data Sharing Partner"
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
    # CUSTOMER LOGIN
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
    # RETURN TO PARTNER + VERIFY TASK 4 SOURCE
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
    echo "${GREEN}${BOLD}║        Partner Authorized View                    ✓          ║${RESET}"
    echo "${GREEN}${BOLD}║        Partner View Authorization + IAM           ✓          ║${RESET}"
    echo "${GREEN}${BOLD}║        Customer Data Update                       ✓          ║${RESET}"
    echo "${GREEN}${BOLD}║        Customer Authorized View                   ✓          ║${RESET}"
    echo "${GREEN}${BOLD}║        Customer View Authorization + IAM          ✓          ║${RESET}"
    echo "${GREEN}${BOLD}║        Customer View Access From Partner          ✓          ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}║                      © ePlus.DEV                             ║${RESET}"
    echo "${GREEN}${BOLD}║                                                              ║${RESET}"
    echo "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"

    echo
    echo "${YELLOW}${BOLD}→ Check my progress: Create the partner authorized view${RESET}"
    echo "${YELLOW}${BOLD}→ Check my progress: Authorize the view and Assign IAM permissions${RESET}"
    echo "${YELLOW}${BOLD}→ Check my progress: Create the customer authorized view${RESET}"
    echo "${YELLOW}${BOLD}→ Check my progress: Authorize the view and Assign IAM permissions${RESET}"

    # ========================================================
    # IMPORTANT FINAL LOOKER INSTRUCTIONS
    # ========================================================

    show_looker_steps
}

main "$@"

)