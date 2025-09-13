#!/bin/bash

# Định nghĩa màu
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
BOLD=$(tput bold)
RESET=$(tput sgr0)

# 0. Biến môi trường
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
export REGION=$(gcloud compute project-info describe \
--format="value(commonInstanceMetadata.items[google-compute-default-region])")
export GITHUB_USERNAME=$(gh api user -q ".login")

echo "${CYAN}${BOLD}==> Project: $PROJECT_ID | Number: $PROJECT_NUMBER | Region: $REGION${RESET}"

# 1. Tạo GitHub repo nếu chưa có
echo "${YELLOW}Tạo repo GitHub my_hugo_site (nếu chưa tồn tại)...${RESET}"
gh repo create my_hugo_site --private || true
gh repo clone my_hugo_site || true
cd my_hugo_site

# 2. Commit ban đầu (nếu repo rỗng)
echo "${YELLOW}Commit ban đầu...${RESET}"
/tmp/hugo new site . --force || true
git add .
git commit -m "Initial commit for Hugo site" || true
git push -u origin main || true

# 3. Xóa connection cũ (nếu có)
gcloud builds connections delete cloud-build-connection --region=$REGION --quiet || true

# 4. Tạo lại connection GitHub
echo "${YELLOW}Tạo Cloud Build GitHub connection...${RESET}"
gcloud builds connections create github cloud-build-connection \
  --project=$PROJECT_ID \
  --region=$REGION

# 5. In ra actionUri để authorize
ACTION_URI=$(gcloud builds connections describe cloud-build-connection --region=$REGION --format="value(installationState.actionUri)")

echo ""
echo "${RED}${BOLD}🔗 COPY LINK DƯỚI ĐÂY VÀ MỞ TRÊN TRÌNH DUYỆT:${RESET}"
echo "${CYAN}${BOLD}$ACTION_URI${RESET}"
echo ""
echo "${YELLOW}⚠️ Dừng lại ở đây! Mở link trên trình duyệt → Login GitHub → Install Cloud Build App → Chọn repo: my_hugo_site${RESET}"
echo "${GREEN}👉 Sau khi authorize xong, nhấn ENTER để tiếp tục...${RESET}"
read

# 6. Tạo repository mapping cho Cloud Build
echo "${YELLOW}Tạo Cloud Build repository mapping...${RESET}"
gcloud builds repositories create hugo-website-build-repository \
  --remote-uri="https://github.com/${GITHUB_USERNAME}/my_hugo_site.git" \
  --connection="cloud-build-connection" \
  --region=$REGION

# 7. Gán quyền Firebase Hosting Admin cho Cloud Build
echo "${YELLOW}Thêm quyền Firebase Hosting Admin cho Cloud Build service account...${RESET}"
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$PROJECT_NUMBER@cloudbuild.gserviceaccount.com" \
  --role="roles/firebasehosting.admin"

# 8. Tạo Trigger build tự động khi push lên branch main
echo "${YELLOW}Tạo Trigger Cloud Build...${RESET}"
gcloud builds triggers create github --name="commit-to-main-branch1" \
   --repository=projects/$PROJECT_ID/locations/$REGION/connections/cloud-build-connection/repositories/hugo-website-build-repository \
   --build-config='cloudbuild.yaml' \
   --service-account=projects/$PROJECT_ID/serviceAccounts/$PROJECT_NUMBER-compute@developer.gserviceaccount.com \
   --region=$REGION \
   --branch-pattern='^main$'

# 9. Test commit
echo "${YELLOW}Test pipeline: commit nhỏ để trigger chạy...${RESET}"
echo "# Test deploy" >> README.md
git add README.md
git commit -m "Trigger test from script"
git push origin main

# 10. Xem build log
echo "${GREEN}Xem build list...${RESET}"
gcloud builds list --region=$REGION
