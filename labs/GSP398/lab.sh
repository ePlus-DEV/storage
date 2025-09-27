#!/bin/bash
# =====================================================================
# 🚀 Vertex AI TensorFlow CNN Challenge Lab - Light Script (No Task 1)
# ---------------------------------------------------------------------
# Author: ePlus.DEV
# Version: 1.0
# Copyright (c) 2025 ePlus.DEV
# =====================================================================

# 🎨 Colors
GREEN="\e[32m"
BLUE="\e[34m"
CYAN="\e[36m"
YELLOW="\e[33m"
RED="\e[31m"
BOLD="\e[1m"
RESET="\e[0m"

echo -e "${CYAN}${BOLD}"
echo "==============================================================="
echo "   🚀 Vertex AI CNN Challenge Lab (No Workbench) - ePlus.DEV"
echo "==============================================================="
echo -e "${RESET}"

# ------------------ CONFIG ------------------
REGION="us-west1"
DISPLAY_NAME="cnn-training-job"
MODEL_NAME="cnn-model"
MACHINE_TYPE="n1-standard-4"
SERVE_MACHINE_TYPE="n1-standard-2"
TRAIN_IMAGE="us-docker.pkg.dev/vertex-ai/training/tf-cpu.2-11:latest"
SERVE_IMAGE="us-docker.pkg.dev/vertex-ai/prediction/tf2-cpu.2-11:latest"

PROJECT_ID=$(gcloud config get-value project)
BUCKET_NAME="${PROJECT_ID}-bucket"

echo -e "${BLUE}📦 Project:${RESET} ${GREEN}$PROJECT_ID${RESET}"
echo -e "${BLUE}🌍 Region:${RESET} ${GREEN}$REGION${RESET}\n"

# ------------------ ENABLE APIS ------------------
echo -e "${YELLOW}🔧 Enabling APIs...${RESET}"
gcloud services enable \
  aiplatform.googleapis.com \
  artifactregistry.googleapis.com \
  container.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  compute.googleapis.com
echo -e "${GREEN}✅ APIs enabled.${RESET}\n"

# ------------------ TASK 2: CREATE BUCKET ------------------
echo -e "${YELLOW}📦 Creating Cloud Storage bucket...${RESET}"
gsutil mb -l $REGION gs://$BUCKET_NAME || echo -e "${BLUE}ℹ️ Bucket already exists, skipping...${RESET}"

# ------------------ TASK 3: CREATE TRAINING SCRIPT ------------------
echo -e "${YELLOW}🧠 Creating task.py training script...${RESET}"
cat > task.py <<'EOF'
import os
import tensorflow as tf

def create_model(num_classes=10):
    model = tf.keras.models.Sequential([
        tf.keras.layers.Conv2D(32, (3, 3), activation='relu', input_shape=(28, 28, 1)),
        tf.keras.layers.MaxPooling2D(pool_size=(2, 2)),
        tf.keras.layers.Conv2D(64, (3, 3), activation='relu'),
        tf.keras.layers.MaxPooling2D(pool_size=(2, 2)),
        tf.keras.layers.Flatten(),
        tf.keras.layers.Dense(128, activation='relu'),
        tf.keras.layers.Dense(num_classes, activation='softmax')
    ])
    model.compile(optimizer='adam',
                  loss='sparse_categorical_crossentropy',
                  metrics=['accuracy'])
    return model

def main():
    (x_train, y_train), (x_test, y_test) = tf.keras.datasets.mnist.load_data()
    x_train, x_test = x_train / 255.0, x_test / 255.0
    x_train, x_test = x_train[..., tf.newaxis], x_test[..., tf.newaxis]
    model = create_model(num_classes=10)
    model.fit(x_train, y_train, epochs=5, batch_size=64, validation_data=(x_test, y_test))
    model_dir = os.getenv("AIP_MODEL_DIR", "./model")
    model.save(model_dir)
    print("✅ Model saved to:", model_dir)

if __name__ == "__main__":
    main()
EOF
echo -e "${GREEN}✅ Training script created.${RESET}\n"

# ------------------ TASK 4: CUSTOM TRAINING JOB ------------------
echo -e "${YELLOW}🛠️ Submitting Custom Training Job...${RESET}"

gcloud ai custom-jobs create-with-python-package \
  --region=$REGION \
  --display-name=$DISPLAY_NAME \
  --python-package-uris=. \
  --python-module=task \
  --container-image-uri=$TRAIN_IMAGE

echo -e "${CYAN}⏳ Training submitted (~8-10 min)...${RESET}\n"

# ------------------ WAIT FOR TRAINING ------------------
echo -e "${YELLOW}🔍 Waiting for training job to complete...${RESET}"
while true; do
  STATUS=$(gcloud ai custom-jobs list --region=$REGION --format="value(STATE)" | head -n 1)
  if [[ "$STATUS" == "JOB_STATE_SUCCEEDED" ]]; then
    echo -e "${GREEN}✅ Training complete!${RESET}"
    break
  elif [[ "$STATUS" == "JOB_STATE_FAILED" ]]; then
    echo -e "${RED}❌ Training failed. Check logs:${RESET} gcloud ai custom-jobs list --region=$REGION"
    exit 1
  else
    echo -e "${YELLOW}🟡 Status: $STATUS - checking again in 60s...${RESET}"
    sleep 60
  fi
done

# ------------------ TASK 5: DEPLOY MODEL ------------------
echo -e "${YELLOW}📦 Retrieving latest model ID...${RESET}"
MODEL_ID=$(gcloud ai models list --region=$REGION --format="value(name)" | tail -n 1 | awk -F/ '{print $6}')
echo -e "${GREEN}✅ MODEL_ID: $MODEL_ID${RESET}\n"

echo -e "${YELLOW}🚀 Creating endpoint...${RESET}"
gcloud ai endpoints create --region=$REGION --display-name=cnn-endpoint

ENDPOINT_ID=$(gcloud ai endpoints list --region=$REGION --format="value(name)" | awk -F/ '{print $6}')
echo -e "${GREEN}✅ ENDPOINT_ID: $ENDPOINT_ID${RESET}\n"

echo -e "${YELLOW}📡 Deploying model to endpoint...${RESET}"
gcloud ai endpoints deploy-model $ENDPOINT_ID \
  --region=$REGION \
  --model=$MODEL_ID \
  --display-name=$MODEL_NAME \
  --machine-type=$SERVE_MACHINE_TYPE \
  --traffic-split=0=100 \
  --min-replica-count=1 \
  --max-replica-count=2

echo -e "${CYAN}⏳ Deployment may take ~10-15 min...${RESET}\n"

# ------------------ TASK 6: PREDICT ------------------
echo -e "${YELLOW}📄 Creating sample input.json...${RESET}"
cat > input.json <<EOF
{
  "instances": [[[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
                 [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
                 [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
                 [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]]]
}
EOF

echo -e "${YELLOW}🤖 Sending prediction request...${RESET}"
gcloud ai endpoints predict $ENDPOINT_ID \
  --region=$REGION \
  --json-request=input.json

echo -e "${GREEN}${BOLD}✅ All tasks completed successfully!${RESET}"
echo -e "${CYAN}${BOLD}🎉 Model trained, deployed & serving online predictions.${RESET}"
echo -e "${BLUE}${BOLD}🔗 Powered by ePlus.DEV ${RESET}\n"