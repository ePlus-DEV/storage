#!/bin/bash
# ===============================================================
#  © 2025 ePlus.DEV. All rights reserved.
#  GKE Probes & Ingress Lab Automation Script
# ===============================================================

# ---- COLOR SCHEME ----
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# ---- HEADER ----
echo "${CYAN}${BOLD}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║    🚀 ePlus.DEV | GKE Probes, Ingress & Load Testing Lab   ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo "${RESET}"

# ---- AUTH & CONFIG ----
echo "${YELLOW}${BOLD}▶ Checking authentication...${RESET}"
gcloud auth list

export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export PROJECT_ID=$(gcloud config get-value project)

gcloud config set project $DEVSHELL_PROJECT_ID
gcloud config set compute/zone "$ZONE"
gcloud config set compute/region "$REGION"

# ---- CLUSTER ----
echo "${GREEN}${BOLD}=== Creating GKE Cluster ===${RESET}"
gcloud container clusters create test-cluster --num-nodes=3 --enable-ip-alias

# ---- FRONTEND POD ----
cat << EOF > gb_frontend_pod.yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    app: gb-frontend
  name: gb-frontend
spec:
  containers:
  - name: gb-frontend
    image: gcr.io/google-samples/gb-frontend-amd64:v5
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
    ports:
    - containerPort: 80
EOF
kubectl apply -f gb_frontend_pod.yaml

# ---- SERVICE CLUSTERIP ----
cat << EOF > gb_frontend_cluster_ip.yaml
apiVersion: v1
kind: Service
metadata:
  name: gb-frontend-svc
  annotations:
    cloud.google.com/neg: '{"ingress": true}'
spec:
  type: ClusterIP
  selector:
    app: gb-frontend
  ports:
  - port: 80
    protocol: TCP
    targetPort: 80
EOF
kubectl apply -f gb_frontend_cluster_ip.yaml

# ---- INGRESS ----
cat << EOF > gb_frontend_ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: gb-frontend-ingress
spec:
  defaultBackend:
    service:
      name: gb-frontend-svc
      port:
        number: 80
EOF
kubectl apply -f gb_frontend_ingress.yaml

# ---- CHECK BACKEND ----
echo "${YELLOW}${BOLD}▶ Waiting for backend service to be ready...${RESET}"
sleep 415
BACKEND_SERVICE=$(gcloud compute backend-services list --format="value(name)" --limit=1)
gcloud compute backend-services get-health $BACKEND_SERVICE --global
kubectl get ingress gb-frontend-ingress

# ---- CONFIRM ----
while true; do
    echo -ne "${YELLOW}${BOLD}Do you want to proceed with Locust setup? (Y/n): ${RESET}"
    read confirm
    case "$confirm" in
        [Yy]) echo "${CYAN}▶ Proceeding...${RESET}"; break ;;
        [Nn]|"") echo "${RED}Operation canceled.${RESET}"; exit 1 ;;
        *) echo "${RED}Invalid input. Please enter Y or N.${RESET}" ;;
    esac
done

# ---- LOCUST LOAD TEST ----
gsutil -m cp -r gs://spls/gsp769/locust-image .
gcloud builds submit --tag gcr.io/${GOOGLE_CLOUD_PROJECT}/locust-tasks:latest locust-image
gsutil cp gs://spls/gsp769/locust_deploy_v2.yaml .
sed "s/\${GOOGLE_CLOUD_PROJECT}/$GOOGLE_CLOUD_PROJECT/g" locust_deploy_v2.yaml | kubectl apply -f -
kubectl get service locust-main

# ---- LIVENESS PROBE DEMO ----
cat > liveness-demo.yaml <<EOF_END
apiVersion: v1
kind: Pod
metadata:
  labels:
    demo: liveness-probe
  name: liveness-demo-pod
spec:
  containers:
  - name: liveness-demo-pod
    image: centos
    args:
    - /bin/sh
    - -c
    - touch /tmp/alive; sleep infinity
    livenessProbe:
      exec:
        command:
        - cat
        - /tmp/alive
      initialDelaySeconds: 5
      periodSeconds: 10
EOF_END
kubectl apply -f liveness-demo.yaml
kubectl describe pod liveness-demo-pod
kubectl exec liveness-demo-pod -- rm /tmp/alive
kubectl describe pod liveness-demo-pod

# ---- READINESS PROBE DEMO ----
cat << EOF > readiness-demo.yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    demo: readiness-probe
  name: readiness-demo-pod
spec:
  containers:
  - name: readiness-demo-pod
    image: nginx
    ports:
    - containerPort: 80
    readinessProbe:
      exec:
        command:
        - cat
        - /tmp/healthz
      initialDelaySeconds: 5
      periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: readiness-demo-svc
  labels:
    demo: readiness-probe
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
  selector:
    demo: readiness-probe
EOF
kubectl apply -f readiness-demo.yaml
kubectl get service readiness-demo-svc
kubectl describe pod readiness-demo-pod
sleep 45
kubectl exec readiness-demo-pod -- touch /tmp/healthz
kubectl describe pod readiness-demo-pod | grep ^Conditions -A 5

# ---- DEPLOYMENT ----
kubectl delete pod gb-frontend
cat << EOF > gb_frontend_deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gb-frontend
  labels:
    run: gb-frontend
spec:
  replicas: 5
  selector:
    matchLabels:
      run: gb-frontend
  template:
    metadata:
      labels:
        run: gb-frontend
    spec:
      containers:
      - name: gb-frontend
        image: gcr.io/google-samples/gb-frontend-amd64:v5
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
        ports:
        - containerPort: 80
          protocol: TCP
EOF
kubectl apply -f gb_frontend_deployment.yaml

# ---- FOOTER ----
echo "${GREEN}${BOLD}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║        ✅ Script Completed | © 2025 ePlus.DEV               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo "${RESET}"