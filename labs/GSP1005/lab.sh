#!/bin/bash

# Define color variables
BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'

NO_COLOR=$'\033[0m'
RESET_FORMAT=$'\033[0m'

# Define text formatting variables
BOLD_TEXT=$'\033[1m'
UNDERLINE_TEXT=$'\033[4m'

clear

# Welcome message with Dr. Abhishek reference
echo
echo "${MAGENTA_TEXT}${BOLD_TEXT}Learn Secrets Management with HashiCorp Vault${RESET_FORMAT}"
echo

# Check authentication
echo "${YELLOW_TEXT}${BOLD_TEXT}Checking Google Cloud authentication...${RESET_FORMAT}"
gcloud auth list

export PROJECT_ID=$(gcloud config get-value project)
echo "${BLUE_TEXT}Project ID: $PROJECT_ID${RESET_FORMAT}"

echo
echo "${GREEN_TEXT}${BOLD_TEXT}Starting HashiCorp Vault Installation...${RESET_FORMAT}"

# Install HashiCorp Vault
echo "${YELLOW_TEXT}${BOLD_TEXT}Adding HashiCorp repository and installing Vault...${RESET_FORMAT}"
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -

sudo apt-add-repository -y "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"

sudo apt-get update
sudo apt-get install -y vault

echo "${GREEN_TEXT}${BOLD_TEXT}Vault installation completed successfully!${RESET_FORMAT}"

# Verify Vault installation
echo "${YELLOW_TEXT}${BOLD_TEXT}Verifying Vault installation...${RESET_FORMAT}"
vault --version

# Start Vault server in development mode
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}Starting Vault server in development mode...${RESET_FORMAT}"
nohup vault server -dev > vault_server.log 2>&1 &

sleep 5

# Set Vault address
export VAULT_ADDR='http://127.0.0.1:8200'

# Check Vault status
echo "${YELLOW_TEXT}${BOLD_TEXT}Checking Vault server status...${RESET_FORMAT}"
vault status

if [ $? -eq 0 ]; then
    echo "${GREEN_TEXT}${BOLD_TEXT}Vault server is running successfully!${RESET_FORMAT}"
else
    echo "${RED_TEXT}${BOLD_TEXT}Vault server failed to start. Check vault_server.log for details.${RESET_FORMAT}"
    exit 1
fi

echo
echo "${GREEN_TEXT}${BOLD_TEXT}Configuring Vault Secrets and Authentication...${RESET_FORMAT}"

# Store initial secret
echo "${YELLOW_TEXT}${BOLD_TEXT}Storing MySQL credentials in Vault...${RESET_FORMAT}"
vault kv put secret/mysql/webapp db_name="users" username="admin" password="passw0rd"

# Enable AppRole authentication
echo "${YELLOW_TEXT}${BOLD_TEXT}Enabling AppRole authentication method...${RESET_FORMAT}"
vault auth enable approle

# Create Jenkins policy
echo "${YELLOW_TEXT}${BOLD_TEXT}Creating Jenkins policy...${RESET_FORMAT}"
vault policy write jenkins -<<EOF
# Read-only permission on secrets stored at 'secret/data/mysql/webapp'
path "secret/data/mysql/webapp" {
  capabilities = [ "read" ]
}
EOF

# Create AppRole for Jenkins
echo "${YELLOW_TEXT}${BOLD_TEXT}Creating AppRole for Jenkins...${RESET_FORMAT}"
vault write auth/approle/role/jenkins token_policies="jenkins" \
    token_ttl=1h token_max_ttl=4h

# Display AppRole configuration
echo "${YELLOW_TEXT}${BOLD_TEXT}AppRole configuration:${RESET_FORMAT}"
vault read auth/approle/role/jenkins

echo
echo "${GREEN_TEXT}${BOLD_TEXT}Generating AppRole Credentials...${RESET_FORMAT}"

