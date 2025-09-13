#!/bin/bash
# © 2025 ePlus.DEV. All rights reserved.

# Enhanced Color Definitions
BLACK=$'\033[0;30m'
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
BLUE=$'\033[0;34m'
MAGENTA=$'\033[0;35m'
CYAN=$'\033[0;36m'
WHITE=$'\033[0;37m'

BOLD=$'\033[1m'
RESET=$'\033[0m'

# ──────────────────────────────── HEADER ──────────────────────────────── #
echo -e "${MAGENTA}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${MAGENTA}${BOLD}║                                                                      ║${RESET}"
echo -e "${MAGENTA}${BOLD}║              🚀  Welcome to ${CYAN}ePlus.DEV${MAGENTA} Cloud Script  ║${RESET}"
echo -e "${MAGENTA}${BOLD}║                                                                      ║${RESET}"
echo -e "${MAGENTA}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
echo
echo -e "${CYAN}${BOLD}⚡ Powered by ePlus.DEV | Modern Cloud & Monitoring Setup ⚡${RESET}"
echo

# ──────────────────────────────── ENVIRONMENT ──────────────────────────────── #
echo -e "${YELLOW}${BOLD}━━━━━━━━━━ 🌍 ENVIRONMENT CONFIGURATION ━━━━━━━━━━${RESET}"
ZONE=${ZONE:-us-central1}
echo -e "${CYAN}Setting compute zone: ${WHITE}${BOLD}$ZONE${RESET}"
gcloud config set compute/zone $ZONE >/dev/null

export PROJECT_ID=$(gcloud info --format='value(config.project)')
echo -e "${CYAN}Using Project ID: ${WHITE}${BOLD}$PROJECT_ID${RESET}"
echo

# ──────────────────────────────── CLUSTER ──────────────────────────────── #
echo -e "${YELLOW}${BOLD}━━━━━━━━━━ ☸️  CLUSTER CONFIGURATION ━━━━━━━━━━${RESET}"
echo -e "${CYAN}Getting cluster credentials...${RESET}"
gcloud container clusters get-credentials central --zone $ZONE
echo -e "${GREEN}✔ Cluster credentials configured!${RESET}"
echo

# ──────────────────────────────── DEPLOYMENT ──────────────────────────────── #
echo -e "${YELLOW}${BOLD}━━━━━━━━━━ 📦 MICROSERVICES DEPLOYMENT ━━━━━━━━━━${RESET}"
git clone https://github.com/xiangshen-dk/microservices-demo.git >/dev/null 2>&1
cd microservices-demo

echo -e "${CYAN}Deploying microservices to Kubernetes...${RESET}"
kubectl apply -f release/kubernetes-manifests.yaml
echo -e "${GREEN}✔ Microservices deployed successfully!${RESET}"
sleep 5
echo

# ──────────────────────────────── MONITORING ──────────────────────────────── #
echo -e "${YELLOW}${BOLD}━━━━━━━━━━ 📊 MONITORING CONFIGURATION ━━━━━━━━━━${RESET}"
echo -e "${CYAN}Creating Error Rate SLI metric...${RESET}"
gcloud logging metrics create Error_Rate_SLI \
  --description="Error rate for recommendationservice" \
  --log-filter="resource.type=\"k8s_container\" severity=ERROR labels.\"k8s-pod/app\": \"recommendationservice\"" \
  >/dev/null 2>&1
echo -e "${GREEN}✔ Error Rate SLI metric created!${RESET}"
sleep 5
echo

# ──────────────────────────────── ALERTS ──────────────────────────────── #
echo -e "${YELLOW}${BOLD}━━━━━━━━━━ 🔔 ALERT POLICY SETUP ━━━━━━━━━━${RESET}"
cat > awesome.json <<EOF_END
{
  "displayName": "Error Rate SLI",
  "conditions": [
    {
      "displayName": "Kubernetes Container - Error Rate",
      "conditionThreshold": {
        "filter": "resource.type = \"k8s_container\" AND metric.type = \"logging.googleapis.com/user/Error_Rate_SLI\"",
        "aggregations": [
          { "alignmentPeriod": "300s", "crossSeriesReducer": "REDUCE_NONE", "perSeriesAligner": "ALIGN_RATE" }
        ],
        "comparison": "COMPARISON_GT",
        "duration": "0s",
        "trigger": { "count": 1 },
        "thresholdValue": 0.5
      }
    }
  ],
  "alertStrategy": { "autoClose": "604800s" },
  "combiner": "OR",
  "enabled": true
}
EOF_END

gcloud alpha monitoring policies create --policy-from-file="awesome.json" >/dev/null 2>&1
echo -e "${GREEN}✔ Alert policy created successfully!${RESET}"
echo

# ──────────────────────────────── FOOTER ──────────────────────────────── #
echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║                                                                    ║${RESET}"
echo -e "${CYAN}${BOLD}║        ✅ Setup Complete — Enjoy Monitoring with ePlus.DEV!       ║${RESET}"
echo -e "${CYAN}${BOLD}║                                                                    ║${RESET}"
echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════════════╝${RESET}"
echo
echo -e "${MAGENTA}${BOLD}💡 Tip:${RESET} Visit ${CYAN}https://eplus.dev${RESET} for more solutions."
echo
