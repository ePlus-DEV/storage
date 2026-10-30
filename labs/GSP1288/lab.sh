#!/usr/bin/env bash
# Copyright (c) 2026 ePlus.DEV | Unlicense
# GSP1288 - Configuring Vector Search in Spanner
# Static validation only; requires an authorized, active Google Skills lab.
set -Eeuo pipefail

if [[ -z "\${NO_COLOR:-}" ]] && { [[ -t 1 ]] || [[ "\${FORCE_COLOR:-0}" == "1" ]]; }; then
  GREEN=$'\033[0;32m'; CYAN=$'\033[0;36m'; YELLOW=$'\033[0;33m'; RED=$'\033[0;31m'; RESET=$'\033[0m'
else
  GREEN=''; CYAN=''; YELLOW=''; RED=''; RESET=''
fi
info() { printf '%s▶ %s%s\n' "$CYAN" "$*" "$RESET"; }
ok() { printf '%s✔ %s%s\n' "$GREEN" "$*" "$RESET"; }
warn() { printf '%s! %s%s\n' "$YELLOW" "$*" "$RESET" >&2; }
die() { printf '%s✖ %s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }
trap 'die "Stopped near line $LINENO. Inspect the preceding command."' ERR
printf '%s\n' "\${CYAN}ePlus.DEV – Starting Execution\${RESET}"
printf '%s\n' "Copyright (c) 2026 ePlus.DEV | Unlicense"
command -v gcloud >/dev/null || die 'Google Cloud CLI is required.'
command -v python3 >/dev/null || die 'Python 3 is required.'

PROJECT_ID="\${PROJECT_ID:-\${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null || true)}}"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != "(unset)" ]] || die 'No active project. Set PROJECT_ID.'
INSTANCE="\${INSTANCE:-cymbal-retail}"
DATABASE="\${DATABASE:-cymbal-bicycles}"
gcloud spanner instances describe "$INSTANCE" --project="$PROJECT_ID" --format='value(name)' >/dev/null ||
  die "Lab-provisioned Spanner instance $INSTANCE not found in $PROJECT_ID."
gcloud spanner databases describe "$DATABASE" --instance="$INSTANCE" --project="$PROJECT_ID" --format='value(name)' >/dev/null ||
  die "Lab-provisioned database $DATABASE not found."
CONFIG="$(gcloud spanner instances describe "$INSTANCE" --project="$PROJECT_ID" --format='value(config)' 2>/dev/null || true)"
SPANNER_REGION="$(printf '%s' "$CONFIG" | sed -nE 's/.*regional-([a-z]+-[a-z0-9]+[0-9]).*/\1/p')"
META_REGION="$(gcloud compute project-info describe --project="$PROJECT_ID" --format=json 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next((i.get("value","") for i in d.get("commonInstanceMetadata",{}).get("items",[]) if i.get("key")=="google-compute-default-region"),""))' 2>/dev/null || true)"
REGION="\${REGION:-\${META_REGION:-\${SPANNER_REGION:-$(gcloud config get-value compute/region 2>/dev/null || true)}}}"
[[ -n "$REGION" && "$REGION" != "(unset)" ]] || die 'Unable to determine region; set REGION from the lab details.'
MODEL_ID="\${MODEL_ID:-gemini-embedding-001}"
[[ "$MODEL_ID" =~ ^[a-zA-Z0-9._-]+$ ]] || die 'Invalid MODEL_ID.'
[[ "$REGION" =~ ^[a-z]+-[a-z0-9]+[0-9]$ ]] || die 'Invalid REGION.'
info "Project: $PROJECT_ID | Spanner: $INSTANCE/$DATABASE | Region: $REGION | Model: $MODEL_ID"

run_sql() {
  gcloud spanner databases execute-sql "$DATABASE" --instance="$INSTANCE" --project="$PROJECT_ID" --sql="$1"
}
run_ddl() {
  gcloud spanner databases ddl update "$DATABASE" --instance="$INSTANCE" --project="$PROJECT_ID" --ddl="$1" --quiet
}
retry() {
  local attempt
  for attempt in 1 2 3 4; do
    if "$@"; then return 0; fi
    if (( attempt == 4 )); then return 1; fi
    warn "Attempt $attempt failed; retrying in 12 seconds..."
    sleep 12
  done
}
ddl_contains() {
  gcloud spanner databases ddl describe "$DATABASE" --instance="$INSTANCE" --project="$PROJECT_ID" --format=json |
    grep -Eiq "$1"
}

info 'Task 1/4 — Create the remote embeddings model.'
if ddl_contains 'CREATE MODEL EmbeddingsModel'; then
  ok 'EmbeddingsModel already exists.'
