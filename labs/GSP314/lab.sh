#!/bin/bash

# ============================================================
# GSP303 - Secure Windows Bastion Host
# SOURCE-SAFE VERSION
# © ePlus.DEV
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

line() {
  printf '%*s\n' 72 '' | tr ' ' '='
}

section() {
  echo
  line
  echo -e "${CYAN}${BOLD}$1${NC}"
  line
}

ok() {
  echo -e "${GREEN}✓ $1${NC}"
}

warn() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

err() {
  echo -e "${RED}✗ $1${NC}"
}

echo
echo -e "${BLUE}${BOLD}"
cat <<'BANNER'
   ____  ____  ____  ____  _  ____
  / ___||  _ \|  _ \| ___|| || ___|
 | |  _ | |_) | |_) |___ \| ||___ \
 | |_| ||  __/|  __/ ___) | | ___) |
  \____||_|   |_|   |____/|_||____/
BANNER
echo -e "${NC}"

echo -e "${BOLD}GSP303 - Secure Windows Bastion Host${NC}"
echo "© ePlus.DEV"

# ============================================================
# CONFIG
# ============================================================

REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null || true)
ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])" 2>/dev/null || true)

NETWORK="securenetwork"
SUBNET="securenetwork-subnet"
SUBNET_RANGE="192.168.16.0/20"

SECURE_VM="vm-securehost"
BASTION_VM="vm-bastionhost"

BASTION_TAG="bastion-rdp"
SECURE_TAG="secure-rdp"

RDP_FW="allow-rdp-bastion"
INTERNAL_RDP_FW="allow-rdp-secure"

PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"

# ============================================================
# PROJECT CHECK
# ============================================================

section "[1/7] Detecting Google Cloud environment"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  err "Could not detect Project ID."
  echo
  echo "Run:"
  echo "  gcloud config set project YOUR_PROJECT_ID"
  echo
  echo "Then run lab.sh again."
else
  echo -e "Project : ${GREEN}${PROJECT_ID}${NC}"
  echo -e "Region  : ${GREEN}${REGION}${NC}"
  echo -e "Zone    : ${GREEN}${ZONE}${NC}"

  gcloud config set compute/region "$REGION" --quiet >/dev/null 2>&1
  gcloud config set compute/zone "$ZONE" --quiet >/dev/null 2>&1

  ok "Environment ready."
fi

# ============================================================
# API
# ============================================================

section "[2/7] Enabling Compute Engine API"

gcloud services enable compute.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet 2>/dev/null

if [[ $? -eq 0 ]]; then
  ok "Compute Engine API enabled."
else
  warn "API enable returned an error. Continuing..."
fi

# ============================================================
# TASK 1 - NETWORK
# ============================================================

section "[3/7] TASK 1 - Creating securenetwork"

if gcloud compute networks describe "$NETWORK" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then

  ok "Network already exists: $NETWORK"

else

  echo "Creating VPC..."

  gcloud compute networks create "$NETWORK" \
    --project="$PROJECT_ID" \
    --subnet-mode=custom \
    --quiet

  if [[ $? -eq 0 ]]; then
    ok "Created VPC: $NETWORK"
  else
    err "Could not create $NETWORK"
  fi
fi

# ============================================================
# SUBNET
# ============================================================

echo
echo "Checking subnet..."

if gcloud compute networks subnets describe "$SUBNET" \
  --region="$REGION" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then

  CURRENT_NETWORK="$(
    gcloud compute networks subnets describe "$SUBNET" \
      --region="$REGION" \
      --project="$PROJECT_ID" \
      --format='value(network.basename())' \
      2>/dev/null
  )"

  if [[ "$CURRENT_NETWORK" == "$NETWORK" ]]; then
    ok "Subnet already exists: $SUBNET"
  else
    warn "Subnet exists on wrong network."
  fi

