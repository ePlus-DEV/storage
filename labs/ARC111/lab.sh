#!/bin/bash

# Define color variables
BLACK=$(tput setaf 0)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)

BG_BLACK=$(tput setab 0)
BG_RED=$(tput setab 1)
BG_GREEN=$(tput setab 2)
BG_YELLOW=$(tput setab 3)
BG_BLUE=$(tput setab 4)
BG_MAGENTA=$(tput setab 5)
BG_CYAN=$(tput setab 6)
BG_WHITE=$(tput setab 7)

BOLD=$(tput bold)
RESET=$(tput sgr0)

#----------------------------------------------------start--------------------------------------------------#

clear

echo "${MAGENTA}${BOLD}====================================================${RESET}"
echo "${MAGENTA}${BOLD}        ePlus.DEV - STARTING EXECUTION              ${RESET}"
echo "${MAGENTA}${BOLD}====================================================${RESET}"
echo

# Remove gs:// prefix if the user enters it
normalize_bucket_name() {
    local bucket_name="$1"
    bucket_name="${bucket_name#gs://}"
    bucket_name="${bucket_name%/}"
    echo "$bucket_name"
}

# Read and validate bucket name
read_bucket() {
    local variable_name="$1"
    local bucket_number="$2"
    local color="$3"
    local bucket_value=""

    while [[ -z "$bucket_value" ]]; do
        echo -ne "${color}${BOLD}Enter Bucket ${bucket_number} name: ${RESET}"
        read -r bucket_value

        bucket_value=$(normalize_bucket_name "$bucket_value")

        if [[ -z "$bucket_value" ]]; then
            echo "${RED}${BOLD}Bucket name cannot be empty. Please try again.${RESET}"
        fi
    done

    printf -v "$variable_name" '%s' "$bucket_value"
    export "$variable_name"
}

# Select form
echo "${WHITE}${BOLD}Select the lab form:${RESET}"
echo "${GREEN}${BOLD}  1) Form 1${RESET}"
echo "${CYAN}${BOLD}  2) Form 2${RESET}"
echo "${YELLOW}${BOLD}  3) Form 3${RESET}"
echo

while true; do
    echo -ne "${MAGENTA}${BOLD}Enter Form Number (1, 2, or 3): ${RESET}"
    read -r form_number

    case "$form_number" in
        1|2|3)
            break
            ;;
        *)
            echo "${RED}${BOLD}Invalid form number. Please enter 1, 2, or 3.${RESET}"
            ;;
    esac
done

echo
echo "${WHITE}${BOLD}Enter the bucket names from the lab instructions.${RESET}"
echo "${WHITE}You can enter either:${RESET}"
echo "${WHITE}  bucket-name${RESET}"
echo "${WHITE}  gs://bucket-name${RESET}"
echo

# Bucket 1: Green
read_bucket "BUCKET_1" "1" "$GREEN"

# Bucket 2: Cyan
read_bucket "BUCKET_2" "2" "$CYAN"

# Bucket 3: Yellow
read_bucket "BUCKET_3" "3" "$YELLOW"

echo
echo "${MAGENTA}${BOLD}---------------- Configuration ----------------${RESET}"
echo "${GREEN}${BOLD}BUCKET_1:${RESET} gs://${BUCKET_1}"
echo "${CYAN}${BOLD}BUCKET_2:${RESET} gs://${BUCKET_2}"
echo "${YELLOW}${BOLD}BUCKET_3:${RESET} gs://${BUCKET_3}"
echo "${MAGENTA}${BOLD}-------------------------------------------------${RESET}"
echo

# Automatically get the currently authenticated account
USER_EMAIL=$(gcloud config get-value account 2>/dev/null)

# Prompt for email if it cannot be detected
if [[ "$form_number" == "2" && ( -z "$USER_EMAIL" || "$USER_EMAIL" == "(unset)" ) ]]; then
    echo -ne "${BLUE}${BOLD}Enter your lab user email: ${RESET}"
    read -r USER_EMAIL
fi

export USER_EMAIL

