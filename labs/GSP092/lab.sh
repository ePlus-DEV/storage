gcloud auth list

export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")


curl -LO 'https://github.com/tsenart/vegeta/releases/download/v12.12.0/vegeta_12.12.0_linux_386.tar.gz'

tar -xvzf vegeta_12.12.0_linux_386.tar.gz

CLOUD_RUN_URL=$(gcloud run services describe helloworld --region=$REGION --format='value(status.url)')
echo $CLOUD_RUN_URL


echo "GET $CLOUD_RUN_URL" | ./vegeta attack -duration=300s -rate=200 > results.bin


gcloud logging metrics create nFunctionLatency-Logs \
  --project=$DEVSHELL_PROJECT_ID \
  --description="like share & subscribe to techcps" \
  --log-filter='resource.type="cloud_run_revision" AND resource.labels.service_name="helloworld"'