export BUCKET="$(gsutil ls -b | head -n 1 | sed 's#gs://##; s#/*$##')"

echo $BUCKET

echo ""

gsutil web set -m index.html -e error.html gs://$BUCKET
gsutil uniformbucketlevelaccess set off gs://$BUCKET
gsutil defacl set public-read gs://$BUCKET
gsutil acl set -a public-read gs://$BUCKET/index.html
gsutil acl set -a public-read gs://$BUCKET/error.html
gsutil acl set -a public-read gs://$BUCKET/style.css
gsutil acl set -a public-read gs://$BUCKET/logo.jpg

echo
echo "DONE. Now click 'Check my progress' in the lab."