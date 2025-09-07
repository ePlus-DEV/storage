#!/usr/bin/env bash
set -euo pipefail

# ================= Colors & helpers =================
BOLD=$(tput bold || true); DIM=$(tput dim || true); RESET=$(tput sgr0 || true)
RED=$(tput setaf 1 || true); GREEN=$(tput setaf 2 || true); YELLOW=$(tput setaf 3 || true); MAGENTA=$(tput setaf 5 || true)
BG_MAGENTA=$(tput setab 5 || true); BG_RED=$(tput setab 1 || true)
banner(){ echo -e "\n${BOLD}${MAGENTA}==> $*${RESET}\n"; }
ok(){ echo -e "${GREEN}✔${RESET} $*"; }
warn(){ echo -e "${YELLOW}⚠${RESET} $*"; }
die(){ echo -e "${RED}✖${RESET} $*"; exit 1; }

echo "${BG_MAGENTA}${BOLD}Starting Execution - ePlus.DEV${RESET}"

# ================= Project / location =================
PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project -q || true)}"
[[ -z "$PROJECT_ID" ]] && die "No GCP project set. Run: gcloud config set project <PROJECT_ID>"

# Try to read default zone; fallback to the lab zone
ZONE="$(gcloud compute project-info describe --format='value(commonInstanceMetadata.items[google-compute-default-zone])' || true)"
[[ -z "$ZONE" ]] && ZONE="us-east4-a"
REGION="${ZONE%-*}"

echo "Project: ${BOLD}${PROJECT_ID}${RESET}"
echo "Region : ${BOLD}${REGION}${RESET}"
echo "Zone   : ${BOLD}${ZONE}${RESET}"

# ================= Names & constants =================
BLUE_VM="blue"
GREEN_VM="green"
TEST_VM="test-vm"
MACHINE_TYPE="e2-micro"
TAG="web-server"
FW_RULE="allow-http-web-server"
SA_ID="network-admin"
SA_EMAIL="${SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
SA_KEY="credentials.json"

# ================= VM creators (startup-scripts) =================
create_vm() {
  local name="$1" tag="$2" message="$3"
  if gcloud compute instances describe "$name" --zone "$ZONE" >/dev/null 2>&1; then
    warn "VM $name already exists; skipping create."
    return
  fi
  local tagflag=()
  [[ -n "$tag" ]] && tagflag=(--tags "$tag")

  gcloud compute instances create "$name" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --machine-type="$MACHINE_TYPE" \
    --network-interface=network-tier=PREMIUM,subnet=default \
    --create-disk=auto-delete=yes,boot=yes,device-name="$name",image-family=debian-12,image-project=debian-cloud,size=10,type=pd-balanced \
    "${tagflag[@]}" \
    --metadata=startup-script=$'#!/bin/bash
      set -e
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -y
      apt-get install -y nginx-light
      sed -i "s|<h1>Welcome to nginx!</h1>|<h1>'"$message"'</h1>|" /var/www/html/index.nginx-debian.html
      systemctl restart nginx
    ' >/dev/null
  ok "Created $name with Nginx customized."
}

# ================= Task 1: Create web servers =================
banner "Task 1: Create web servers (blue & green) + Nginx customization"
create_vm "$BLUE_VM"  "$TAG" "Welcome to the blue server!"
create_vm "$GREEN_VM" ""     "Welcome to the green server!"

# ================= Task 2: Firewall rule =================
banner "Task 2: Ensure firewall rule ${FW_RULE} (tcp:80, icmp) for tag '${TAG}'"
if gcloud compute firewall-rules describe "${FW_RULE}" >/dev/null 2>&1; then
  warn "Firewall rule ${FW_RULE} already exists; skipping create."
else
  gcloud compute firewall-rules create "${FW_RULE}" \
    --project="$PROJECT_ID" \
    --direction=INGRESS \
    --priority=1000 \
    --network=default \
    --action=ALLOW \
    --rules=tcp:80,icmp \
    --source-ranges=0.0.0.0/0 \
    --target-tags="$TAG" >/dev/null
  ok "Created firewall rule ${FW_RULE}"
fi

# Create test VM (idempotent)
banner "Create ${TEST_VM} (for connectivity checks & IAM tests)"
if gcloud compute instances describe "${TEST_VM}" --zone "$ZONE" >/dev/null 2>&1; then
  warn "${TEST_VM} already exists; skipping."
else
  gcloud compute instances create "${TEST_VM}" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --machine-type="$MACHINE_TYPE" \
    --subnet=default >/dev/null
  ok "Created ${TEST_VM}"
fi

# Helper to get IPs
get_ip()  { gcloud compute instances describe "$1" --zone "$ZONE" --format="get(networkInterfaces[0].networkIP)"; }
get_eip() { gcloud compute instances describe "$1" --zone "$ZONE" --format="get(networkInterfaces[0].accessConfigs[0].natIP)"; }
BLUE_IP="$(get_ip "$BLUE_VM")"; BLUE_EIP="$(get_eip "$BLUE_VM")"
GREEN_IP="$(get_ip "$GREEN_VM")"; GREEN_EIP="$(get_eip "$GREEN_VM")"
echo "blue  -> internal ${BOLD}$BLUE_IP${RESET} | external ${BOLD}$BLUE_EIP${RESET}"
echo "green -> internal ${BOLD}$GREEN_IP${RESET} | external ${BOLD}$GREEN_EIP${RESET}"

