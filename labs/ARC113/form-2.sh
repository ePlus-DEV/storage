#!/bin/bash

# Color Definitions
BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'

RESET_FORMAT=$'\033[0m'
BOLD_TEXT=$'\033[1m'
UNDERLINE_TEXT=$'\033[4m'

clear

echo "${CYAN_TEXT}${BOLD_TEXT}==============================================================${RESET_FORMAT}"
echo "${MAGENTA_TEXT}${BOLD_TEXT}     🚀 ePlus.DEV – GCP Lab      ${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}==============================================================${RESET_FORMAT}"
echo

LOCATION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")


echo
echo "${BLUE_TEXT}${BOLD_TEXT}Step 1:${RESET_FORMAT} ${WHITE_TEXT}Creating Pub/Sub schema using Avro format...${RESET_FORMAT}"
echo
gcloud pubsub schemas create city-temp-schema \
        --type=avro \
        --definition='{                                             
            "type" : "record",                               
            "name" : "Avro",                                 
            "fields" : [                                     
            { "name" : "city", "type" : "string" },           
            { "name" : "temperature", "type" : "double" },    
            { "name" : "pressure", "type" : "int" },          
            { "name" : "time_position", "type" : "string" }   
        ]                                                    
    }'

echo
echo "${BLUE_TEXT}${BOLD_TEXT}Step 2:${RESET_FORMAT} ${WHITE_TEXT}Creating Pub/Sub topic with JSON message encoding...${RESET_FORMAT}"
echo
gcloud pubsub topics create temp-topic \
        --message-encoding=JSON \
        --schema=temperature-schema

echo
echo "${BLUE_TEXT}${BOLD_TEXT}Step 3:${RESET_FORMAT} ${WHITE_TEXT}Enabling necessary Google Cloud services...${RESET_FORMAT}"
echo
gcloud services enable eventarc.googleapis.com
gcloud services enable run.googleapis.com

echo
echo "${BLUE_TEXT}${BOLD_TEXT}Step 4:${RESET_FORMAT} ${WHITE_TEXT}Generating Node.js Cloud Function file...${RESET_FORMAT}"
echo
cat > index.js <<'EOF_END'
const functions = require('@google-cloud/functions-framework');

functions.cloudEvent('helloPubSub', cloudEvent => {
  const base64name = cloudEvent.data.message.data;

  const name = base64name
    ? Buffer.from(base64name, 'base64').toString()
    : 'World';

  console.log(`Hello, ${name}!`);
});
EOF_END

echo
echo "${BLUE_TEXT}${BOLD_TEXT}Step 5:${RESET_FORMAT} ${WHITE_TEXT}Creating package.json with dependencies...${RESET_FORMAT}"
echo
cat > package.json <<'EOF_END'
{
  "name": "gcf_hello_world",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": {
    "start": "node index.js",
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0"
  }
}
EOF_END

echo
echo "${BLUE_TEXT}${BOLD_TEXT}Step 6:${RESET_FORMAT} ${WHITE_TEXT}Deploying the Cloud Function...${RESET_FORMAT}"
echo

deploy_function() {
gcloud functions deploy gcf-pubsub \
  --gen2 \
  --runtime=nodejs22 \
  --region=$LOCATION \
  --source=. \
  --entry-point=helloPubSub \
  --trigger-topic gcf-topic \
  --quiet
}

deploy_success=false

echo "${CYAN_TEXT}${BOLD_TEXT}Deployment Status:${RESET_FORMAT} ${WHITE_TEXT}Deploying Cloud Function...${RESET_FORMAT}"
while [ "$deploy_success" = false ]; do
    if deploy_function; then
        echo "${GREEN_TEXT}${BOLD_TEXT}✅ Success:${RESET_FORMAT} ${WHITE_TEXT}Function deployed successfully!${RESET_FORMAT}"
        deploy_success=true
    else
        echo "${YELLOW_TEXT}${BOLD_TEXT}⚠️ Retrying:${RESET_FORMAT} ${WHITE_TEXT}Retrying in 20 seconds...${RESET_FORMAT}"
        sleep 20
    fi
done

echo
echo "${MAGENTA_TEXT}${BOLD_TEXT}==============================================================${RESET_FORMAT}"
echo "${MAGENTA_TEXT}${BOLD_TEXT}        🎉 LAB COMPLETED SUCCESSFULLY – GREAT JOB!            ${RESET_FORMAT}"
echo "${MAGENTA_TEXT}${BOLD_TEXT}==============================================================${RESET_FORMAT}"
echo