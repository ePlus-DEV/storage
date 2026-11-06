# Dynamic volume provisioning on GKE with Google Cloud NetApp Volumes - GSP1309

## Overview

NetApp Trident is a Kubernetes Container Storage Interface (CSI) orchestrator. In this lab, a pre-created Google Kubernetes Engine (GKE) cluster uses Trident to provision a Google Cloud NetApp Volumes share dynamically from a PersistentVolumeClaim (PVC). The exercises cover installation, an authenticated storage backend, a StorageClass, and a bound PVC. This is an independently written walkthrough based on the public lab requirements, not a reproduction of Google's copyrighted manual.

### What you'll do

- Connect to the lab's existing `cluster1` and deploy Trident 25.02.0.
- Configure a lab-scoped service account, a Kubernetes Secret, a Trident backend, and a StorageClass.
- Request a 1 GiB `ReadWriteMany` volume and verify its binding.
- Check the five Google Skills checkpoints: Install Trident, Create a secret, Create a backend, Create a storage class, and Create a persistent volume claim.

## Setup and requirements

### Before you click the Start Lab button

Use a private/incognito browser window and only the temporary Google Skills lab account. Start the timed lab, open the Google Cloud console from the lab panel, and sign in with the temporary credentials supplied there. Do not use a personal Google Cloud project. The project ID and the cluster/storage-pool locations differ between lab sessions and must be read from the active environment.

The official lab supplies a GKE cluster named `cluster1` and a NetApp storage pool. It expects Trident 25.02.0. You need `gcloud`, `kubectl`, `curl`, `tar`, and Python 3 in Cloud Shell. The lab's instructions require a service-account JSON key for Trident; protect it carefully and never paste it into a public repository or logs.

### Activate Cloud Shell

Open Cloud Shell from the console and authorize its temporary account. Check your current project and list the cluster:

```bash
gcloud config get-value project
gcloud auth list
gcloud container clusters list --format='table(name,location,status)'
gcloud netapp storage-pools list --format='table(name,serviceLevel,state)'
```

Record the actual cluster location and NetApp zonal pool location from the output; the following commands discover them automatically when the project contains a single matching resource.

```bash
export PROJECT_ID="$(gcloud config get-value project)"
export CLUSTER_LOCATION="$(gcloud container clusters list --filter='name=cluster1' --format='value(location)' | head -n 1)"
test -n "$PROJECT_ID" && test -n "$CLUSTER_LOCATION"
gcloud container clusters get-credentials cluster1 --location="$CLUSTER_LOCATION" --project="$PROJECT_ID"
kubectl get nodes
```

If the lab has more than one zonal NetApp pool, identify the intended pool in **NetApp Volumes → Storage pools** before proceeding. Do not guess a zone or select a different project.

## Task 1. Deploy NetApp Trident

### Connect to the Kubernetes cluster

Confirm that `kubectl get nodes` shows the pre-provisioned cluster nodes in a ready state. This is the cluster on which Trident will run; no new GKE cluster is needed.

### Download and install Trident

The official exercise uses version 25.02.0. Work in a new directory to avoid overwriting existing files:

```bash
mkdir -p "$HOME/gsp1309-manual"
cd "$HOME/gsp1309-manual"
curl -fL --retry 3 \
  https://github.com/NetApp/trident/releases/download/v25.02.0/trident-installer-25.02.0.tar.gz \
  -o trident-installer-25.02.0.tar.gz
tar -tzf trident-installer-25.02.0.tar.gz >/dev/null
tar -xzf trident-installer-25.02.0.tar.gz
kubectl apply -f trident-installer/deploy/crds/trident.netapp.io_tridentorchestrators_crd_post1.16.yaml
kubectl create namespace trident --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f trident-installer/deploy/bundle_post_1_25.yaml
kubectl -n trident rollout status deployment/trident-operator --timeout=300s
kubectl apply -f trident-installer/deploy/crds/tridentorchestrator_cr.yaml
```

The operator installs the Trident controller and node components. Wait until they become ready, then inspect them:

```bash
kubectl -n trident get tridentorchestrators
kubectl -n trident get pods
kubectl -n trident rollout status deployment/trident-controller --timeout=360s
```

### Test completed task

On Google Skills, choose **Check my progress → Install Trident** after the operator/controller are ready. The expected Kubernetes status is Running/Ready; a grader result has not been verified for this script.

## Task 2. Configure the requirements

### Create a Google Cloud service account

The official lab explicitly asks for `roles/netapp.admin` on the lab-scoped `netapp-trident` service account. This is broader than would be ideal in production; do not reuse the key or the role outside the temporary lab project.

```bash
export PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
export SA_EMAIL="netapp-trident@${PROJECT_ID}.iam.gserviceaccount.com"
if ! gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud iam service-accounts create netapp-trident --project="$PROJECT_ID" \
    --description='NetApp Trident lab service account' --display-name='NetApp Trident'
fi
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$SA_EMAIL" --role=roles/netapp.admin --condition=None
```

### Create a Kubernetes Secret

The lab requires a private key in `gcnv-secret`. Generate it only inside a private temporary directory, never print the key or check it into Git, and remove the local copy once the Kubernetes Secret is created. For a fresh lab session:

```bash
umask 077
mkdir -p "$HOME/gsp1309-private"
gcloud iam service-accounts keys create "$HOME/gsp1309-private/key.json" \
  --iam-account="$SA_EMAIL" --project="$PROJECT_ID"
python3 - <<'PY'
import json, pathlib
p=pathlib.Path.home()/'gsp1309-private'
k=json.loads((p/'key.json').read_text())
for name in ('private_key_id','private_key'):
    (p/name).write_text(k[name])
PY
kubectl -n trident create secret generic gcnv-secret \
  --from-file="private_key_id=$HOME/gsp1309-private/private_key_id" \
  --from-file="private_key=$HOME/gsp1309-private/private_key" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n trident get secret gcnv-secret
```

### Test completed task

Use **Check my progress → Create a secret** after verifying that the secret exists in the `trident` namespace. Do not expose its decoded data.

### Create the Trident backend

Set `LAB_ZONE` to the actual zone of the pre-created NetApp storage pool (visible in the Google Cloud console or in `gcloud netapp storage-pools list --format=json`). The backend requires the project number and the OAuth `client_id` from the generated JSON key. Keep the key only until you have created the backend.

```bash
export LAB_ZONE="$(gcloud config get-value compute/zone 2>/dev/null)"
# If the above is unset, use the real zonal NetApp storage-pool location.
test -n "$LAB_ZONE" && test "$LAB_ZONE" != '(unset)'
export CLIENT_ID="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["client_id"])' "$HOME/gsp1309-private/key.json")"
cat > "$HOME/gsp1309-manual/gcnv-backend-zonal-flex.yaml" <<EOF
apiVersion: trident.netapp.io/v1
kind: TridentBackendConfig
metadata:
  name: gcnv-zonal-flex
  namespace: trident
spec:
  version: 1
  storageDriverName: google-cloud-netapp-volumes
  backendName: gcnv-zonal-flex
  projectNumber: '$PROJECT_NUMBER'
  location: '$LAB_ZONE'
  apiKey:
    type: service_account
    project_id: '$PROJECT_ID'
    client_email: '$SA_EMAIL'
    client_id: '$CLIENT_ID'
    auth_uri: https://accounts.google.com/o/oauth2/auth
    token_uri: https://oauth2.googleapis.com/token
    auth_provider_x509_cert_url: https://www.googleapis.com/oauth2/v1/certs
    client_x509_cert_url: https://www.googleapis.com/robot/v1/metadata/x509/$SA_EMAIL
  credentials:
    name: gcnv-secret
  storage:
    - labels:
        performance: flex
        availability: zonal
      serviceLevel: flex
EOF
kubectl -n trident apply -f "$HOME/gsp1309-manual/gcnv-backend-zonal-flex.yaml"
kubectl -n trident get tridentbackendconfig gcnv-zonal-flex
rm -f "$HOME/gsp1309-private/key.json" "$HOME/gsp1309-private/private_key_id" "$HOME/gsp1309-private/private_key"
```