# Form 1
run_form_1() {
    echo "${GREEN}${BOLD}Running Form 1...${RESET}"
    echo

    echo "${GREEN}${BOLD}[1/4] Creating Coldline bucket:${RESET} gs://${BUCKET_1}"
    gsutil mb -c coldline "gs://${BUCKET_1}"

    echo
    echo "${CYAN}${BOLD}[2/4] Setting 30-second retention policy:${RESET} gs://${BUCKET_2}"
    gsutil retention set 30s "gs://${BUCKET_2}"

    echo
    echo "${YELLOW}${BOLD}[3/4] Creating sample.txt...${RESET}"
    echo "Awesome Lab" > sample.txt

    echo
    echo "${YELLOW}${BOLD}[4/4] Uploading sample.txt:${RESET} gs://${BUCKET_3}"
    gsutil cp sample.txt "gs://${BUCKET_3}/"
}

# Form 2
run_form_2() {
    echo "${CYAN}${BOLD}Running Form 2...${RESET}"
    echo

    echo "${GREEN}${BOLD}[1/7] Creating bucket:${RESET} gs://${BUCKET_1}"
    gsutil mb "gs://${BUCKET_1}"

    echo
    echo "${CYAN}${BOLD}[2/7] Disabling Uniform Bucket-Level Access:${RESET} gs://${BUCKET_2}"
    gcloud storage buckets update "gs://${BUCKET_2}" \
        --no-uniform-bucket-level-access

    echo
    echo "${CYAN}${BOLD}[3/7] Granting OWNER permission to:${RESET} ${USER_EMAIL}"
    gsutil acl ch -u "${USER_EMAIL}:OWNER" "gs://${BUCKET_2}"

    echo
    echo "${CYAN}${BOLD}[4/7] Removing existing sample.txt if present...${RESET}"
    gsutil rm "gs://${BUCKET_2}/sample.txt" 2>/dev/null || true

    echo
    echo "${CYAN}${BOLD}[5/7] Creating and uploading sample.txt...${RESET}"
    echo "Awesome Lab" > sample.txt
    gsutil cp sample.txt "gs://${BUCKET_2}/sample.txt"

    echo
    echo "${CYAN}${BOLD}[6/7] Making sample.txt publicly readable...${RESET}"
    gsutil acl ch -u allUsers:R "gs://${BUCKET_2}/sample.txt"

    echo
    echo "${YELLOW}${BOLD}[7/7] Adding label to bucket:${RESET} gs://${BUCKET_3}"
    gcloud storage buckets update "gs://${BUCKET_3}" \
        --update-labels=key=value
}

# Form 3
run_form_3() {
    echo "${YELLOW}${BOLD}Running Form 3...${RESET}"
    echo

    echo "${GREEN}${BOLD}[1/3] Creating Nearline bucket:${RESET} gs://${BUCKET_1}"
    gsutil mb -c nearline "gs://${BUCKET_1}"

    echo
    echo "${CYAN}${BOLD}[2/3] Creating sample.txt in:${RESET} gs://${BUCKET_2}"
    echo "This is an example of editing the file content for cloud storage object" \
        | gsutil cp - "gs://${BUCKET_2}/sample.txt"

    echo
    echo "${YELLOW}${BOLD}[3/3] Setting default storage class to ARCHIVE:${RESET} gs://${BUCKET_3}"
    gsutil defstorageclass set ARCHIVE "gs://${BUCKET_3}"
}

# Execute selected form
case "$form_number" in
    1)
        run_form_1
        ;;
    2)
        run_form_2
        ;;
    3)
        run_form_3
        ;;
esac

# Clean up local sample file
rm -f sample.txt

echo
echo "${GREEN}${BOLD}====================================================${RESET}"
echo "${GREEN}${BOLD}       Congratulations! Lab tasks completed.        ${RESET}"
echo "${GREEN}${BOLD}                    ePlus.DEV                       ${RESET}"
echo "${GREEN}${BOLD}====================================================${RESET}"

#-----------------------------------------------------end----------------------------------------------------------#