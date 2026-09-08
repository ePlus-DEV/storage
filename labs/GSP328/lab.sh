#!/bin/bash

# ============================================================
# GSP328 - Develop Serverless Applications on Cloud Run
# Challenge Lab
#
# © ePlus.DEV
# ============================================================

set -o pipefail

# ============================================================
# COLORS
# ============================================================

BLACK=$(tput setaf 0 2>/dev/null || true)
RED=$(tput setaf 1 2>/dev/null || true)
GREEN=$(tput setaf 2 2>/dev/null || true)
YELLOW=$(tput setaf 3 2>/dev/null || true)
BLUE=$(tput setaf 4 2>/dev/null || true)
MAGENTA=$(tput setaf 5 2>/dev/null || true)
CYAN=$(tput setaf 6 2>/dev/null || true)
WHITE=$(tput setaf 7 2>/dev/null || true)

BG_RED=$(tput setab 1 2>/dev/null || true)
BG_GREEN=$(tput setab 2 2>/dev/null || true)
BG_BLUE=$(tput setab 4 2>/dev/null || true)
BG_MAGENTA=$(tput setab 5 2>/dev/null || true)
BG_CYAN=$(tput setab 6 2>/dev/null || true)

BOLD=$(tput bold 2>/dev/null || true)
RESET=$(tput sgr0 2>/dev/null || true)

# ============================================================
# FUNCTIONS
# ============================================================

header() {
    clear
    echo
    echo "${BG_MAGENTA}${WHITE}${BOLD}==============================================================${RESET}"
    echo "${BG_MAGENTA}${WHITE}${BOLD}      GSP328 - CLOUD RUN CHALLENGE LAB                        ${RESET}"
    echo "${BG_MAGENTA}${WHITE}${BOLD}                     © ePlus.DEV                              ${RESET}"
    echo "${BG_MAGENTA}${WHITE}${BOLD}==============================================================${RESET}"
    echo
}

section() {
    echo
    echo "${CYAN}${BOLD}==============================================================${RESET}"
    echo "${CYAN}${BOLD} $1${RESET}"
    echo "${CYAN}${BOLD}==============================================================${RESET}"
}

info() {
    echo "${BLUE}${BOLD}➜${RESET} $1"
}

success() {
    echo "${GREEN}${BOLD}✓${RESET} $1"
}

warn() {
    echo "${YELLOW}${BOLD}⚠${RESET} $1"
}

error() {
    echo "${RED}${BOLD}✗ $1${RESET}"
}

die() {
    error "$1"
    exit 1
}

run_cmd() {
    "$@"
    STATUS=$?

    if [[ $STATUS -ne 0 ]]; then
        error "Command failed:"
        echo "$*"
        exit "$STATUS"
    fi
}

input_value() {
    local LABEL="$1"
    local DEFAULT_VALUE="$2"
    local RESULT

    read -rp "$(echo "${YELLOW}${BOLD}${LABEL}${RESET} [${GREEN}${DEFAULT_VALUE}${RESET}]: ")" RESULT

    if [[ -z "$RESULT" ]]; then
        RESULT="$DEFAULT_VALUE"
    fi

    echo "$RESULT"
}

wait_for_service() {
    local SERVICE="$1"

    info "Waiting for $SERVICE to become ready..."

    for i in {1..30}; do

        READY=$(gcloud run services describe "$SERVICE" \
            --region="$REGION" \
            --platform=managed \
            --project="$PROJECT_ID" \
            --format="value(status.conditions[0].status)" \
            2>/dev/null || true)

        if [[ "$READY" == "True" ]]; then
            echo
            success "$SERVICE is ready."
            return 0
        fi

        printf "\r${YELLOW}Waiting... %02d/30${RESET}" "$i"
        sleep 3
    done

    echo
    warn "Timeout waiting for $SERVICE."
}

# ============================================================
# START
# ============================================================

header

section "ENTER LAB VARIABLES"

# ------------------------------------------------------------
# Auto detect project
# ------------------------------------------------------------

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
    PROJECT_ID=$(gcloud projects list \
        --filter="projectId:qwiklabs-gcp" \
        --format="value(projectId)" \
        --limit=1)
fi

[[ -n "$PROJECT_ID" ]] || die "Could not detect Qwiklabs project."

# ------------------------------------------------------------
# Auto detect REGION
# ------------------------------------------------------------

DETECTED_REGION=$(gcloud compute project-info describe \
    --format="value(commonInstanceMetadata.items[google-compute-default-region])" \
    2>/dev/null || true)

if [[ -z "$DETECTED_REGION" ]]; then
    DETECTED_REGION="us-west1"
fi

echo
echo "${MAGENTA}${BOLD}Enter the lab values below.${RESET}"
echo "${WHITE}Press ENTER to use the value shown inside [ ].${RESET}"
echo