Wait until the backend reports a healthy/Bound state. If it fails, inspect `kubectl -n trident describe tridentbackendconfig gcnv-zonal-flex` and confirm the zone, permissions, and secret rather than repeatedly creating keys.

### Test completed task

Use **Check my progress → Create a backend** once `gcnv-zonal-flex` is present and healthy.

### Create the StorageClass

The class selects the zonal Flex backend by labels. It also permits later volume expansion.

```bash
cat > "$HOME/gsp1309-manual/gcnv-storageclass-zonal-flex.yaml" <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gcnv-zonal-flex
provisioner: csi.trident.netapp.io
parameters:
  backendType: google-cloud-netapp-volumes
  selector: 'performance=flex; availability=zonal'
allowVolumeExpansion: true
EOF
kubectl apply -f "$HOME/gsp1309-manual/gcnv-storageclass-zonal-flex.yaml"
kubectl get storageclass gcnv-zonal-flex
```

### Test completed task

Use **Check my progress → Create a storage class** when Kubernetes lists the class.

## Task 3. Create a Persistent Volume Claim

The storage pool already exists. The claim requests a 1 GiB NFS-compatible volume with shared read/write access; Trident is responsible for provisioning the corresponding NetApp volume and Kubernetes PV.

```bash
cat > "$HOME/gsp1309-manual/gcnv-pvc-zonal-flex.yaml" <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-zonal-flex
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: gcnv-zonal-flex
  resources:
    requests:
      storage: 1Gi
EOF
kubectl apply -f "$HOME/gsp1309-manual/gcnv-pvc-zonal-flex.yaml"
kubectl get pvc pvc-zonal-flex -w
```

Stop the watch with `Ctrl+C` once the phase is `Bound`. Verify the PV and, in the console, the dynamically created NetApp volume (usually named with a `pvc-` prefix):

```bash
kubectl get pvc pvc-zonal-flex
kubectl get pv
kubectl -n trident get tridentbackendconfig gcnv-zonal-flex
```

### Test completed task

Use **Check my progress → Create a persistent volume claim**. If the PVC remains Pending, inspect `kubectl describe pvc pvc-zonal-flex` and Trident controller logs. Check pool capacity, project/zone, and backend credentials before making changes.

---

## Solution of Lab

### Quick

The following **two commands** reference the repository's `main` branch. **They will only work after the Draft PR is merged into `main`.** Do not use this URL to test the unmerged PR.

```bash
curl -LO https://raw.githubusercontent.com/ePlus-DEV/storage/refs/heads/main/labs/GSP1309/lab.sh
source lab.sh
```

The script detects the current project, GKE location, and a unique zonal NetApp pool; it stops when a location cannot be established safely. It downloads the official Trident release, creates only the lab-required objects, and removes the local private-key file. It does not delete pre-existing lab resources. After grading, revoke the temporary service-account key and remove the Kubernetes Secret in the disposable lab environment.

### Manual

Chưa tìm thấy video YouTube hướng dẫn thủ công đã xác minh cho lab này.

The manual commands above are an independent, step-by-step alternative to the Quick script and do not depend on a video.

### Sources and verification

- [Official Google Skills GSP1309](https://www.skills.google/focuses/124121?parent=catalog) — task names, checkpoint order, required resources and Trident version.
- [NetApp Trident release v25.02.0](https://github.com/NetApp/trident/releases/tag/v25.02.0) — installer.
- [Google Cloud NetApp Volumes documentation](https://docs.cloud.google.com/netapp/volumes/docs).
- [Google Cloud IAM service-account key creation](https://docs.cloud.google.com/sdk/gcloud/reference/iam/service-accounts/keys/create).
- [Kubernetes PersistentVolumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/).

**Verification:** static validated only; runtime/grader unverified. No Google Cloud lab account was used. This Markdown file is prepared for Hashnode, **not published**. No Google Skills screenshots are embedded because reuse/embedding rights have not been verified; refer to the official page for those UI illustrations. The temporary key is required by this lab's published procedure, but should not be used as a production authentication pattern.
