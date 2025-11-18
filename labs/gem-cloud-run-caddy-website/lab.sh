#!/bin/bash

# ===========================================================
#  ePlus.DEV
# ===========================================================
PROJECT_ID=$(gcloud projects list --format="value(projectId)" --limit=1)
REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
REPO_NAME="caddy-repo"
IMAGE_NAME="caddy-static"
IMAGE_URL="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO_NAME/$IMAGE_NAME:latest"
# ===========================================================

echo "=== Task 1 — Set up environment ==="
gcloud config set project $PROJECT_ID
gcloud config set run/region $REGION

gcloud services enable \
    run.googleapis.com \
    artifactregistry.googleapis.com \
    cloudbuild.googleapis.com

echo "=== Task 2 — Create Artifact Registry Repo ==="
gcloud artifacts repositories create $REPO_NAME \
    --repository-format=docker \
    --location=$REGION \
    --description="Docker repository for Caddy images"

echo "=== Task 3 — Create Static Website + Caddyfile ==="
cat > index.html << 'EOF'
<html>
<head>
  <title>My Static Website</title>
</head>
<body>
  <div>Hello from Caddy on Cloud Run!</div>
  <p>This website is served by Caddy running in a Docker container on Google Cloud Run.</p>
</body>
</html>
EOF

cat > Caddyfile << 'EOF'
:8080
root * /usr/share/caddy
file_server
EOF

echo "=== Task 4 — Create Dockerfile ==="
cat > Dockerfile << 'EOF'
FROM caddy:2-alpine

WORKDIR /usr/share/caddy

COPY index.html .
COPY Caddyfile /etc/caddy/Caddyfile
EOF

echo "=== Task 5 — Build + Push Image ==="
docker build -t $IMAGE_URL .
docker push $IMAGE_URL

echo "=== Task 6 — Deploy to Cloud Run ==="
gcloud run deploy $IMAGE_NAME \
    --image $IMAGE_URL \
    --platform managed \
    --allow-unauthenticated

echo "=== DONE — ePlus.DEV ==="
