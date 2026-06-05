#!/bin/bash
BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'
BOLD_TEXT=$'\033[1m'
RESET_FORMAT=$'\033[0m'
clear

# Welcome message
echo "${CYAN_TEXT}${BOLD_TEXT}==================================================================${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}      ePlus.DEV - INITIATING EXECUTION...  ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}==================================================================${RESET_FORMAT}"
echo

# ─── AUTO-FETCH REGION ───────────────────────────────────────────────
echo "${YELLOW_TEXT}${BOLD_TEXT}[INFO] Fetching project region... | ${RESET_FORMAT}"
export REGION=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])" 2>/dev/null)

if [ -z "$REGION" ]; then
  export REGION=$(gcloud config get-value compute/region 2>/dev/null)
fi

if [ -z "$REGION" ]; then
  echo "${YELLOW_TEXT}[WARN] Region not found. Defaulting to us-east1.${RESET_FORMAT}"
  export REGION="us-east1"
fi

export ZONE_A="${REGION}-b"
export ZONE_C="${REGION}-c"

echo "${GREEN_TEXT}  Region : ${REGION}${RESET_FORMAT}"
echo "${GREEN_TEXT}  Zone A : ${ZONE_A}${RESET_FORMAT}"
echo "${GREEN_TEXT}  Zone C : ${ZONE_C}${RESET_FORMAT}"
echo ""

# ─── HELPERS ─────────────────────────────────────────────────────────
create_if_not_exists() {
  local CHECK_CMD="$1"
  local CREATE_CMD="$2"
  local SUCCESS_MSG="$3"

  if eval "$CHECK_CMD" >/dev/null 2>&1; then
    echo "${YELLOW_TEXT}  Already exists, skipping.${RESET_FORMAT}"
  else
    eval "$CREATE_CMD"
  fi

  echo "${GREEN_TEXT}  ✔ ${SUCCESS_MSG}${RESET_FORMAT}"
}

# ─── TASK 1: NETWORK & SUBNETS ───────────────────────────────────────
echo "${CYAN_TEXT}${BOLD_TEXT}[TASK 1] Creating VPC network and subnets... | ${RESET_FORMAT}"

if gcloud compute networks describe lb-network >/dev/null 2>&1; then
  echo "${YELLOW_TEXT}  lb-network already exists, skipping.${RESET_FORMAT}"
else
  gcloud compute networks create lb-network \
    --subnet-mode=custom \
    --description="ePlus.DEV - GSP636 custom VPC network" \
    --quiet
fi
echo "${GREEN_TEXT}  ✔ lb-network ready${RESET_FORMAT}"

if gcloud compute networks subnets describe backend-subnet --region=${REGION} >/dev/null 2>&1; then
  echo "${YELLOW_TEXT}  backend-subnet already exists, skipping.${RESET_FORMAT}"
else
  gcloud compute networks subnets create backend-subnet \
    --network=lb-network \
    --region=${REGION} \
    --range=10.1.2.0/24 \
    --description="ePlus.DEV - backend instances subnet" \
    --quiet
fi
echo "${GREEN_TEXT}  ✔ backend-subnet ready (10.1.2.0/24)${RESET_FORMAT}"

if gcloud compute networks subnets describe proxy-only-subnet --region=${REGION} >/dev/null 2>&1; then
  echo "${YELLOW_TEXT}  proxy-only-subnet already exists, skipping.${RESET_FORMAT}"
else
  gcloud compute networks subnets create proxy-only-subnet \
    --network=lb-network \
    --region=${REGION} \
    --range=10.129.0.0/23 \
    --purpose=REGIONAL_MANAGED_PROXY \
    --role=ACTIVE \
    --description="ePlus.DEV - proxy-only subnet for internal NLB Envoy proxies" \
    --quiet
fi
echo "${GREEN_TEXT}  ✔ proxy-only-subnet ready (10.129.0.0/23)${RESET_FORMAT}"
echo ""

# ─── TASK 2: FIREWALL RULES ──────────────────────────────────────────
echo "${CYAN_TEXT}${BOLD_TEXT}[TASK 2] Creating firewall rules... | ${RESET_FORMAT}"

if gcloud compute firewall-rules describe fw-allow-ssh >/dev/null 2>&1; then
  echo "${YELLOW_TEXT}  fw-allow-ssh already exists, skipping.${RESET_FORMAT}"
else
  gcloud compute firewall-rules create fw-allow-ssh \
    --network=lb-network \
    --action=ALLOW \
    --direction=INGRESS \
    --target-tags=allow-ssh \
    --source-ranges=0.0.0.0/0 \
    --rules=tcp:22 \
    --description="ePlus.DEV - allow SSH to backend and client VMs" \
    --quiet
