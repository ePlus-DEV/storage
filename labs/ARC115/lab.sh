#!/usr/bin/env bash

# ARC115 / Cloud Monitoring Challenge Lab
# ePlus.DEV - Ops Agent version

# If accidentally sourced, don't allow this script to terminate the current shell.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  echo "Please run this script with: bash ${BASH_SOURCE[0]}"
  return 0 2>/dev/null || true
fi

set -Eeuo pipefail

# ================= COLORS =================
RED=$'\033[0;91m'
GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
BLUE=$'\033[0;94m'
MAGENTA=$'\033[0;95m'
CYAN=$'\033[0;96m'
WHITE=$'\033[0;97m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

step() {
  echo
  echo "${CYAN}${BOLD}======================================================================${RESET}"
  echo "${CYAN}${BOLD}$1${RESET}"
  echo "${CYAN}${BOLD}======================================================================${RESET}"
}

ok()   { echo "${GREEN}${BOLD}✓ $*${RESET}"; }
warn() { echo "${YELLOW}${BOLD}⚠ $*${RESET}"; }
fail() { echo "${RED}${BOLD}✗ $*${RESET}"; }

on_error() {
  local ec=$?
  fail "Script failed at line ${BASH_LINENO[0]} (exit code ${ec})."
  echo "${YELLOW}You can safely run this script again after fixing the reported error.${RESET}"
  exit "$ec"
}
trap on_error ERR

clear 2>/dev/null || true

echo "${MAGENTA}${BOLD}╔════════════════════════════════════════════════════════════════════╗${RESET}"
echo "${MAGENTA}${BOLD}║              Google Cloud Monitoring Challenge Lab               ║${RESET}"
echo "${MAGENTA}${BOLD}║                         © ePlus.DEV                               ║${RESET}"
echo "${MAGENTA}${BOLD}╚════════════════════════════════════════════════════════════════════╝${RESET}"

# ================= DETECT ENVIRONMENT =================
step "[1/8] Detecting lab environment"

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
ACCOUNT_EMAIL="$(gcloud config get-value account 2>/dev/null)"

if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  fail "Unable to detect the current Google Cloud project."
  exit 1
fi

ZONE="$(gcloud compute instances list \
  --project="$PROJECT_ID" \
  --filter='name=(apache-vm)' \
  --format='value(zone.basename())' \
  --limit=1)"

if [[ -z "$ZONE" ]]; then
  fail "VM apache-vm was not found in project $PROJECT_ID."
  exit 1
fi

INSTANCE_ID="$(gcloud compute instances describe apache-vm \
  --project="$PROJECT_ID" \
  --zone="$ZONE" \
  --format='value(id)')"

VM_EXTERNAL_IP="$(gcloud compute instances describe apache-vm \
  --project="$PROJECT_ID" \
  --zone="$ZONE" \
  --format='value(networkInterfaces[0].accessConfigs[0].natIP)')"

REGION="${ZONE%-*}"

echo "Project ID     : $PROJECT_ID"
echo "Account        : $ACCOUNT_EMAIL"
echo "VM             : apache-vm"
echo "Zone           : $ZONE"
echo "Region         : $REGION"
echo "Instance ID    : $INSTANCE_ID"
echo "External IP    : $VM_EXTERNAL_IP"
ok "Lab environment detected."

# ================= ENABLE APIS =================
step "[2/8] Enabling required APIs"

gcloud services enable \
  compute.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet

ok "Compute Engine, Cloud Logging, and Cloud Monitoring APIs are enabled."

# ================= OPS AGENT =================
step "[3/8] Installing and configuring Ops Agent on apache-vm"

REMOTE_SCRIPT="$(mktemp)"
cat > "$REMOTE_SCRIPT" <<'REMOTE_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
RESET=$'\033[0m'

# Debian 12 Qwiklabs images can contain obsolete repositories left by the
# legacy Stackdriver agents. They break apt-get update with a 404 response.
echo "Checking for obsolete legacy agent repositories..."
for f in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
  [[ -f "$f" ]] || continue
  if sudo grep -qE 'google-cloud-(logging|monitoring)-' "$f"; then
    echo "Disabling obsolete entries in: $f"
    sudo sed -i -E '/google-cloud-(logging|monitoring)-/ s|^[[:space:]]*deb |# disabled-by-eplus: deb |' "$f"
  fi