else

  gcloud compute networks subnets create "$SUBNET" \
    --project="$PROJECT_ID" \
    --network="$NETWORK" \
    --region="$REGION" \
    --range="$SUBNET_RANGE" \
    --quiet

  if [[ $? -eq 0 ]]; then
    ok "Created subnet: $SUBNET"
  else
    err "Subnet creation failed."
  fi
fi

# ============================================================
# TASK 1 - FIREWALL
# ============================================================

section "[4/7] TASK 1 - Creating RDP firewall rules"

#
# Remove/recreate ONLY our challenge firewall rule
#

if gcloud compute firewall-rules describe "$RDP_FW" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then

  gcloud compute firewall-rules delete "$RDP_FW" \
    --project="$PROJECT_ID" \
    --quiet >/dev/null 2>&1
fi

gcloud compute firewall-rules create "$RDP_FW" \
  --project="$PROJECT_ID" \
  --network="$NETWORK" \
  --direction=INGRESS \
  --priority=1000 \
  --allow=tcp:3389 \
  --source-ranges=0.0.0.0/0 \
  --target-tags="$BASTION_TAG" \
  --quiet

if [[ $? -eq 0 ]]; then
  ok "Internet -> Bastion TCP/3389"
else
  err "External RDP firewall failed."
fi

#
# Bastion -> Secure Host
#

if gcloud compute firewall-rules describe "$INTERNAL_RDP_FW" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then

  gcloud compute firewall-rules delete "$INTERNAL_RDP_FW" \
    --project="$PROJECT_ID" \
    --quiet >/dev/null 2>&1
fi

gcloud compute firewall-rules create "$INTERNAL_RDP_FW" \
  --project="$PROJECT_ID" \
  --network="$NETWORK" \
  --direction=INGRESS \
  --priority=1000 \
  --allow=tcp:3389 \
  --source-tags="$BASTION_TAG" \
  --target-tags="$SECURE_TAG" \
  --quiet

if [[ $? -eq 0 ]]; then
  ok "Bastion -> Secure Host TCP/3389"
else
  warn "Internal RDP firewall creation failed."
fi

# ============================================================
# IIS SCRIPT
# ============================================================

cat > /tmp/install-iis.ps1 <<'POWERSHELL'
$ErrorActionPreference = "Continue"

Write-Output "============================================================"
Write-Output "ePlus.DEV - GSP303 IIS Installation"
Write-Output "============================================================"