else
  retry run_ddl "CREATE MODEL EmbeddingsModel INPUT(content STRING(MAX),) OUTPUT(embeddings STRUCT<statistics STRUCT<truncated BOOL, token_count FLOAT32>, values ARRAY<FLOAT32>>,) REMOTE OPTIONS(endpoint = '//aiplatform.googleapis.com/projects/$PROJECT_ID/locations/$REGION/publishers/google/models/$MODEL_ID')" ||
    die 'Failed to create EmbeddingsModel.'
fi

info 'Task 2/4 — Create the products table and load 10 original sample records.'
if ddl_contains 'CREATE TABLE products'; then
  ok 'Products table already exists.'
else
  retry run_ddl 'CREATE TABLE products (categoryId INT64 NOT NULL, productId INT64 NOT NULL, productName STRING(MAX) NOT NULL, productDescription STRING(MAX) NOT NULL, productDescriptionEmbedding ARRAY<FLOAT32>, createTime TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true), inventoryCount INT64 NOT NULL, priceInCents INT64) PRIMARY KEY(categoryId, productId)' ||
    die 'Failed to create products table.'
fi
# Independently written descriptions, not copied from the lab or codelab.
rows=(
  '1|Cymbal Helios Helmet|Adjustable youth helmet with vents and a comfortable protective fit.|100|10999'
  '2|Cymbal Sprout|Small balance bicycle designed for toddlers aged two to four.|10|13999'
  '3|Cymbal Spark Jr.|First pedal bicycle for young riders learning confident handling.|34|13900'
  '4|Cymbal Summit|Mountain bicycle with suspension for rugged off road trails.|0|79999'
  '5|Cymbal Breeze|Electric commuter bicycle with assisted pedaling and battery power.|72|129999'
  '6|Cymbal Trailblazer Backpack|Weather resistant backpack for cycling tools and supplies.|24|7999'
  '7|Cymbal Phoenix Lights|Front and rear bicycle lights for visibility after sunset.|87|3999'
  '8|Cymbal Windstar Pump|Compact portable bicycle tire pump for quick inflation.|36|24999'
  '9|Cymbal Odyssey Multi-Tool|Pocket tool kit with screwdrivers and bicycle repair keys.|52|999'
  '10|Cymbal Nomad Water Bottle|Reusable leak resistant bottle for hydration on rides.|42|1299'
)
for record in "\${rows[@]}"; do
  IFS='|' read -r product_id name description inventory price <<< "$record"
  sql="INSERT INTO products (categoryId,productId,productName,productDescription,createTime,inventoryCount,priceInCents) SELECT 1,$product_id,'$name','$description',PENDING_COMMIT_TIMESTAMP(),$inventory,$price WHERE NOT EXISTS (SELECT 1 FROM products WHERE categoryId=1 AND productId=$product_id)"
  retry run_sql "$sql" >/dev/null || die "Failed to load product $product_id."
done
ok '10 product keys inserted or already present.'

info 'Task 3/4 — Grant Spanner service-agent role and generate embeddings.'
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
[[ "$PROJECT_NUMBER" =~ ^[0-9]+$ ]] || die 'Could not resolve project number.'
SERVICE_AGENT="service-$PROJECT_NUMBER@gcp-sa-spanner.iam.gserviceaccount.com"
retry gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SERVICE_AGENT" --role='roles/spanner.serviceAgent' --condition=None --quiet >/dev/null ||
  die 'Cannot grant the documented Spanner service-agent role.'
retry run_sql 'UPDATE products p1 SET productDescriptionEmbedding = (SELECT embeddings.values FROM ML.PREDICT(MODEL EmbeddingsModel, (SELECT productDescription AS content FROM products p2 WHERE p2.productId=p1.productId))) WHERE categoryId=1 AND productDescriptionEmbedding IS NULL' ||
  die 'Embedding update failed; verify model ID, IAM propagation and region.'

info 'Task 4/4 — Run semantic similarity search.'
retry run_sql "SELECT productName,inventoryCount,COSINE_DISTANCE(productDescriptionEmbedding,(SELECT embeddings.values FROM ML.PREDICT(MODEL EmbeddingsModel,(SELECT 'starter bicycle for a three year old child' AS content)))) AS distance FROM products WHERE inventoryCount>0 AND productDescriptionEmbedding IS NOT NULL ORDER BY distance LIMIT 5" ||
  die 'Similarity query failed.'
info 'Read-back: check the number of products and non-null embeddings.'
run_sql 'SELECT COUNT(*) AS products,COUNTIF(productDescriptionEmbedding IS NOT NULL) AS embedded FROM products WHERE categoryId=1'
ok 'Finished SQL workflow. Check each Google Skills grader checkpoint manually.'
warn 'static validated only; runtime/grader unverified.'
