#!/bin/bash
set -euo pipefail

YELLOW='\033[0;33m'; NC='\033[0m'
banner(){
  local pattern=(
  "**********************************************************"
  "**                 S U B S C R I B E  TO                **"
  "**                       ePlus.DEV                      **"
  "**                                                      **"
  "**********************************************************"
  )
  for line in "${pattern[@]}"; do echo -e "${YELLOW}${line}${NC}"; done
}

banner
: "${DEVSHELL_PROJECT_ID:?DEVSHELL_PROJECT_ID is not set}"

read -rp "ENTER YOUR ZONE: " ZONE
: "${ZONE:?Zone is required}"

PROJECT="$DEVSHELL_PROJECT_ID"
NAME="speaking-with-a-webpage"
TAG="dev-ports"
PORT="8443"

echo
echo "==> Ensuring firewall rule '$TAG' for tcp:$PORT exists (target-tag: $TAG)..."
if ! gcloud compute firewall-rules describe "$TAG" --project="$PROJECT" >/dev/null 2>&1; then
  gcloud compute firewall-rules create "$TAG" \
    --project="$PROJECT" \
    --allow="tcp:${PORT}" \
    --source-ranges="0.0.0.0/0" \
    --target-tags="$TAG" \
    --description="Allow dev port ${PORT}"
else
  echo "Firewall rule '$TAG' already exists."
fi

echo
echo "==> Creating VM (Debian 12 / Bookworm) to tránh lỗi bullseye-backports..."
gcloud compute instances create "$NAME" \
  --project="$PROJECT" \
  --zone="$ZONE" \
  --machine-type="e2-medium" \
  --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default \
  --metadata=enable-oslogin=true \
  --provisioning-model=STANDARD \
  --scopes=https://www.googleapis.com/auth/cloud-platform \
  --tags="$TAG" \
  --create-disk=auto-delete=yes,boot=yes,device-name="$NAME",\
image=projects/debian-cloud/global/images/family/debian-12,mode=rw,size=10,\
type="zones/${ZONE}/diskTypes/pd-balanced" \
  --no-shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring \
  --labels=goog-ec-src=vm_add-gcloud \
  --reservation-affinity=any

echo
echo "==> Installing dependencies & running Jetty on ${PORT}…"
gcloud compute ssh "$NAME" --zone "$ZONE" --project "$PROJECT" --quiet --command '
  set -euo pipefail
  sudo apt-get update
  # Debian 12: Java 17 là mặc định ổn định
  sudo apt-get install -y git maven default-jdk
  if [ ! -d "$HOME/speaking-with-a-webpage" ]; then
    git clone https://github.com/googlecodelabs/speaking-with-a-webpage.git
  fi
  cd "$HOME/speaking-with-a-webpage/01-hello-https"
  # chạy nền để giữ phiên ssh ngắn gọn
  nohup mvn -q clean jetty:run > "$HOME/jetty_${PORT}.log" 2>&1 &
  echo "App started. Log: ~/jetty_'${PORT}'.log"
'

echo
echo "==> VM external IP:"
gcloud compute instances describe "$NAME" --zone "$ZONE" --project "$PROJECT" \
  --format="get(networkInterfaces[0].accessConfigs[0].natIP)"

echo
banner
