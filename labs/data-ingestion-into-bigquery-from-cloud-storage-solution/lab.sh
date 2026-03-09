export PROJECT_ID=$(gcloud config get-value project)
export BUCKET=${PROJECT_ID}-a1f8-bucket

bq mk -d work_day || true

bq load \
--source_format=CSV \
--skip_leading_rows=1 \
work_day.employee \
gs://$BUCKET/employees.csv \
employee_id:INTEGER,device_id:STRING,username:STRING,department:STRING,office:STRING