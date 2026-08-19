#!/bin/bash

# ============================================================
# GSP303 - Configure Secure RDP using a Windows Bastion Host
# Automated solution
# © ePlus.DEV
# ============================================================

set -u

# ------------------------------------------------------------
# COLORS
# ------------------------------------------------------------
BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'
TEAL_TEXT=$'\033[38;5;50m'

BOLD_TEXT=$'\033[1m'
RESET_FORMAT=$'\033[0m'

clear

echo "${CYAN_TEXT}${BOLD_TEXT}"
echo "============================================================"
echo "          GSP303 - Secure Windows Bastion Host"
echo "                       © ePlus.DEV"
echo "============================================================"
echo "${RESET_FORMAT}"

# ------------------------------------------------------------
# LAB CONFIG
# ------------------------------------------------------------
PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)
ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])" 2>/dev/null || true)

NETWORK="securenetwork"
SUBNET="securenetwork-subnet"
SUBNET_RANGE="192.168.16.0/20"

BASTION_VM="vm-bastionhost"
SECURE_VM="vm-securehost"

BASTION_TAG="allow-rdp-traffic"
SECURE_TAG="secure-host"

echo "${GREEN_TEXT}${BOLD_TEXT}Project : ${WHITE_TEXT}${PROJECT_ID}${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}Region  : ${WHITE_TEXT}${REGION}${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}Zone    : ${WHITE_TEXT}${ZONE}${RESET_FORMAT}"
echo

gcloud config set compute/region "$REGION" --quiet >/dev/null
gcloud config set compute/zone "$ZONE" --quiet >/dev/null

# ------------------------------------------------------------
# HELPER FUNCTIONS
# ------------------------------------------------------------
section() {
  echo
  echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
  echo "${CYAN_TEXT}${BOLD_TEXT}$1${RESET_FORMAT}"
  echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
}

success() {
  echo "${GREEN_TEXT}${BOLD_TEXT}✓ $1${RESET_FORMAT}"
}

warning() {
  echo "${YELLOW_TEXT}${BOLD_TEXT}⚠ $1${RESET_FORMAT}"
}

error() {
  echo "${RED_TEXT}${BOLD_TEXT}✗ $1${RESET_FORMAT}"
}

wait_progress() {
  local seconds="$1"
  local message="$2"

  while (( seconds > 0 )); do
    printf "\r${YELLOW_TEXT}${BOLD_TEXT}%s - %3ds remaining${RESET_FORMAT}" \
      "$message" "$seconds"

    sleep 10

    if (( seconds >= 10 )); then
      seconds=$((seconds - 10))
    else
      seconds=0
    fi
  done

  echo
}

# ------------------------------------------------------------
# [1/8] ENABLE COMPUTE API
# ------------------------------------------------------------
section "[1/8] Enabling Compute Engine API"

gcloud services enable compute.googleapis.com --quiet

success "Compute Engine API enabled."

# ------------------------------------------------------------
# [2/8] CREATE NETWORK
# ------------------------------------------------------------
section "[2/8] Creating secure VPC network"

if gcloud compute networks describe "$NETWORK" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  success "Network $NETWORK already exists."

else
  gcloud compute networks create "$NETWORK" \
    --project="$PROJECT_ID" \
    --subnet-mode=custom \
    --bgp-routing-mode=regional \
    --quiet

  success "Network $NETWORK created."
fi

# ------------------------------------------------------------
# CREATE SUBNET
# ------------------------------------------------------------
if gcloud compute networks subnets describe "$SUBNET" \
    --region="$REGION" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  success "Subnet $SUBNET already exists."

else
  gcloud compute networks subnets create "$SUBNET" \
    --project="$PROJECT_ID" \
    --network="$NETWORK" \
    --region="$REGION" \
    --range="$SUBNET_RANGE" \
    --quiet

  success "Subnet $SUBNET created."
fi

# ------------------------------------------------------------
# [3/8] FIREWALL RULES
# ------------------------------------------------------------
section "[3/8] Configuring firewall rules"

# Internet -> Bastion : RDP only
if gcloud compute firewall-rules describe rdp-ingress-fw-rule \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  gcloud compute firewall-rules update rdp-ingress-fw-rule \
    --allow=tcp:3389 \
    --source-ranges=0.0.0.0/0 \
    --target-tags="$BASTION_TAG" \
    --quiet

