# Configuring Vector Search in Spanner - GSP1288

## Overview

This Google Skills lab uses an existing Spanner instance and a Google-hosted embedding model to demonstrate semantic product search. The exercise creates a remote model, loads ten product records, generates vectors, and ranks available products by cosine distance. This guide is independently written from the publicly accessible task requirements.

### What you'll do

- Configure a remote embeddings model in a lab-provisioned Spanner database.
- Create a product schema and insert ten product records.
- Authorize the Spanner service agent to call the model and generate embeddings.
- Run a similarity query and verify the four graded checkpoints.

## Setup and requirements

### Before you click the Start Lab button

Open the [official GSP1288 lab](https://www.skills.google/focuses/119411). Use a private browsing window and sign in with the temporary lab account shown in the lab panel. Do not use your personal Google Cloud account, and do not publish the temporary username, password, project ID, or any access token. The lab is timed and resources are temporary.

The lab provides a Spanner instance named `cymbal-retail` and a GoogleSQL database named `cymbal-bicycles`. Wait for these resources to become ready. The model name and region must match your lab's current configuration.

### Activate Cloud Shell

Open Cloud Shell in the Google Cloud console, authorize it using the lab account, and confirm the active project:

```bash
gcloud config get-value project
gcloud spanner instances describe cymbal-retail --format='value(config)'
gcloud spanner databases describe cymbal-bicycles --instance=cymbal-retail
```

Set variables from your active project and lab configuration. The sample model identifier below can be overridden if the lab displays another value:

```bash
export PROJECT_ID="$(gcloud config get-value project)"
export INSTANCE=cymbal-retail
export DATABASE=cymbal-bicycles
export REGION="$(gcloud spanner instances describe "$INSTANCE" --format='value(config)' | sed -nE 's/.*regional-([a-z]+-[a-z0-9]+[0-9]).*/\1/p')"
export MODEL_ID="${MODEL_ID:-gemini-embedding-001}"
printf 'Project: %s | Region: %s | Model: %s\n' "$PROJECT_ID" "$REGION" "$MODEL_ID"
```

If the instance is multi-regional or the displayed region differs, set `REGION` to the lab-provided Agent Platform endpoint location. Do not guess the region.

## Task 1. Create an embeddings model in Spanner and configure it to an Agent Platform model endpoint

In the Google Cloud console, open Spanner, select the `cymbal-retail` instance and `cymbal-bicycles` database, then open Spanner Studio. Create a new SQL tab. The remote model passes text to the Google model and returns a vector and statistics.

From Cloud Shell, the equivalent DDL is:

```bash
gcloud spanner databases ddl update "$DATABASE" --instance="$INSTANCE" --project="$PROJECT_ID" --ddl="
CREATE MODEL EmbeddingsModel
INPUT(content STRING(MAX),)
OUTPUT(embeddings STRUCT<statistics STRUCT<truncated BOOL, token_count FLOAT32>, values ARRAY<FLOAT32>>,)
REMOTE OPTIONS(endpoint='//aiplatform.googleapis.com/projects/$PROJECT_ID/locations/$REGION/publishers/google/models/$MODEL_ID')"
```

Only create the model if it does not already exist; rerunning the same `CREATE MODEL` statement produces an already-exists error.

### Test completed task

Use the first Google Skills **Check my progress** checkpoint to verify creation of `EmbeddingsModel`. Check its DDL using:

```bash
gcloud spanner databases ddl describe "$DATABASE" --instance="$INSTANCE" --project="$PROJECT_ID"
```

## Task 2. Create a new table and load products data

Create the products table in Spanner Studio or with the CLI. The `ARRAY<FLOAT32>` column will hold the model output; the timestamp column allows commit timestamps.

```sql
CREATE TABLE products (
  categoryId INT64 NOT NULL,
  productId INT64 NOT NULL,
  productName STRING(MAX) NOT NULL,
  productDescription STRING(MAX) NOT NULL,
  productDescriptionEmbedding ARRAY<FLOAT32>,
  createTime TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp = true),
  inventoryCount INT64 NOT NULL,
  priceInCents INT64
) PRIMARY KEY(categoryId, productId);
```

To run this from Cloud Shell, save the DDL as `products.sql` and use `gcloud spanner databases ddl update "$DATABASE" --instance="$INSTANCE" --ddl-file=products.sql`.

Load ten bicycle-related products. The independently authored sample below uses the same ten product identities and inventory fields as the lab, with shorter original descriptions rather than reproducing copyrighted source prose. For exact reference data, consult the official lab. Execute in Spanner Studio:

```sql
INSERT INTO products (categoryId,productId,productName,productDescription,createTime,inventoryCount,priceInCents)
VALUES
(1,1,'Cymbal Helios Helmet','Adjustable youth helmet with vents and a comfortable protective fit.',PENDING_COMMIT_TIMESTAMP(),100,10999),
(1,2,'Cymbal Sprout','Small balance bicycle designed for toddlers aged two to four.',PENDING_COMMIT_TIMESTAMP(),10,13999),
(1,3,'Cymbal Spark Jr.','First pedal bicycle for young riders learning confident handling.',PENDING_COMMIT_TIMESTAMP(),34,13900),
(1,4,'Cymbal Summit','Mountain bicycle with suspension for rugged off road trails.',PENDING_COMMIT_TIMESTAMP(),0,79999),
(1,5,'Cymbal Breeze','Electric commuter bicycle with assisted pedaling and battery power.',PENDING_COMMIT_TIMESTAMP(),72,129999),
(1,6,'Cymbal Trailblazer Backpack','Weather resistant backpack for cycling tools and supplies.',PENDING_COMMIT_TIMESTAMP(),24,7999),
(1,7,'Cymbal Phoenix Lights','Front and rear bicycle lights for visibility after sunset.',PENDING_COMMIT_TIMESTAMP(),87,3999),
(1,8,'Cymbal Windstar Pump','Compact portable bicycle tire pump for quick inflation.',PENDING_COMMIT_TIMESTAMP(),36,24999),
(1,9,'Cymbal Odyssey Multi-Tool','Pocket tool kit with screwdrivers and bicycle repair keys.',PENDING_COMMIT_TIMESTAMP(),52,999),
(1,10,'Cymbal Nomad Water Bottle','Reusable leak resistant bottle for hydration on rides.',PENDING_COMMIT_TIMESTAMP(),42,1299);
```

Confirm the table contains ten rows:

```sql
SELECT COUNT(*) AS product_count FROM products WHERE categoryId=1;
```

### Test completed task

Use the second Google Skills checkpoint after the table and ten records exist. Do not insert duplicates on a rerun; the automated script uses per-product existence checks.

## Task 3. Generate and store text embeddings for the products data

Find the Google Cloud project number and grant the lab-specified **Cloud Spanner API Service Agent** role to the Spanner-managed service agent. This permission is specifically required for the model endpoint integration.

```bash
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
SPANNER_AGENT="service-${PROJECT_NUMBER}@gcp-sa-spanner.iam.gserviceaccount.com"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SPANNER_AGENT" \
  --role='roles/spanner.serviceAgent' --condition=None
```

After IAM propagation, run the following SQL in Spanner Studio:

```sql
UPDATE products p1
SET productDescriptionEmbedding = (
  SELECT embeddings.values FROM ML.PREDICT(
    MODEL EmbeddingsModel,
    (SELECT productDescription AS content FROM products p2 WHERE p2.productId=p1.productId)
  )
)
WHERE categoryId=1 AND productDescriptionEmbedding IS NULL;
```

Check for ten populated vectors:

```sql
SELECT COUNT(*) AS embedded_products
FROM products
WHERE categoryId=1 AND productDescriptionEmbedding IS NOT NULL;
```

If model invocation returns a permission error, wait briefly for IAM propagation and retry. Verify that the model ID and region are correct before changing permissions.

### Test completed task

Run the third Google Skills checkpoint after the product embeddings have been stored.

## Task 4. Perform vector search using text embeddings in Spanner

Generate an embedding for a search phrase and rank products by cosine distance. Filter out unavailable inventory and return the five closest matches:

```sql
SELECT productName, productDescription, inventoryCount,
  COSINE_DISTANCE(productDescriptionEmbedding, (
    SELECT embeddings.values
    FROM ML.PREDICT(MODEL EmbeddingsModel,
      (SELECT 'starter bicycle for a three year old child' AS content))
  )) AS distance
FROM products
WHERE inventoryCount > 0 AND productDescriptionEmbedding IS NOT NULL
ORDER BY distance
LIMIT 5;
```

Smaller distances indicate closer semantic similarity. The balance bicycle should be relevant to a toddler search, although the exact ranking may vary with the embedding model and sample descriptions.

### Test completed task

Run the fourth Google Skills checkpoint. The automated script performs a final count of total rows and non-null vectors, but cannot invoke the grader itself.

---

## Solution of Lab

### Quick

Run these two commands **only after the Draft PR has been merged into `main`**. Until then the main-branch URL may return 404.

```bash
curl -LO https://raw.githubusercontent.com/ePlus-DEV/storage/refs/heads/main/labs/GSP1288/lab.sh
source lab.sh
```

The script auto-detects the active project and Spanner region, honors `NO_COLOR` and `FORCE_COLOR=1`, checks for existing schema/data, and retries transient failures. Override `MODEL_ID` or `REGION` only when your lab configuration requires it.

### Manual

Chưa tìm thấy video YouTube hướng dẫn thủ công đã xác minh cho lab này.

The full manual task sequence and SQL commands are provided above; a video is optional and does not replace the lab instructions.

## Sources and verification

- [Official Google Skills GSP1288](https://www.skills.google/focuses/119411) — official task and checkpoint order.
- [Google Codelab: Getting started with Spanner Vector Search](https://codelabs.developers.google.com/spanner-getting-started-vector-search) — related technical background, not a substitute for the lab.
- [Spanner DML via gcloud](https://docs.cloud.google.com/spanner/docs/dml-tasks) and [Spanner DDL CLI](https://docs.cloud.google.com/sdk/gcloud/reference/spanner/databases/ddl/update).

Image assets from the Google Skills page have not been embedded because reuse and public hotlink permissions have not been verified. Consult the linked official page for original screenshots.

**Verification status:** static validated only; runtime/grader unverified. No Google Cloud lab credentials were used, and no grader result is claimed.
