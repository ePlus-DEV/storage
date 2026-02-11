#!/bin/bash
# Google Cloud Monitoring & Prometheus Lab

# ======================
BOLD=$(tput bold)
UNDERLINE=$(tput smul)
RESET=$(tput sgr0)

# Text Colors
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)

# Background Colors
BG_RED=$(tput setab 1)
BG_GREEN=$(tput setab 2)
BG_YELLOW=$(tput setab 3)
BG_BLUE=$(tput setab 4)
BG_MAGENTA=$(tput setab 5)
BG_CYAN=$(tput setab 6)

# Random color selection
COLORS=($RED $GREEN $YELLOW $BLUE $MAGENTA $CYAN)
RAND_COLOR=${COLORS[$RANDOM % ${#COLORS[@]}]}


# ======================
clear
echo "${BG_BLUE}${BOLD}${WHITE}=============================${RESET}"
echo "${BG_BLUE}${BOLD}${WHITE}   WELCOME TO EPLUS.DEV     ${RESET}"
echo "${BG_BLUE}${BOLD}${WHITE}=============================${RESET}"
echo ""
echo "${YELLOW}${BOLD}🌍 Website: ${UNDERLINE}https://eplus.dev${RESET}"
echo ""

gcloud auth list

git clone https://github.com/GoogleCloudPlatform/policy-library.git

cd policy-library/
cp samples/iam_service_accounts_only.yaml policies/constraints

cat policies/constraints/iam_service_accounts_only.yaml

cat > main.tf <<EOF_END
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "~> 3.84"
    }
  }
}

resource "google_project_iam_binding" "sample_iam_binding" {
  project = "$DEVSHELL_PROJECT_ID"
  role    = "roles/viewer"

  members = [
    "user:$USER_EMAIL"
  ]
}
EOF_END

terraform init

terraform plan -out=test.tfplan

terraform show -json ./test.tfplan > ./tfplan.json

sudo apt-get install google-cloud-sdk-terraform-tools

gcloud beta terraform vet tfplan.json --policy-library=.


cd policies/constraints


cat > iam_service_accounts_only.yaml <<EOF_END
apiVersion: constraints.gatekeeper.sh/v1alpha1
kind: GCPIAMAllowedPolicyMemberDomainsConstraintV1
metadata:
  name: service_accounts_only
spec:
  severity: high
  match:
    target: ["organizations/**"]
  parameters:
    domains:
      - gserviceaccount.com
      - qwiklabs.net
EOF_END


cd ~

cd policy-library

terraform plan -out=test.tfplan

gcloud beta terraform vet tfplan.json --policy-library=.

terraform apply test.tfplan

terraform plan -out=test.tfplan

gcloud beta terraform vet tfplan.json --policy-library=.

terraform apply test.tfplan

echo "${GREEN}✔ Cleanup complete - ePlus.DEV${RESET}"