#!/bin/bash
set -euo pipefail

GREEN=$(tput setaf 2 || true)
YELLOW=$(tput setaf 3 || true)
RED=$(tput setaf 1 || true)
MAGENTA=$(tput setaf 5 || true)
CYAN=$(tput setaf 6 || true)
BOLD=$(tput bold || true)
RESET=$(tput sgr0 || true)

echo "${MAGENTA}${BOLD}"
echo "============================================================"
echo " Build Global and Regional Load Balancing Solutions Challenge"
echo "                    © ePlus.DEV"
echo "============================================================"
echo "${RESET}"

PROJECT_ID=$(gcloud config get-value project)
NETWORK="lb-network"

echo "${CYAN}Project: ${PROJECT_ID}${RESET}"
echo "${CYAN}Network: ${NETWORK}${RESET}"

# Detect regions
REGION_A=$(gcloud compute networks subnets list \
  --filter="network:($NETWORK) AND name~region-a" \
  --format="value(region.basename())" | head -n1)

REGION_B=$(gcloud compute networks subnets list \
  --filter="network:($NETWORK) AND name~region-b" \
  --format="value(region.basename())" | head -n1)

if [[ -z "$REGION_A" || -z "$REGION_B" ]]; then
  echo "${YELLOW}Could not detect by subnet name. Falling back to sorted regions...${RESET}"
  REGION_A=$(gcloud compute networks subnets list \
    --filter="network:($NETWORK)" \
    --format="value(region.basename())" | sort -u | head -n1)

  REGION_B=$(gcloud compute networks subnets list \
    --filter="network:($NETWORK)" \
    --format="value(region.basename())" | sort -u | tail -n1)
fi

SUBNET_A=$(gcloud compute networks subnets list \
  --filter="network:($NETWORK) AND region:($REGION_A)" \
  --format="value(name)" | grep -vi proxy | head -n1)

SUBNET_B=$(gcloud compute networks subnets list \
  --filter="network:($NETWORK) AND region:($REGION_B)" \
  --format="value(name)" | grep -vi proxy | head -n1)

ZONE_A=$(gcloud compute zones list \
  --filter="region:($REGION_A) status=UP" \
  --format="value(name)" | head -n1)

ZONE_B=$(gcloud compute zones list \
  --filter="region:($REGION_B) status=UP" \
  --format="value(name)" | head -n1)

echo "${GREEN}Region A: ${REGION_A} / Subnet: ${SUBNET_A} / Zone: ${ZONE_A}${RESET}"
echo "${GREEN}Region B: ${REGION_B} / Subnet: ${SUBNET_B} / Zone: ${ZONE_B}${RESET}"

# Template resolver
get_global_template() {
  gcloud compute instance-templates describe "$1" \
    --format="value(selfLink)" 2>/dev/null || true
}

get_regional_template() {
  gcloud compute instance-templates describe "$1" \
    --region="$2" \
    --format="value(selfLink)" 2>/dev/null || true
}

echo "${YELLOW}Checking required lab templates...${RESET}"

# For proxy internal: prefer regional template in Region B, fallback global
PROXY_TEMPLATE_LINK=$(get_regional_template template-proxy-internal "$REGION_B")
if [[ -z "$PROXY_TEMPLATE_LINK" ]]; then
  PROXY_TEMPLATE_LINK=$(get_global_template template-proxy-internal)
fi

# For ALB: use global template as lab requires template-alb-api
ALB_TEMPLATE_LINK=$(get_global_template template-alb-api)

if [[ -z "$PROXY_TEMPLATE_LINK" ]]; then
  echo "${RED}Missing template-proxy-internal.${RESET}"
  exit 1
fi

if [[ -z "$ALB_TEMPLATE_LINK" ]]; then
  echo "${RED}Missing template-alb-api.${RESET}"
  exit 1
fi

echo "${GREEN}Proxy template: ${PROXY_TEMPLATE_LINK}${RESET}"
echo "${GREEN}ALB template   : ${ALB_TEMPLATE_LINK}${RESET}"
echo ""