REGION=$(input_value \
    "Enter REGION" \
    "$DETECTED_REGION")

TASK_1_SERVICES_NAME=$(input_value \
    "Enter Task 1 Public Billing Service Name" \
    "public-billing-service-748")

TASK_2_SERVICES_NAME=$(input_value \
    "Enter Task 2 Frontend Staging Service Name" \
    "frontend-staging-service-657")

TASK_3_SERVICES_NAME=$(input_value \
    "Enter Task 3 Private Billing Service Name" \
    "private-billing-service-473")

TASK_4_SERVICES_NAME=$(input_value \
    "Enter Task 4 Billing Service Account Name" \
    "billing-service-sa-699")

TASK_5_SERVICES_NAME=$(input_value \
    "Enter Task 5 Production Billing Service Name" \
    "billing-prod-service-311")

TASK_6_SERVICES_NAME=$(input_value \
    "Enter Task 6 Frontend Service Account Name" \
    "frontend-service-sa-122")

TASK_7_SERVICES_NAME=$(input_value \
    "Enter Task 7 Production Frontend Service Name" \
    "frontend-prod-service-578")

export PROJECT_ID
export REGION
export TASK_1_SERVICES_NAME
export TASK_2_SERVICES_NAME
export TASK_3_SERVICES_NAME
export TASK_4_SERVICES_NAME
export TASK_5_SERVICES_NAME
export TASK_6_SERVICES_NAME
export TASK_7_SERVICES_NAME

# ============================================================
# SHOW CONFIG
# ============================================================

section "LAB CONFIGURATION"

echo "${WHITE}Project ID              : ${GREEN}$PROJECT_ID${RESET}"
echo "${WHITE}Region                  : ${GREEN}$REGION${RESET}"
echo
echo "${WHITE}Task 1 Public Billing   : ${GREEN}$TASK_1_SERVICES_NAME${RESET}"
echo "${WHITE}Task 2 Staging Frontend : ${GREEN}$TASK_2_SERVICES_NAME${RESET}"
echo "${WHITE}Task 3 Private Billing  : ${GREEN}$TASK_3_SERVICES_NAME${RESET}"
echo "${WHITE}Task 4 Billing SA       : ${GREEN}$TASK_4_SERVICES_NAME${RESET}"
echo "${WHITE}Task 5 Prod Billing     : ${GREEN}$TASK_5_SERVICES_NAME${RESET}"
echo "${WHITE}Task 6 Frontend SA      : ${GREEN}$TASK_6_SERVICES_NAME${RESET}"
echo "${WHITE}Task 7 Prod Frontend    : ${GREEN}$TASK_7_SERVICES_NAME${RESET}"

echo
read -rp "$(echo "${YELLOW}${BOLD}Press ENTER to start the lab...${RESET}")"

# ============================================================
# CONFIGURE GCLOUD
# ============================================================

section "CONFIGURE GOOGLE CLOUD"

run_cmd gcloud config set project "$PROJECT_ID" --quiet
run_cmd gcloud config set run/region "$REGION" --quiet
run_cmd gcloud config set run/platform managed --quiet

success "Google Cloud configuration completed."

# ============================================================
# ENABLE APIS
# ============================================================

section "ENABLE REQUIRED APIS"

run_cmd gcloud services enable \
    run.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com \
    iam.googleapis.com \
    --project="$PROJECT_ID" \
    --quiet

success "Required APIs enabled."

# ============================================================
# GET SOURCE
# ============================================================

section "DOWNLOAD PET THEORY SOURCE"

cd "$HOME" || exit 1

if [[ -d "$HOME/pet-theory/.git" ]]; then
    info "pet-theory repository already exists."
else
    run_cmd git clone https://github.com/rosera/pet-theory.git
fi

[[ -d "$HOME/pet-theory/lab07" ]] || \
    die "pet-theory/lab07 was not found."

success "Source code ready."

# ============================================================
# TASK 1
# ============================================================

section "TASK 1 - PUBLIC BILLING SERVICE"

cd "$HOME/pet-theory/lab07/unit-api-billing" || exit 1

TASK1_IMAGE="gcr.io/${PROJECT_ID}/billing-staging-api:0.1"

info "Building:"
echo "$TASK1_IMAGE"

run_cmd gcloud builds submit \
    --tag="$TASK1_IMAGE" \
    --project="$PROJECT_ID" \
    --quiet

success "Image built."

info "Deploying $TASK_1_SERVICES_NAME..."

run_cmd gcloud run deploy "$TASK_1_SERVICES_NAME" \
    --image="$TASK1_IMAGE" \
    --region="$REGION" \
    --platform=managed \
    --allow-unauthenticated \
    --project="$PROJECT_ID" \
    --quiet

