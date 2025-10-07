#!/bin/bash
# ===============================================================
# 🌐 Google Cloud Monitoring Automation Script
# 🧑‍💻 Author: ePlus.DEV (Nguyễn Ngọc Minh Hoàng)
# 📅 Version: 2.0.0
# 🛡️ License: © 2025 ePlus.DEV - All rights reserved
# 🎨 Color theme: Neon Blue & Green
# ===============================================================

# --- COLORS ---
RED='\033[0;31m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
PURPLE='\033[1;35m'
NC='\033[0m' # No Color

echo -e "${CYAN}=============================================================="
echo -e " 🌐 GOOGLE CLOUD MONITORING LAB - FULL AUTOMATION SCRIPT"
echo -e " 🧑‍💻 Author: ${GREEN}ePlus.DEV${NC}"
echo -e " 📜 License: ${YELLOW}© 2025 ePlus.DEV - All rights reserved${NC}"
echo -e " 🎨 Theme: ${PURPLE}Neon Blue & Green${NC}"
echo -e "==============================================================\n"

# ----------------------------------------------
# 1️⃣ Setup project and region
# ----------------------------------------------
echo -e "${BLUE}🔧 Setting up project and region...${NC}"
export PROJECT_ID=$(gcloud config get-value project)
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

echo -e "${GREEN}✅ Project:${NC} $PROJECT_ID"
echo -e "${GREEN}✅ Region:${NC} $REGION\n"

# ----------------------------------------------
# 2️⃣ Enable required APIs
# ----------------------------------------------
echo -e "${BLUE}📡 Enabling required APIs...${NC}"
gcloud services enable run.googleapis.com \
    logging.googleapis.com \
    monitoring.googleapis.com \
    cloudfunctions.googleapis.com
echo -e "${GREEN}✅ APIs enabled successfully.${NC}\n"

# ----------------------------------------------
# 3️⃣ Verify Cloud Run Service Created
# ----------------------------------------------
echo -e "${BLUE}🔍 Checking if 'helloworld' service exists...${NC}"
SERVICE_EXISTS=$(gcloud run services list --region=$REGION --format="value(metadata.name)" | grep "helloworld" || true)

if [ -z "$SERVICE_EXISTS" ]; then
  echo -e "${RED}⚠️ Service 'helloworld' not found!${NC}"
  echo -e "${YELLOW}👉 Please go to Cloud Console and create the service manually first:${NC}"
  echo -e "   - Service name: ${CYAN}helloworld${NC}"
  echo -e "   - Region: ${CYAN}us-central1${NC}"
  echo -e "   - Authentication: ${CYAN}Allow unauthenticated${NC}"
  echo -e "   - Execution environment: ${CYAN}Second generation${NC}"
  echo -e "   - Max instances: ${CYAN}5${NC}"
  echo -e "\n❗ After creation, rerun this script.\n"
  exit 1
else
  echo -e "${GREEN}✅ Service 'helloworld' detected. Continuing...${NC}\n"
fi

# ----------------------------------------------
# 4️⃣ Get Cloud Run URL
# ----------------------------------------------
echo -e "${BLUE}🔗 Fetching Cloud Run URL...${NC}"
CLOUD_RUN_URL=$(gcloud run services describe helloworld --region=$REGION --format='value(status.url)')

if [ -z "$CLOUD_RUN_URL" ]; then
  echo -e "${RED}❌ Could not retrieve Cloud Run URL. Please check deployment.${NC}"
  exit 1
else
  echo -e "${GREEN}✅ Cloud Run URL:${NC} $CLOUD_RUN_URL\n"
fi

# ----------------------------------------------
# 5️⃣ Test the function
# ----------------------------------------------
echo -e "${BLUE}🧪 Testing Cloud Run function...${NC}"
curl -s $CLOUD_RUN_URL && echo -e "\n${GREEN}✅ Test successful: Hello World received.${NC}\n"

# ----------------------------------------------
# 6️⃣ Install Vegeta for traffic generation
# ----------------------------------------------
echo -e "${BLUE}📊 Installing Vegeta load testing tool...${NC}"
cd ~
curl -LO 'https://github.com/tsenart/vegeta/releases/download/v12.12.0/vegeta_12.12.0_linux_386.tar.gz'
tar -xvzf vegeta_12.12.0_linux_386.tar.gz
chmod +x vegeta

# ----------------------------------------------
# 7️⃣ Send traffic
# ----------------------------------------------
echo -e "${CYAN}📈 Sending load traffic to generate logs (5 mins)...${NC}"
echo "GET $CLOUD_RUN_URL" | ./vegeta attack -duration=300s -rate=200 > results.bin &
echo -e "${GREEN}✅ Traffic generation started in the background.${NC}\n"

# ----------------------------------------------
# 8️⃣ Guide for Logs-Based Metric
# ----------------------------------------------
echo -e "${YELLOW}⚙️ Logs-based metrics must be created in the console manually:${NC}"
echo -e "👉 Go to: ${CYAN}Navigation Menu → Logging → Logs Explorer${NC}"
echo -e "   - Resource: ${GREEN}Cloud Run Revision${NC}"
echo -e "   - Service name: ${GREEN}helloworld${NC}"
echo -e "   - Create Metric → Distribution"
echo -e "   - Name: ${GREEN}CloudRunFunctionLatency-Logs${NC}"
echo -e "   - Field name: ${GREEN}httpRequest.latency${NC}"
echo -e "💡 Wait a few minutes and refresh if metric doesn't appear immediately.\n"

# ----------------------------------------------
# 9️⃣ Create Dashboard
# ----------------------------------------------
echo -e "${BLUE}📊 Creating a custom Monitoring Dashboard...${NC}"
cat > dashboard.json <<EOF
{
  "displayName": "Cloud Run Function Custom Dashboard",
  "gridLayout": {
    "columns": 2,
    "widgets": [
      {
        "title": "🌐 Request Count",
        "xyChart": {
          "dataSets": [{
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "metric.type=\"run.googleapis.com/request_count\"",
                "aggregation": {
                  "alignmentPeriod": "60s",
                  "perSeriesAligner": "ALIGN_RATE"
                }
              }
            }
          }]
        }
      },
      {
        "title": "⚡ Latency (Logs-Based Metric)",
        "xyChart": {
          "dataSets": [{
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "metric.type=\"logging.googleapis.com/user/CloudRunFunctionLatency-Logs\"",
                "aggregation": {
                  "alignmentPeriod": "60s",
                  "perSeriesAligner": "ALIGN_PERCENTILE_95"
                }
              }
            }
          }]
        }
      }
    ]
  }
}
EOF

gcloud monitoring dashboards create --config-from-file=dashboard.json
echo -e "${GREEN}✅ Dashboard created successfully.${NC}\n"

# ----------------------------------------------
# ✅ Summary
# ----------------------------------------------
echo -e "${PURPLE}==============================================================${NC}"
echo -e "🎉 ${GREEN}All steps completed successfully!${NC}"
echo -e "🌐 Cloud Run URL: ${YELLOW}$CLOUD_RUN_URL${NC}"
echo -e "📊 Metrics Explorer: ${CYAN}https://console.cloud.google.com/monitoring/metrics-explorer?project=$PROJECT_ID${NC}"
echo -e "📈 Dashboards: ${CYAN}https://console.cloud.google.com/monitoring/dashboards?project=$PROJECT_ID${NC}"
echo -e "${PURPLE}==============================================================${NC}"