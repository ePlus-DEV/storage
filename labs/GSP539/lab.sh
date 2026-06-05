#!/bin/bash
set -euo pipefail

# ================= COLOR =================
BLACK=$(tput setaf 0 || true)
RED=$(tput setaf 1 || true)
GREEN=$(tput setaf 2 || true)
YELLOW=$(tput setaf 3 || true)
BLUE=$(tput setaf 4 || true)
MAGENTA=$(tput setaf 5 || true)
CYAN=$(tput setaf 6 || true)
WHITE=$(tput setaf 7 || true)
BOLD=$(tput bold || true)
RESET=$(tput sgr0 || true)

echo "${MAGENTA}${BOLD}"
echo "============================================================"
echo "        Build Global and Regional Load Balancing Lab"
echo "                    © ePlus.DEV"
echo "============================================================"
echo "${RESET}"

# ================= CONFIG =================
PROJECT_ID=$(gcloud config get-value project)
NETWORK="lb-network"

# Auto detect Region B by proxy-only subnet CIDR
REGION_B=${REGION_B:-$(gcloud compute networks subnets list \
  --filter="network:($NETWORK) AND ipCidrRange=10.129.0.0/23" \
  --format="value(region.basename())" | head -n1)}

if [[ -z "${REGION_B}" ]]; then
  echo "${YELLOW}Không tìm thấy proxy-only subnet 10.129.0.0/23. Tự chọn Region B từ subnet trong lb-network...${RESET}"
  REGION_B=$(gcloud compute networks subnets list \
    --filter="network:($NETWORK)" \
    --format="value(region.basename())" | sort -u | head -n1)
fi

# Auto detect Region A as another region in lb-network
REGION_A=${REGION_A:-$(gcloud compute networks subnets list \
  --filter="network:($NETWORK)" \
  --format="value(region.basename())" | sort -u | grep -v "^${REGION_B}$" | head -n1)}

if [[ -z "${REGION_A}" ]]; then
  echo "${YELLOW}Không tìm thấy Region A khác Region B, dùng tạm Region B.${RESET}"
  REGION_A="$REGION_B"
fi

SUBNET_B=$(gcloud compute networks subnets list \
  --filter="network:($NETWORK) AND region:($REGION_B)" \
  --format="value(name)" | grep -v proxy | head -n1)

SUBNET_A=$(gcloud compute networks subnets list \
  --filter="network:($NETWORK) AND region:($REGION_A)" \
  --format="value(name)" | grep -v proxy | head -n1)

ZONE_B=$(gcloud compute zones list \
  --filter="region:($REGION_B) status=UP" \
  --format="value(name)" | head -n1)

echo "${CYAN}Project : ${PROJECT_ID}${RESET}"
echo "${CYAN}Network : ${NETWORK}${RESET}"
echo "${CYAN}Region A: ${REGION_A} / Subnet: ${SUBNET_A}${RESET}"
echo "${CYAN}Region B: ${REGION_B} / Subnet: ${SUBNET_B} / Zone: ${ZONE_B}${RESET}"
echo ""

# ================= HELPERS =================
exists_mig() {
  gcloud compute instance-groups managed describe "$1" --region "$2" >/dev/null 2>&1
}

exists_fw() {
  gcloud compute firewall-rules describe "$1" >/dev/null 2>&1
}

exists_regional_hc() {
  gcloud compute health-checks describe "$1" --region "$2" >/dev/null 2>&1
}

exists_global_hc() {
  gcloud compute health-checks describe "$1" --global >/dev/null 2>&1
}

exists_regional_backend() {
  gcloud compute backend-services describe "$1" --region "$2" >/dev/null 2>&1
}

exists_global_backend() {
  gcloud compute backend-services describe "$1" --global >/dev/null 2>&1
}

# ============================================================
# TASK 1 - REGIONAL INTERNAL PROXY NLB
# ============================================================
echo "${MAGENTA}${BOLD}[Task 1] Secure internal transaction processor${RESET}"

echo "${YELLOW}Creating regional MIG: mig-proxy-internal...${RESET}"
if ! exists_mig mig-proxy-internal "$REGION_B"; then
  gcloud compute instance-groups managed create mig-proxy-internal \
    --region="$REGION_B" \
    --template=template-proxy-internal \
    --size=2
else
  echo "${GREEN}mig-proxy-internal already exists.${RESET}"
fi

gcloud compute instance-groups managed set-named-ports mig-proxy-internal \
  --region="$REGION_B" \
  --named-ports=tcp80:80

echo "${YELLOW}Creating internal proxy firewall rules...${RESET}"
if ! exists_fw fw-allow-hc-proxy-internal; then
  gcloud compute firewall-rules create fw-allow-hc-proxy-internal \
    --network="$NETWORK" \
    --direction=INGRESS \
    --action=ALLOW \
    --rules=tcp:80 \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags=tag-proxy-internal
else
  echo "${GREEN}fw-allow-hc-proxy-internal already exists.${RESET}"
fi

