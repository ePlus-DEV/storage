
echo '[{"origin":["http://example.com"],"method":["GET"],"responseHeader":["Content-Type"],"maxAgeSeconds":3600}]' > cors.json

gcloud storage buckets update gs://$(gcloud config get-value project)-bucket --cors-file=cors.json