# ============================================================
# TASK 1
# ============================================================
echo "${MAGENTA}${BOLD}[Task 1] Secure internal transaction processor${RESET}"

echo "${YELLOW}Creating regional MIG: mig-proxy-internal...${RESET}"
if ! gcloud compute instance-groups managed describe mig-proxy-internal --region="$REGION_B" >/dev/null 2>&1; then
  gcloud compute instance-groups managed create mig-proxy-internal \
    --region="$REGION_B" \
    --template="$PROXY_TEMPLATE_LINK" \
    --size=2
else
  echo "${GREEN}mig-proxy-internal already exists.${RESET}"
fi

gcloud compute instance-groups managed set-named-ports mig-proxy-internal \
  --region="$REGION_B" \
  --named-ports=tcp80:80

echo "${YELLOW}Creating internal proxy firewall rules...${RESET}"
if ! gcloud compute firewall-rules describe fw-allow-hc-proxy-internal >/dev/null 2>&1; then
  gcloud compute firewall-rules create fw-allow-hc-proxy-internal \
    --network="$NETWORK" \
    --action=ALLOW \
    --direction=INGRESS \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags=tag-proxy-internal \
    --rules=tcp:80
fi

if ! gcloud compute firewall-rules describe fw-allow-proxy-subnet-internal >/dev/null 2>&1; then
  gcloud compute firewall-rules create fw-allow-proxy-subnet-internal \
    --network="$NETWORK" \
    --action=ALLOW \
    --direction=INGRESS \
    --source-ranges=10.129.0.0/23 \
    --target-tags=tag-proxy-internal \
    --rules=tcp:80
fi

echo "${YELLOW}Creating regional TCP health check...${RESET}"
if ! gcloud compute health-checks describe hc-internal-proxy --region="$REGION_B" >/dev/null 2>&1; then
  gcloud compute health-checks create tcp hc-internal-proxy \
    --region="$REGION_B" \
    --port=80
fi

echo "${YELLOW}Reserving internal static IP: ip-internal-proxy...${RESET}"
if ! gcloud compute addresses describe ip-internal-proxy --region="$REGION_B" >/dev/null 2>&1; then
  gcloud compute addresses create ip-internal-proxy \
    --region="$REGION_B" \
    --subnet="$SUBNET_B" \
    --purpose=SHARED_LOADBALANCER_VIP
fi

INTERNAL_LB_IP=$(gcloud compute addresses describe ip-internal-proxy \
  --region="$REGION_B" \
  --format="value(address)")

echo "${YELLOW}Creating regional backend service...${RESET}"
if ! gcloud compute backend-services describe internal-proxy-backend --region="$REGION_B" >/dev/null 2>&1; then
  gcloud compute backend-services create internal-proxy-backend \
    --load-balancing-scheme=INTERNAL_MANAGED \
    --protocol=TCP \
    --port-name=tcp80 \
    --region="$REGION_B" \
    --health-checks=hc-internal-proxy \
    --health-checks-region="$REGION_B"
fi

gcloud compute backend-services add-backend internal-proxy-backend \
  --instance-group=mig-proxy-internal \
  --instance-group-region="$REGION_B" \
  --region="$REGION_B" \
  --balancing-mode=CONNECTION \
  --max-connections-per-instance=100 >/dev/null 2>&1 || true

echo "${YELLOW}Creating regional target TCP proxy...${RESET}"
if ! gcloud compute target-tcp-proxies describe proxy-internal-proxy --region="$REGION_B" >/dev/null 2>&1; then
  gcloud compute target-tcp-proxies create proxy-internal-proxy \
    --region="$REGION_B" \
    --backend-service=internal-proxy-backend \
    --backend-service-region="$REGION_B"
fi

