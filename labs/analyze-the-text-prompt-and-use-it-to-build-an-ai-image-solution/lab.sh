#!/bin/bash
# ==============================================
#  Google Cloud Challenge Lab
#  Task: Generate image using Vertex AI Imagen
# ==============================================

set -e

WORKDIR="/home/student"
PY_FILE="generate_image.py"

echo "=============================================="
echo "🚀 Starting Challenge Lab Script"
echo "📁 Working directory: $WORKDIR"
echo "=============================================="

cd "$WORKDIR"

echo "==> Creating Python file: $PY_FILE"

cat << 'PYEOF' > "$PY_FILE"
import vertexai
from vertexai.preview.vision_models import ImageGenerationModel

def generate_image(prompt: str):
    # Vertex AI init (project & region auto-configured in lab)
    vertexai.init()

    model = ImageGenerationModel.from_pretrained(
        "imagen-3.0-generate-002"
    )

    images = model.generate_images(
        prompt=prompt,
        number_of_images=1
    )

    images[0].save("image.jpeg")
    print("✅ Image generated and saved as image.jpeg")


if __name__ == "__main__":
    generate_image(
        "Create an image of a cricket ground in the heart of Los Angeles"
    )
PYEOF

echo "==> Running Python script..."
/usr/bin/python3 "$PY_FILE"

echo "=============================================="
echo "🎉 DONE! - ePlus.DEV"
echo "📷 Open EXPLORER → image.jpeg"
echo "✅ Now click: Check my progress"
echo "=============================================="