# Get Role ID and Secret ID
ROLE_ID=$(vault read -field=role_id auth/approle/role/jenkins/role-id)
SECRET_ID=$(vault write -force -field=secret_id auth/approle/role/jenkins/secret-id)

echo "${BLUE_TEXT}Role ID: $ROLE_ID${RESET_FORMAT}"
echo "${BLUE_TEXT}Secret ID: $SECRET_ID${RESET_FORMAT}"

# Login with AppRole and get token
echo "${YELLOW_TEXT}${BOLD_TEXT}Logging in with AppRole...${RESET_FORMAT}"
TOKEN=$(vault write -field=token auth/approle/login role_id="$ROLE_ID" secret_id="$SECRET_ID")

export APP_TOKEN="$TOKEN"
echo "${BLUE_TEXT}Application Token: $APP_TOKEN${RESET_FORMAT}"

# Test the token by reading secrets
echo
echo "${GREEN_TEXT}${BOLD_TEXT}Testing AppRole Access...${RESET_FORMAT}"

echo "${YELLOW_TEXT}${BOLD_TEXT}Reading MySQL credentials with AppRole token:${RESET_FORMAT}"
VAULT_TOKEN=$APP_TOKEN vault kv get secret/mysql/webapp

# Extract individual secret values to files
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}Extracting secret values to files...${RESET_FORMAT}"
VAULT_TOKEN=$APP_TOKEN vault kv get -format=json secret/mysql/webapp | jq -r .data.data.db_name > db_name.txt
VAULT_TOKEN=$APP_TOKEN vault kv get -format=json secret/mysql/webapp | jq -r .data.data.password > password.txt
VAULT_TOKEN=$APP_TOKEN vault kv get -format=json secret/mysql/webapp | jq -r .data.data.username > username.txt

echo "${GREEN_TEXT}${BOLD_TEXT}Secret values extracted to:${RESET_FORMAT}"
echo "${BLUE_TEXT}- db_name.txt${RESET_FORMAT}"
echo "${BLUE_TEXT}- password.txt${RESET_FORMAT}"
echo "${BLUE_TEXT}- username.txt${RESET_FORMAT}"

# Display the extracted values
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}Extracted Values:${RESET_FORMAT}"
echo "Database Name: $(cat db_name.txt)"
echo "Username: $(cat username.txt)"
echo "Password: $(cat password.txt)"

# Upload to Google Cloud Storage
echo
echo "${GREEN_TEXT}${BOLD_TEXT}Uploading secret files to Google Cloud Storage...${RESET_FORMAT}"
gsutil cp *.txt gs://$PROJECT_ID

if [ $? -eq 0 ]; then
    echo "${GREEN_TEXT}${BOLD_TEXT}Files successfully uploaded to gs://$PROJECT_ID${RESET_FORMAT}"
else
    echo "${RED_TEXT}${BOLD_TEXT}Failed to upload files to Cloud Storage${RESET_FORMAT}"
fi

# Final message with Dr. Abhishek references
echo
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}        HASHICORP VAULT LAB COMPLETED SUCCESSFULLY!    ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}=======================================================${RESET_FORMAT}"
echo
echo "${BLUE_TEXT}${BOLD_TEXT}https://eplus.dev${RESET_FORMAT}"
echo
echo
echo "${CYAN_TEXT}${BOLD_TEXT}Lab Summary:${RESET_FORMAT}"
echo "${WHITE_TEXT}✓ Vault installed and configured${RESET_FORMAT}"
echo "${WHITE_TEXT}✓ Secrets stored and managed${RESET_FORMAT}"
echo "${WHITE_TEXT}✓ AppRole authentication enabled${RESET_FORMAT}"
echo "${WHITE_TEXT}✓ Jenkins policy created${RESET_FORMAT}"
echo "${WHITE_TEXT}✓ Secure secret retrieval demonstrated${RESET_FORMAT}"
echo "${WHITE_TEXT}✓ Files uploaded to Cloud Storage${RESET_FORMAT}"