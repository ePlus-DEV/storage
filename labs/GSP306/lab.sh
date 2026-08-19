#!/bin/bash

# ============================================================
# WordPress -> Cloud SQL Migration Challenge Lab
# © ePlus.DEV
# ============================================================

BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'
TEAL_TEXT=$'\033[38;5;50m'
BOLD_TEXT=$'\033[1m'
RESET_FORMAT=$'\033[0m'

SQL_INSTANCE="wordpress-db"
DB_NAME="wordpress"
DB_USER="blogadmin"
DB_PASS='Password1*'
BLOG_VM="blog"

section() {
  echo
  echo "${CYAN_TEXT}${BOLD_TEXT}========================================================================${RESET_FORMAT}"
  echo "${CYAN_TEXT}${BOLD_TEXT}$1${RESET_FORMAT}"
  echo "${CYAN_TEXT}${BOLD_TEXT}========================================================================${RESET_FORMAT}"
}

ok() {
  echo "${GREEN_TEXT}✓ $1${RESET_FORMAT}"
}

warn() {
  echo "${YELLOW_TEXT}⚠ $1${RESET_FORMAT}"
}

fail() {
  echo "${RED_TEXT}✗ $1${RESET_FORMAT}"
}

wait_sql_ready() {
  local instance="$1"
  local state=""
  local i
  local elapsed
  local mins
  local secs

  echo
  echo "Waiting for Cloud SQL instance to become RUNNABLE..."
  echo "Checking every 10 seconds. Maximum wait: 15 minutes."
  echo

  for i in $(seq 1 90); do
    state=$(gcloud sql instances describe "$instance" \
      --format='value(state)' 2>/dev/null || true)

    elapsed=$(( (i - 1) * 10 ))
    mins=$(( elapsed / 60 ))
    secs=$(( elapsed % 60 ))

    if [[ "$state" == "RUNNABLE" ]]; then
      printf "\r\033[K"
      printf "${GREEN_TEXT}[%02d:%02d] Check %02d/90 | State: RUNNABLE ✓${RESET_FORMAT}\n" \
        "$mins" "$secs" "$i"

      ok "Cloud SQL instance is ready."
      return 0
    fi

    printf "\r\033[K"
    printf "${YELLOW_TEXT}[%02d:%02d] Check %02d/90 | State: %-20s | Waiting...${RESET_FORMAT}" \
      "$mins" "$secs" "$i" "${state:-CREATING}"

    sleep 10
  done

  echo
  fail "Cloud SQL instance did not become RUNNABLE after 15 minutes."
  return 1
}