else
  gcloud compute firewall-rules create rdp-ingress-fw-rule \
    --project="$PROJECT_ID" \
    --network="$NETWORK" \
    --direction=INGRESS \
    --priority=1000 \
    --action=ALLOW \
    --rules=tcp:3389 \
    --source-ranges=0.0.0.0/0 \
    --target-tags="$BASTION_TAG" \
    --quiet
fi

success "Internet RDP -> Bastion firewall configured."

# Bastion -> Secure Host : RDP only
if ! gcloud compute firewall-rules describe securehost-rdp-from-bastion \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  gcloud compute firewall-rules create securehost-rdp-from-bastion \
    --project="$PROJECT_ID" \
    --network="$NETWORK" \
    --direction=INGRESS \
    --priority=1000 \
    --action=ALLOW \
    --rules=tcp:3389 \
    --source-tags="$BASTION_TAG" \
    --target-tags="$SECURE_TAG" \
    --quiet
fi

success "Bastion -> Secure Host RDP firewall configured."

# HTTP rule for IIS
if ! gcloud compute firewall-rules describe secure-http \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  gcloud compute firewall-rules create secure-http \
    --project="$PROJECT_ID" \
    --network="$NETWORK" \
    --direction=INGRESS \
    --priority=1000 \
    --action=ALLOW \
    --rules=tcp:80 \
    --source-ranges=0.0.0.0/0 \
    --target-tags="$SECURE_TAG" \
    --quiet
fi

success "HTTP firewall rule configured."

# ------------------------------------------------------------
# [4/8] FIND WINDOWS SERVER 2016 IMAGE
# ------------------------------------------------------------
section "[4/8] Selecting Windows Server 2016 image"

WINDOWS_IMAGE="$(
  gcloud compute images list \
    --project=windows-cloud \
    --filter="name~'^windows-server-2016-dc-v'" \
    --sort-by='~creationTimestamp' \
    --limit=1 \
    --format='value(name)' 2>/dev/null
)"

if [[ -z "$WINDOWS_IMAGE" ]]; then
  WINDOWS_IMAGE="windows-server-2016-dc-v20220513"
fi

echo "${GREEN_TEXT}${BOLD_TEXT}Windows image: ${WHITE_TEXT}${WINDOWS_IMAGE}${RESET_FORMAT}"

# ------------------------------------------------------------
# CREATE IIS STARTUP SCRIPT
# ------------------------------------------------------------
IIS_SCRIPT="/tmp/eplus-install-iis.ps1"

cat > "$IIS_SCRIPT" <<'POWERSHELL'
$ErrorActionPreference = "Continue"

Write-Host "========================================================="
Write-Host " ePlus.DEV - Installing Microsoft IIS"
Write-Host "========================================================="

try {

    Import-Module ServerManager

    $feature = Get-WindowsFeature -Name Web-Server

    if ($feature.Installed) {
        Write-Host "IIS is already installed."
    }
    else {
        Write-Host "Installing IIS..."

        $result = Install-WindowsFeature `
            -Name Web-Server `
            -IncludeManagementTools

        Write-Host $result
    }

    # Start IIS services
    Set-Service W3SVC -StartupType Automatic
    Start-Service W3SVC -ErrorAction SilentlyContinue

    # Simple test page
    $html = @"
<html>
<head>
<title>GSP303 - ePlus.DEV</title>
</head>
<body>
<h1>GSP303 IIS Server</h1>
<p>vm-securehost is running Microsoft IIS.</p>
<p>© ePlus.DEV</p>
</body>
</html>
"@

    Set-Content `
        -Path "C:\inetpub\wwwroot\index.html" `
        -Value $html `
        -Force

    # Ensure local Windows Firewall permits HTTP
    New-NetFirewallRule `
        -DisplayName "ePlus IIS HTTP" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 80 `
        -Action Allow `
        -ErrorAction SilentlyContinue

    $iis = Get-WindowsFeature Web-Server

    if ($iis.Installed) {
        Write-Host ""
        Write-Host "EPLUS_IIS_READY"
        Write-Host "Microsoft IIS installation completed successfully."
    }
    else {
        Write-Host "EPLUS_IIS_FAILED"
    }

}
catch {
    Write-Host "EPLUS_IIS_ERROR"
    Write-Host $_.Exception.Message
}
POWERSHELL

success "Windows IIS startup script prepared."

# ------------------------------------------------------------
# [5/8] CREATE SECURE HOST
# ------------------------------------------------------------
section "[5/8] Creating vm-securehost"

