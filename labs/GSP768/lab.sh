#!/bin/bash
# ===============================================
#  GKE Autoscaling Lab - Full Script
#  Covers: HPA, VPA, Cluster Autoscaler, NAP, Pause Pods
#  © 2025 ePlus.DEV
# ===============================================

# Colors
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# ---- HEADER ----
echo "${CYAN}${BOLD}"
echo "╔════════════════════════════════════╗"
echo "║                                    ║"
echo "║        🚀 ePlus.DEV | GSP768       ║"
echo "║                                     ║"
echo "╚═════════════════════════════════════╝"
echo "${RESET}"

echo "${CYAN}${BOLD}▶ Starting GKE Autoscaling Lab...${RESET}"

# -----------------------------------------------
# Task 1: Horizontal Pod Autoscaler (HPA)
# -----------------------------------------------
echo "${YELLOW}==> Task 1: Deploy php-apache & enable HPA${RESET}"

export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")

gcloud config set compute/zone $ZONE

gcloud container clusters create scaling-demo --num-nodes=3 --enable-vertical-pod-autoscaling

cat << EOF > php-apache.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: php-apache
spec:
  selector:
    matchLabels:
      run: php-apache
  replicas: 3
  template:
    metadata:
      labels:
        run: php-apache
    spec:
      containers:
      - name: php-apache
        image: k8s.gcr.io/hpa-example
        ports:
        - containerPort: 80
        resources:
          limits:
            cpu: 500m
          requests:
            cpu: 200m
---
apiVersion: v1
kind: Service
metadata:
  name: php-apache
  labels:
    run: php-apache
spec:
  ports:
  - port: 80
  selector:
    run: php-apache
EOF

kubectl apply -f php-apache.yaml

kubectl autoscale deployment php-apache --cpu-percent=50 --min=1 --max=10

kubectl get hpa

# -----------------------------------------------
# Task 2: Vertical Pod Autoscaler (VPA)
# -----------------------------------------------
echo "${YELLOW}==> Task 2: Deploy hello-server & enable VPA${RESET}"

kubectl create deployment hello-server --image=gcr.io/google-samples/hello-app:1.0
kubectl set resources deployment hello-server --requests=cpu=450m

cat << EOF > hello-vpa.yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: hello-server-vpa
spec:
  targetRef:
    apiVersion: "apps/v1"
    kind:       Deployment
    name:       hello-server
  updatePolicy:
    updateMode: "Auto"
EOF

kubectl apply -f hello-vpa.yaml
kubectl scale deployment hello-server --replicas=2

# -----------------------------------------------
# Task 3: HPA Results
# -----------------------------------------------
echo "${YELLOW}==> Task 3: Check HPA status${RESET}"
kubectl get hpa

# -----------------------------------------------
# Task 4: VPA Results
# -----------------------------------------------
echo "${YELLOW}==> Task 4: Check VPA recommendations${RESET}"
kubectl describe vpa hello-server-vpa | tail -n 20

# -----------------------------------------------
# Task 5: Cluster Autoscaler
# -----------------------------------------------
echo "${YELLOW}==> Task 5: Enable Cluster Autoscaler${RESET}"

gcloud beta container clusters update scaling-demo --enable-autoscaling --min-nodes 1 --max-nodes 5
gcloud beta container clusters update scaling-demo --autoscaling-profile optimize-utilization

# Allow system pods rescheduling
for pdb in kube-dns prometheus kube-proxy metrics-agent metrics-server fluentd backend kube-dns-autoscaler stackdriver event; do
  case $pdb in
    kube-proxy) selector="component=kube-proxy" ;;
    backend) selector="k8s-app=glbc" ;;
    stackdriver) selector="app=stackdriver-metadata-agent" ;;
    event) selector="k8s-app=event-exporter" ;;
    *) selector="k8s-app=$pdb" ;;
  esac
  kubectl create poddisruptionbudget ${pdb}-pdb --namespace=kube-system --selector $selector --max-unavailable 1
done

kubectl get nodes

# -----------------------------------------------
# Task 6: Node Auto Provisioning (NAP)
# -----------------------------------------------
echo "${YELLOW}==> Task 6: Enable Node Auto Provisioning${RESET}"

gcloud container clusters update scaling-demo \
    --enable-autoprovisioning \
    --min-cpu 1 \
    --min-memory 2 \
    --max-cpu 45 \
    --max-memory 160

# -----------------------------------------------
# Task 7: Load Test
# -----------------------------------------------
echo "${YELLOW}==> Task 7: Run load test (busybox)${RESET}"
echo "${CYAN}Run this in a separate Cloud Shell tab if needed:${RESET}"
echo "kubectl run -i --tty load-generator --rm --image=busybox --restart=Never -- /bin/sh -c \"while sleep 0.01; do wget -q -O- http://php-apache; done\""

# -----------------------------------------------
# Task 8: Pause Pods (Overprovisioning)
# -----------------------------------------------
echo "${YELLOW}==> Task 8: Deploy Pause Pods for buffer capacity${RESET}"

cat << EOF > pause-pod.yaml
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: overprovisioning
value: -1
globalDefault: false
description: "Priority class used by overprovisioning."
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: overprovisioning
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      run: overprovisioning
  template:
    metadata:
      labels:
        run: overprovisioning
    spec:
      priorityClassName: overprovisioning
      containers:
      - name: reserve-resources
        image: k8s.gcr.io/pause
        resources:
          requests:
            cpu: 1
            memory: 4Gi
EOF

kubectl apply -f pause-pod.yaml

# -----------------------------------------------
# Finish
# -----------------------------------------------
echo
# ---- FOOTER ----
echo "${GREEN}${BOLD}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║   ✅ Script Completed | © 2025 ePlus.DEV                   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo "${RESET}"