done

# Refresh APT after removing broken legacy repositories.
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get clean
sudo apt-get update -y
sudo apt-get install -y curl ca-certificates

# Enable Apache mod_status (required by the Ops Agent Apache metrics receiver).
if command -v a2enmod >/dev/null 2>&1; then
  sudo a2enmod status >/dev/null 2>&1 || true
  sudo systemctl restart apache2
fi

# Verify Apache is alive before installing the agent.
curl -fsS http://localhost/ >/dev/null

# Install the current Google Cloud Ops Agent, unless already present.
if ! dpkg-query -W -f='${Status}' google-cloud-ops-agent 2>/dev/null | grep -q 'install ok installed'; then
  cd /tmp
  curl -fsSLO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
  sudo bash add-google-cloud-ops-agent-repo.sh --also-install
else
  echo "Ops Agent is already installed."
fi

# Task 1 explicitly requires the Apache integration for metrics AND logging.
# The additional raw receiver named apache-access provides textPayload entries
# with logName apache-access, matching Task 5's exact log-based metric filter.
sudo mkdir -p /etc/google-cloud-ops-agent
if [[ -f /etc/google-cloud-ops-agent/config.yaml ]]; then
  sudo cp /etc/google-cloud-ops-agent/config.yaml "/etc/google-cloud-ops-agent/config.yaml.bak.$(date +%s)" || true
fi

sudo tee /etc/google-cloud-ops-agent/config.yaml >/dev/null <<'YAML_EOF'
metrics:
  receivers:
    apache:
      type: apache
      collection_interval: 60s
      server_status_url: http://localhost:80/server-status?auto
  service:
    pipelines:
      apache:
        receivers: [apache]

logging:
  receivers:
    apache_access:
      type: apache_access
    apache_error:
      type: apache_error
    apache-access:
      type: files
      include_paths:
        - /var/log/apache2/access.log
  service:
    pipelines:
      apache_builtin:
        receivers: [apache_access, apache_error]
      apache_raw:
        receivers: [apache-access]
YAML_EOF

sudo systemctl restart google-cloud-ops-agent
sleep 3

if ! sudo systemctl is-active --quiet google-cloud-ops-agent; then
  echo "Ops Agent failed to start. Recent logs:"
  sudo journalctl -u google-cloud-ops-agent -n 80 --no-pager
  exit 1
fi

echo
sudo systemctl --no-pager --full status 'google-cloud-ops-agent*' | head -n 50 || true

echo
printf 'Apache server-status: '
if curl -fsS 'http://localhost:80/server-status?auto' | grep -q 'Total Accesses'; then
  echo "OK"
else
  echo "FAILED"
  curl -sS 'http://localhost:80/server-status?auto' | head -n 20 || true
  exit 1
fi

# Generate sustained Apache traffic without blocking the SSH command for 120s.
# This feeds both apache.requests/apache.traffic and the apache-access raw log.
nohup timeout 180 bash -c 'while true; do curl -fsS http://localhost/ >/dev/null 2>&1 || true; sleep 0.05; done' \
  >/tmp/apache-lab-traffic.log 2>&1 </dev/null &

echo "Traffic generator started in background (180 seconds)."
REMOTE_EOF

chmod +x "$REMOTE_SCRIPT"

gcloud compute scp "$REMOTE_SCRIPT" apache-vm:/tmp/eplus-arc115-setup.sh \
  --project="$PROJECT_ID" \
  --zone="$ZONE" \
  --quiet

gcloud compute ssh apache-vm \
  --project="$PROJECT_ID" \
  --zone="$ZONE" \
  --quiet \
  --command='bash /tmp/eplus-arc115-setup.sh'

rm -f "$REMOTE_SCRIPT"
ok "Ops Agent and Apache integration configured successfully."

# ================= UPTIME CHECK =================
step "[4/8] Creating URL uptime check"