echo "${YELLOW}Creating forwarding rule: rule-internal-proxy...${RESET}"
if ! gcloud compute forwarding-rules describe rule-internal-proxy --region="$REGION_B" >/dev/null 2>&1; then
  gcloud compute forwarding-rules create rule-internal-proxy \
    --region="$REGION_B" \
    --load-balancing-scheme=INTERNAL_MANAGED \
    --network="$NETWORK" \
    --subnet="$SUBNET_B" \
    --address=ip-internal-proxy \
    --ports=110 \
    --target-tcp-proxy=proxy-internal-proxy \
    --target-tcp-proxy-region="$REGION_B"
fi

echo "${YELLOW}Creating client VM: vm-client-internal...${RESET}"
if ! gcloud compute instances describe vm-client-internal --zone="$ZONE_B" >/dev/null 2>&1; then
  gcloud compute instances create vm-client-internal \
    --zone="$ZONE_B" \
    --machine-type=e2-micro \
    --network="$NETWORK" \
    --subnet="$SUBNET_B" \
    --tags=allow-ssh \
    --quiet
fi

sleep 30

gcloud compute ssh vm-client-internal \
  --zone="$ZONE_B" \
  --quiet \
  --command="curl -s --connect-timeout 10 http://${INTERNAL_LB_IP}:110 || true"

echo "${GREEN}Task 1 completed. Internal LB IP: ${INTERNAL_LB_IP}:110${RESET}"
echo ""

# ============================================================
# TASK 2
# ============================================================
echo "${MAGENTA}${BOLD}[Task 2] Global external market data feed HTTPS ALB${RESET}"

echo "${YELLOW}Creating mig-alb-api-a...${RESET}"
if ! gcloud compute instance-groups managed describe mig-alb-api-a --region="$REGION_A" >/dev/null 2>&1; then
  gcloud compute instance-groups managed create mig-alb-api-a \
    --region="$REGION_A" \
    --template="$ALB_TEMPLATE_LINK" \
    --size=2
fi

gcloud compute instance-groups managed set-named-ports mig-alb-api-a \
  --region="$REGION_A" \
  --named-ports=http80:80

echo "${YELLOW}Creating mig-alb-api-b...${RESET}"
if ! gcloud compute instance-groups managed describe mig-alb-api-b --region="$REGION_B" >/dev/null 2>&1; then
  gcloud compute instance-groups managed create mig-alb-api-b \
    --region="$REGION_B" \
    --template="$ALB_TEMPLATE_LINK" \
    --size=2
fi

gcloud compute instance-groups managed set-named-ports mig-alb-api-b \
  --region="$REGION_B" \
  --named-ports=http80:80

echo "${YELLOW}Creating firewall rule: fw-allow-health-check-and-proxy...${RESET}"
if ! gcloud compute firewall-rules describe fw-allow-health-check-and-proxy >/dev/null 2>&1; then
  gcloud compute firewall-rules create fw-allow-health-check-and-proxy \
    --network="$NETWORK" \
    --action=ALLOW \
    --direction=INGRESS \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --rules=tcp:80
fi

echo "${YELLOW}Creating global HTTP health check...${RESET}"
if ! gcloud compute health-checks describe http-check-alb --global >/dev/null 2>&1; then
  gcloud compute health-checks create http http-check-alb \
    --global \
    --port=80
fi

echo "${YELLOW}Creating global backend service...${RESET}"
if ! gcloud compute backend-services describe service-alb-global --global >/dev/null 2>&1; then
  gcloud compute backend-services create service-alb-global \
    --global \
    --load-balancing-scheme=EXTERNAL_MANAGED \
    --protocol=HTTP \
    --port-name=http80 \
    --health-checks=http-check-alb
fi

gcloud compute backend-services add-backend service-alb-global \
  --global \
  --instance-group=mig-alb-api-a \
  --instance-group-region="$REGION_A" \
  --balancing-mode=RATE \
  --max-rate=1 >/dev/null 2>&1 || true

