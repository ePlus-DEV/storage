#!/bin/bash

# ANSI color codes
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BLACK=`tput setaf 0`
GREEN=`tput setaf 2`
BLUE=`tput setaf 4`
MAGENTA=`tput setaf 5`
CYAN=`tput setaf 6`
WHITE=`tput setaf 7`

BG_BLACK=`tput setab 0`
BG_RED=`tput setab 1`
BG_GREEN=`tput setab 2`
BG_YELLOW=`tput setab 3`
BG_BLUE=`tput setab 4`
BG_MAGENTA=`tput setab 5`
BG_CYAN=`tput setab 6`
BG_WHITE=`tput setab 7`

BOLD=`tput bold`
RESET=`tput sgr0`
NC='\033[0m' # No Color

echo -e "${CYAN}=====================================${NC}"
echo -e "   ${YELLOW}Copyright (c) 2025 ePlus.DEV${NC}"
echo -e "${CYAN}=====================================${NC}\n"

echo "Please export the values."

# Prompt user to input values
read -p "Enter REGION (e.g. us-east4): " REGION

gcloud config set compute/region $REGION

gcloud services disable dataflow.googleapis.com
gcloud services enable dataflow.googleapis.com
gcloud services enable cloudscheduler.googleapis.com

sleep 20

PROJECT_ID=$(gcloud config get-value project)
BUCKET_NAME="${PROJECT_ID}-bucket"
TOPIC_ID=my-id

gsutil mb gs://$BUCKET_NAME

gcloud pubsub topics create $TOPIC_ID

if [ "$REGION" == "us-central1" ]; then
  gcloud app create --region us-central
elif [ "$REGION" == "europe-west1" ]; then
  gcloud app create --region europe-west
else
  gcloud app create --region "$REGION"
fi

gcloud scheduler jobs create pubsub publisher-job --schedule="* * * * *" \
    --topic=$TOPIC_ID --message-body="Hello!"

sleep 60

gcloud scheduler jobs run publisher-job --location=$REGION

sleep 60

gcloud scheduler jobs run publisher-job --location=$REGION

cat > automate_commands.sh <<EOF_END
#!/bin/bash

git clone https://github.com/GoogleCloudPlatform/python-docs-samples.git
cd python-docs-samples/pubsub/streaming-analytics
pip install -U -r requirements.txt
python PubSubToGCS.py \
--project=$PROJECT_ID \
--region=$REGION \
--input_topic=projects/$PROJECT_ID/topics/$TOPIC_ID \
--output_path=gs://$BUCKET_NAME/samples/output \
--runner=DataflowRunner \
--window_size=2 \
--num_shards=2 \
--temp_location=gs://$BUCKET_NAME/temp
EOF_END

chmod +x automate_commands.sh

docker run -it -e DEVSHELL_PROJECT_ID=$DEVSHELL_PROJECT_ID -e BUCKET_NAME=$BUCKET_NAME -e PROJECT_ID=$PROJECT_ID -e REGION=$REGION -e TOPIC_ID=$TOPIC_ID -v $(pwd)/automate_commands.sh:/automate_commands.sh python:3.7 /bin/bash -c "/automate_commands.sh"



echo -e "${CYAN}=====================================${NC}"
echo -e "   ${YELLOW}Congratulations For Completing!!! - ePlus.DEV{NC}"
echo -e "${CYAN}=====================================${NC}\n"