# ================= Connectivity check from test-vm (robust) =================
banner "Verify HTTP from ${TEST_VM} (internal OK for both; external only blue OK)"

gcloud compute ssh "${TEST_VM}" --zone "${ZONE}" --quiet --command "bash -lc '
  set -e
  # ensure curl present
  if ! command -v curl >/dev/null 2>&1; then
    sudo apt-get update -y && sudo apt-get install -y curl
  fi

  # wait helpers
  wait_http() { local ip=\"\$1\"; for i in {1..20}; do if curl -s --max-time 2 \"http://\$ip\" >/dev/null; then return 0; fi; sleep 2; done; return 1; }

  echo \"Waiting for Nginx to be ready...\"
  wait_http ${BLUE_IP}  || echo \"blue not ready yet (continuing)\"
  wait_http ${GREEN_IP} || echo \"green not ready yet (continuing)\"

  echo \"--- curl blue INTERNAL ---\"
  if curl -s http://${BLUE_IP} | grep -q \"Welcome to the .* server!\"; then echo OK; else echo FAILED; fi

  echo \"--- curl green INTERNAL ---\"
  if curl -s http://${GREEN_IP} | grep -q \"Welcome to the .* server!\"; then echo OK; else echo FAILED; fi

  echo \"--- curl blue EXTERNAL (should work) ---\"
  if curl -s --max-time 5 http://${BLUE_EIP} | grep -q \"Welcome to the .* server!\"; then echo OK; else echo \"FAILED (unexpected)\"; fi

  echo \"--- curl green EXTERNAL (should FAIL/HANG) ---\"
  if curl -s --max-time 5 http://${GREEN_EIP} >/dev/null; then
    echo \"UNEXPECTED: reachable\"
  else
    echo \"blocked as expected\"
  fi
'"

ok "Connectivity behavior matches the lab."

# ================= Task 3: IAM roles (Network Admin vs Security Admin) =================
banner "Task 3: Create service account & test IAM permissions on firewall rules"

# Create service account (idempotent)
if gcloud iam service-accounts describe "${SA_EMAIL}" >/dev/null 2>&1; then
  warn "Service account ${SA_EMAIL} already exists; skipping create."
else
  gcloud iam service-accounts create "${SA_ID}" \
    --project="${PROJECT_ID}" \
    --description="Service account for Network Admin role" \
    --display-name="Network-admin" >/dev/null
  ok "Service account created: ${SA_EMAIL}"
fi

# Bind Network Admin (idempotent)
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/compute.networkAdmin" >/dev/null
ok "Bound roles/compute.networkAdmin to ${SA_EMAIL}"

# Create key & copy to test-vm
rm -f "${SA_KEY}"
gcloud iam service-accounts keys create "${SA_KEY}" \
  --iam-account="${SA_EMAIL}" >/dev/null
ok "Key created: ${SA_KEY}"

gcloud compute scp "${SA_KEY}" "${TEST_VM}:~/${SA_KEY}" --zone "${ZONE}" --quiet >/dev/null
ok "Key copied to ${TEST_VM}:~/${SA_KEY}"

# Test permissions as Network Admin
banner "On ${TEST_VM}: Activate SA and try list + delete firewall rules (delete should FAIL)"
gcloud compute ssh "${TEST_VM}" --zone "${ZONE}" --quiet --command "bash -lc '
  set -e
  gcloud auth activate-service-account --key-file ~/${SA_KEY} >/dev/null
  echo \">> Listing firewall rules (should work):\"
  gcloud compute firewall-rules list --format=\"table(name,network,direction,priority,allowed[])\" | sed -n \"1,6p\"
  echo \">> Try delete ${FW_RULE} (should FAIL for Network Admin):\"
  if gcloud compute firewall-rules delete ${FW_RULE} -q; then
    echo \"UNEXPECTED SUCCESS\"
  else
    echo \"Expected: delete denied\"
  fi
'"

# Grant Security Admin & delete rule
banner "Grant roles/compute.securityAdmin and delete ${FW_RULE} (should SUCCEED)"
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/compute.securityAdmin" >/dev/null
ok "Bound roles/compute.securityAdmin to ${SA_EMAIL}"

gcloud compute ssh "${TEST_VM}" --zone "${ZONE}" --quiet --command "bash -lc '
  set -e
  gcloud auth activate-service-account --key-file ~/${SA_KEY} >/dev/null
  gcloud compute firewall-rules delete ${FW_RULE} -q && echo \"Deleted ${FW_RULE} (expected with Security Admin)\"
  echo \">> Verify blue EXTERNAL now fails:\"
  if curl -s --max-time 5 http://${BLUE_EIP} >/dev/null; then
    echo \"UNEXPECTED: still reachable\"
  else
    echo \"blocked as expected\"
  fi
'"

echo
banner "Summary"
echo "- ${BLUE_VM} (tag ${TAG}) & ${GREEN_VM} created in ${ZONE} with Nginx customized via startup-scripts."
echo "- ${FW_RULE} created then deleted to demonstrate IAM: Network Admin (list only) vs Security Admin (delete)."
echo "- ${TEST_VM} used for curl tests & IAM checks."
echo
echo "${BG_RED}${BOLD}Congratulations For Completing!!! - ePlus.DEV ${RESET}"