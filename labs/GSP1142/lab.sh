#!/bin/bash
# ==============================================
# Full Automation for Document AI Custom Extractor Lab (GSP1142)
# ==============================================

echo "==============================================="
echo "👉 https://eplus.dev"
echo "==============================================="
echo ""


export ZONE=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
export REGION=$(gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])")
export PROJECT_ID=$(gcloud config get-value project)

# ----------------------------------------------
# 2. Enable API & Install SDK
# ----------------------------------------------
echo ""
echo "🔹 Enabling Document AI API..."
gcloud services enable documentai.googleapis.com

echo "🔹 Installing Python SDK (if needed)..."
pip3 install --upgrade google-cloud-documentai

# ----------------------------------------------
# 3. Download Required Data (Error-Free)
# ----------------------------------------------
echo "🔹 Preparing local data folders and downloading content..."

mkdir -p ./AutoLabel
mkdir -p ./JSON-2

echo " · Downloading sample W-2 document"
gcloud storage cp gs://cloud-samples-data/documentai/Custom/W2/PDF/W2_XL_input_clean_2950.pdf ./ || exit 1

echo " · Downloading AutoLabel dataset"
gcloud storage cp -r gs://cloud-samples-data/documentai/Custom/W2/AutoLabel/* ./AutoLabel/ || exit 1

echo " · Downloading Prelabeled JSON-2 dataset"
gcloud storage cp -r gs://cloud-samples-data/documentai/Custom/W2/JSON-2/* ./JSON-2/ || exit 1

echo "✅ All required files are now downloaded and ready."
echo ""

# ----------------------------------------------
# 4. Instructions for Manual Steps in Console UI
# ----------------------------------------------
echo "============= NEXT STEPS (Manual in Console UI) ============="
echo "1️⃣ Go to Google Cloud Console → Navigation → Document AI → Workbench"
echo "2️⃣ Click 'Create Custom Processor' → Choose 'Custom Extractor'"
echo "   - Name: lab-custom-extractor"
echo "   - Location: $LOCATION"
echo "3️⃣ Define schema fields (one by one):"
echo "   • control_number (Number, Optional multiple)"
echo "   • employees_social_security_number (Number, Required multiple)"
echo "   • employer_identification_number (Number, Required multiple)"
echo "   • employers_name_address_and_zip_code (Address, Required multiple)"
echo "   • federal_income_tax_withheld (Money, Required multiple)"
echo "   • social_security_tax_withheld (Money, Required multiple)"
echo "   • social_security_wages (Money, Required multiple)"
echo "   • wages_tips_other_compensation (Money, Required multiple)"
echo "4️⃣ Upload sample W-2 PDF and label it"
echo "5️⃣ Build processor version using Foundation model → 'w2-foundation-model'"
echo "6️⃣ Import AutoLabel data from './AutoLabel/' with auto-labeling ON"
echo "7️⃣ Import Prelabeled data from './JSON-2/' with Auto-split"
echo "8️⃣ Train a new custom model version → Name it 'w2-custom-model'"
echo "============================================================="
echo ""

# ----------------------------------------------
# YouTube Subscribe Reminder (End)
# ----------------------------------------------
echo "==============================================="
echo "✅ Prep complete! Time to follow through the UI steps above."
echo "👉 https://eplus.dev"
echo "==============================================="