fi
echo "${GREEN_TEXT}  ✔ fw-allow-ssh ready${RESET_FORMAT}"

if gcloud compute firewall-rules describe fw-allow-health-check >/dev/null 2>&1; then
  echo "${YELLOW_TEXT}  fw-allow-health-check already exists, skipping.${RESET_FORMAT}"
else
  gcloud compute firewall-rules create fw-allow-health-check \
    --network=lb-network \
    --action=ALLOW \
    --direction=INGRESS \
    --target-tags=allow-health-check \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --rules=tcp:80 \
    --description="ePlus.DEV - allow GCP health checker IPs to reach backends on port 80" \
    --quiet
fi
echo "${GREEN_TEXT}  ✔ fw-allow-health-check ready${RESET_FORMAT}"

if gcloud compute firewall-rules describe fw-allow-proxy-only-subnet >/dev/null 2>&1; then
  echo "${YELLOW_TEXT}  fw-allow-proxy-only-subnet already exists, skipping.${RESET_FORMAT}"
else
  gcloud compute firewall-rules create fw-allow-proxy-only-subnet \
    --network=lb-network \
    --action=ALLOW \
    --direction=INGRESS \
    --target-tags=allow-proxy-only-subnet \
    --source-ranges=10.129.0.0/23 \
    --rules=tcp:80 \
    --description="ePlus.DEV - allow proxy-only-subnet Envoy traffic to backends on port 80" \
    --quiet
fi
echo "${GREEN_TEXT}  ✔ fw-allow-proxy-only-subnet ready${RESET_FORMAT}"
echo ""

# ─── TASK 3: INSTANCE TEMPLATE & MIGs ───────────────────────────────
echo "${CYAN_TEXT}${BOLD_TEXT}[TASK 3] Creating instance template... | ${RESET_FORMAT}"

if gcloud compute instance-templates describe int-tcp-proxy-backend-template --region=${REGION} >/dev/null 2>&1; then
  echo "${YELLOW_TEXT}  Regional template exists, skipping.${RESET_FORMAT}"
elif gcloud compute instance-templates describe int-tcp-proxy-backend-template >/dev/null 2>&1; then
  echo "${YELLOW_TEXT}  Global template exists, skipping.${RESET_FORMAT}"
else
  gcloud compute instance-templates create int-tcp-proxy-backend-template \
    --region=${REGION} \
    --network=lb-network \
    --subnet=backend-subnet \
    --tags=allow-ssh,allow-health-check,allow-proxy-only-subnet \
    --description="ePlus.DEV - backend template for GSP636 internal proxy NLB" \
    --metadata=startup-script='#! /bin/bash
apt-get update
apt-get install apache2 -y
a2ensite default-ssl
a2enmod ssl
vm_hostname="$(curl -H "Metadata-Flavor:Google" http://metadata.google.internal/computeMetadata/v1/instance/name)"
echo "Page served from: $vm_hostname | ePlus.DEV" | tee /var/www/html/index.html
systemctl restart apache2' \
    --quiet
fi

echo "${GREEN_TEXT}  ✔ int-tcp-proxy-backend-template ready${RESET_FORMAT}"
echo ""

echo "${CYAN_TEXT}${BOLD_TEXT}[TASK 3] Creating MIG mig-a in ${ZONE_A}... | ${RESET_FORMAT}"

if gcloud compute instance-groups managed describe mig-a --zone=${ZONE_A} >/dev/null 2>&1; then
  echo "${YELLOW_TEXT}  mig-a already exists, skipping create.${RESET_FORMAT}"
else
  gcloud compute instance-groups managed create mig-a \
    --template=int-tcp-proxy-backend-template \
    --size=2 \
    --zone=${ZONE_A} \
    --description="ePlus.DEV - mig-a backend group zone ${ZONE_A}" \
    --quiet
fi

gcloud compute instance-groups managed set-named-ports mig-a \
  --named-ports=tcp80:80 \
  --zone=${ZONE_A} \
  --quiet

echo "${GREEN_TEXT}  ✔ mig-a ready (zone: ${ZONE_A})${RESET_FORMAT}"

echo "${CYAN_TEXT}${BOLD_TEXT}[TASK 3] Creating MIG mig-c in ${ZONE_C}... | ${RESET_FORMAT}"

if gcloud compute instance-groups managed describe mig-c --zone=${ZONE_C} >/dev/null 2>&1; then
  echo "${YELLOW_TEXT}  mig-c already exists, skipping create.${RESET_FORMAT}"
else
  gcloud compute instance-groups managed create mig-c \
    --template=int-tcp-proxy-backend-template \
    --size=2 \
    --zone=${ZONE_C} \
    --description="ePlus.DEV - mig-c backend group zone ${ZONE_C}" \
    --quiet
fi

