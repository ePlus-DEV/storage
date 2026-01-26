#!/usr/bin/env python3
"""
Cymbal Solutions - Vertex AI Gemini chat + image generation demo
Model: gemini-2.5-flash
"""

import os
import base64
from typing import Optional

import vertexai
from vertexai.generative_models import GenerativeModel, GenerationConfig


def get_chat_response(prompt: str) -> str:
    """
    Invokes the Gemini model with the supplied prompt.
    Uses Gemini's multimodal capability to generate an image from text.

    Returns:
      A text response (and saves an image to disk if one is generated).
    """
    # Qwiklabs / Cloud Shell often provides these env vars automatically.
    project_id = os.environ.get("GOOGLE_CLOUD_PROJECT") or os.environ.get("DEVSHELL_PROJECT_ID")
    location = os.environ.get("GOOGLE_CLOUD_REGION") or os.environ.get("REGION") or "us-central1"

    if not project_id:
        raise RuntimeError(
            "Missing PROJECT_ID. Set GOOGLE_CLOUD_PROJECT or DEVSHELL_PROJECT_ID environment variable."
        )

    vertexai.init(project=project_id, location=location)

    model = GenerativeModel("gemini-2.5-flash")

    # Ask Gemini to generate both text + an image (if supported in your lab environment).
    # Some labs enable image outputs; if not, you'll still get text.
    config = GenerationConfig(
        temperature=0.7,
        max_output_tokens=1024,
        response_modalities=["TEXT", "IMAGE"],  # Request image generation
    )

    response = model.generate_content(prompt, generation_config=config)

    # Always return text if available
    text_out = getattr(response, "text", "") or ""

    # If an image was generated, save it as PNG
    # Depending on SDK version, images may be in response.generated_images
    image_saved_msg: Optional[str] = None
    try:
        imgs = getattr(response, "generated_images", None)
        if imgs:
            img_bytes = imgs[0].image_bytes
            out_path = "gemini_output.png"
            with open(out_path, "wb") as f:
                f.write(img_bytes)
            image_saved_msg = f"\n[Image saved to: {out_path}]"
    except Exception:
        # If the environment/model doesn't return images, ignore gracefully.
        pass

    if image_saved_msg:
        return (text_out.strip() + image_saved_msg).strip()

    return text_out.strip()


if __name__ == "__main__":
    questions = [
        "Hello! What are all the colors in a rainbow?",
        "What is Prism?",
    ]

    # Build a single prompt that includes both required questions and requests an AI image.
    prompt = (
        "You are a science tutoring assistant. Answer the questions clearly for a student.\n\n"
        f"Q1: {questions[0]}\n"
        f"Q2: {questions[1]}\n\n"
        "After answering, generate an AI image that illustrates a prism splitting white light into a rainbow.\n"
        "Keep the image simple, educational, and labeled."
    )

    result = get_chat_response(prompt)
    print(result)
