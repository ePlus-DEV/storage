PROJECT_ID=$(gcloud projects list --format="value(projectId)" --limit=1)

bq mk work_day && bq load --source_format=CSV --skip_leading_rows=1 work_day.employee gs://${PROJECT_ID}-bucket/employees.csv employee_id:INTEGER,device_id:STRING,username:STRING,department:STRING,office:STRING