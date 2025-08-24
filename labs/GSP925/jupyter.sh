# Minimal: auto-detect PROJECT_ID and bucket, then run the 3 lab commands

PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project -q 2>/dev/null | tr -d '\n')}"
if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  PROJECT_ID="$(curl -s -H 'Metadata-Flavor: Google' \
    http://metadata.google.internal/computeMetadata/v1/project/project-id)"
fi
LAB_BUCKET="gs://${PROJECT_ID}-labconfig-bucket"

echo "PROJECT_ID=$PROJECT_ID"
echo "LAB_BUCKET=$LAB_BUCKET"

# 1) Import notebooks
gsutil cp "${LAB_BUCKET}/notebooks/"*.ipynb .

# 2) Install required libraries
python -m pip install --upgrade google-cloud-core google-cloud-documentai google-cloud-storage prettytable

# 3) Download sample form
gsutil cp "${LAB_BUCKET}/health-intake-form.pdf" form.pdf
