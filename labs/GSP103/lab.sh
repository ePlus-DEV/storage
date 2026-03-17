clear

#!/bin/bash
# Define color variables

BLACK=`tput setaf 0`
RED=`tput setaf 1`
GREEN=`tput setaf 2`
YELLOW=`tput setaf 3`
BLUE=`tput setaf 4`
MAGENTA=`tput setaf 5`
CYAN=`tput setaf 6`
WHITE=`tput setaf 7`

BG_BLACK=`tput setab 0`
BG_RED=`tput setab 1`
BG_GREEN=`tput setab 2`
BG_YELLOW=`tput setab 3`
BG_BLUE=`tput setab 4`
BG_MAGENTA=`tput setab 5`
BG_CYAN=`tput setab 6`
BG_WHITE=`tput setab 7`

BOLD=`tput bold`
RESET=`tput sgr0`

# Array of color codes excluding black and white
TEXT_COLORS=($RED $GREEN $YELLOW $BLUE $MAGENTA $CYAN)
BG_COLORS=($BG_RED $BG_GREEN $BG_YELLOW $BG_BLUE $BG_MAGENTA $BG_CYAN)

# Pick random colors
RANDOM_TEXT_COLOR=${TEXT_COLORS[$RANDOM % ${#TEXT_COLORS[@]}]}
RANDOM_BG_COLOR=${BG_COLORS[$RANDOM % ${#BG_COLORS[@]}]}

#----------------------------------------------------start--------------------------------------------------#

echo "${RANDOM_BG_COLOR}${RANDOM_TEXT_COLOR}${BOLD}Starting Execution - ePlus.DEV${RESET}"

CLUSTER_NAME="example-cluster"

run_cmd() {
    "$@"
    local status=$?
    if [ $status -ne 0 ]; then
        echo "${RED}${BOLD}Command failed:${RESET} $*"
        exit $status
    fi
}

# Step 1: Set Compute Zone
echo "${BOLD}${BLUE}Setting Compute Zone${RESET}"
export ZONE=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-zone])")

# Step 2: Set Compute Region
echo "${BOLD}${GREEN}Setting Compute Region${RESET}"
export REGION=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-region])")

# Fallback in case default region is empty
if [[ -z "$REGION" && -n "$ZONE" ]]; then
    REGION="${ZONE%-*}"
fi

# Step 3: Get Project Number
echo "${BOLD}${YELLOW}Getting Project Number${RESET}"
export PROJECT_NUMBER="$(gcloud projects describe $DEVSHELL_PROJECT_ID --format='get(projectNumber)')"

echo "${CYAN}${BOLD}Project:${RESET} $DEVSHELL_PROJECT_ID"
echo "${CYAN}${BOLD}Project Number:${RESET} $PROJECT_NUMBER"
echo "${CYAN}${BOLD}Region:${RESET} $REGION"
echo "${CYAN}${BOLD}Zone:${RESET} $ZONE"

# Step 4: Enable required APIs
echo "${BOLD}${MAGENTA}Enabling Required APIs${RESET}"
run_cmd gcloud services enable dataproc.googleapis.com compute.googleapis.com storage.googleapis.com

# Step 5: Grant Storage Admin Role
echo "${BOLD}${MAGENTA}Granting Storage Admin Role to Compute Service Account${RESET}"
gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID \
    --member serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com \
    --role roles/storage.objectAdmin --quiet >/dev/null

# Step 6: Grant Dataproc Worker Role
echo "${BOLD}${CYAN}Granting Dataproc Worker Role to Compute Service Account${RESET}"
gcloud projects add-iam-policy-binding $DEVSHELL_PROJECT_ID \
    --member serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com \
    --role roles/dataproc.worker --quiet >/dev/null

# Wait for IAM propagation
echo "${BOLD}${YELLOW}Waiting for IAM propagation${RESET}"
sleep 20

# Step 7: Check existing cluster
echo "${BOLD}${BLUE}Checking Existing Dataproc Cluster${RESET}"
EXISTING_STATE=$(gcloud dataproc clusters describe "$CLUSTER_NAME" \
    --region "$REGION" \
    --format="value(status.state)" 2>/dev/null)

if [[ -n "$EXISTING_STATE" ]]; then
    echo "${YELLOW}${BOLD}Cluster already exists with state:${RESET} $EXISTING_STATE"

    if [[ "$EXISTING_STATE" == "ERROR" || "$EXISTING_STATE" == "CREATING" || "$EXISTING_STATE" == "DELETING" || "$EXISTING_STATE" == "UPDATING" ]]; then
        echo "${RED}${BOLD}Deleting unusable cluster:${RESET} $CLUSTER_NAME"
        run_cmd gcloud dataproc clusters delete "$CLUSTER_NAME" \
            --region "$REGION" \
            --quiet
        EXISTING_STATE=""
    fi
fi

# Step 8: Create Dataproc Cluster if needed
if [[ -z "$EXISTING_STATE" ]]; then
    echo "${BOLD}${RED}Creating Dataproc Cluster${RESET}"
    run_cmd gcloud dataproc clusters create "$CLUSTER_NAME" \
        --enable-component-gateway \
        --region "$REGION" \
        --zone "$ZONE" \
        --master-machine-type e2-standard-2 \
        --master-boot-disk-size 30 \
        --num-workers 2 \
        --worker-machine-type e2-standard-2 \
        --worker-boot-disk-size 30 \
        --image-version 2.2-debian12 \
        --project "$DEVSHELL_PROJECT_ID"
else
    echo "${GREEN}${BOLD}Using existing healthy cluster:${RESET} $CLUSTER_NAME"
fi

# Step 9: Verify cluster status
echo "${BOLD}${GREEN}Verifying Cluster Status${RESET}"
CURRENT_STATE=$(gcloud dataproc clusters describe "$CLUSTER_NAME" \
    --region "$REGION" \
    --format="value(status.state)")

echo "${CYAN}${BOLD}Current cluster state:${RESET} $CURRENT_STATE"

if [[ "$CURRENT_STATE" != "RUNNING" ]]; then
    echo "${RED}${BOLD}Cluster is not RUNNING. Current state:${RESET} $CURRENT_STATE"
    exit 1
fi

# Step 10: Submit Spark Job
echo "${BOLD}${BLUE}Submitting Spark Job to Cluster${RESET}"
run_cmd gcloud dataproc jobs submit spark \
    --cluster "$CLUSTER_NAME" \
    --region "$REGION" \
    --class org.apache.spark.examples.SparkPi \
    --jars file:///usr/lib/spark/examples/jars/spark-examples.jar \
    -- 1000

# Step 11: Update Cluster Worker Count
echo "${BOLD}${GREEN}Updating Cluster to Increase Number of Workers${RESET}"
run_cmd gcloud dataproc clusters update "$CLUSTER_NAME" \
    --region "$REGION" \
    --num-workers 4

echo

# Function to display a random congratulatory message
function random_congrats() {
    MESSAGES=(
        "${GREEN}Congratulations For Completing The Lab! Keep up the great work!${RESET}"
        "${CYAN}Well done! Your hard work and effort have paid off!${RESET}"
        "${YELLOW}Amazing job! You’ve successfully completed the lab!${RESET}"
        "${BLUE}Outstanding! Your dedication has brought you success!${RESET}"
        "${MAGENTA}Great work! You’re one step closer to mastering this!${RESET}"
        "${RED}Fantastic effort! You’ve earned this achievement!${RESET}"
        "${CYAN}Congratulations! Your persistence has paid off brilliantly!${RESET}"
        "${GREEN}Bravo! You’ve completed the lab with flying colors!${RESET}"
        "${YELLOW}Excellent job! Your commitment is inspiring!${RESET}"
        "${BLUE}You did it! Keep striving for more successes like this!${RESET}"
        "${MAGENTA}Kudos! Your hard work has turned into a great accomplishment!${RESET}"
        "${RED}You’ve smashed it! Completing this lab shows your dedication!${RESET}"
        "${CYAN}Impressive work! You’re making great strides!${RESET}"
        "${GREEN}Well done! This is a big step towards mastering the topic!${RESET}"
        "${YELLOW}You nailed it! Every step you took led you to success!${RESET}"
        "${BLUE}Exceptional work! Keep this momentum going!${RESET}"
        "${MAGENTA}Fantastic! You’ve achieved something great today!${RESET}"
        "${RED}Incredible job! Your determination is truly inspiring!${RESET}"
        "${CYAN}Well deserved! Your effort has truly paid off!${RESET}"
        "${GREEN}You’ve got this! Every step was a success!${RESET}"
        "${YELLOW}Nice work! Your focus and effort are shining through!${RESET}"
        "${BLUE}Superb performance! You’re truly making progress!${RESET}"
        "${MAGENTA}Top-notch! Your skill and dedication are paying off!${RESET}"
        "${RED}Mission accomplished! This success is a reflection of your hard work!${RESET}"
        "${CYAN}You crushed it! Keep pushing towards your goals!${RESET}"
        "${GREEN}You did a great job! Stay motivated and keep learning!${RESET}"
        "${YELLOW}Well executed! You’ve made excellent progress today!${RESET}"
        "${BLUE}Remarkable! You’re on your way to becoming an expert!${RESET}"
        "${MAGENTA}Keep it up! Your persistence is showing impressive results!${RESET}"
        "${RED}This is just the beginning! Your hard work will take you far!${RESET}"
        "${CYAN}Terrific work! Your efforts are paying off in a big way!${RESET}"
        "${GREEN}You’ve made it! This achievement is a testament to your effort!${RESET}"
        "${YELLOW}Excellent execution! You’re well on your way to mastering the subject!${RESET}"
        "${BLUE}Wonderful job! Your hard work has definitely paid off!${RESET}"
        "${MAGENTA}You’re amazing! Keep up the awesome work!${RESET}"
        "${RED}What an achievement! Your perseverance is truly admirable!${RESET}"
        "${CYAN}Incredible effort! This is a huge milestone for you!${RESET}"
        "${GREEN}Awesome! You’ve done something incredible today!${RESET}"
        "${YELLOW}Great job! Keep up the excellent work and aim higher!${RESET}"
        "${BLUE}You’ve succeeded! Your dedication is your superpower!${RESET}"
        "${MAGENTA}Congratulations! Your hard work has brought great results!${RESET}"
        "${RED}Fantastic work! You’ve taken a huge leap forward today!${RESET}"
        "${CYAN}You’re on fire! Keep up the great work!${RESET}"
        "${GREEN}Well deserved! Your efforts have led to success!${RESET}"
        "${YELLOW}Incredible! You’ve achieved something special!${RESET}"
        "${BLUE}Outstanding performance! You’re truly excelling!${RESET}"
        "${MAGENTA}Terrific achievement! Keep building on this success!${RESET}"
        "${RED}Bravo! You’ve completed the lab with excellence!${RESET}"
        "${CYAN}Superb job! You’ve shown remarkable focus and effort!${RESET}"
        "${GREEN}Amazing work! You’re making impressive progress!${RESET}"
        "${YELLOW}You nailed it again! Your consistency is paying off!${RESET}"
        "${BLUE}Incredible dedication! Keep pushing forward!${RESET}"
        "${MAGENTA}Excellent work! Your success today is well earned!${RESET}"
        "${RED}You’ve made it! This is a well-deserved victory!${RESET}"
        "${CYAN}Wonderful job! Your passion and hard work are shining through!${RESET}"
        "${GREEN}You’ve done it! Keep up the hard work and success will follow!${RESET}"
        "${YELLOW}Great execution! You’re truly mastering this!${RESET}"
        "${BLUE}Impressive! This is just the beginning of your journey!${RESET}"
        "${MAGENTA}You’ve achieved something great today! Keep it up!${RESET}"
        "${RED}You’ve made remarkable progress! This is just the start!${RESET}"
    )

    RANDOM_INDEX=$((RANDOM % ${#MESSAGES[@]}))
    echo -e "${BOLD}${MESSAGES[$RANDOM_INDEX]} - ePlus.DEV"
}

# Display a random congratulatory message
random_congrats

echo -e "\n"

cd

remove_files() {
    # Loop through all files in the current directory
    for file in *; do
        # Check if the file name starts with "gsp", "arc", or "shell"
        if [[ "$file" == gsp* || "$file" == arc* || "$file" == shell* ]]; then
            # Check if it's a regular file (not a directory)
            if [[ -f "$file" ]]; then
                # Remove the file and echo the file name
                rm "$file"
                echo "File removed: $file"
            fi
        fi
    done
}

remove_files