wait_for_service "$TASK_1_SERVICES_NAME"

PUBLIC_BILLING_URL=$(gcloud run services describe \
    "$TASK_1_SERVICES_NAME" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format="value(status.url)")

success "Task 1 completed."
echo
echo "${GREEN}${BOLD}$PUBLIC_BILLING_URL${RESET}"

info "Testing endpoint..."

curl -fsS "$PUBLIC_BILLING_URL" || \
    warn "Curl test returned an error."

echo

# ============================================================
# TASK 2
# ============================================================

section "TASK 2 - STAGING FRONTEND"

cd "$HOME/pet-theory/lab07/staging-frontend-billing" || exit 1

TASK2_IMAGE="gcr.io/${PROJECT_ID}/frontend-staging:0.1"

info "Building:"
echo "$TASK2_IMAGE"

run_cmd gcloud builds submit \
    --tag="$TASK2_IMAGE" \
    --project="$PROJECT_ID" \
    --quiet

success "Image built."

run_cmd gcloud run deploy "$TASK_2_SERVICES_NAME" \
    --image="$TASK2_IMAGE" \
    --region="$REGION" \
    --platform=managed \
    --allow-unauthenticated \
    --project="$PROJECT_ID" \
    --quiet

wait_for_service "$TASK_2_SERVICES_NAME"

STAGING_FRONTEND_URL=$(gcloud run services describe \
    "$TASK_2_SERVICES_NAME" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format="value(status.url)")

success "Task 2 completed."

echo
echo "${GREEN}${BOLD}$STAGING_FRONTEND_URL${RESET}"

curl -fsS -o /dev/null "$STAGING_FRONTEND_URL" \
    && success "Frontend responds successfully." \
    || warn "Frontend curl test failed."

# ============================================================
# CHECKPOINT
# ============================================================

echo
echo "${BG_BLUE}${WHITE}${BOLD}==============================================================${RESET}"
echo "${BG_BLUE}${WHITE}${BOLD}              CHECK TASK 1 AND TASK 2                         ${RESET}"
echo "${BG_BLUE}${WHITE}${BOLD}==============================================================${RESET}"
echo
echo "${YELLOW}Task 3 will delete the Task 1 public billing service.${RESET}"
echo
echo "Please click:"
echo "${GREEN}✓ Check my progress - Task 1${RESET}"
echo "${GREEN}✓ Check my progress - Task 2${RESET}"
echo
read -rp "$(echo "${YELLOW}${BOLD}After both tasks are GREEN, press ENTER...${RESET}")"

# ============================================================
# TASK 3
# ============================================================

section "TASK 3 - PRIVATE BILLING SERVICE"

info "Deleting old public billing service..."

gcloud run services delete "$TASK_1_SERVICES_NAME" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --platform=managed \
    --quiet 2>/dev/null || true

cd "$HOME/pet-theory/lab07/staging-api-billing" || exit 1

TASK3_IMAGE="gcr.io/${PROJECT_ID}/billing-staging-api:0.2"

run_cmd gcloud builds submit \
    --tag="$TASK3_IMAGE" \
    --project="$PROJECT_ID" \
    --quiet

run_cmd gcloud run deploy "$TASK_3_SERVICES_NAME" \
    --image="$TASK3_IMAGE" \
    --region="$REGION" \
    --platform=managed \
    --no-allow-unauthenticated \
    --project="$PROJECT_ID" \
    --quiet

wait_for_service "$TASK_3_SERVICES_NAME"

BILLING_URL=$(gcloud run services describe \
    "$TASK_3_SERVICES_NAME" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format="value(status.url)")

export BILLING_URL

success "Task 3 completed."
echo
echo "${GREEN}$BILLING_URL${RESET}"

info "Testing authenticated endpoint..."

curl -fsS \
    -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
    "$BILLING_URL" || \
    warn "Authenticated curl test failed."

echo

# ============================================================
# TASK 4
# ============================================================

section "TASK 4 - BILLING SERVICE ACCOUNT"

BILLING_SA_EMAIL="${TASK_4_SERVICES_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

if gcloud iam service-accounts describe "$BILLING_SA_EMAIL" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

    warn "Service Account already exists."
else

    run_cmd gcloud iam service-accounts create \
        "$TASK_4_SERVICES_NAME" \
        --display-name="Billing Service Cloud Run" \
        --project="$PROJECT_ID"
fi

success "Task 4 completed."
echo "$BILLING_SA_EMAIL"

# ============================================================
# TASK 5
# ============================================================

section "TASK 5 - PRODUCTION BILLING SERVICE"

cd "$HOME/pet-theory/lab07/prod-api-billing" || exit 1

TASK5_IMAGE="gcr.io/${PROJECT_ID}/billing-prod-api:0.1"