UPTIME_NAME="Apache Web Server Uptime Check"
EXISTING_UPTIME="$(gcloud monitoring uptime list-configs \
  --project="$PROJECT_ID" \
  --filter="displayName=\"$UPTIME_NAME\"" \
  --format='value(name)' \
  --limit=1 2>/dev/null || true)"

if [[ -z "$EXISTING_UPTIME" ]]; then
  gcloud monitoring uptime create "$UPTIME_NAME" \
    --project="$PROJECT_ID" \
    --resource-type=uptime-url \
    --resource-labels="host=$VM_EXTERNAL_IP,project_id=$PROJECT_ID" \
    --protocol=http \
    --path=/ \
    --port=80 \
    --period=1 \
    --timeout=10 \
    --quiet
  ok "URL uptime check created for http://$VM_EXTERNAL_IP/."
else
  ok "Uptime check already exists; keeping it."
fi

# ================= NOTIFICATION CHANNEL =================
step "[5/8] Creating notification channel and Apache traffic alert"

CHANNEL_DISPLAY="Apache Alert - Current Account"
CHANNEL_ID="$(gcloud beta monitoring channels list \
  --project="$PROJECT_ID" \
  --filter="displayName=\"$CHANNEL_DISPLAY\"" \
  --format='value(name)' \
  --limit=1 2>/dev/null || true)"

if [[ -z "$CHANNEL_ID" ]]; then
  CHANNEL_ID="$(gcloud beta monitoring channels create \
    --project="$PROJECT_ID" \
    --display-name="$CHANNEL_DISPLAY" \
    --type=email \
    --channel-labels="email_address=$ACCOUNT_EMAIL" \
    --format='value(name)' \
    --quiet)"
  ok "Notification channel created for $ACCOUNT_EMAIL."
else
  ok "Notification channel already exists for this lab."
fi

# Apache workload metrics are sampled every 60 seconds. Give the Ops Agent one
# collection interval to publish the first metric before creating the policy.
echo "Waiting for the first Apache metric sample (about 65 seconds)..."
sleep 65

POLICY_NAME="Apache Traffic > 3 KiB/s"
EXISTING_POLICY="$(gcloud monitoring policies list \
  --project="$PROJECT_ID" \
  --filter="displayName=\"$POLICY_NAME\"" \
  --format='value(name)' \
  --limit=1 2>/dev/null || true)"

if [[ -z "$EXISTING_POLICY" ]]; then
  POLICY_FILE="$(mktemp)"
  cat > "$POLICY_FILE" <<EOF_POLICY
{
  "displayName": "$POLICY_NAME",
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": ["$CHANNEL_ID"],
  "conditions": [
    {
      "displayName": "Apache traffic rate exceeds 3 KiB/s",
      "conditionThreshold": {
        "filter": "resource.type = \"gce_instance\" AND metric.type = \"workload.googleapis.com/apache.traffic\"",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_RATE"
          }
        ],
        "comparison": "COMPARISON_GT",
        "thresholdValue": 3072,
        "duration": "0s",
        "trigger": {"count": 1}
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  }
}
EOF_POLICY

  gcloud monitoring policies create \
    --project="$PROJECT_ID" \
    --policy-from-file="$POLICY_FILE" \
    --quiet
  rm -f "$POLICY_FILE"
  ok "Apache traffic alert policy created at 3072 bytes/s (3 KiB/s)."
else
  ok "Alert policy already exists; keeping it."
fi

# ================= DASHBOARD =================
step "[6/8] Creating dashboard with required charts"

DASHBOARD_NAME="Apache Web Server Dashboard"
OLD_DASHBOARD="$(gcloud monitoring dashboards list \
  --project="$PROJECT_ID" \
  --filter="displayName=\"$DASHBOARD_NAME\"" \
  --format='value(name)' \
  --limit=1 2>/dev/null || true)"

if [[ -n "$OLD_DASHBOARD" ]]; then
  gcloud monitoring dashboards delete "$OLD_DASHBOARD" \
    --project="$PROJECT_ID" \
    --quiet >/dev/null 2>&1 || true
fi