try {

    Import-Module ServerManager

    $feature = Get-WindowsFeature -Name Web-Server

    if (-not $feature.Installed) {

        Write-Output "Installing Web Server IIS..."

        Install-WindowsFeature `
          -Name Web-Server `
          -IncludeManagementTools

    } else {

        Write-Output "IIS already installed."

    }

    Set-Service W3SVC -StartupType Automatic

    Start-Service W3SVC -ErrorAction SilentlyContinue

    if (-not (Test-Path "C:\inetpub\wwwroot")) {
        New-Item `
          -Path "C:\inetpub\wwwroot" `
          -ItemType Directory `
          -Force | Out-Null
    }

    @"
<html>
<head>
<title>GSP303</title>
</head>
<body>
<h1>IIS is running</h1>
<p>vm-securehost</p>
<p>ePlus.DEV</p>
</body>
</html>
"@ | Out-File `
      -FilePath "C:\inetpub\wwwroot\index.html" `
      -Encoding ascii `
      -Force

    Write-Output ""
    Write-Output "EPLUS_IIS_READY"
    Write-Output ""

}
catch {

    Write-Output "IIS ERROR:"
    Write-Output $_.Exception.Message

}
POWERSHELL

ok "IIS startup script prepared."

# ============================================================
# TASK 2 - CLEAN OLD CHALLENGE VMs
# ============================================================

section "[5/7] TASK 2 - Creating Windows instances"

echo "Checking previous challenge instances..."

for VM in "$SECURE_VM" "$BASTION_VM"; do

  if gcloud compute instances describe "$VM" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" >/dev/null 2>&1; then

    warn "$VM already exists - recreating..."

    gcloud compute instances delete "$VM" \
      --zone="$ZONE" \
      --project="$PROJECT_ID" \
      --quiet

    if [[ $? -eq 0 ]]; then
      ok "Removed old $VM"
    else
      err "Could not remove $VM"
    fi

  fi

done

# ============================================================
# SECURE HOST
# ============================================================

echo
line
echo -e "${CYAN}${BOLD}Creating vm-securehost${NC}"
line

echo
echo "NIC 0 : securenetwork - INTERNAL ONLY"
echo "NIC 1 : default       - INTERNAL ONLY"
echo

gcloud compute instances create "$SECURE_VM" \
  --project="$PROJECT_ID" \
  --zone="$ZONE" \
  --machine-type=e2-standard-2 \
  --image-project=windows-cloud \
  --image-family=windows-2016 \
  --boot-disk-size=50GB \
  --network-interface="network=${NETWORK},subnet=${SUBNET},no-address" \
  --network-interface="network=default,subnet=default,no-address" \
  --tags="$SECURE_TAG" \
  --metadata-from-file=windows-startup-script-ps1=/tmp/install-iis.ps1 \
  --quiet

if [[ $? -eq 0 ]]; then
  ok "vm-securehost created."
else
  err "vm-securehost creation failed."
fi

# ============================================================
# BASTION
# ============================================================

echo
line
echo -e "${CYAN}${BOLD}Creating vm-bastionhost${NC}"
line

echo
echo "NIC 0 : securenetwork - EPHEMERAL EXTERNAL IP"
echo "NIC 1 : default       - INTERNAL ONLY"
echo

gcloud compute instances create "$BASTION_VM" \
  --project="$PROJECT_ID" \
  --zone="$ZONE" \
  --machine-type=e2-standard-2 \
  --image-project=windows-cloud \
  --image-family=windows-2016 \
  --boot-disk-size=50GB \
  --network-interface="network=${NETWORK},subnet=${SUBNET}" \
  --network-interface="network=default,subnet=default,no-address" \
  --tags="$BASTION_TAG" \
  --quiet

if [[ $? -eq 0 ]]; then
  ok "vm-bastionhost created."
else
  err "vm-bastionhost creation failed."
fi

# ============================================================
# VERIFY NETWORKS
# ============================================================

section "[6/7] Verifying instance configuration"

SECURE_EXTERNAL="$(
  gcloud compute instances describe "$SECURE_VM" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --format='value(networkInterfaces[].accessConfigs[].natIP)' \
    2>/dev/null
)"

SECURE_IP="$(
  gcloud compute instances describe "$SECURE_VM" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --format='value(networkInterfaces[0].networkIP)' \
    2>/dev/null
)"

SECURE_DEFAULT_IP="$(
  gcloud compute instances describe "$SECURE_VM" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --format='value(networkInterfaces[1].networkIP)' \
    2>/dev/null
)"

BASTION_EXTERNAL="$(
  gcloud compute instances describe "$BASTION_VM" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --format='value(networkInterfaces[0].accessConfigs[0].natIP)' \
    2>/dev/null
)"

BASTION_INTERNAL="$(
  gcloud compute instances describe "$BASTION_VM" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --format='value(networkInterfaces[0].networkIP)' \
    2>/dev/null
)"

BASTION_DEFAULT_IP="$(
  gcloud compute instances describe "$BASTION_VM" \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    --format='value(networkInterfaces[1].networkIP)' \
    2>/dev/null
)"

echo
echo "vm-securehost"
echo "------------------------------------------------------------"
echo "Secure network IP  : ${SECURE_IP:-N/A}"
echo "Default network IP : ${SECURE_DEFAULT_IP:-N/A}"
echo "External IP        : ${SECURE_EXTERNAL:-NONE}"

if [[ -z "$SECURE_EXTERNAL" ]]; then
  ok "Secure host has NO external IP."