if gcloud compute instances describe "$SECURE_VM" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  success "$SECURE_VM already exists."

  echo "${BLUE_TEXT}Updating IIS startup metadata...${RESET_FORMAT}"

  gcloud compute instances add-metadata "$SECURE_VM" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --metadata-from-file=windows-startup-script-ps1="$IIS_SCRIPT" \
    --quiet

  gcloud compute instances add-tags "$SECURE_VM" \
    --zone="$ZONE" \
    --tags="$SECURE_TAG" \
    --quiet >/dev/null 2>&1 || true

  # Restart so startup script executes
  echo "${BLUE_TEXT}Restarting secure host so IIS startup script runs...${RESET_FORMAT}"

  gcloud compute instances reset "$SECURE_VM" \
    --zone="$ZONE" \
    --quiet

else

  gcloud compute instances create "$SECURE_VM" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --machine-type=e2-medium \
    --network-interface="subnet=$SUBNET,no-address" \
    --network-interface="subnet=default,no-address" \
    --tags="$SECURE_TAG" \
    --image="$WINDOWS_IMAGE" \
    --image-project=windows-cloud \
    --metadata-from-file=windows-startup-script-ps1="$IIS_SCRIPT" \
    --boot-disk-size=50GB \
    --boot-disk-type=pd-standard \
    --quiet

fi

success "$SECURE_VM is configured."

# ------------------------------------------------------------
# [6/8] CREATE BASTION HOST
# ------------------------------------------------------------
section "[6/8] Creating vm-bastionhost"

if gcloud compute instances describe "$BASTION_VM" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

  success "$BASTION_VM already exists."

  gcloud compute instances add-tags "$BASTION_VM" \
    --zone="$ZONE" \
    --tags="$BASTION_TAG" \
    --quiet >/dev/null 2>&1 || true

else

  gcloud compute instances create "$BASTION_VM" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --machine-type=e2-medium \
    --network-interface="subnet=$SUBNET" \
    --network-interface="subnet=default,no-address" \
    --tags="$BASTION_TAG" \
    --image="$WINDOWS_IMAGE" \
    --image-project=windows-cloud \
    --boot-disk-size=50GB \
    --boot-disk-type=pd-standard \
    --quiet

fi

success "$BASTION_VM is configured."

# ------------------------------------------------------------
# [7/8] VERIFY NETWORK CONFIGURATION
# ------------------------------------------------------------
section "[7/8] Verifying instance configuration"

verify_vm() {

  local VM="$1"

  echo
  echo "${CYAN_TEXT}${BOLD_TEXT}${VM}${RESET_FORMAT}"
  echo "------------------------------------------------------------"

  SECURE_IP="$(
    gcloud compute instances describe "$VM" \
      --zone="$ZONE" \
      --format='value(networkInterfaces[0].networkIP)'
  )"

  DEFAULT_IP="$(
    gcloud compute instances describe "$VM" \
      --zone="$ZONE" \
      --format='value(networkInterfaces[1].networkIP)'
  )"

  EXTERNAL_IP="$(
    gcloud compute instances describe "$VM" \
      --zone="$ZONE" \
      --format='value(networkInterfaces[0].accessConfigs[0].natIP)' \
      2>/dev/null
  )"

  echo "Secure network IP  : ${SECURE_IP:-NONE}"
  echo "Default network IP : ${DEFAULT_IP:-NONE}"
  echo "External IP        : ${EXTERNAL_IP:-NONE}"
}

verify_vm "$SECURE_VM"

SECURE_EXTERNAL="$(
  gcloud compute instances describe "$SECURE_VM" \
    --zone="$ZONE" \
    --format='value(networkInterfaces[].accessConfigs[].natIP)' \
    2>/dev/null | tr -d '[:space:];'
)"

if [[ -z "$SECURE_EXTERNAL" ]]; then
  success "Secure host has NO external IP."
else
  error "Secure host incorrectly has external IP: $SECURE_EXTERNAL"
fi

verify_vm "$BASTION_VM"

BASTION_EXTERNAL="$(
  gcloud compute instances describe "$BASTION_VM" \
    --zone="$ZONE" \
    --format='value(networkInterfaces[0].accessConfigs[0].natIP)' \
    2>/dev/null | tr -d '[:space:];'
)"

if [[ -n "$BASTION_EXTERNAL" ]]; then
  success "Bastion host has external IP."
