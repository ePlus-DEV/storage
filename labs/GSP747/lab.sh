# 1. Biến môi trường
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
export REGION=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-region])")
export GITHUB_USERNAME=$(gh api user -q ".login")

# 2. Tạo kết nối GitHub (Cloud Build Connection)
gcloud builds connections create github cloud-build-connection \
  --project=$PROJECT_ID \
  --region=$REGION

# 3. Kiểm tra kết nối và lấy link actionUri để authorize
gcloud builds connections describe cloud-build-connection --region=$REGION
# 👉 Copy "actionUri" mở trong trình duyệt → Login GitHub → Authorize Cloud Build → chọn repo my_hugo_site

# 4. Tạo Cloud Build repository mapping
gcloud builds repositories create hugo-website-build-repository \
  --remote-uri="https://github.com/${GITHUB_USERNAME}/my_hugo_site.git" \
  --connection="cloud-build-connection" \
  --region=$REGION

# 5. Gán quyền cho Cloud Build service account
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$PROJECT_NUMBER@cloudbuild.gserviceaccount.com" \
  --role="roles/firebasehosting.admin"

# 6. Tạo Trigger build khi có commit lên branch main
gcloud builds triggers create github --name="commit-to-main-branch1" \
   --repository=projects/$PROJECT_ID/locations/$REGION/connections/cloud-build-connection/repositories/hugo-website-build-repository \
   --build-config='cloudbuild.yaml' \
   --service-account=projects/$PROJECT_ID/serviceAccounts/$PROJECT_NUMBER-compute@developer.gserviceaccount.com \
   --region=$REGION \
   --branch-pattern='^main$'

# 7. Test: commit & push để trigger chạy
cd ~/my_hugo_site
echo "# Test deploy" >> README.md
git add .
git commit -m "Test Cloud Build Trigger"
git push -u origin main

# 8. Xem log build
gcloud builds list --region=$REGION
gcloud builds log --region=$REG
