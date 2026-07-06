# Project
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

# Zone
ZONE=$(gcloud config get-value compute/zone 2>/dev/null)
ZONE=${ZONE##*/}

# Region
REGION=$(gcloud config get-value compute/region 2>/dev/null)

# Nếu chưa có region nhưng có zone
if [[ -z "$REGION" && -n "$ZONE" ]]; then
    REGION="${ZONE%-*}"
fi

# Nếu vẫn chưa có thì hỏi người dùng
if [[ -z "$ZONE" ]]; then
    read -rp "Enter Zone (e.g. europe-west4-b): " ZONE
    REGION="${ZONE%-*}"
fi

export ZONE REGION

echo "PROJECT_ID=$PROJECT_ID"
echo "PROJECT_NUMBER=$PROJECT_NUMBER"
echo "ZONE=$ZONE"
echo "REGION=$REGION"

gcloud config set compute/region $REGION
gcloud config set compute/zone $ZONE

gcloud services enable cloudkms.googleapis.com cloudbuild.googleapis.com container.googleapis.com containerregistry.googleapis.com artifactregistry.googleapis.com containerscanning.googleapis.com ondemandscanning.googleapis.com binaryauthorization.googleapis.com

gcloud artifacts repositories create artifact-scanning-repo \
  --repository-format=docker \
  --location=$REGION \
  --description="Docker repository"

gcloud auth configure-docker ${REGION}-docker.pkg.dev -q

mkdir -p vuln-scan
cd vuln-scan

cat > Dockerfile <<'EOF'
FROM python:3.8-alpine
WORKDIR /app
COPY . ./
RUN pip3 install Flask==2.1.0
RUN pip3 install gunicorn==20.1.0
RUN pip3 install Werkzeug==2.2.2
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 main:app
EOF

cat > main.py <<'EOF'
import os
from flask import Flask

app = Flask(__name__)

@app.route("/")
def hello_world():
    name = os.environ.get("NAME", "Worlds")
    return "Hello {}!".format(name)

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
EOF

gcloud builds submit . -t ${REGION}-docker.pkg.dev/${PROJECT_ID}/artifact-scanning-repo/sample-image

cat > vulnz_note.json <<EOF
{
  "attestation": {
    "hint": {
      "human_readable_name": "Container Vulnerabilities attestation authority"
    }
  }
}
EOF

NOTE_ID=vulnz_note

curl -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  --data-binary @vulnz_note.json \
  "https://containeranalysis.googleapis.com/v1/projects/${PROJECT_ID}/notes/?noteId=${NOTE_ID}"

ATTESTOR_ID=vulnz-attestor

gcloud container binauthz attestors create $ATTESTOR_ID \
  --attestation-authority-note=$NOTE_ID \
  --attestation-authority-note-project=${PROJECT_ID}

BINAUTHZ_SA_EMAIL="service-${PROJECT_NUMBER}@gcp-sa-binaryauthorization.iam.gserviceaccount.com"

cat > iam_request.json <<EOF
{
  "resource": "projects/${PROJECT_ID}/notes/${NOTE_ID}",
  "policy": {
    "bindings": [
      {
        "role": "roles/containeranalysis.notes.occurrences.viewer",
        "members": [
          "serviceAccount:${BINAUTHZ_SA_EMAIL}"
        ]
      }
    ]
  }
}
EOF

curl -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  --data-binary @iam_request.json \
  "https://containeranalysis.googleapis.com/v1/projects/${PROJECT_ID}/notes/${NOTE_ID}:setIamPolicy"

KEY_LOCATION=global
KEYRING=binauthz-keys
KEY_NAME=codelab-key
KEY_VERSION=1

gcloud kms keyrings create "$KEYRING" --location="$KEY_LOCATION"

gcloud kms keys create "$KEY_NAME" \
  --keyring="$KEYRING" \
  --location="$KEY_LOCATION" \
  --purpose asymmetric-signing \
  --default-algorithm="ec-sign-p256-sha256"

gcloud beta container binauthz attestors public-keys add \
  --attestor="$ATTESTOR_ID" \
  --keyversion-project="$PROJECT_ID" \
  --keyversion-location="$KEY_LOCATION" \
  --keyversion-keyring="$KEYRING" \
  --keyversion-key="$KEY_NAME" \
  --keyversion="$KEY_VERSION"

CONTAINER_PATH=${REGION}-docker.pkg.dev/${PROJECT_ID}/artifact-scanning-repo/sample-image
DIGEST=$(gcloud container images describe ${CONTAINER_PATH}:latest --format='get(image_summary.digest)')

gcloud beta container binauthz attestations sign-and-create \
  --artifact-url="${CONTAINER_PATH}@${DIGEST}" \
  --attestor="$ATTESTOR_ID" \
  --attestor-project="$PROJECT_ID" \
  --keyversion-project="$PROJECT_ID" \
  --keyversion-location="$KEY_LOCATION" \
  --keyversion-keyring="$KEYRING" \
  --keyversion-key="$KEY_NAME" \
  --keyversion="$KEY_VERSION"

gcloud beta container clusters create binauthz \
  --zone $ZONE \
  --binauthz-evaluation-mode=PROJECT_SINGLETON_POLICY_ENFORCE

gcloud container clusters get-credentials binauthz --zone $ZONE

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/container.developer"

gcloud container binauthz policy export > policy.yaml

cat > policy.yaml <<EOF
globalPolicyEvaluationMode: ENABLE
defaultAdmissionRule:
  evaluationMode: ALWAYS_DENY
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
name: projects/${PROJECT_ID}/policy
EOF

gcloud container binauthz policy import policy.yaml

sleep 10

kubectl run hello-server --image gcr.io/google-samples/hello-app:1.0 --port 8080 || true

cat > policy.yaml <<EOF
globalPolicyEvaluationMode: ENABLE
defaultAdmissionRule:
  evaluationMode: ALWAYS_ALLOW
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
name: projects/${PROJECT_ID}/policy
EOF

gcloud container binauthz policy import policy.yaml

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/binaryauthorization.attestorsViewer"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/cloudkms.signerVerifier"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role="roles/cloudkms.signerVerifier"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/containeranalysis.notes.attacher"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/ondemandscanning.admin"

git clone https://github.com/GoogleCloudPlatform/cloud-builders-community.git
cd cloud-builders-community/binauthz-attestation
gcloud builds submit . --config cloudbuild.yaml
cd ../..
rm -rf cloud-builders-community

cat > cloudbuild.yaml <<EOF
steps:
- id: "build"
  name: "gcr.io/cloud-builders/docker"
  args: ["build", "-t", "${REGION}-docker.pkg.dev/${PROJECT_ID}/artifact-scanning-repo/sample-image", "."]

- id: "retag"
  name: "gcr.io/cloud-builders/docker"
  args: ["tag", "${REGION}-docker.pkg.dev/${PROJECT_ID}/artifact-scanning-repo/sample-image", "${REGION}-docker.pkg.dev/${PROJECT_ID}/artifact-scanning-repo/sample-image:good"]

- id: "push"
  name: "gcr.io/cloud-builders/docker"
  args: ["push", "${REGION}-docker.pkg.dev/${PROJECT_ID}/artifact-scanning-repo/sample-image:good"]

- id: "create-attestation"
  name: "gcr.io/${PROJECT_ID}/binauthz-attestation:latest"
  args:
    - "--artifact-url"
    - "${REGION}-docker.pkg.dev/${PROJECT_ID}/artifact-scanning-repo/sample-image:good"
    - "--attestor"
    - "projects/${PROJECT_ID}/attestors/${ATTESTOR_ID}"
    - "--keyversion"
    - "projects/${PROJECT_ID}/locations/${KEY_LOCATION}/keyRings/${KEYRING}/cryptoKeys/${KEY_NAME}/cryptoKeyVersions/${KEY_VERSION}"

images:
- "${REGION}-docker.pkg.dev/${PROJECT_ID}/artifact-scanning-repo/sample-image:good"
EOF

gcloud builds submit

cat > binauth_policy.yaml <<EOF
defaultAdmissionRule:
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
  evaluationMode: REQUIRE_ATTESTATION
  requireAttestationsBy:
  - projects/${PROJECT_ID}/attestors/vulnz-attestor
globalPolicyEvaluationMode: ENABLE
clusterAdmissionRules:
  ${ZONE}.binauthz:
    evaluationMode: REQUIRE_ATTESTATION
    enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
    requireAttestationsBy:
    - projects/${PROJECT_ID}/attestors/vulnz-attestor
EOF

gcloud beta container binauthz policy import binauth_policy.yaml

CONTAINER_PATH=${REGION}-docker.pkg.dev/${PROJECT_ID}/artifact-scanning-repo/sample-image
DIGEST=$(gcloud container images describe ${CONTAINER_PATH}:good --format='get(image_summary.digest)')

cat > deploy.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: deb-httpd
spec:
  selector:
    app: deb-httpd
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: deb-httpd
spec:
  replicas: 1
  selector:
    matchLabels:
      app: deb-httpd
  template:
    metadata:
      labels:
        app: deb-httpd
    spec:
      containers:
      - name: deb-httpd
        image: ${CONTAINER_PATH}@${DIGEST}
        ports:
        - containerPort: 8080
        env:
        - name: PORT
          value: "8080"
EOF

kubectl apply -f deploy.yaml

docker build -t ${REGION}-docker.pkg.dev/${PROJECT_ID}/artifact-scanning-repo/sample-image:bad .
docker push ${REGION}-docker.pkg.dev/${PROJECT_ID}/artifact-scanning-repo/sample-image:bad

DIGEST=$(gcloud container images describe ${CONTAINER_PATH}:bad --format='get(image_summary.digest)')

cat > deploy.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: deb-httpd
spec:
  selector:
    app: deb-httpd
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: deb-httpd
spec:
  replicas: 1
  selector:
    matchLabels:
      app: deb-httpd
  template:
    metadata:
      labels:
        app: deb-httpd
    spec:
      containers:
      - name: deb-httpd
        image: ${CONTAINER_PATH}@${DIGEST}
        ports:
        - containerPort: 8080
        env:
        - name: PORT
          value: "8080"
EOF

kubectl apply -f deploy.yaml || true

echo "DONE"