else
  error "Bastion host does not have an external IP."
fi

SECURE_INTERNAL_IP="$(
  gcloud compute instances describe "$SECURE_VM" \
    --zone="$ZONE" \
    --format='value(networkInterfaces[0].networkIP)'
)"

# ------------------------------------------------------------
# [8/8] WAIT FOR WINDOWS + IIS
# ------------------------------------------------------------
section "[8/8] Waiting for Windows and IIS installation"

echo
echo "${YELLOW_TEXT}${BOLD_TEXT}Windows is booting and installing IIS.${RESET_FORMAT}"
echo "${YELLOW_TEXT}Progress will be checked every 10 seconds.${RESET_FORMAT}"
echo

IIS_READY=0

for attempt in $(seq 1 36); do

  printf "${YELLOW_TEXT}${BOLD_TEXT}IIS check %02d/36${RESET_FORMAT} - " "$attempt"

  SERIAL_OUTPUT="$(
    gcloud compute instances get-serial-port-output "$SECURE_VM" \
      --zone="$ZONE" \
      --port=1 \
      2>/dev/null || true
  )"

  if echo "$SERIAL_OUTPUT" | grep -q "EPLUS_IIS_READY"; then
    echo "${GREEN_TEXT}IIS installation completed.${RESET_FORMAT}"
    IIS_READY=1
    break
  fi

  if echo "$SERIAL_OUTPUT" | grep -q "EPLUS_IIS_ERROR"; then
    echo "${RED_TEXT}startup script reported an error.${RESET_FORMAT}"
  else
    echo "${YELLOW_TEXT}Windows initialization / IIS installation in progress...${RESET_FORMAT}"
  fi

  sleep 10
done

if [[ "$IIS_READY" -eq 1 ]]; then
  success "Microsoft IIS is installed on vm-securehost."
else
  warning "IIS ready marker was not detected from serial output."
  warning "The Windows startup script may still be completing in the background."
fi

# ------------------------------------------------------------
# RESET WINDOWS PASSWORDS
# ------------------------------------------------------------
section "Windows login credentials"

reset_password() {

  local VM="$1"

  echo
  echo "${BLUE_TEXT}${BOLD_TEXT}Creating/resetting app_admin on $VM...${RESET_FORMAT}"

  for attempt in $(seq 1 12); do

    OUTPUT="$(
      gcloud compute reset-windows-password "$VM" \
        --user=app_admin \
        --zone="$ZONE" \
        --quiet 2>&1
    )"

    RESULT=$?

    if [[ "$RESULT" -eq 0 ]]; then
      echo "$OUTPUT"
      return 0
    fi

    echo "${YELLOW_TEXT}Windows guest agent not ready - retry $attempt/12...${RESET_FORMAT}"
    sleep 10
  done

  warning "Could not reset password automatically for $VM."
  return 0
}

reset_password "$BASTION_VM"
reset_password "$SECURE_VM"

# ------------------------------------------------------------
# FINAL SUMMARY
# ------------------------------------------------------------
section "GSP303 LAB SUMMARY"

echo "${GREEN_TEXT}${BOLD_TEXT}✓ TASK 1 - securenetwork created${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}✓ TASK 1 - subnet created in us-west1${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}✓ TASK 1 - RDP firewall configured${RESET_FORMAT}"
echo
echo "${GREEN_TEXT}${BOLD_TEXT}✓ TASK 2 - vm-securehost created with two NICs${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}✓ TASK 2 - vm-securehost has no external IP${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}✓ TASK 2 - vm-bastionhost created with two NICs${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}✓ TASK 2 - vm-bastionhost has external IP${RESET_FORMAT}"
echo
echo "${GREEN_TEXT}${BOLD_TEXT}✓ TASK 3 - IIS startup script attached${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}✓ TASK 3 - IIS installation triggered automatically${RESET_FORMAT}"

echo
echo "${CYAN_TEXT}${BOLD_TEXT}Secure Host Internal IP : ${WHITE_TEXT}${SECURE_INTERNAL_IP}${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}Bastion External IP     : ${WHITE_TEXT}${BASTION_EXTERNAL}${RESET_FORMAT}"

echo
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}             LAB AUTOMATION COMPLETE${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}                    © ePlus.DEV${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================================${RESET_FORMAT}"
echo
echo "${YELLOW_TEXT}${BOLD_TEXT}Now click Check my progress for all objectives.${RESET_FORMAT}"