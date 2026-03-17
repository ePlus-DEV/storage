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

# Welcome message
clear
echo "${BG_BLUE}${BOLD}${WHITE}╔════════════════════════════════════════════════════════╗${RESET}"
echo "${BG_BLUE}${BOLD}${WHITE}   Welcome to ePlus.DEV Cloud Lab Setup Script        ${RESET}"
echo "${BG_BLUE}${BOLD}${WHITE}╚════════════════════════════════════════════════════════╝${RESET}"
echo
echo "${GREEN}${BOLD}This script will help you set up your cloud lab environment${RESET}"
echo "${CYAN}For more tutorials, visit: https://eplus.dev${RESET}"
echo

echo "${RANDOM_BG_COLOR}${RANDOM_TEXT_COLOR}${BOLD}Starting Execution${RESET}"

# Step 1: Get default zone & region
echo "${BOLD}${BLUE}Getting default zone & region${RESET}"
export ZONE_1=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-zone])")

export REGION_1=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-region])")

gcloud config set compute/zone $ZONE_1
gcloud config set compute/region $REGION_1

get_and_export_zones() {
  echo
  echo "${YELLOW}${BOLD}Please enter values for the following:${RESET}"

  echo
  read -p "$(echo -e "${CYAN}${BOLD}Enter ZONE_2 (e.g., us-central1-a): ${RESET}")" ZONE_2
  export ZONE_2=$ZONE_2
  REGION_2=$(echo "$ZONE_2" | sed 's/-[a-z]$//')
  export REGION_2=$REGION_2

  echo

  read -p "$(echo -e "${CYAN}${BOLD}Enter ZONE_3 (e.g., us-central1-b): ${RESET}")" ZONE_3
  export ZONE_3=$ZONE_3
  REGION_3=$(echo "$ZONE_3" | sed 's/-[a-z]$//')
  export REGION_3=$REGION_3
  echo
}

get_and_export_zones

# Step 2: Create VM us-test-01
echo "${BOLD}${BLUE}Creating instance us-test-01${RESET}"
gcloud compute instances create us-test-01 \
--subnet subnet-$REGION_1 \
--zone $ZONE_1 \
--machine-type e2-standard-2 \
--tags ssh,http,rules

# Step 3: Create VM us-test-02
echo "${BOLD}${GREEN}Creating instance us-test-02${RESET}"
gcloud compute instances create us-test-02 \
--subnet subnet-$REGION_2 \
--zone $ZONE_2 \
--machine-type e2-standard-2 \
--tags ssh,http,rules

# Step 4: Create VM us-test-03
echo "${BOLD}${CYAN}Creating instance us-test-03${RESET}"
gcloud compute instances create us-test-03 \
--subnet subnet-$REGION_3 \
--zone $ZONE_3 \
--machine-type e2-standard-2 \
--tags ssh,http,rules

# Step 5: Create VM us-test-04
echo "${BOLD}${YELLOW}Creating instance us-test-04${RESET}"
gcloud compute instances create us-test-04 \
--subnet subnet-$REGION_1 \
--zone $ZONE_1 \
--tags ssh,http

# Step 6: Install tools on us-test-01
echo "${BOLD}${RED}Installing tools on us-test-01${RESET}"
cat > prepare_disk.sh <<'EOF_END'
sudo apt-get update
sudo apt-get -y install traceroute mtr tcpdump iperf whois host dnsutils siege

timeout 10 traceroute -m 8 www.icann.org
EOF_END

gcloud compute scp prepare_disk.sh us-test-01:/tmp --project=$DEVSHELL_PROJECT_ID --zone=$ZONE_1 --quiet
gcloud compute ssh us-test-01 --project=$DEVSHELL_PROJECT_ID --zone=$ZONE_1 --quiet --command="bash /tmp/prepare_disk.sh"

# Step 7: Install tools on us-test-02
echo "${BOLD}${BLUE}Installing tools on us-test-02${RESET}"
cat > prepare_disk.sh <<'EOF_END'
sudo apt-get update
sudo apt-get -y install traceroute mtr tcpdump iperf whois host dnsutils siege

timeout 10 traceroute -m 8 www.icann.org
EOF_END

gcloud compute scp prepare_disk.sh us-test-02:/tmp --project=$DEVSHELL_PROJECT_ID --zone=$ZONE_2 --quiet
gcloud compute ssh us-test-02 --project=$DEVSHELL_PROJECT_ID --zone=$ZONE_2 --quiet --command="bash /tmp/prepare_disk.sh"

# Step 8: Start iperf server on us-test-01
echo "${BOLD}${GREEN}Starting iperf server on us-test-01${RESET}"
cat > prepare_disk.sh <<'EOF_END'
nohup iperf -s > iperf-server.log 2>&1 &
EOF_END

gcloud compute scp prepare_disk.sh us-test-01:/tmp --project=$DEVSHELL_PROJECT_ID --zone=$ZONE_1 --quiet
gcloud compute ssh us-test-01 --project=$DEVSHELL_PROJECT_ID --zone=$ZONE_1 --quiet --command="bash /tmp/prepare_disk.sh"

# Step 9: Run iperf client from us-test-02 to us-test-01
echo "${BOLD}${CYAN}Running iperf client on us-test-02${RESET}"
cat > prepare_disk.sh <<EOF_END
sudo apt-get update

sudo apt-get -y install traceroute mtr tcpdump iperf whois host dnsutils siege

iperf -c us-test-01.$ZONE_1 #run in client mode
EOF_END

gcloud compute scp prepare_disk.sh us-test-02:/tmp --project=$DEVSHELL_PROJECT_ID --zone=$ZONE_2 --quiet
gcloud compute ssh us-test-02 --project=$DEVSHELL_PROJECT_ID --zone=$ZONE_2 --quiet --command="bash /tmp/prepare_disk.sh"

# Step 10: Install tools on us-test-04
echo "${BOLD}${MAGENTA}Installing tools on us-test-04${RESET}"
cat > prepare_disk.sh <<'EOF_END'
sudo apt-get update

sudo apt-get -y install traceroute mtr tcpdump iperf whois host dnsutils siege
EOF_END

gcloud compute scp prepare_disk.sh us-test-04:/tmp --project=$DEVSHELL_PROJECT_ID --zone=$ZONE_1 --quiet
gcloud compute ssh us-test-04 --project=$DEVSHELL_PROJECT_ID --zone=$ZONE_1 --quiet --command="bash /tmp/prepare_disk.sh"

echo

# Completion message
echo
echo "${BG_GREEN}${BOLD}${BLACK}╔════════════════════════════════════════════════════════╗${RESET}"
echo "${BG_GREEN}${BOLD}${BLACK}   Congratulations! Lab Setup Completed Successfully!      ${RESET}"
echo "${BG_GREEN}${BOLD}${BLACK}╚════════════════════════════════════════════════════════╝${RESET}"
echo
echo "${MAGENTA}${BOLD}Thank you for using ePlus.DEV Cloud Lab Setup Script${RESET}"
echo "${CYAN}${BOLD}For more tutorials and cloud computing content, subscribe to:${RESET}"
echo "${BLUE}${UNDERLINE}https://eplus.dev${RESET}"
echo

# Cleanup function
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