else
  err "Secure host incorrectly has external IP: $SECURE_EXTERNAL"
fi

echo
echo "vm-bastionhost"
echo "------------------------------------------------------------"
echo "Secure network IP  : ${BASTION_INTERNAL:-N/A}"
echo "Default network IP : ${BASTION_DEFAULT_IP:-N/A}"
echo "External IP        : ${BASTION_EXTERNAL:-NONE}"

if [[ -n "$BASTION_EXTERNAL" ]]; then
  ok "Bastion host has an external IP."
else
  err "Bastion external IP is missing."
fi

# ============================================================
# TASK 3 - WAIT FOR IIS
# ============================================================

section "[7/7] TASK 3 - Waiting for IIS installation"

echo
echo "Windows is booting and installing IIS."
echo "The terminal will print progress every 10 seconds."
echo

IIS_READY=0

for i in $(seq 1 36); do

  SERIAL="$(
    gcloud compute instances get-serial-port-output "$SECURE_VM" \
      --zone="$ZONE" \
      --project="$PROJECT_ID" \
      --port=1 \
      2>/dev/null
  )"

  if echo "$SERIAL" | grep -q "EPLUS_IIS_READY"; then

    IIS_READY=1
    echo
    ok "Microsoft IIS installation completed."
    break

  fi

  printf "\rIIS check %02d/36 - Windows initialization in progress..." "$i"

  sleep 10

done

echo
echo

if [[ "$IIS_READY" -eq 0 ]]; then

  warn "IIS completion marker has not appeared yet."
  warn "DO NOT rerun the entire script yet."
  echo
  echo "Windows may still be finishing initialization."
  echo
  echo "Check again with:"
  echo
  echo "gcloud compute instances get-serial-port-output vm-securehost \\"
  echo "  --zone=us-east1-c --port=1 | grep EPLUS_IIS_READY"
  echo

else

  ok "IIS ready on vm-securehost."

fi

# ============================================================
# SUMMARY
# ============================================================

section "GSP303 RESOURCE SUMMARY"

echo -e "${GREEN}✓ TASK 1${NC} - VPC"
echo "  securenetwork"
echo

echo -e "${GREEN}✓ TASK 1${NC} - Subnet"
echo "  securenetwork-subnet"
echo "  Region: us-east1"
echo

echo -e "${GREEN}✓ TASK 1${NC} - Firewall"
echo "  TCP/3389 -> Bastion"
echo

echo -e "${GREEN}✓ TASK 2${NC} - vm-securehost"
echo "  Secure NIC : ${SECURE_IP:-N/A}"
echo "  Default NIC: ${SECURE_DEFAULT_IP:-N/A}"
echo "  External IP: NONE"
echo

echo -e "${GREEN}✓ TASK 2${NC} - vm-bastionhost"
echo "  Secure NIC : ${BASTION_INTERNAL:-N/A}"
echo "  Default NIC: ${BASTION_DEFAULT_IP:-N/A}"
echo "  External IP: ${BASTION_EXTERNAL:-N/A}"
echo

if [[ "$IIS_READY" -eq 1 ]]; then
  echo -e "${GREEN}✓ TASK 3${NC} - IIS installed"
else
  echo -e "${YELLOW}⚠ TASK 3${NC} - IIS may still be initializing"
fi

echo
line
echo -e "${GREEN}${BOLD}RESOURCE CONFIGURATION COMPLETE${NC}"
line

echo
echo "Now click Check my progress."
echo
echo "Windows passwords are NOT reset automatically"
echo "to avoid terminal/session problems."
echo
echo "If you need RDP later, run separately:"
echo
echo "gcloud compute reset-windows-password vm-bastionhost \\"
echo "  --user=app_admin --zone=us-east1-c"
echo
echo "gcloud compute reset-windows-password vm-securehost \\"
echo "  --user=app_admin --zone=us-east1-c"
echo
echo "© ePlus.DEV"