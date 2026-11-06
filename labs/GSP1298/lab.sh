#!/usr/bin/env bash
# GSP1298 — Stream data with pipelines - Esports Use case
# Copyright (c) 2026 ePlus.DEV | Unlicense
# static validated only; runtime/grader unverified
set -Eeuo pipefail
umask 077
if [[ -n "${NO_COLOR+x}" ]]; then C='' G='' Y='' R='';
elif [[ -t 1 || "${FORCE_COLOR:-0}" == 1 ]]; then
  C=$'\033[36m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[0m'
else C='' G='' Y='' R=''; fi
info(){ printf '%s[INFO]%s %s\n' "$C" "$R" "$*"; }
ok(){ printf '%s[OK]%s %s\n' "$G" "$R" "$*"; }
warn(){ printf '%s[WARN]%s %s\n' "$Y" "$R" "$*" >&2; }
die(){ printf '[ERROR] %s\n' "$*" >&2; exit 1; }
trap 'warn "Stopped near line $LINENO; inspect errors. No grader PASS is implied."' ERR
printf '%sePlus.DEV – Starting Execution%s\n' "$C" "$R"
printf 'Copyright (c) 2026 ePlus.DEV | Unlicense\n'
for cmd in gcloud bq curl python3 jq; do command -v "$cmd" >/dev/null || die "Missing $cmd"; done
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != '(unset)' ]] || die 'Choose the temporary lab project.'
REGION="${REGION:-$(gcloud config get-value compute/region 2>/dev/null)}"
if [[ -z "$REGION" || "$REGION" == '(unset)' ]]; then
  ZONE="$(gcloud config get-value compute/zone 2>/dev/null)"
  [[ -n "$ZONE" && "$ZONE" != '(unset)' ]] || die 'Set REGION to the lab-assigned region.'
  REGION="${ZONE%-*}"
fi
[[ "$REGION" =~ ^[a-z]+-[a-z0-9]+[0-9]$ ]] || die 'Invalid region.'
BUCKET_NAME="${BUCKET_NAME:-${PROJECT_ID}-bucket}"
BUCKET_NAME="${BUCKET_NAME#gs://}"; BUCKET_NAME="${BUCKET_NAME%/}"
gcloud storage buckets describe "gs://$BUCKET_NAME" --project="$PROJECT_ID" >/dev/null ||
  die 'Expected pre-provisioned lab bucket is missing. Set BUCKET_NAME from the lab panel.'
WORKDIR="${WORKDIR:-$HOME/esports}"
mkdir -p "$WORKDIR"
info "Project=$PROJECT_ID Region=$REGION Bucket=gs://$BUCKET_NAME"
retry(){ local count="$1" delay="$2" n; shift 2
  for ((n=1;n<=count;n++)); do
    if "$@"; then return 0; fi
    if ((n<count)); then warn "Retry $n/$count"; sleep "$delay"; fi
  done; return 1; }

info 'Task 1: configure project, region, and existing lab bucket'
gcloud config get-value project >/dev/null
info 'Task 2: create Pub/Sub and BigQuery resources without duplicates'
gcloud services enable pubsub.googleapis.com bigquery.googleapis.com dataflow.googleapis.com --project="$PROJECT_ID" --quiet
gcloud pubsub topics describe esports_events_topic --project="$PROJECT_ID" >/dev/null 2>&1 ||
  gcloud pubsub topics create esports_events_topic --project="$PROJECT_ID"
gcloud pubsub subscriptions describe esports_events_topic-sub --project="$PROJECT_ID" >/dev/null 2>&1 ||
  gcloud pubsub subscriptions create esports_events_topic-sub --project="$PROJECT_ID" --topic=esports_events_topic
bq show --project_id="$PROJECT_ID" --format=none "$PROJECT_ID:esports_analytics" >/dev/null 2>&1 ||
  bq --project_id="$PROJECT_ID" --location=US mk --dataset esports_analytics
gcloud pubsub topics describe esports_events_topic --project="$PROJECT_ID" >/dev/null
gcloud pubsub subscriptions describe esports_events_topic-sub --project="$PROJECT_ID" >/dev/null
bq show --project_id="$PROJECT_ID" "$PROJECT_ID:esports_analytics" >/dev/null
ok 'Checkpoint: Create the cloud resources (30 points)'

