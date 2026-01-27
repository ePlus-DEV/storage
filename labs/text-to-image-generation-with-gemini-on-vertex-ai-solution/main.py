import os
import vertexai
from vertexai.generative_models import GenerativeModel, GenerationConfig

def get_chat_response(prompt: str) -> str:
    PROJECT_ID = "qwiklabs-gcp-04-00e01999fb87"
    LOCATION = "us-west1"
    if not PROJECT_ID:
        raise RuntimeError("Missing PROJECT_ID. Set GOOGLE_CLOUD_PROJECT or DEVSHELL_PROJECT_ID.")

    vertexai.init(project=PROJECT_ID, location=LOCATION)

    model = GenerativeModel("gemini-2.5-flash")

    config = GenerationConfig(
        temperature=0.7,
        max_output_tokens=1024,
        response_modalities=["TEXT", "IMAGE"],
    )

    response = model.generate_content(prompt)

    text_out = (getattr(response, "text", "") or "").strip()

    imgs = getattr(response, "generated_images", None)
    first_img = None
    if imgs is not None:
        try:
            first_img = next(iter(imgs), None)
        except TypeError:
            first_img = None

    if first_img is not None and hasattr(first_img, "image_bytes"):
        with open("output.png", "wb") as f:
            f.write(first_img.image_bytes)
        text_out += "\n[Image saved to: output.png]"

    return text_out

if __name__ == "__main__":
    prompt = (
        "You are an interactive science tutoring assistant.\n\n"
        "Question 1: Hello! What are all the colors in a rainbow?\n"
        "Question 2: What is Prism?\n\n"
        "After answering, generate an educational image showing a prism "
        "splitting white light into a rainbow."
    )
    print(get_chat_response(prompt))