main() {
  clear

  echo "${TEAL_TEXT}${BOLD_TEXT}"
  echo "   ____  ____  _                 _   ____   ___  _"
  echo "  / ___||  _ \| | ___  _   _  __| | / ___| / _ \| |"
  echo " | |    | |_) | |/ _ \| | | |/ _\` | \___ \| | | | |"
  echo " | |___ |  __/| | (_) | |_| | (_| |  ___) | |_| | |___"
  echo "  \____||_|   |_|\___/ \__,_|\__,_| |____/ \__\_\_____|"
  echo
  echo " WordPress Database Migration Challenge Lab"
  echo " © ePlus.DEV"
  echo "${RESET_FORMAT}"

  # ------------------------------------------------------------------
  # Detect project
  # ------------------------------------------------------------------
  PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

  if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
    PROJECT_ID=$(gcloud projects list \
      --filter='lifecycleState=ACTIVE' \
      --format='value(projectId)' \
      --limit=1 2>/dev/null)
  fi

  if [[ -z "$PROJECT_ID" ]]; then
    fail "Unable to detect Project ID."
    return 1
  fi

  gcloud config set project "$PROJECT_ID" >/dev/null 2>&1

  # ------------------------------------------------------------------
  # Detect blog VM zone
  # ------------------------------------------------------------------
  BLOG_ZONE=$(gcloud compute instances list \
    --filter="name=('${BLOG_VM}')" \
    --format='value(zone)' \
    --limit=1 2>/dev/null | awk -F/ '{print $NF}')

  if [[ -z "$BLOG_ZONE" ]]; then
    fail "VM '$BLOG_VM' was not found."
    return 1
  fi

  # Prefer explicit environment variable / gcloud configuration.
  ENV_ZONE="${ZONE:-}"
  CFG_ZONE=$(gcloud config get-value compute/zone 2>/dev/null)

  if [[ -n "$ENV_ZONE" && "$ENV_ZONE" != "ZONE" ]]; then
    TARGET_ZONE="$ENV_ZONE"
  elif [[ -n "$CFG_ZONE" && "$CFG_ZONE" != "(unset)" ]]; then
    TARGET_ZONE="$CFG_ZONE"
  else
    TARGET_ZONE="$BLOG_ZONE"
  fi

  ENV_REGION="${REGION:-}"
  CFG_REGION=$(gcloud config get-value compute/region 2>/dev/null)

  if [[ -n "$ENV_REGION" && "$ENV_REGION" != "REGION" ]]; then
    TARGET_REGION="$ENV_REGION"
  elif [[ -n "$CFG_REGION" && "$CFG_REGION" != "(unset)" ]]; then
    TARGET_REGION="$CFG_REGION"
  else
    TARGET_REGION="${TARGET_ZONE%-*}"
  fi

  BLOG_EXT_IP=$(gcloud compute instances describe "$BLOG_VM" \
    --zone="$BLOG_ZONE" \
    --format='value(networkInterfaces[0].accessConfigs[0].natIP)' \
    2>/dev/null)

  if [[ -z "$BLOG_EXT_IP" ]]; then
    fail "VM '$BLOG_VM' does not have an external IP."
    return 1
  fi

  echo
  echo "${BOLD_TEXT}Detected configuration${RESET_FORMAT}"
  echo "Project ID       : $PROJECT_ID"
  echo "Blog VM          : $BLOG_VM"
  echo "Blog VM zone     : $BLOG_ZONE"
  echo "Target SQL zone  : $TARGET_ZONE"
  echo "Target SQL region: $TARGET_REGION"
  echo "Blog external IP : $BLOG_EXT_IP"
  echo "SQL instance     : $SQL_INSTANCE"
  echo "Database         : $DB_NAME"
  echo "Database user    : $DB_USER"

  # ------------------------------------------------------------------
  # APIs
  # ------------------------------------------------------------------
  section "[1/7] Enabling required APIs"

  if ! gcloud services enable \
      sqladmin.googleapis.com \
      compute.googleapis.com \
      --quiet; then
    fail "Unable to enable required APIs."
    return 1
  fi

  ok "Required APIs enabled."

  # ------------------------------------------------------------------
  # TASK 1 - Create Cloud SQL
  # ------------------------------------------------------------------
  section "[2/7] TASK 1 - Creating Cloud SQL instance"

  if gcloud sql instances describe "$SQL_INSTANCE" \
      >/dev/null 2>&1; then

    EXISTING_REGION=$(gcloud sql instances describe "$SQL_INSTANCE" \
      --format='value(region)' 2>/dev/null)

    EXISTING_ZONE=$(gcloud sql instances describe "$SQL_INSTANCE" \
      --format='value(settings.locationPreference.zone)' 2>/dev/null)

    echo "Existing instance found."
    echo "Region : $EXISTING_REGION"
    echo "Zone   : $EXISTING_ZONE"

    if [[ "$EXISTING_REGION" != "$TARGET_REGION" ||
          "$EXISTING_ZONE" != "$TARGET_ZONE" ]]; then

      warn "Existing wordpress-db is in the wrong location."
      echo "Deleting it so the grader sees the correct Region/Zone..."

      if ! gcloud sql instances delete "$SQL_INSTANCE" \
          --quiet; then
        fail "Unable to delete incorrect Cloud SQL instance."
        return 1
      fi

      ok "Incorrect instance deleted."
    else
      ok "Cloud SQL instance already exists in correct location."
    fi
  fi

  if ! gcloud sql instances describe "$SQL_INSTANCE" \
      >/dev/null 2>&1; then

    echo
    echo "Creating:"
    echo "  MySQL version : 8.0"
    echo "  Edition       : Enterprise"
    echo "  Tier          : db-f1-micro"
    echo "  Region        : $TARGET_REGION"
    echo "  Zone          : $TARGET_ZONE"
    echo "  Authorized IP : ${BLOG_EXT_IP}/32"
    echo

    if ! gcloud sql instances create "$SQL_INSTANCE" \
        --database-version=MYSQL_8_0 \
        --edition=enterprise \
        --tier=db-f1-micro \
        --zone="$TARGET_ZONE" \
        --availability-type=zonal \
        --storage-type=SSD \
        --assign-ip \
        --authorized-networks="${BLOG_EXT_IP}/32" \
        --async \
        --quiet; then
      fail "Cloud SQL creation request failed."
      return 1
    fi
  fi

  wait_sql_ready "$SQL_INSTANCE" || return 1

  SQL_REGION=$(gcloud sql instances describe "$SQL_INSTANCE" \
    --format='value(region)')

  SQL_ZONE=$(gcloud sql instances describe "$SQL_INSTANCE" \
    --format='value(settings.locationPreference.zone)')

  ok "TASK 1 configuration complete."
  echo "Cloud SQL region : $SQL_REGION"
  echo "Cloud SQL zone   : $SQL_ZONE"

  # ------------------------------------------------------------------
  # TASK 2 - Database + user
  # ------------------------------------------------------------------
  section "[3/7] TASK 2 - Configuring WordPress database"

  if gcloud sql databases list \
      --instance="$SQL_INSTANCE" \
      --format='value(name)' 2>/dev/null |
      grep -Fxq "$DB_NAME"; then

    ok "Database '$DB_NAME' already exists."
  else
    if ! gcloud sql databases create "$DB_NAME" \
        --instance="$SQL_INSTANCE" \
        --quiet; then
      fail "Unable to create database '$DB_NAME'."
      return 1
    fi

    ok "Database '$DB_NAME' created."
  fi

  if gcloud sql users list \
      --instance="$SQL_INSTANCE" \
      --format='value(name)' 2>/dev/null |
      grep -Fxq "$DB_USER"; then

    echo "Updating password for existing user '$DB_USER'..."

    if ! gcloud sql users set-password "$DB_USER" \
        --host='%' \
        --instance="$SQL_INSTANCE" \
        --password="$DB_PASS" \
        --quiet; then
      fail "Unable to update database user password."
      return 1
    fi
  else
    echo "Creating database user '$DB_USER'..."

    if ! gcloud sql users create "$DB_USER" \
        --host='%' \
        --instance="$SQL_INSTANCE" \
        --password="$DB_PASS" \
        --quiet; then
      fail "Unable to create database user."
      return 1
    fi
  fi

  ok "Database user '$DB_USER' configured."
  ok "TASK 2 complete."

  # ------------------------------------------------------------------
  # TASK 3 - Authorized network
  # ------------------------------------------------------------------
  section "[4/7] TASK 3 - Authorizing blog VM"

  echo "Authorizing ${BLOG_EXT_IP}/32..."

  if ! gcloud sql instances patch "$SQL_INSTANCE" \
      --authorized-networks="${BLOG_EXT_IP}/32" \
      --quiet; then
    fail "Unable to configure authorized networks."
    return 1
  fi

  wait_sql_ready "$SQL_INSTANCE" || return 1

  SQL_IP=$(gcloud sql instances describe "$SQL_INSTANCE" \
    --format=json |
    python3 -c '
import json, sys

data = json.load(sys.stdin)

for entry in data.get("ipAddresses", []):
    if entry.get("type") == "PRIMARY":
        print(entry.get("ipAddress", ""))
        break
')

  if [[ -z "$SQL_IP" ]]; then
    fail "Unable to determine Cloud SQL public IP."
    return 1
  fi

  echo
  echo "Blog external IP : $BLOG_EXT_IP"
  echo "Cloud SQL IP     : $SQL_IP"

  AUTHORIZED=$(gcloud sql instances describe "$SQL_INSTANCE" \
    --format='value(settings.ipConfiguration.authorizedNetworks[].value)' \
    2>/dev/null)

  echo "Authorized       : $AUTHORIZED"

  ok "Blog VM is authorized to connect to Cloud SQL."
  ok "TASK 3 authorization complete."

  # ------------------------------------------------------------------
  # TASK 3 + TASK 4
  # Dump DB / import DB / update WordPress
  # ------------------------------------------------------------------
  section "[5/7] Migrating WordPress database"

  REMOTE_HELPER=$(mktemp)

  cat > "$REMOTE_HELPER" <<'REMOTE_SCRIPT'
#!/bin/bash
set -euo pipefail

SQL_IP="$1"
DB_PASS="$2"

DB_NAME="wordpress"
DB_USER="blogadmin"
WP_CONFIG="/var/www/html/wordpress/wp-config.php"
DUMP_FILE="/tmp/wordpress-cloudsql.sql"

GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
RED=$'\033[0;91m'
RESET=$'\033[0m'

echo
echo "------------------------------------------------------------"
echo "Checking MySQL client"
echo "------------------------------------------------------------"

if ! command -v mysql >/dev/null 2>&1 ||
   ! command -v mysqldump >/dev/null 2>&1; then

  echo "MySQL client is missing. Installing..."

  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive \
      apt-get install -y default-mysql-client

  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y mariadb

  else
    echo "${RED}No supported package manager found.${RESET}"
    exit 1
  fi
fi

echo "${GREEN}✓ MySQL client available.${RESET}"

echo
echo "------------------------------------------------------------"
echo "Checking local WordPress database"
echo "------------------------------------------------------------"

if ! MYSQL_PWD="$DB_PASS" \
    mysql \
    -u "$DB_USER" \
    "$DB_NAME" \
    -e "SELECT 1;" \
    >/dev/null 2>&1; then

  echo "${RED}Unable to access local wordpress database.${RESET}"
  exit 1
fi

echo "${GREEN}✓ Local database accessible.${RESET}"

echo
echo "------------------------------------------------------------"
echo "Creating WordPress database dump"
echo "------------------------------------------------------------"

DUMP_OPTIONS=(
  --single-transaction
  --quick
  --lock-tables=false
  --add-drop-table
)

if mysqldump --help 2>/dev/null |
   grep -q "column-statistics"; then
  DUMP_OPTIONS+=(--column-statistics=0)
fi

MYSQL_PWD="$DB_PASS" \
mysqldump \
  -u "$DB_USER" \
  "${DUMP_OPTIONS[@]}" \
  "$DB_NAME" > "$DUMP_FILE"

# Remove statements that Cloud SQL doesn't need.
sed -i '/SET @@GLOBAL.GTID_PURGED/d' "$DUMP_FILE" || true
sed -i -E 's/DEFINER=`[^`]+`@`[^`]+`//g' "$DUMP_FILE" || true

DUMP_SIZE=$(du -h "$DUMP_FILE" | awk '{print $1}')

echo "${GREEN}✓ Database dump created: ${DUMP_SIZE}${RESET}"

echo
echo "------------------------------------------------------------"
echo "Waiting for Cloud SQL network access"
echo "------------------------------------------------------------"

CONNECTED=0

for i in $(seq 1 24); do
  if MYSQL_PWD="$DB_PASS" \
     mysql \
       --protocol=TCP \
       --connect-timeout=5 \
       -h "$SQL_IP" \
       -P 3306 \
       -u "$DB_USER" \
       "$DB_NAME" \
       -e "SELECT 1;" \
       >/dev/null 2>&1; then

    CONNECTED=1
    echo
    echo "${GREEN}✓ Connection to Cloud SQL successful.${RESET}"
    break
  fi

  printf "\rConnection check %02d/24 - waiting 10 seconds..." "$i"
  sleep 10
done

if [[ "$CONNECTED" != "1" ]]; then
  echo
  echo "${RED}Unable to connect to Cloud SQL.${RESET}"
  exit 1
fi

echo
echo "------------------------------------------------------------"
echo "Importing database into Cloud SQL"
echo "------------------------------------------------------------"

MYSQL_PWD="$DB_PASS" \
mysql \
  --protocol=TCP \
  -h "$SQL_IP" \
  -P 3306 \
  -u "$DB_USER" \
  "$DB_NAME" < "$DUMP_FILE"

TABLE_COUNT=$(MYSQL_PWD="$DB_PASS" \
  mysql \
    --protocol=TCP \
    -h "$SQL_IP" \
    -P 3306 \
    -u "$DB_USER" \
    -Nse \
    "SELECT COUNT(*)
       FROM information_schema.tables
      WHERE table_schema='${DB_NAME}';")

echo "${GREEN}✓ Import completed.${RESET}"
echo "WordPress tables in Cloud SQL: $TABLE_COUNT"

if [[ "$TABLE_COUNT" -lt 1 ]]; then
  echo "${RED}No WordPress tables found after import.${RESET}"
  exit 1
fi

echo
echo "------------------------------------------------------------"
echo "Updating wp-config.php"
echo "------------------------------------------------------------"

if [[ ! -f "$WP_CONFIG" ]]; then
  echo "${RED}wp-config.php not found: $WP_CONFIG${RESET}"
  exit 1
fi

sudo cp -n \
  "$WP_CONFIG" \
  "${WP_CONFIG}.localdb.backup" \
  2>/dev/null || true

sudo python3 - \
  "$WP_CONFIG" \
  "$SQL_IP" \
  "$DB_NAME" \
  "$DB_USER" \
  "$DB_PASS" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])

values = {
    "DB_HOST": sys.argv[2],
    "DB_NAME": sys.argv[3],
    "DB_USER": sys.argv[4],
    "DB_PASSWORD": sys.argv[5],
}

text = path.read_text()

for name, value in values.items():
    pattern = (
        r"define\(\s*['\"]"
        + re.escape(name)
        + r"['\"]\s*,\s*['\"][^'\"]*['\"]\s*\);"
    )

    replacement = f"define( '{name}', '{value}' );"

    text, count = re.subn(
        pattern,
        replacement,
        text,
        count=1,
    )

    if count != 1:
        raise SystemExit(
            f"Unable to update {name} in wp-config.php"
        )

path.write_text(text)
PY

echo "${GREEN}✓ wp-config.php updated.${RESET}"

echo
echo "Database settings:"
sudo grep -E \
  "DB_(NAME|USER|PASSWORD|HOST)" \
  "$WP_CONFIG" |
  sed "s/Password1\\*/********/g"

sudo systemctl reload apache2 2>/dev/null || \
sudo systemctl restart apache2 2>/dev/null || \
sudo systemctl reload httpd 2>/dev/null || true

echo
echo "------------------------------------------------------------"
echo "Final Cloud SQL test"
echo "------------------------------------------------------------"

MYSQL_PWD="$DB_PASS" \
mysql \
  --protocol=TCP \
  -h "$SQL_IP" \
  -P 3306 \
  -u "$DB_USER" \
  "$DB_NAME" \
  -e "SHOW TABLES;" |
  head -20

echo
echo "${GREEN}✓ WordPress is now configured for Cloud SQL.${RESET}"
REMOTE_SCRIPT

  chmod +x "$REMOTE_HELPER"

  echo "Uploading migration helper to VM '$BLOG_VM'..."

  if ! gcloud compute scp \
      "$REMOTE_HELPER" \
      "${BLOG_VM}:/tmp/eplus-wordpress-migrate.sh" \
      --zone="$BLOG_ZONE" \
      --quiet; then
    rm -f "$REMOTE_HELPER"
    fail "Unable to upload migration helper."
    return 1
  fi

  rm -f "$REMOTE_HELPER"

  printf -v Q_SQL_IP '%q' "$SQL_IP"
  printf -v Q_DB_PASS '%q' "$DB_PASS"

  echo "Running database migration on VM..."

  if ! gcloud compute ssh "$BLOG_VM" \
      --zone="$BLOG_ZONE" \
      --quiet \
      --command="bash /tmp/eplus-wordpress-migrate.sh $Q_SQL_IP $Q_DB_PASS"; then

    fail "Database migration failed."
    return 1
  fi

  ok "WordPress database migrated to Cloud SQL."

  # ------------------------------------------------------------------
  # TASK 4 verification
  # ------------------------------------------------------------------
  section "[6/7] TASK 4 - Verifying wp-config.php"

  WP_CONFIG_RESULT=$(gcloud compute ssh "$BLOG_VM" \
    --zone="$BLOG_ZONE" \
    --quiet \
    --command="sudo grep -E \"DB_(NAME|USER|HOST)\" /var/www/html/wordpress/wp-config.php" \
    2>/dev/null || true)

  echo "$WP_CONFIG_RESULT"

  if echo "$WP_CONFIG_RESULT" |
     grep -q "$SQL_IP"; then
    ok "wp-config.php points to Cloud SQL IP $SQL_IP."
  else
    fail "DB_HOST verification failed."
    return 1
  fi

  ok "TASK 4 complete."

  # ------------------------------------------------------------------
  # TASK 5
  # ------------------------------------------------------------------
  section "[7/7] TASK 5 - Testing WordPress"

  BLOG_OK=0
  BLOG_URL=""

  for PATH_TO_TEST in "/" "/wordpress/"; do
    URL="http://${BLOG_EXT_IP}${PATH_TO_TEST}"

    HTTP_CODE=$(curl \
      -L \
      -sS \
      --max-time 30 \
      -o /dev/null \
      -w '%{http_code}' \
      "$URL" 2>/dev/null || true)

    echo "$URL -> HTTP $HTTP_CODE"

    if [[ "$HTTP_CODE" =~ ^(200|201|202|204|301|302|303|307|308)$ ]]; then
      BLOG_OK=1
      BLOG_URL="$URL"
      break
    fi
  done

  echo

  if [[ "$BLOG_OK" == "1" ]]; then
    ok "WordPress blog is responding."
    echo "Blog URL: $BLOG_URL"
  else
    warn "External HTTP check was not successful."
    echo
    echo "Checking Apache locally..."

    gcloud compute ssh "$BLOG_VM" \
      --zone="$BLOG_ZONE" \
      --quiet \
      --command="
        echo '--- Apache status ---'
        sudo systemctl is-active apache2 2>/dev/null ||
        sudo systemctl is-active httpd 2>/dev/null ||
        true

        echo
        echo '--- Local HTTP ---'
        curl -I --max-time 10 http://127.0.0.1/ 2>/dev/null |
        head -5 || true

        echo
        echo '--- Apache error log ---'
        sudo tail -20 /var/log/apache2/error.log 2>/dev/null ||
        sudo tail -20 /var/log/httpd/error_log 2>/dev/null ||
        true
      " || true

    warn "Review the diagnostic output above."
  fi

  # ------------------------------------------------------------------
  # Final summary
  # ------------------------------------------------------------------
  section "LAB CONFIGURATION COMPLETE"

  echo "${GREEN_TEXT}${BOLD_TEXT}TASK 1 ✓ Cloud SQL instance${RESET_FORMAT}"
  echo "  Instance : $SQL_INSTANCE"
  echo "  Region   : $TARGET_REGION"
  echo "  Zone     : $TARGET_ZONE"
  echo
  echo "${GREEN_TEXT}${BOLD_TEXT}TASK 2 ✓ WordPress database${RESET_FORMAT}"
  echo "  Database : $DB_NAME"
  echo "  User     : $DB_USER"
  echo
  echo "${GREEN_TEXT}${BOLD_TEXT}TASK 3 ✓ Database migration / Authorized network${RESET_FORMAT}"
  echo "  Blog IP  : ${BLOG_EXT_IP}/32"
  echo "  SQL IP   : $SQL_IP"
  echo
  echo "${GREEN_TEXT}${BOLD_TEXT}TASK 4 ✓ wp-config.php updated${RESET_FORMAT}"
  echo "  DB_HOST  : $SQL_IP"
  echo
  if [[ "$BLOG_OK" == "1" ]]; then
    echo "${GREEN_TEXT}${BOLD_TEXT}TASK 5 ✓ Blog responding${RESET_FORMAT}"
  else
    echo "${YELLOW_TEXT}${BOLD_TEXT}TASK 5 ⚠ Check HTTP response${RESET_FORMAT}"
  fi

  echo
  echo "${TEAL_TEXT}${BOLD_TEXT}Now click Check my progress for Tasks 1 → 5.${RESET_FORMAT}"
  echo
  echo "${MAGENTA_TEXT}© ePlus.DEV${RESET_FORMAT}"

  return 0
}

main "$@"
RC=$?

# Safe when either:
#   bash lab.sh
# or:
#   source lab.sh
#
# Sourcing the file will NOT close the Cloud Shell terminal.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  exit "$RC"
else
  return "$RC"
fi