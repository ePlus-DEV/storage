
cat <<'EOF' > lab.py

#!/usr/bin/python3
import vertexai
from vertexai.generative_models import GenerativeModel

# Prompt required by the lab
PROMPT = "Give me ten interview questions for the role of program manager."

def interview(prompt: str) -> str:
    """
    Invoke Vertex AI Gemini model (gemini-2.5-flash-lite) with the supplied prompt
    and return the generated text response.
    """
    # Auto-detect project and region from the gcloud environment (Qwiklabs usually sets these)
    project_id = None
    location = None
    try:
        import subprocess
        project_id = subprocess.check_output(
            ["gcloud", "config", "get-value", "project"],
            text=True
        ).strip()
        location = subprocess.check_output(
            ["gcloud", "config", "get-value", "ai/region"],
            text=True
        ).strip()
    except Exception:
        pass

    # Sensible defaults for most labs if ai/region isn't set
    if not project_id:
        raise RuntimeError("Could not detect GCP project. Run: gcloud config get-value project")
    if not location or location == "(unset)":
        location = "us-central1"

    vertexai.init(project=project_id, location=location)

    model = GenerativeModel("gemini-2.5-flash-lite")
    response = model.generate_content(
        prompt,
        generation_config={
            "temperature": 0.7,
            "max_output_tokens": 512,
        },
    )

    # Return the text output
    return response.text if hasattr(response, "text") else str(response)

if __name__ == "__main__":
    print(interview(PROMPT))

/usr/bin/python3 lab.py