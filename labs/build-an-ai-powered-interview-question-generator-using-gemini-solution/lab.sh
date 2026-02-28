
cat <<'EOF' > lab.py

import vertexai
from vertexai.generative_models import GenerativeModel

def interview(prompt):
    vertexai.init()
    model = GenerativeModel("gemini-2.5-flash-lite")
    response = model.generate_content(prompt)
    return response.text

# Custom prompt example
if __name__ == "__main__":
    custom_prompt = input("Enter your prompt: ") or "Give me ten interview questions for the role of program manager."
    result = interview(custom_prompt)
    print("\n" + "="*50)
    print(result)
    print("="*50)
EOF

/usr/bin/python3 /lab.py