info 'Task 3: fetch official Python source and configure all dynamic values'
for name in esports-simulation.py esports-pipeline.py; do
  if [[ ! -e "$WORKDIR/$name" ]]; then
    retry 3 5 curl -fL --retry 3 "https://storage.googleapis.com/spls/gsp1298/$name" \
      -o "$WORKDIR/$name" || die "Unable to retrieve official $name"
  fi
  [[ -s "$WORKDIR/$name" ]] || die "Empty $name"
done
python3 - "$WORKDIR" "$PROJECT_ID" "$REGION" "$BUCKET_NAME" <<'PY'
from pathlib import Path
import re
import sys
directory, project, region, bucket = sys.argv[1:]
for name in ("esports-simulation.py", "esports-pipeline.py"):
    path = Path(directory) / name
    text = path.read_text(encoding="utf-8")
    fields = {"PROJECT_ID": project}
    if name == "esports-pipeline.py":
        fields.update({"REGION": region, "GCS_TEMP_LOCATION": f"gs://{bucket}/temp"})
    for key, value in fields.items():
        pattern = rf"^{re.escape(key)}\s*=\s*.*$"
        text, count = re.subn(pattern, f"{key} = {value!r}", text, flags=re.MULTILINE)
        if count != 1:
            raise SystemExit(f"Expected exactly one {key} assignment in {name}, got {count}")
    path.write_text(text, encoding="utf-8")
PY
python3 -m py_compile "$WORKDIR/esports-simulation.py" "$WORKDIR/esports-pipeline.py"
gcloud storage cp "$WORKDIR/esports-simulation.py" "gs://$BUCKET_NAME/esports/esports-simulation.py" --quiet
gcloud storage cp "$WORKDIR/esports-pipeline.py" "gs://$BUCKET_NAME/esports/esports-pipeline.py" --quiet
gcloud storage objects describe "gs://$BUCKET_NAME/esports/esports-simulation.py" >/dev/null
gcloud storage objects describe "gs://$BUCKET_NAME/esports/esports-pipeline.py" >/dev/null
ok 'Checkpoint: Retrieve the Python files and configure them (20 points)'

info 'Task 4: install isolated dependencies and launch bounded background processes'
if [[ ! -x "$WORKDIR/df-env/bin/python" ]]; then python3 -m venv "$WORKDIR/df-env"; fi
retry 3 8 "$WORKDIR/df-env/bin/python" -m pip install --disable-pip-version-check \
  google-cloud-pubsub 'apache-beam[gcp]' ||
  die 'Unable to install required Python dependencies.'
if [[ -s "$WORKDIR/simulator.pid" ]] &&
   kill -0 "$(cat "$WORKDIR/simulator.pid")" 2>/dev/null; then
  info 'Existing simulator process is running.'
else
  nohup "$WORKDIR/df-env/bin/python" "$WORKDIR/esports-simulation.py" \
    > "$WORKDIR/simulator.log" 2>&1 < /dev/null &
  echo "$!" > "$WORKDIR/simulator.pid"
fi
sleep 10
kill -0 "$(cat "$WORKDIR/simulator.pid")" 2>/dev/null ||
  die 'Simulator exited unexpectedly; inspect simulator.log.'

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
[[ "$PROJECT_NUMBER" =~ ^[0-9]+$ ]] || die 'Could not discover project number.'
WORKER_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
DATAFLOW_AGENT="service-${PROJECT_NUMBER}@dataflow-service-producer-prod.iam.gserviceaccount.com"
gcloud beta services identity create --service=dataflow.googleapis.com --project="$PROJECT_ID" >/dev/null
# Grant the Dataflow service identity only the documented agent role.
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$DATAFLOW_AGENT" \
  --role=roles/dataflow.serviceAgent --condition=None --quiet >/dev/null
# Let the Dataflow service agent impersonate the pre-provisioned worker identity.
gcloud iam service-accounts add-iam-policy-binding "$WORKER_SA" \
  --project="$PROJECT_ID" --member="serviceAccount:$DATAFLOW_AGENT" \
  --role=roles/iam.serviceAccountUser --quiet >/dev/null
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$WORKER_SA" \
  --role=roles/dataflow.worker --condition=None --quiet >/dev/null

