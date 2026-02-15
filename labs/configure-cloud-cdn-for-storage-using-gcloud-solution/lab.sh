BUCKET_NAME=$(gcloud config get-value project)-bucket
BACKEND_BUCKET=static-backend-bucket
URL_MAP=cdn-map
PROXY=cdn-http-proxy
FORWARDING_RULE=cdn-http-rule

gcloud compute backend-buckets create $BACKEND_BUCKET --gcs-bucket-name=$BUCKET_NAME --enable-cdn

gcloud compute url-maps create $URL_MAP --default-backend-bucket=$BACKEND_BUCKET
# karta hu copy abhishek ji ki video ki mai to hu nal;ayak
gcloud compute target-http-proxies create $PROXY --url-map=$URL_MAP

gcloud compute forwarding-rules create $FORWARDING_RULE --global --target-http-proxy=$PROXY --ports=80

gcloud compute forwarding-rules describe $FORWARDING_RULE --global --format="value(IPAddress)"

gsutil ls gs://$BUCKET_NAME/images/
# jaise video banata hai sir mai ajata copy karne ko :D md file bhi na banane aati meko
curl -o nature.png http://IP_ADDRESS/images/nature.png