gcloud compute backend-services add-backend service-alb-global \
  --global \
  --instance-group=mig-alb-api-b \
  --instance-group-region="$REGION_B" \
  --balancing-mode=RATE \
  --max-rate=1 >/dev/null 2>&1 || true

echo "${YELLOW}Creating SSL certificate...${RESET}"
if ! gcloud compute ssl-certificates describe cert-self-signed --global >/dev/null 2>&1; then
  openssl genrsa -out key.pem 2048
  openssl req -new -x509 -key key.pem -out cert.pem -days 1 -subj "/CN=example.com"

  gcloud compute ssl-certificates create cert-self-signed \
    --certificate=cert.pem \
    --private-key=key.pem \
    --global
fi

echo "${YELLOW}Reserving global IP...${RESET}"
if ! gcloud compute addresses describe ip-alb-global --global >/dev/null 2>&1; then
  gcloud compute addresses create ip-alb-global \
    --ip-version=IPV4 \
    --global
fi

ALB_IP=$(gcloud compute addresses describe ip-alb-global \
  --global \
  --format="value(address)")

echo "${YELLOW}Creating HTTPS frontend...${RESET}"
if ! gcloud compute url-maps describe map-alb-global >/dev/null 2>&1; then
  gcloud compute url-maps create map-alb-global \
    --default-service=service-alb-global
fi

if ! gcloud compute target-https-proxies describe proxy-alb-global >/dev/null 2>&1; then
  gcloud compute target-https-proxies create proxy-alb-global \
    --url-map=map-alb-global \
    --ssl-certificates=cert-self-signed
fi

if ! gcloud compute forwarding-rules describe rule-alb-global --global >/dev/null 2>&1; then
  gcloud compute forwarding-rules create rule-alb-global \
    --global \
    --load-balancing-scheme=EXTERNAL_MANAGED \
    --address=ip-alb-global \
    --target-https-proxy=proxy-alb-global \
    --ports=443
fi

echo "${GREEN}Task 2 completed. Global HTTPS ALB IP: ${ALB_IP}${RESET}"
echo ""

# ============================================================
# TASK 3
# ============================================================
echo "${MAGENTA}${BOLD}[Task 3] Test failover and global distribution${RESET}"

sleep 90

for i in {1..10}; do
  curl -k -s "https://${ALB_IP}" | grep "Hello from" || true
  sleep 0.5
done

read -r FAIL_VM FAIL_ZONE <<< "$(gcloud compute instance-groups managed list-instances mig-alb-api-a \
  --region="$REGION_A" \
  --format="value(instance.basename(),zone.basename())" | head -n1)"

if [[ -n "${FAIL_VM:-}" && -n "${FAIL_ZONE:-}" ]]; then
  gcloud compute ssh "$FAIL_VM" \
    --zone="$FAIL_ZONE" \
    --quiet \
    --command="sudo systemctl stop nginx"

  RESTORE_CMD="gcloud compute ssh ${FAIL_VM} --zone=${FAIL_ZONE} --command='sudo systemctl start nginx'"
else
  RESTORE_CMD="Manually SSH into one mig-alb-api-a VM and run: sudo systemctl start nginx"
fi

echo ""
echo "${GREEN}${BOLD}DONE - Only lab-required resources were created.${RESET}"
echo "${CYAN}Internal Proxy LB:${RESET} ${INTERNAL_LB_IP}:110"
echo "${CYAN}Global HTTPS ALB:${RESET} https://${ALB_IP}"
echo ""
echo "${YELLOW}Click Check my progress now. Keep nginx stopped for Task 3.${RESET}"
echo ""
echo "${MAGENTA}${BOLD}Traffic distribution test:${RESET}"
echo "while true; do curl -k -s https://${ALB_IP} | grep 'Hello from'; sleep 0.5; done"
echo ""
echo "${MAGENTA}${BOLD}Restore backend after Task 3 passes:${RESET}"
echo "${RESTORE_CMD}"
echo ""
echo "${MAGENTA}${BOLD}© ePlus.DEV${RESET}"