if [[ -s "$WORKDIR/pipeline.pid" ]] &&
   kill -0 "$(cat "$WORKDIR/pipeline.pid")" 2>/dev/null; then
  info 'Existing Dataflow launcher is running.'
elif gcloud dataflow jobs list --project="$PROJECT_ID" --region="$REGION" --format=json |
     jq -e '.[] | select((.name | startswith("esports-leaderboard")) and
       (.state == "Running" or .state == "JOB_STATE_RUNNING"))' >/dev/null; then
  info 'Existing esports Dataflow job is running.'
else
  nohup "$WORKDIR/df-env/bin/python" "$WORKDIR/esports-pipeline.py" \
    --project="$PROJECT_ID" --region="$REGION" --runner=DataflowRunner --streaming \
    --temp_location="gs://$BUCKET_NAME/temp" --job_name=esports-leaderboard-pipeline \
    --worker_machine_type=e2-standard-2 > "$WORKDIR/pipeline.log" 2>&1 < /dev/null &
  echo "$!" > "$WORKDIR/pipeline.pid"
fi
running=0
for ((i=1;i<=24;i++)); do
  if gcloud dataflow jobs list --project="$PROJECT_ID" --region="$REGION" --format=json |
     jq -e '.[] | select((.name | startswith("esports-leaderboard")) and
       (.state == "Running" or .state == "JOB_STATE_RUNNING"))' >/dev/null; then
    running=1; break
  fi
  sleep 15
done
(( running == 1 )) || die 'Dataflow job did not reach RUNNING in 6 minutes. Inspect pipeline.log.'
ok 'Checkpoint: Generate synthetic data and run the pipeline (30 points)'

info 'Task 5: wait for streaming tables, then create the two official leaderboard views'
ready=0
for ((i=1;i<=24;i++)); do
  if bq show "$PROJECT_ID:esports_analytics.player_score_updates" >/dev/null 2>&1 &&
     bq show "$PROJECT_ID:esports_analytics.team_score_updates" >/dev/null 2>&1; then
    ready=1; break
  fi
  sleep 15
done
(( ready == 1 )) || die 'Expected streaming score tables not ready; inspect Dataflow logs.'
bq query --project_id="$PROJECT_ID" --use_legacy_sql=false --format=none \
"CREATE OR REPLACE VIEW `$PROJECT_ID.esports_analytics.player_leaderboard_live` AS
 SELECT RANK() OVER (ORDER BY total_score DESC) AS rank, player_id, total_score, last_updated
 FROM (SELECT player_id, total_score, last_updated,
 ROW_NUMBER() OVER (PARTITION BY player_id ORDER BY last_updated DESC) AS rn
 FROM `$PROJECT_ID.esports_analytics.player_score_updates`) WHERE rn=1;"
bq query --project_id="$PROJECT_ID" --use_legacy_sql=false --format=none \
"CREATE OR REPLACE VIEW `$PROJECT_ID.esports_analytics.team_leaderboard_live` AS
 SELECT RANK() OVER (ORDER BY total_wins DESC) AS rank, team_id, total_wins, last_updated
 FROM (SELECT team_id, total_wins, last_updated,
 ROW_NUMBER() OVER (PARTITION BY team_id ORDER BY last_updated DESC) AS rn
 FROM `$PROJECT_ID.esports_analytics.team_score_updates`) WHERE rn=1;"
bq show "$PROJECT_ID:esports_analytics.player_leaderboard_live" >/dev/null
bq show "$PROJECT_ID:esports_analytics.team_leaderboard_live" >/dev/null
bq query --project_id="$PROJECT_ID" --use_legacy_sql=false \
  "SELECT * FROM `$PROJECT_ID.esports_analytics.player_leaderboard_live` ORDER BY rank LIMIT 10"
bq query --project_id="$PROJECT_ID" --use_legacy_sql=false \
  "SELECT * FROM `$PROJECT_ID.esports_analytics.team_leaderboard_live` ORDER BY rank LIMIT 10"
ok 'Checkpoint: Verify the results in BigQuery (20 points)'
info 'Streaming jobs remain running for the timed lab. Do not cancel before grader review.'
info 'static validated only; runtime/grader unverified'