if ! exists_fw fw-allow-proxy-only-internal; then
  gcloud compute firewall-rules create fw-allow-proxy-only-internal \
    --network="$NETWORK" \
    --direction=INGRESS \
    --action=ALLOW \
    --rules=tcp:80 \
    --source-ranges=10.129.0.0/23 \
    --target-tags=tag-proxy-internal
else
  echo "${GREEN}fw-allow-proxy-only-internal already exists.${RESET}"
fi

echo "${YELLOW}Ensuring proxy-only subnet exists in Region B...${RESET}"
PROXY_SUBNET=$(gcloud compute networks subnets list \
  --filter="network:($NETWORK) AND region:($REGION_B) AND purpose:REGIONAL_MANAGED_PROXY" \
  --format="value(name)" | head -n1 || true)

if [[ -z "$PROXY_SUBNET" ]]; then
  gcloud compute networks subnets create proxy-only-subnet \
    --network="$NETWORK" \
    --region="$REGION_B" \
    --range=10.129.0.0/23 \
    --purpose=REGIONAL_MANAGED_PROXY \
    --role=ACTIVE
fi

echo "${YELLOW}Creating internal proxy NLB backend components...${RESET}"
if ! exists_regional_hc hc-internal-proxy "$REGION_B"; then
  gcloud compute health-checks create tcp hc-internal-proxy \
    --region="$REGION_B" \
    --port=80
fi

if ! exists_regional_backend service-internal-proxy "$REGION_B"; then
  gcloud compute backend-services create service-internal-proxy \
    --region="$REGION_B" \
    --load-balancing-scheme=INTERNAL_MANAGED \
    --protocol=TCP \
    --port-name=tcp80 \
    --health-checks=hc-internal-proxy \
    --health-checks-region="$REGION_B"
fi

gcloud compute backend-services add-backend service-internal-proxy \
  --region="$REGION_B" \
  --instance-group=mig-proxy-internal \
  --instance-group-region="$REGION_B" \
  --balancing-mode=CONNECTION \
  --max-connections-per-instance=100 || true

if ! gcloud compute target-tcp-proxies describe proxy-internal-proxy --region="$REGION_B" >/dev/null 2>&1; then
  gcloud compute target-tcp-proxies create proxy-internal-proxy \
    --region="$REGION_B" \
    --backend-service=service-internal-proxy \
    --backend-service-region="$REGION_B"
fi

echo "${YELLOW}Reserving internal IP: ip-internal-proxy...${RESET}"
if ! gcloud compute addresses describe ip-internal-proxy --region="$REGION_B" >/dev/null 2>&1; then
  gcloud compute addresses create ip-internal-proxy \
    --region="$REGION_B" \
    --subnet="$SUBNET_B" \
    --addresses="" \
    --purpose=SHARED_LOADBALANCER_VIP
fi

INTERNAL_IP=$(gcloud compute addresses describe ip-internal-proxy \
  --region="$REGION_B" \
  --format="value(address)")

echo "${YELLOW}Creating forwarding rule: rule-internal-proxy on TCP 110...${RESET}"
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

echo "${YELLOW}Creating SSH firewall and client VM...${RESET}"
if ! exists_fw fw-allow-ssh; then
  gcloud compute firewall-rules create fw-allow-ssh \
    --network="$NETWORK" \
    --direction=INGRESS \
    --action=ALLOW \
    --rules=tcp:22 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=allow-ssh
fi

if ! gcloud compute instances describe vm-client-internal --zone="$ZONE_B" >/dev/null 2>&1; then
  gcloud compute instances create vm-client-internal \
    --zone="$ZONE_B" \
    --machine-type=e2-micro \
    --network="$NETWORK" \
    --subnet="$SUBNET_B" \
    --tags=allow-ssh \
    --quiet
fi

echo "${YELLOW}Testing internal proxy LB from client VM...${RESET}"
sleep 20
gcloud compute ssh vm-client-internal \
  --zone="$ZONE_B" \
  --quiet \
  --command="curl -s --connect-timeout 5 http://${INTERNAL_IP}:110 || true"

echo "${GREEN}Internal Proxy LB IP: ${INTERNAL_IP}:110${RESET}"
echo ""

# ============================================================
# TASK 2 - GLOBAL EXTERNAL HTTPS ALB
# ============================================================
echo "${MAGENTA}${BOLD}[Task 2] Global external market data feed HTTPS ALB${RESET}"

echo "${YELLOW}Creating MIG: mig-alb-api-a in ${REGION_A}...${RESET}"
if ! exists_mig mig-alb-api-a "$REGION_A"; then
  gcloud compute instance-groups managed create mig-alb-api-a \
    --region="$REGION_A" \
    --template=template-alb-api \
    --size=2
else
  echo "${GREEN}mig-alb-api-a already exists.${RESET}"
fi

gcloud compute instance-groups managed set-named-ports mig-alb-api-a \
  --region="$REGION_A" \
  --named-ports=http80:80

echo "${YELLOW}Creating MIG: mig-alb-api-b in ${REGION_B}...${RESET}"
if ! exists_mig mig-alb-api-b "$REGION_B"; then
  gcloud compute instance-groups managed create mig-alb-api-b \
    --region="$REGION_B" \
    --template=template-alb-api \
    --size=2