DASH_FILE="$(mktemp)"
cat > "$DASH_FILE" <<EOF_DASH
{
  "displayName": "$DASHBOARD_NAME",
  "mosaicLayout": {
    "columns": 12,
    "tiles": [
      {
        "xPos": 0,
        "yPos": 0,
        "width": 6,
        "height": 4,
        "widget": {
          "title": "VM - CPU load (1m)",
          "xyChart": {
            "dataSets": [
              {
                "plotType": "LINE",
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"gce_instance\" AND metric.type=\"agent.googleapis.com/cpu/load_1m\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_MEAN"
                    }
                  }
                }
              }
            ],
            "yAxis": {"label": "CPU load (1m)", "scale": "LINEAR"},
            "chartOptions": {"mode": "COLOR"}
          }
        }
      },
      {
        "xPos": 6,
        "yPos": 0,
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Apache Web Server - Requests",
          "xyChart": {
            "dataSets": [
              {
                "plotType": "LINE",
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"gce_instance\" AND metric.type=\"workload.googleapis.com/apache.requests\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE"
                    }
                  }
                }
              }
            ],
            "yAxis": {"label": "Requests/s", "scale": "LINEAR"},
            "chartOptions": {"mode": "COLOR"}
          }
        }
      }
    ]
  }
}
EOF_DASH

gcloud monitoring dashboards create \
  --project="$PROJECT_ID" \
  --config-from-file="$DASH_FILE" \
  --quiet
rm -f "$DASH_FILE"
ok "Dashboard created with CPU load (1m) and Apache Requests charts."

# ================= LOG-BASED METRIC =================
step "[7/8] Creating the required log-based metric"

LOG_METRIC_NAME="apache-200-responses"
LOG_FILTER="resource.type=\"gce_instance\"
logName=\"projects/$PROJECT_ID/logs/apache-access\"
textPayload:\"200\""

if gcloud logging metrics describe "$LOG_METRIC_NAME" \
  --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud logging metrics update "$LOG_METRIC_NAME" \
    --project="$PROJECT_ID" \
    --description="Count Apache access-log entries containing HTTP 200" \
    --log-filter="$LOG_FILTER" \
    --quiet
  ok "Existing log-based metric updated."
else
  gcloud logging metrics create "$LOG_METRIC_NAME" \
    --project="$PROJECT_ID" \
    --description="Count Apache access-log entries containing HTTP 200" \
    --log-filter="$LOG_FILTER" \
    --quiet
  ok "Log-based metric '$LOG_METRIC_NAME' created."
fi

# Generate a few fresh 200 log entries after the metric exists.
gcloud compute ssh apache-vm \
  --project="$PROJECT_ID" \
  --zone="$ZONE" \
  --quiet \
  --command="for i in \$(seq 1 30); do curl -fsS http://localhost/ >/dev/null 2>&1 || true; done"

# ================= VERIFY =================
step "[8/8] Verification summary"

echo "Checking Ops Agent one final time..."
gcloud compute ssh apache-vm \
  --project="$PROJECT_ID" \
  --zone="$ZONE" \
  --quiet \
  --command="sudo systemctl is-active google-cloud-ops-agent && curl -fsS 'http://localhost/server-status?auto' | head -n 8"

echo
ok "Task 1: Ops Agent + Apache metrics/logging configuration"
ok "Task 2: URL uptime check -> $VM_EXTERNAL_IP"
ok "Task 3: Apache traffic alert > 3 KiB/s -> $ACCOUNT_EMAIL"
ok "Task 4: Dashboard -> CPU load (1m) + Apache Requests"
ok "Task 5: Log metric -> apache-access + textPayload:\"200\""

echo
printf '%s\n' "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════════════╗${RESET}" \
              "${GREEN}${BOLD}║                    LAB AUTOMATION COMPLETE                       ║${RESET}" \
              "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════════════╝${RESET}"
echo
warn "Monitoring data and grader checks can take a couple of minutes to propagate."
echo "Dashboard: https://console.cloud.google.com/monitoring/dashboards?project=$PROJECT_ID"
echo "Alerting : https://console.cloud.google.com/monitoring/alerting?project=$PROJECT_ID"
echo "Log metrics: https://console.cloud.google.com/logs/metrics?project=$PROJECT_ID"