gcloud compute instance-groups managed set-named-ports mig-c \
  --named-ports=tcp80:80 \
  --zone=${ZONE_C} \
  --quiet

echo "${GREEN_TEXT}  ✔ mig-c ready (zone: ${ZONE_C})${RESET_FORMAT}"
echo ""

# ─── TASK 4: LOAD BALANCER ───────────────────────────────────────────
echo "${CYAN_TEXT}${BOLD_TEXT}[TASK 4] Creating Load Balancer resources... | ${RESET_FORMAT}"

if gcloud compute addresses describe int-tcp-ip-address --region=${REGION} >/dev/null 2>&1; then
  echo "${YELLOW_TEXT}  int-tcp-ip-address already exists, skipping.${RESET_FORMAT}"
else
  gcloud compute addresses create int-tcp-ip-address \
    --region=${REGION} \
    --subnet=backend-subnet \
    --purpose=SHARED_LOADBALANCER_VIP \
    --quiet
fi
echo "${GREEN_TEXT}  ✔ int-tcp-ip-address ready${RESET_FORMAT}"

if gcloud compute health-checks describe tcp-health-check --region=${REGION} >/dev/null 2>&1; then
  echo "${YELLOW_TEXT}  tcp-health-check already exists, skipping.${RESET_FORMAT}"
else
  gcloud compute health-checks create tcp tcp-health-check \
    --region=${REGION} \
    --port=80 \
    --quiet
fi
echo "${GREEN_TEXT}  ✔ tcp-health-check ready${RESET_FORMAT}"

if gcloud compute backend-services describe my-int-tcp-lb --region=${REGION} >/dev/null 2>&1; then
  echo "${YELLOW_TEXT}  my-int-tcp-lb backend service already exists, skipping.${RESET_FORMAT}"
else
  gcloud compute backend-services create my-int-tcp-lb \
    --load-balancing-scheme=INTERNAL_MANAGED \
    --protocol=TCP \
    --region=${REGION} \
    --health-checks=tcp-health-check \
    --health-checks-region=${REGION} \
    --port-name=tcp80 \
    --quiet
fi
echo "${GREEN_TEXT}  ✔ backend service ready${RESET_FORMAT}"

# Add MIGs to backend service. Ignore duplicate backend errors.
gcloud compute backend-services add-backend my-int-tcp-lb \
  --region=${REGION} \
  --instance-group=mig-a \
  --instance-group-zone=${ZONE_A} \
  --balancing-mode=UTILIZATION \
  --max-utilization=0.8 \
  --quiet 2>/dev/null || true

gcloud compute backend-services add-backend my-int-tcp-lb \
  --region=${REGION} \
  --instance-group=mig-c \
  --instance-group-zone=${ZONE_C} \
  --balancing-mode=UTILIZATION \
  --max-utilization=0.8 \
  --quiet 2>/dev/null || true

echo "${GREEN_TEXT}  ✔ MIG backends attached${RESET_FORMAT}"

if gcloud compute target-tcp-proxies describe my-int-tcp-lb-proxy --region=${REGION} >/dev/null 2>&1; then
  echo "${YELLOW_TEXT}  target tcp proxy already exists, skipping.${RESET_FORMAT}"
else
  gcloud compute target-tcp-proxies create my-int-tcp-lb-proxy \
    --backend-service=my-int-tcp-lb \
    --backend-service-region=${REGION} \
    --region=${REGION} \
    --quiet
fi
echo "${GREEN_TEXT}  ✔ target tcp proxy ready${RESET_FORMAT}"

LB_IP=$(gcloud compute addresses describe int-tcp-ip-address \
  --region=${REGION} \
  --format='value(address)')

if gcloud compute forwarding-rules describe int-tcp-forwarding-rule --region=${REGION} >/dev/null 2>&1; then
  echo "${YELLOW_TEXT}  forwarding rule already exists, skipping.${RESET_FORMAT}"
else
  gcloud compute forwarding-rules create int-tcp-forwarding-rule \
    --load-balancing-scheme=INTERNAL_MANAGED \
    --network=lb-network \
    --subnet=backend-subnet \
    --address=int-tcp-ip-address \
    --ports=110 \
    --region=${REGION} \
    --target-tcp-proxy=my-int-tcp-lb-proxy \
    --target-tcp-proxy-region=${REGION} \
    --quiet
fi

echo "${GREEN_TEXT}  ✔ forwarding rule ready${RESET_FORMAT}"
echo "${GREEN_TEXT}  LB IP: ${LB_IP}${RESET_FORMAT}"
echo ""

# ─── TASK 5: CLIENT VM ───────────────────────────────────────────────
echo "${CYAN_TEXT}${BOLD_TEXT}[TASK 5] Creating client VM... | ${RESET_FORMAT}"