else
  echo "${GREEN}mig-alb-api-b already exists.${RESET}"
fi

gcloud compute instance-groups managed set-named-ports mig-alb-api-b \
  --region="$REGION_B" \
  --named-ports=http80:80

echo "${YELLOW}Creating ALB firewall rule...${RESET}"
if ! exists_fw fw-allow-health-check-and-proxy; then
  gcloud compute firewall-rules create fw-allow-health-check-and-proxy \
    --network="$NETWORK" \
    --direction=INGRESS \
    --action=ALLOW \
    --rules=tcp:80 \
    --source-ranges=130.211.0.0/22,35.191.0.0/16
else
  echo "${GREEN}fw-allow-health-check-and-proxy already exists.${RESET}"
fi

echo "${YELLOW}Creating global HTTP health check...${RESET}"
if ! exists_global_hc http-check-alb; then
  gcloud compute health-checks create http http-check-alb \
    --global \
    --port=80
fi

echo "${YELLOW}Creating global backend service...${RESET}"
if ! exists_global_backend service-alb-global; then
  gcloud compute backend-services create service-alb-global \
    --global \
    --load-balancing-scheme=EXTERNAL_MANAGED \
    --protocol=HTTP \
    --port-name=http80 \
    --health-checks=http-check-alb
fi

echo "${YELLOW}Adding both regional MIGs as RATE backends, max RPS = 1...${RESET}"
gcloud compute backend-services add-backend service-alb-global \
  --global \
  --instance-group=mig-alb-api-a \
  --instance-group-region="$REGION_A" \
  --balancing-mode=RATE \
  --max-rate-per-instance=1 || true

gcloud compute backend-services add-backend service-alb-global \
  --global \
  --instance-group=mig-alb-api-b \
  --instance-group-region="$REGION_B" \
  --balancing-mode=RATE \
  --max-rate-per-instance=1 || true

echo "${YELLOW}Generating self-signed SSL certificate...${RESET}"
if ! gcloud compute ssl-certificates describe cert-self-signed --global >/dev/null 2>&1; then
  openssl genrsa -out key.pem 2048
  openssl req -new -x509 -key key.pem -out cert.pem -days 1 -subj "/CN=example.com"

  gcloud compute ssl-certificates create cert-self-signed \
    --certificate=cert.pem \
    --private-key=key.pem \
    --global
fi

echo "${YELLOW}Reserving global static IP: ip-alb-global...${RESET}"
if ! gcloud compute addresses describe ip-alb-global --global >/dev/null 2>&1; then
  gcloud compute addresses create ip-alb-global \
    --ip-version=IPV4 \
    --global
fi

ALB_IP=$(gcloud compute addresses describe ip-alb-global \
  --global \
  --format="value(address)")

echo "${YELLOW}Creating URL map, HTTPS proxy, and forwarding rule...${RESET}"
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

echo "${GREEN}Global HTTPS ALB IP: ${ALB_IP}${RESET}"
echo ""

# ============================================================
# TASK 3 - TEST DISTRIBUTION + FAILOVER
# ============================================================
echo "${MAGENTA}${BOLD}[Task 3] Test global distribution and failover${RESET}"

echo "${YELLOW}Waiting for ALB health checks...${RESET}"
sleep 60

echo "${CYAN}Test HTTPS ALB:${RESET}"
for i in {1..10}; do
  curl -k -s "https://${ALB_IP}" | grep "Hello from" || true
  sleep 0.5
done

echo ""
echo "${YELLOW}Finding one VM from mig-alb-api-a to stop nginx...${RESET}"
read -r INST_A ZONE_A_INST <<< "$(gcloud compute instance-groups managed list-instances mig-alb-api-a \
  --region="$REGION_A" \
  --format="value(instance.basename(),zone.basename())" | head -n1)"

echo "${CYAN}Stopping nginx on ${INST_A} / ${ZONE_A_INST}...${RESET}"
gcloud compute ssh "$INST_A" \
  --zone="$ZONE_A_INST" \
  --quiet \
  --command="sudo systemctl stop nginx"

echo ""
echo "${GREEN}${BOLD}DONE - Resources created.${RESET}"
echo "${YELLOW}Now click Check my progress for Task 3 while nginx is stopped.${RESET}"
echo ""
echo "${CYAN}ALB IP:${RESET} https://${ALB_IP}"
echo "${CYAN}Internal Proxy IP:${RESET} ${INTERNAL_IP}:110"
echo ""
echo "${MAGENTA}${BOLD}Test distribution command:${RESET}"
echo "while true; do curl -k -s https://${ALB_IP} | grep 'Hello from'; sleep 0.5; done"
echo ""
echo "${MAGENTA}${BOLD}Restore backend after scoring Task 3:${RESET}"
echo "gcloud compute ssh ${INST_A} --zone=${ZONE_A_INST} --command='sudo systemctl start nginx'"
echo ""
echo "${MAGENTA}${BOLD}© ePlus.DEV${RESET}"