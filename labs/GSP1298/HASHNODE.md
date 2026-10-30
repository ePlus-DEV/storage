# Stream data with pipelines - Esports Use case - GSP1298

## Overview

In this Google Skills lab, a Python simulator publishes esports match events to Pub/Sub, Apache Beam processes them on Dataflow, and BigQuery stores raw events and player/team score updates. Two views select each competitor's latest score and rank the leaderboard.

The official lab contains **five Tasks and four checkpoints** (30/20/30/20 points). The [original architecture diagrams](https://www.skills.google/focuses/132337?parent=catalog) are linked, not copied, because reuse/embedding rights are unverified.

### What you'll do

- Identify the lab project, region, and existing Cloud Storage bucket.
- Create a Pub/Sub topic/subscription and BigQuery dataset.
- Retrieve and configure two official Python files.
- Run a synthetic event producer and Dataflow streaming job.
- Create and query live player/team leaderboard views.

## Setup and requirements

### Before you click the Start Lab button

Open [GSP1298 on Google Skills](https://www.skills.google/focuses/132337?parent=catalog). Start the timed lab only when ready, use a private browser, and sign in with the **temporary student account** from the lab panel. Do not use a personal project or publish student credentials.

The lab provisions a Cloud Storage bucket and assigns a region. Use the provided values, not guessed defaults. A streaming Dataflow job can incur usage outside the timed lab.

### Activate Cloud Shell

Activate Cloud Shell, authorize the lab account, and inspect the project, region, and bucket:

```bash
gcloud auth list
export PROJECT_ID="$(gcloud config get-value project)"
export REGION="$(gcloud config get-value compute/region)"
export BUCKET_NAME="${PROJECT_ID}-bucket"
printf 'Project=%s Region=%s Bucket=%s\n' "$PROJECT_ID" "$REGION" "$BUCKET_NAME"
gcloud storage buckets describe "gs://$BUCKET_NAME"
```

If the configured region is unset, use the region displayed in the lab panel. The bucket must already exist; do not create a substitute.

## Task 1. Configure environment variables in Cloud Shell

Keep `PROJECT_ID`, `REGION`, and `BUCKET_NAME` exported for all commands. New Cloud Shell tabs may require exporting them again.

```bash
echo "$PROJECT_ID"
echo "$REGION"
echo "$BUCKET_NAME"
gcloud config get-value project
```

## Task 2. Create the cloud resources

Create the exact Pub/Sub topic and subscription, and a BigQuery dataset in the `US` multiregion as specified by Google Skills:

```bash
gcloud services enable pubsub.googleapis.com bigquery.googleapis.com dataflow.googleapis.com
gcloud pubsub topics create esports_events_topic
gcloud pubsub subscriptions create esports_events_topic-sub --topic=esports_events_topic
bq --location=US mk --dataset esports_analytics
```

Check the resources before repeating any creation command:

```bash
gcloud pubsub topics describe esports_events_topic
gcloud pubsub subscriptions describe esports_events_topic-sub
bq show "$PROJECT_ID:esports_analytics"
```

### Test completed task

Click **Check my progress** for **Create the cloud resources** (30 points). Confirm the subscription belongs to the expected topic.

## Task 3. Retrieve the Python files and configure them

Download the two official source files, which are provided as public Google Cloud Storage objects. The simulator generates match-start, elimination and match-end messages; the pipeline reads them from Pub/Sub and writes BigQuery score tables.

```bash
mkdir -p "$HOME/esports"
cd "$HOME/esports"
curl -fL --retry 3 -o esports-simulation.py \
  https://storage.googleapis.com/spls/gsp1298/esports-simulation.py
curl -fL --retry 3 -o esports-pipeline.py \
  https://storage.googleapis.com/spls/gsp1298/esports-pipeline.py
```

Update the top-level `PROJECT_ID` assignments in both files and the `REGION` and `GCS_TEMP_LOCATION` assignments in the pipeline. This Python helper replaces only the expected assignments and fails if the upstream file structure differs:

```bash
python3 - "$HOME/esports" "$PROJECT_ID" "$REGION" "$BUCKET_NAME" <<'PY'
from pathlib import Path
import re
import sys
folder, project, region, bucket = sys.argv[1:]
for name in ("esports-simulation.py", "esports-pipeline.py"):
    path = Path(folder) / name
    source = path.read_text()
    fields = {"PROJECT_ID": project}
    if name == "esports-pipeline.py":
        fields.update({"REGION": region, "GCS_TEMP_LOCATION": f"gs://{bucket}/temp"})
    for key, value in fields.items():
        source, count = re.subn(
            rf"^{key}\s*=\s*.*$", f"{key} = {value!r}", source, flags=re.MULTILINE
        )
        if count != 1:
            raise SystemExit(f"Expected one {key} assignment in {name}, found {count}")
    path.write_text(source)
PY
python3 -m py_compile esports-simulation.py esports-pipeline.py
```

Upload the configured files into the lab bucket under the required `esports/` prefix:

```bash
gcloud storage cp esports-simulation.py "gs://$BUCKET_NAME/esports/"
gcloud storage cp esports-pipeline.py "gs://$BUCKET_NAME/esports/"
gcloud storage ls "gs://$BUCKET_NAME/esports/"
```

### Test completed task

Click **Check my progress** for **Retrieve the Python files and configure them** (20 points). These official Python files are runtime dependencies, not copied into the ePlus repository.

## Task 4. Generate synthetic data and run the pipeline

### Run the simulator

Create a Python virtual environment, install the required Pub/Sub and Beam packages, and start the simulator. It runs continuously; keep the terminal open.

```bash
cd "$HOME/esports"
python3 -m venv df-env
source df-env/bin/activate
python3 -m pip install google-cloud-pubsub 'apache-beam[gcp]'
python3 esports-simulation.py
```

In the Google Cloud console, inspect Pub/Sub → Subscriptions → `esports_events_topic-sub` for incoming messages.

### Set up Dataflow permissions

The official lab documents a potential Dataflow service-agent IAM error. First inspect the project and pre-provisioned worker identity:

```bash
export PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
export WORKER_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
export DATAFLOW_AGENT="service-${PROJECT_NUMBER}@dataflow-service-producer-prod.iam.gserviceaccount.com"
gcloud beta services identity create --service=dataflow.googleapis.com --project="$PROJECT_ID"
```

If permissions are missing, apply the scoped Dataflow roles in the authorized lab project:

```bash
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$DATAFLOW_AGENT" \
  --role=roles/dataflow.serviceAgent --condition=None
gcloud iam service-accounts add-iam-policy-binding "$WORKER_SA" \
  --member="serviceAccount:$DATAFLOW_AGENT" \
  --role=roles/iam.serviceAccountUser
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$WORKER_SA" \
  --role=roles/dataflow.worker --condition=None
```

A Cloud Storage **soft-delete warning** is described in the official lab. The automation does not disable bucket protection automatically; a warning alone is not a failure.

### Launch Dataflow

Open a second Cloud Shell tab, export the project, region, and bucket values again, activate the virtual environment, and submit the streaming job:

```bash
cd "$HOME/esports"
source df-env/bin/activate
python3 esports-pipeline.py \
  --project="$PROJECT_ID" --region="$REGION" \
  --runner=DataflowRunner --streaming \
  --temp_location="gs://$BUCKET_NAME/temp" \
  --job_name=esports-leaderboard-pipeline \
  --worker_machine_type=e2-standard-2
```

Inspect Dataflow → Jobs. Wait for a job whose name starts with `esports-leaderboard` to become **Running**. Check worker logs and the BigQuery tables `raw_events`, `player_score_updates`, and `team_score_updates`. Time-window aggregation can delay the score tables by several minutes.

### Test completed task

Click **Check my progress** for **Generate synthetic data and run the pipeline** (30 points). Keep the streaming job active until grading is finished.

## Task 5. Verify the results in BigQuery

Create the player leaderboard view, selecting each player's latest score before ranking:

```sql
CREATE OR REPLACE VIEW esports_analytics.player_leaderboard_live AS
SELECT RANK() OVER (ORDER BY total_score DESC) AS rank,
       player_id, total_score, last_updated
FROM (
  SELECT player_id, total_score, last_updated,
         ROW_NUMBER() OVER (PARTITION BY player_id ORDER BY last_updated DESC) AS rn
  FROM esports_analytics.player_score_updates
)
WHERE rn = 1;
```

Create the team leaderboard view in the same way:

```sql
CREATE OR REPLACE VIEW esports_analytics.team_leaderboard_live AS
SELECT RANK() OVER (ORDER BY total_wins DESC) AS rank,
       team_id, total_wins, last_updated
FROM (
  SELECT team_id, total_wins, last_updated,
         ROW_NUMBER() OVER (PARTITION BY team_id ORDER BY last_updated DESC) AS rn
  FROM esports_analytics.team_score_updates
)
WHERE rn = 1;
```

Query both views with BigQuery Studio or the CLI:

```bash
bq query --use_legacy_sql=false \
  'SELECT * FROM esports_analytics.player_leaderboard_live ORDER BY rank LIMIT 10'
bq query --use_legacy_sql=false \
  'SELECT * FROM esports_analytics.team_leaderboard_live ORDER BY rank LIMIT 10'
```

The leading player and team vary with the synthetic events. Do not hardcode the result.

### Test completed task

Click **Check my progress** for **Verify the results in BigQuery** (20 points). The checkpoints total 100 points; grader success is not asserted.

---

## Solution of Lab

### Quick

Run the following two commands in the **authorized temporary lab Cloud Shell**. The URL deliberately targets `main`; it will only work **after the Draft PR is merged**. The script leaves streaming jobs running for grading.

```bash
curl -LO https://raw.githubusercontent.com/ePlus-DEV/storage/refs/heads/main/labs/GSP1298/lab.sh
source lab.sh
```

The script discovers the project and region, uses the existing lab bucket, downloads and syntax-checks the official Python files, provisions the resources, launches the pipeline, and creates the views. It does not press Google Skills' grader buttons.

### Manual

Chưa tìm thấy video YouTube hướng dẫn thủ công đã xác minh cho lab này.

Follow Tasks 1–5 above or the [official lab](https://www.skills.google/focuses/132337?parent=catalog).

## Sources and verification status

- [Google Skills GSP1298 official lab](https://www.skills.google/focuses/132337?parent=catalog), last tested October 15, 2026.
- [Official simulator source](https://storage.googleapis.com/spls/gsp1298/esports-simulation.py).
- [Official Dataflow pipeline source](https://storage.googleapis.com/spls/gsp1298/esports-pipeline.py).
- [Dataflow security and permissions](https://cloud.google.com/dataflow/docs/concepts/security-and-permissions).
- [BigQuery views documentation](https://cloud.google.com/bigquery/docs/views-intro).

**static validated only; runtime/grader unverified.** The official Python source URLs were identified but not executed in an authorized lab. Python syntax is checked at runtime, while Bash/ShellCheck require latest-commit GitHub CI. IAM propagation, Dataflow worker readiness and streaming table creation vary by session. No private credentials are embedded. This Markdown is committed for review, not published to Hashnode.

Copyright (c) 2026 ePlus.DEV | Unlicense — original automation and explanatory prose.
