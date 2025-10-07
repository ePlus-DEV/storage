#!/bin/bash
# ===============================================================
# 🌐 Google Cloud Monitoring Automation Script
# 🧑‍💻 Author: ePlus.DEV (Nguyễn Ngọc Minh Hoàng)
# 📅 Version: 1.0.0
# 🛡️ License: © 2025 ePlus.DEV - All rights reserved
# 🎨 Color theme: Neon Blue & Green for readability
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
echo -e " 🌐 GOOGLE CLOUD MONITORING LAB - AUTO SCRIPT"
echo -e " 🧑‍💻 Author: ${GREEN}ePlus.DEV${NC}"
echo -e " 📜 License: ${YELLOW}© 2025 ePlus.DEV - All rights reserved${NC}"
echo -e " 🎨 Theme: ${PURPLE}Neon Blue & Green${NC}"
echo -e "==============================================================\n"

# ----------------------------------------------
# 1️⃣ Set project & region
# ----------------------------------------------
echo -e "${BLUE}🔧 Setting up project and region...${NC}"
export PROJECT_ID=$(gcloud config get-value project)
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")

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
# 3️⃣ Deploy HelloWorld Cloud Run function
# ----------------------------------------------
echo -e "${BLUE}🚀 Creating and deploying Hello World Cloud Run function...${NC}"
mkdir helloworld && cd helloworld

cat > index.js <<'EOF'
const express = require('express');
const app = express();

app.get('/', (req, res) => {
  console.log("🔥 New request received!");
  res.send("Hello World!");
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => console.log(`🚀 Server running on port ${PORT}`));
EOF

cat > package.json <<'EOF'
{
  "name": "helloworld",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF

echo -e "${CYAN}📦 Deploying service...${NC}"
gcloud run deploy helloworld \
  --source . \
  --region=$REGION \
  --allow-unauthenticated \
  --max-instances=5 \
  --execution-environment=gen2 \
  --runtime=nodejs22

# ----------------------------------------------
# 4️⃣ Get URL and test function
# ----------------------------------------------
echo -e "${BLUE}🔗 Fetching Cloud Run URL...${NC}"
CLOUD_RUN_URL=$(gcloud run services describe helloworld --region=$REGION --format='value(status.url)')
echo -e "${GREEN}✅ Cloud Run URL:${NC} $CLOUD_RUN_URL\n"

echo -e "${CYAN}🧪 Sending test request...${NC}"
curl $CLOUD_RUN_URL

# ----------------------------------------------
# 5️⃣ Install Vegeta load testing tool
# ----------------------------------------------
echo -e "${BLUE}📊 Installing Vegeta load testing tool...${NC}"
cd ~
curl -LO 'https://github.com/tsenart/vegeta/releases/download/v12.12.0/vegeta_12.12.0_linux_386.tar.gz'
tar -xvzf vegeta_12.12.0_linux_386.tar.gz
chmod +x vegeta

echo -e "${CYAN}📈 Sending load traffic for 5 minutes...${NC}"
echo "GET $CLOUD_RUN_URL" | ./vegeta attack -duration=300s -rate=200 > results.bin &
echo -e "${GREEN}✅ Traffic generation started in the background.${NC}\n"

# ----------------------------------------------
# 6️⃣ Create logs-based metric
# ----------------------------------------------
echo -e "${BLUE}📊 Creating logs-based latency metric...${NC}"
gcloud beta logging metrics create CloudRunFunctionLatency-Logs \
  --description="Distribution metric for Cloud Run latency" \
  --log-filter='resource.type="cloud_run_revision" AND resource.labels.service_name="helloworld"' \
  --value-extractor="EXTRACT(httpRequest.latency)" \
  --metric-type="distribution" \
  --bucket-options='linearBuckets: {numFiniteBuckets: 50, width: 0.1, offset: 0.0}'

echo -e "${GREEN}✅ Logs-based metric created successfully.${NC}\n"

# ----------------------------------------------
# 7️⃣ Verify metric creation
# ----------------------------------------------
echo -e "${CYAN}🔍 Verifying metric...${NC}"
gcloud logging metrics list | grep CloudRunFunctionLatency-Logs
echo -e "${GREEN}✅ Metric verified.${NC}\n"

# ----------------------------------------------
# 8️⃣ Create Monitoring Dashboard
# ----------------------------------------------
echo -e "${BLUE}📊 Creating Monitoring Dashboard...${NC}"
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