run_cmd gcloud builds submit \
    --tag="$TASK5_IMAGE" \
    --project="$PROJECT_ID" \
    --quiet

run_cmd gcloud run deploy "$TASK_5_SERVICES_NAME" \
    --image="$TASK5_IMAGE" \
    --service-account="$BILLING_SA_EMAIL" \
    --region="$REGION" \
    --platform=managed \
    --no-allow-unauthenticated \
    --project="$PROJECT_ID" \
    --quiet

wait_for_service "$TASK_5_SERVICES_NAME"

PROD_BILLING_URL=$(gcloud run services describe \
    "$TASK_5_SERVICES_NAME" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format="value(status.url)")

export PROD_BILLING_URL

success "Task 5 completed."

echo
echo "${GREEN}${BOLD}$PROD_BILLING_URL${RESET}"

info "Testing production billing..."

curl -fsS \
    -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
    "$PROD_BILLING_URL" || \
    warn "Authenticated curl test failed."

echo

# ============================================================
# TASK 6
# ============================================================

section "TASK 6 - FRONTEND SERVICE ACCOUNT"

FRONTEND_SA_EMAIL="${TASK_6_SERVICES_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

if gcloud iam service-accounts describe "$FRONTEND_SA_EMAIL" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

    warn "Frontend Service Account already exists."

else

    run_cmd gcloud iam service-accounts create \
        "$TASK_6_SERVICES_NAME" \
        --display-name="Billing Service Cloud Run Invoker" \
        --project="$PROJECT_ID"
fi

success "Frontend Service Account created."

info "Granting roles/run.invoker..."

run_cmd gcloud run services add-iam-policy-binding \
    "$TASK_5_SERVICES_NAME" \
    --region="$REGION" \
    --platform=managed \
    --member="serviceAccount:${FRONTEND_SA_EMAIL}" \
    --role="roles/run.invoker" \
    --project="$PROJECT_ID" \
    --quiet

success "Task 6 completed."

# ============================================================
# TASK 7
# ============================================================

section "TASK 7 - PRODUCTION FRONTEND"

cd "$HOME/pet-theory/lab07/prod-frontend-billing" || exit 1

TASK7_IMAGE="gcr.io/${PROJECT_ID}/frontend-prod:0.1"

run_cmd gcloud builds submit \
    --tag="$TASK7_IMAGE" \
    --project="$PROJECT_ID" \
    --quiet

info "Deploying frontend with:"
echo "Service Account : $FRONTEND_SA_EMAIL"
echo "Billing URL     : $PROD_BILLING_URL"

run_cmd gcloud run deploy "$TASK_7_SERVICES_NAME" \
    --image="$TASK7_IMAGE" \
    --service-account="$FRONTEND_SA_EMAIL" \
    --set-env-vars="BILLING_URL=${PROD_BILLING_URL}" \
    --region="$REGION" \
    --platform=managed \
    --allow-unauthenticated \
    --project="$PROJECT_ID" \
    --quiet

wait_for_service "$TASK_7_SERVICES_NAME"

FRONTEND_PROD_URL=$(gcloud run services describe \
    "$TASK_7_SERVICES_NAME" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format="value(status.url)")

success "Task 7 completed."

# ============================================================
# FINAL
# ============================================================

section "FINAL RESULT"

echo "${WHITE}PROJECT:${RESET}"
echo "${GREEN}$PROJECT_ID${RESET}"

echo
echo "${WHITE}REGION:${RESET}"
echo "${GREEN}$REGION${RESET}"

echo
echo "${WHITE}Private Billing:${RESET}"
echo "${GREEN}$BILLING_URL${RESET}"

echo
echo "${WHITE}Production Billing:${RESET}"
echo "${GREEN}$PROD_BILLING_URL${RESET}"

echo
echo "${WHITE}Production Frontend:${RESET}"
echo "${GREEN}${BOLD}$FRONTEND_PROD_URL${RESET}"

echo
echo "${CYAN}${BOLD}Cloud Run Services:${RESET}"

gcloud run services list \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --format="table(
        metadata.name:label=SERVICE,
        status.url:label=URL,
        spec.template.spec.serviceAccountName:label=SERVICE_ACCOUNT
    )"

echo
echo "${BG_GREEN}${BLACK}${BOLD}==============================================================${RESET}"
echo "${BG_GREEN}${BLACK}${BOLD}                  LAB COMPLETED                               ${RESET}"
echo "${BG_GREEN}${BLACK}${BOLD}                    © ePlus.DEV                               ${RESET}"
echo "${BG_GREEN}${BLACK}${BOLD}==============================================================${RESET}"
echo
echo "${YELLOW}${BOLD}Production Frontend:${RESET}"
echo "${GREEN}${BOLD}$FRONTEND_PROD_URL${RESET}"
echo