EXISTING_CLIENT_ZONE=$(gcloud compute instances list \
  --filter="name=('client-vm')" \
  --format="value(zone.basename())" \
  --limit=1 2>/dev/null)

if [ -n "$EXISTING_CLIENT_ZONE" ]; then
  export CLIENT_ZONE="$EXISTING_CLIENT_ZONE"
  echo "${YELLOW_TEXT}  client-vm already exists in ${CLIENT_ZONE}, reusing it.${RESET_FORMAT}"
else
  ZONE_CANDIDATES=$(
    printf "%s\n%s\n%s\n" "${REGION}-c" "${REGION}-b" "${REGION}-d"
    gcloud compute zones list \
      --filter="region:(${REGION}) status=UP" \
      --format="value(name)" 2>/dev/null
  | awk 'NF && !seen[$0]++')

  MACHINE_TYPES="e2-micro e2-small n1-standard-1"
  CLIENT_CREATED="false"

  for MACHINE_TYPE in $MACHINE_TYPES; do
    for ZONE in $ZONE_CANDIDATES; do
      echo "${YELLOW_TEXT}  Trying client-vm in ${ZONE} with ${MACHINE_TYPE}...${RESET_FORMAT}"

      if gcloud compute instances create client-vm \
        --zone=${ZONE} \
        --machine-type=${MACHINE_TYPE} \
        --network=lb-network \
        --subnet=backend-subnet \
        --tags=allow-ssh \
        --description="ePlus.DEV - internal client VM to test GSP636 NLB" \
        --quiet; then
        export CLIENT_ZONE="$ZONE"
        export CLIENT_MACHINE_TYPE="$MACHINE_TYPE"
        CLIENT_CREATED="true"
        break 2
      fi

      echo "${YELLOW_TEXT}  ${ZONE}/${MACHINE_TYPE} unavailable, trying next...${RESET_FORMAT}"
    done
  done

  if [ "$CLIENT_CREATED" != "true" ]; then
    echo "${RED_TEXT}[ERROR] Could not create client-vm in any UP zone of ${REGION}.${RESET_FORMAT}"
    echo "${YELLOW_TEXT}Try again later or manually create client-vm in lb-network/backend-subnet.${RESET_FORMAT}"
    exit 1
  fi
fi

echo "${GREEN_TEXT}  ✔ client-vm ready in ${CLIENT_ZONE}${RESET_FORMAT}"
echo ""

# ─── WAIT FOR BACKENDS ───────────────────────────────────────────────
echo "${YELLOW_TEXT}${BOLD_TEXT}[WAIT] Pausing 5 min for MIG instances + startup scripts... | ${RESET_FORMAT}"
for i in {1..5}; do
  echo "${BLACK_TEXT}  ${i}/5 min... | ${RESET_FORMAT}"
  sleep 60
done
echo ""

# ─── HEALTH CHECK ────────────────────────────────────────────────────
echo "${YELLOW_TEXT}${BOLD_TEXT}[CHECK] Backend health status: | ePlus.DEV${RESET_FORMAT}"
gcloud compute backend-services get-health my-int-tcp-lb --region=${REGION}
echo ""

# ─── TEST LOAD BALANCER ──────────────────────────────────────────────
echo "${CYAN_TEXT}${BOLD_TEXT}[TEST] Curl internal LB from client-vm... | ${RESET_FORMAT}"

LB_IP=$(gcloud compute addresses describe int-tcp-ip-address \
  --region=${REGION} \
  --format='value(address)')

echo "${YELLOW_TEXT}  LB IP: ${LB_IP}${RESET_FORMAT}"
echo "${YELLOW_TEXT}  Client Zone: ${CLIENT_ZONE}${RESET_FORMAT}"

for i in {1..5}; do
  echo "${CYAN_TEXT}  Request $i:${RESET_FORMAT}"
  gcloud compute ssh client-vm \
    --zone=${CLIENT_ZONE} \
    --command="curl -s ${LB_IP}:110" \
    --quiet || true
done

# ─── SUMMARY ─────────────────────────────────────────────────────────
echo ""
echo "${CYAN_TEXT}${BOLD_TEXT}============================================${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}         LAB SETUP COMPLETE!               ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}============================================${RESET_FORMAT}"
echo ""
echo "${GREEN_TEXT}Client VM Zone : ${CLIENT_ZONE}${RESET_FORMAT}"
echo "${GREEN_TEXT}LB IP          : ${LB_IP}${RESET_FORMAT}"
echo ""
echo "${YELLOW_TEXT}Manual test command:${RESET_FORMAT}"
echo "gcloud compute ssh client-vm --zone=${CLIENT_ZONE} --command=\"curl ${LB_IP}:110\""
echo ""
echo "${YELLOW_TEXT}Now click Check my progress for Task 5.${RESET_FORMAT}"