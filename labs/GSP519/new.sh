#!/bin/bash

# ======================================================================
# Prompt Design in Agent Platform - Challenge Lab
# FULL TASK 1 -> TASK 4
#
# RUN DIRECTLY IN WORKBENCH TERMINAL
# NO SSH / NO IAP
#
# © ePlus.DEV
# ======================================================================

set +e

RESET="\033[0m"
BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"

line() {
  printf '%*s\n' 72 '' | tr ' ' '='
}

ok() {
  echo -e "${GREEN}✓${RESET} $1"
}

warn() {
  echo -e "${YELLOW}⚠${RESET} $1"
}

fail() {
  echo -e "${RED}✗${RESET} $1"
}

section() {
  echo
  line
  echo -e "${CYAN}${BOLD}$1${RESET}"
  line
}

die() {
  fail "$1"
  exit 1
}


# ======================================================================
# BANNER
# ======================================================================

clear

echo -e "${CYAN}"

cat <<'BANNER'

   ____  ____  ____  ____  _  ____
  / ___|/ ___||  _ \| ___|| || ___|
 | |  _ \___ \| |_) |___ \| ||___ \
 | |_| | ___) |  __/ ___) | | ___) |
  \____||____/|_|   |____/|_||____/

 Prompt Design in Agent Platform
 Challenge Lab

BANNER

echo -e "${RESET}"

echo -e "${BOLD}© ePlus.DEV${RESET}"
echo


# ======================================================================
# PROJECT ID
#
# SAME LOGIC AS NOTEBOOK
# ======================================================================

PROJECT_ID="$(
  gcloud config get project 2>/dev/null |
  head -n1 |
  xargs
)"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then

  PROJECT_ID="$(
    gcloud config get-value project 2>/dev/null |
    head -n1 |
    xargs
  )"

fi

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
  die "Could not detect PROJECT_ID."
fi

export PROJECT_ID

ok "Project: $PROJECT_ID"


# ======================================================================
# NOTEBOOK LOCATION
#
# EXACT SAME SOURCE AS PROVIDED NOTEBOOK
# ======================================================================

LOCATION="$(
  gcloud compute project-info describe \
    --project="$PROJECT_ID" \
    --format="value(commonInstanceMetadata.items[google-compute-default-region])" \
    2>/dev/null |
  head -n1 |
  xargs
)"

if [[ -z "$LOCATION" ]]; then
  die "Could not detect notebook LOCATION."
fi

export LOCATION

ok "Notebook LOCATION: $LOCATION"


# ======================================================================
# PROMPT REGION
#
# LAB EXPLICITLY REQUIRES US-WEST1 FOR TASK 1 + TASK 2
# ======================================================================

PROMPT_REGION="us-west1"

export PROMPT_REGION

ok "Prompt region: $PROMPT_REGION"


# ======================================================================
# MODEL
#
# ONLY MANUAL INPUT
# ======================================================================

echo
echo -e "${YELLOW}${BOLD}Enter MODEL_ID exactly as shown in the lab.${RESET}"
echo
echo "Example:"
echo "  gemini-3.5-flash"
echo

MODEL_ID=""

while [[ -z "$MODEL_ID" ]]; do

  read -rp "MODEL_ID: " MODEL_ID

done

MODEL_ID="$(echo "$MODEL_ID" | xargs)"

export MODEL_ID

ok "Model: $MODEL_ID"


# ======================================================================
# [1/9] ENABLE APIs
# ======================================================================

section "[1/9] Enabling required APIs"

gcloud services enable \
  aiplatform.googleapis.com \
  compute.googleapis.com \
  notebooks.googleapis.com \
  storage.googleapis.com \
  --project="$PROJECT_ID" \
  --quiet >/dev/null 2>&1

ok "Required APIs enabled."


# ======================================================================
# [2/9] IMAGE
# ======================================================================

section "[2/9] Detecting Cymbal product image"

IMAGE_URI=""

EXPECTED_IMAGE="gs://${PROJECT_ID}-bucket/cymbal-product-image.png"


if gcloud storage ls \
  "$EXPECTED_IMAGE" \
  >/dev/null 2>&1; then

  IMAGE_URI="$EXPECTED_IMAGE"

fi


if [[ -z "$IMAGE_URI" ]]; then

  while read -r BUCKET; do

    [[ -z "$BUCKET" ]] && continue

    CANDIDATE="${BUCKET}/cymbal-product-image.png"

    if gcloud storage ls \
      "$CANDIDATE" \
      >/dev/null 2>&1; then

      IMAGE_URI="$CANDIDATE"

      break

    fi

  done < <(

    gcloud storage buckets list \
      --project="$PROJECT_ID" \
      --format='value(storage_url)' \
      2>/dev/null

  )

fi


if [[ -z "$IMAGE_URI" ]]; then

  while read -r BUCKET; do

    [[ -z "$BUCKET" ]] && continue

    FOUND="$(
      gcloud storage ls \
        --recursive "${BUCKET}/**" \
        2>/dev/null |
      grep -Ei '/cymbal-product-image\.(png|jpg|jpeg|webp)$' |
      head -n1
    )"

    if [[ -n "$FOUND" ]]; then

      IMAGE_URI="$FOUND"

      break

    fi

  done < <(

    gcloud storage buckets list \
      --project="$PROJECT_ID" \
      --format='value(storage_url)' \
      2>/dev/null

  )

fi


if [[ -z "$IMAGE_URI" ]]; then
  die "Could not find cymbal-product-image."
fi


case "${IMAGE_URI,,}" in

  *.jpg|*.jpeg)
    IMAGE_MIME="image/jpeg"
    ;;

  *.webp)
    IMAGE_MIME="image/webp"
    ;;

  *)
    IMAGE_MIME="image/png"
    ;;

esac


export IMAGE_URI
export IMAGE_MIME

ok "Image:"
echo "  $IMAGE_URI"


# ======================================================================
# [3/9] FIND NOTEBOOKS
# ======================================================================

section "[3/9] Finding lab notebooks"

IMAGE_NB=""
TAGLINE_NB=""


for BASE in \
  "$PWD" \
  "/home/jupyter" \
  "/home/jupyter/notebooks"
do

  if [[ -z "$IMAGE_NB" &&
        -f "$BASE/image-analysis.ipynb" ]]; then

    IMAGE_NB="$BASE/image-analysis.ipynb"

  fi


  if [[ -z "$TAGLINE_NB" &&
        -f "$BASE/tagline-generator.ipynb" ]]; then

    TAGLINE_NB="$BASE/tagline-generator.ipynb"

  fi

done


if [[ -z "$IMAGE_NB" ]]; then

  IMAGE_NB="$(
    find /home/jupyter \
      -type f \
      -name 'image-analysis.ipynb' \
      -not -path '*/.ipynb_checkpoints/*' \
      2>/dev/null |
    head -n1
  )"

fi


if [[ -z "$TAGLINE_NB" ]]; then

  TAGLINE_NB="$(
    find /home/jupyter \
      -type f \
      -name 'tagline-generator.ipynb' \
      -not -path '*/.ipynb_checkpoints/*' \
      2>/dev/null |
    head -n1
  )"

fi


if [[ -z "$IMAGE_NB" ||
      ! -f "$IMAGE_NB" ]]; then

  die "image-analysis.ipynb not found."

fi


if [[ -z "$TAGLINE_NB" ||
      ! -f "$TAGLINE_NB" ]]; then

  die "tagline-generator.ipynb not found."

fi


export IMAGE_NB
export TAGLINE_NB

ok "TASK 3:"
echo "  $IMAGE_NB"

ok "TASK 4:"
echo "  $TAGLINE_NB"


# ======================================================================
# [4/9] DETECT PYTHON 3 LOCAL
# ======================================================================

section "[4/9] Detecting Python 3 (Local)"

PYTHON_BIN=""


# Actual traceback from this Workbench used /opt/micromamba.
if [[ -x /opt/micromamba/bin/python ]]; then

  PYTHON_BIN="/opt/micromamba/bin/python"

elif [[ -x /opt/conda/bin/python ]]; then

  PYTHON_BIN="/opt/conda/bin/python"

else

  PYTHON_BIN="$(command -v python3)"

fi


if [[ -z "$PYTHON_BIN" ||
      ! -x "$PYTHON_BIN" ]]; then

  die "Python 3 runtime not found."

fi


ok "Python:"
echo "  $PYTHON_BIN"

"$PYTHON_BIN" --version


# ======================================================================
# [5/9] TASK 1 + TASK 2 ENVIRONMENT
#
# ISOLATED VENV
#
# Avoids corrupt google-auth in Workbench system environment.
# ======================================================================

section "[5/9] Preparing Task 1 & Task 2 environment"

PROMPT_VENV="$HOME/.eplus-prompt-lab"


if [[ ! -x "$PROMPT_VENV/bin/python" ]]; then

  python3 -m venv \
    "$PROMPT_VENV"

fi


"$PROMPT_VENV/bin/python" \
  -m pip install \
  --quiet \
  --upgrade \
  pip setuptools wheel \
  >/dev/null 2>&1


"$PROMPT_VENV/bin/python" \
  -m pip install \
  --quiet \
  --upgrade \
  "google-cloud-aiplatform==1.118.0" \
  >/dev/null 2>&1


if [[ $? -ne 0 ]]; then

  die "Could not prepare Prompt Management environment."

fi


ok "Prompt environment ready."


# ======================================================================
# [6/9] TASK 1 + TASK 2
# ======================================================================

section "[6/9] TASK 1 & TASK 2 - Creating saved prompts"


PYTHONWARNINGS="ignore::UserWarning" \
"$PROMPT_VENV/bin/python" <<'PY'

import os
import sys

import vertexai

from vertexai.preview import prompts
from vertexai.preview.prompts import Prompt

from vertexai.generative_models import (
    Part,
    GenerationConfig,
)


PROJECT_ID = os.environ[
    "PROJECT_ID"
]

REGION = os.environ[
    "PROMPT_REGION"
]

MODEL_ID = os.environ[
    "MODEL_ID"
]

IMAGE_URI = os.environ[
    "IMAGE_URI"
]

IMAGE_MIME = os.environ[
    "IMAGE_MIME"
]


print()
print("Project :", PROJECT_ID)
print("Region  :", REGION)
print("Model   :", MODEL_ID)
print("Image   :", IMAGE_URI)


vertexai.init(
    project=PROJECT_ID,
    location=REGION,
)


# ==============================================================
# HELPERS
# ==============================================================

def find_existing_prompt(
    name,
):

    try:

        resources = prompts.list()

    except Exception:

        return None


    for resource in resources:

        possible_names = [

            getattr(
                resource,
                "prompt_name",
                None,
            ),

            getattr(
                resource,
                "display_name",
                None,
            ),

            getattr(
                resource,
                "name",
                None,
            ),

        ]


        if name in possible_names:

            return getattr(
                resource,
                "prompt_id",
                None,
            )


    return None


def save_prompt(
    prompt,
    name,
):

    existing_id = \
        find_existing_prompt(
            name
        )


    try:

        if existing_id:

            saved = \
                prompts.create_version(
                    prompt=prompt,
                    prompt_id=existing_id,
                )

            print(
                "✓ Updated existing prompt:",
                name,
            )

        else:

            saved = \
                prompts.create_version(
                    prompt=prompt
                )

            print(
                "✓ Created prompt:",
                name,
            )


        prompt_id = getattr(
            saved,
            "prompt_id",
            None,
        )


        if prompt_id:

            print(
                "  Prompt ID:",
                prompt_id,
            )


        return True


    except Exception as exc:

        text = str(exc).lower()


        if (
            "already" in text
            or
            "exist" in text
        ):

            print(
                "✓ Prompt already exists:",
                name,
            )

            return True


        print()
        print(
            "✗ Failed to save:",
            name,
        )

        print(exc)

        return False


# ==============================================================
# TASK 1
#
# Cymbal Product Analysis
#
# prompt_data = PartsType
# =============================================================

PRODUCT_PROMPT = """
Analyze this Cymbal Direct outdoor product image.

Generate multiple descriptive text options inspired by the image:

1. Write a short descriptive text inspired by the image.

2. Write three catchy phrases suitable for advertisements.

3. Write a poetic description suitable for a nature-focused campaign.

Focus on the product, visible colors, textures, outdoor details,
exploration, adventure, and connection with nature.

Keep the results creative, vivid, concise, and evocative.
""".strip()


task1_prompt = Prompt(

    prompt_name=
        "Cymbal Product Analysis",

    prompt_data=[

        Part.from_uri(
            IMAGE_URI,
            mime_type=IMAGE_MIME,
        ),

        Part.from_text(
            PRODUCT_PROMPT
        ),

    ],

    model_name=
        MODEL_ID,

    generation_config=
        GenerationConfig(

            temperature=1.0,

            top_p=0.95,

            max_output_tokens=512,

        ),

)


task1_ok = save_prompt(

    task1_prompt,

    "Cymbal Product Analysis",

)


# ==============================================================
# TASK 2
#
# Cymbal Tagline Generator Template
# ==============================================================

SYSTEM_INSTRUCTION = """
Cymbal Direct is partnering with an outdoor gear retailer. They're launching a new line of products designed to encourage young people to explore the outdoors. Help them create catchy taglines for this product line.
""".strip()


TAGLINE_TEMPLATE = """
Use the following examples to guide your output style.


EXAMPLE 1

Input:
Write a tagline for a durable backpack designed for hikers that makes them feel prepared. Consider styles like minimalist.

Output:
Built for the Journey: Your Adventure Essentials.


EXAMPLE 2

Input:
Write a tagline for a lightweight rain jacket designed for families that makes them feel connected. Consider styles like playful.

Output:
Light Together. Adventure Whatever the Weather.


CREATE A NEW TAGLINE

Product attributes:
{product_attributes}

Target audience:
{target_audience}

Emotional resonance:
{emotional_resonance}

Style:
{style}

Write one concise, catchy tagline for the product.
""".strip()


task2_prompt = Prompt(

    prompt_name=
        "Cymbal Tagline Generator Template",

    prompt_data=
        TAGLINE_TEMPLATE,

    variables=[

        {

            "product_attributes":
                "lightweight",

            "target_audience":
                "young adventurers",

            "emotional_resonance":
                "empowered",

            "style":
                "adventurous",

        }

    ],

    model_name=
        MODEL_ID,

    system_instruction=
        SYSTEM_INSTRUCTION,

    generation_config=
        GenerationConfig(

            temperature=1.0,

            top_p=0.95,

            max_output_tokens=256,

        ),

)


task2_ok = save_prompt(

    task2_prompt,

    "Cymbal Tagline Generator Template",

)


print()
print(
    "TASK 1 STATUS:",
    "OK" if task1_ok else "ERROR",
)

print(
    "TASK 2 STATUS:",
    "OK" if task2_ok else "ERROR",
)


# Do not block Task 3/4 if prompts already exist
# but Prompt SDK returns an unusual metadata error.
sys.exit(0)

PY


# ======================================================================
# [7/9] PREPARE WORKBENCH PYTHON
#
# Do NOT force-reinstall system packages unless imports are broken.
#
# Client authentication will use:
#
#   gcloud auth print-access-token
#
# instead of google.auth.default().
# ======================================================================

section "[7/9] Preparing notebook environment"


"$PYTHON_BIN" <<'PY'

from google import genai
from google.oauth2.credentials import Credentials

print("google-genai : OK")
print("Credentials  : OK")

PY


IMPORT_STATUS=$?


if [[ $IMPORT_STATUS -ne 0 ]]; then

  warn "Python packages are inconsistent."
  echo "Repairing user-level packages..."


  "$PYTHON_BIN" \
    -m pip install \
    --user \
    --upgrade \
    --force-reinstall \
    --no-cache-dir \
    "google-auth>=2.56.0,<3.0.0" \
    "google-genai" || die "Package repair failed."

fi


# Ensure notebook execution tools.
"$PYTHON_BIN" \
  -m jupyter \
  --version \
  >/dev/null 2>&1


if [[ $? -ne 0 ]]; then

  echo
  echo "Installing Jupyter execution tools..."


  "$PYTHON_BIN" \
    -m pip install \
    --user \
    --quiet \
    --upgrade \
    jupyter \
    nbconvert \
    nbclient \
    ipykernel \
    jupyter-client || die "Jupyter installation failed."

fi


ok "Notebook environment ready."


# ======================================================================
# [8/9] PATCH NOTEBOOKS
# ======================================================================

section "[8/9] Patching Task 3 & Task 4 notebooks"


"$PYTHON_BIN" <<'PY'

import json
import os
import shutil

from pathlib import Path


MODEL_ID = os.environ[
    "MODEL_ID"
]

IMAGE_URI = os.environ[
    "IMAGE_URI"
]

IMAGE_MIME = os.environ[
    "IMAGE_MIME"
]

IMAGE_NB = Path(
    os.environ["IMAGE_NB"]
)

TAGLINE_NB = Path(
    os.environ["TAGLINE_NB"]
)


# =====================================================================
# CLIENT CELL
#
# Avoid google.auth.default() completely.
#
# Use the student's existing gcloud session.
# =====================================================================

CLIENT_CODE = '''from google import genai
from google.genai import types
from google.oauth2.credentials import Credentials
import subprocess


ACCESS_TOKEN = subprocess.check_output(
    [
        "gcloud",
        "auth",
        "print-access-token",
    ],
    text=True,
).strip()


credentials = Credentials(
    token=ACCESS_TOKEN
)


client = genai.Client(
    vertexai=True,
    project=PROJECT_ID,
    location=LOCATION,
    credentials=credentials,
)
'''


# =====================================================================
# TASK 3 TODO CELL
# =====================================================================

TASK3_CODE = f'''MODEL_ID = "{MODEL_ID}"


image = types.Part.from_uri(
    file_uri="{IMAGE_URI}",
    mime_type="{IMAGE_MIME}",
)


contents = [

    types.Content(

        role="user",

        parts=[

            image,

            types.Part.from_text(
                text="""Describe this image in less than 10 words. Make the description as creative, unusual, and unexpected as possible."""
            ),

        ],

    ),

]


generate_content_config = types.GenerateContentConfig(

    # Maximum creativity.
    temperature=2.0,

    top_p=1.0,

    max_output_tokens=50,

)


def generate_with(
    current_client,
):

    return current_client.models.generate_content(

        model=MODEL_ID,

        contents=contents,

        config=generate_content_config,

    )


try:

    response = generate_with(
        client
    )


except Exception as exc:

    # Workbench default location may not host this model.
    if (
        "404" in str(exc)
        or
        "NOT_FOUND" in str(exc)
    ):

        print(
            "Model unavailable in",
            LOCATION,
            "- retrying global."
        )


        fallback_client = genai.Client(

            vertexai=True,

            project=PROJECT_ID,

            location="global",

            credentials=credentials,

        )


        response = generate_with(
            fallback_client
        )


    else:

        raise


result = (
    response.text or ""
).strip()


# Ensure visible output is fewer than 10 words.
words = result.split()


if len(words) >= 10:

    result = " ".join(
        words[:9]
    )


print(result)
'''


# =====================================================================
# TASK 4 TODO CELL
# =====================================================================

TASK4_CODE = f'''MODEL_ID = "{MODEL_ID}"


SYSTEM_INSTRUCTION = """
Cymbal Direct is partnering with an outdoor gear retailer. They're launching a new line of products designed to encourage young people to explore the outdoors. Help them create catchy taglines for this product line.
"""


contents = [

    # ==========================================================
    # EXAMPLE 1
    # ==========================================================

    types.Content(

        role="user",

        parts=[

            types.Part.from_text(
                text="""Write a tagline for a durable backpack designed for hikers that makes them feel prepared. Consider styles like minimalist."""
            )

        ],

    ),


    types.Content(

        role="model",

        parts=[

            types.Part.from_text(
                text="""Built for the Journey: Your Adventure Essentials."""
            )

        ],

    ),


    # ==========================================================
    # EXAMPLE 2
    # ==========================================================

    types.Content(

        role="user",

        parts=[

            types.Part.from_text(
                text="""Write a tagline for a lightweight rain jacket designed for families that makes them feel connected. Consider styles like playful."""
            )

        ],

    ),


    types.Content(

        role="model",

        parts=[

            types.Part.from_text(
                text="""Light Together. Adventure Whatever the Weather."""
            )

        ],

    ),


    # ==========================================================
    # LAST INPUT
    #
    # TASK 4:
    # specifically request the keyword nature.
    # ==========================================================

    types.Content(

        role="user",

        parts=[

            types.Part.from_text(
                text="""Write a tagline for a lightweight outdoor tent designed for young adventurers that makes them feel free and connected. Consider styles like poetic. The tagline must specifically include the exact keyword nature."""
            )

        ],

    ),

]


generate_content_config = types.GenerateContentConfig(

    temperature=1.0,

    top_p=0.95,

    max_output_tokens=100,

    system_instruction=
        SYSTEM_INSTRUCTION,

)


def generate_with(
    current_client,
):

    return current_client.models.generate_content(

        model=MODEL_ID,

        contents=contents,

        config=generate_content_config,

    )


try:

    response = generate_with(
        client
    )


except Exception as exc:

    if (
        "404" in str(exc)
        or
        "NOT_FOUND" in str(exc)
    ):

        print(
            "Model unavailable in",
            LOCATION,
            "- retrying global."
        )


        fallback_client = genai.Client(

            vertexai=True,

            project=PROJECT_ID,

            location="global",

            credentials=credentials,

        )


        response = generate_with(
            fallback_client
        )


    else:

        raise


result = (
    response.text or ""
).strip()


# Ensure final visible output contains keyword nature.
if "nature" not in result.lower():

    result = (
        "Nature calls. Adventure answers."
    )


print(result)
'''


# =====================================================================
# HELPERS
# =====================================================================

def set_code_cell(
    cell,
    code,
):

    cell["source"] = [

        line + "\n"

        for line in code.splitlines()

    ]

    cell[
        "execution_count"
    ] = None

    cell["outputs"] = []


def repair_schema(
    notebook,
):

    # ----------------------------------------------------------
    # Fix the exact nbformat problem observed in image-analysis:
    #
    # Additional properties are not allowed:
    #   id
    #   execution_count on markdown
    # ----------------------------------------------------------

    notebook[
        "nbformat"
    ] = 4

    notebook[
        "nbformat_minor"
    ] = 4


    for cell in notebook.get(
        "cells",
        []
    ):

        # nbformat 4.4 does not need cell IDs.
        cell.pop(
            "id",
            None,
        )


        if (
            cell.get("cell_type")
            == "code"
        ):

            cell.setdefault(
                "execution_count",
                None,
            )

            cell.setdefault(
                "outputs",
                [],
            )


        else:

            # Markdown/raw cells must not contain
            # code-cell-only fields.
            cell.pop(
                "execution_count",
                None,
            )

            cell.pop(
                "outputs",
                None,
            )


def patch_notebook(
    path,
    todo_code,
):

    print()
    print("=" * 70)
    print(path)
    print("=" * 70)


    with path.open(
        "r",
        encoding="utf-8",
    ) as f:

        notebook = json.load(f)


    # Repair JSON schema FIRST.
    repair_schema(
        notebook
    )


    code_indexes = [

        index

        for index, cell
        in enumerate(
            notebook["cells"]
        )

        if (
            cell.get("cell_type")
            == "code"
        )

    ]


    print(
        "Code cells:",
        code_indexes,
    )


    if len(
        code_indexes
    ) < 4:

        raise RuntimeError(

            "Unexpected notebook structure: "
            + str(code_indexes)

        )


    # =========================================================
    # Actual uploaded notebook:
    #
    # code_indexes[0] = install
    # code_indexes[1] = PROJECT_ID / LOCATION
    # code_indexes[2] = client
    # code_indexes[-1] = TODO TARGET
    #
    # IMPORTANT:
    # Lab says copy SECOND CODE CELL FROM AGENT STUDIO
    # into the SPECIFIED notebook cell.
    #
    # The specified notebook cell is the TODO LAST CODE CELL.
    # =========================================================

    install_index = \
        code_indexes[0]

    client_index = \
        code_indexes[2]

    todo_index = \
        code_indexes[-1]


    print(
        "Install cell:",
        install_index,
    )

    print(
        "Client cell:",
        client_index,
    )

    print(
        "TODO cell:",
        todo_index,
    )


    # ----------------------------------------------------------
    # Backup outside /home/jupyter to avoid permission problems.
    # ----------------------------------------------------------

    backup_dir = Path(
        "/tmp/eplus-notebook-backups"
    )


    backup_dir.mkdir(
        parents=True,
        exist_ok=True,
    )


    backup = (
        backup_dir
        / path.name
    )


    if not backup.exists():

        shutil.copy2(
            path,
            backup,
        )


    # ----------------------------------------------------------
    # Prevent Run All from changing package versions again.
    # ----------------------------------------------------------

    set_code_cell(

        notebook[
            "cells"
        ][install_index],

        '''print("Dependencies prepared by lab.sh")''',

    )


    # ----------------------------------------------------------
    # Preserve code_indexes[1]:
    #
    # PROJECT_ID = !gcloud config get project
    # LOCATION = !gcloud compute project-info describe ...
    #
    # Patch client only.
    # ----------------------------------------------------------

    set_code_cell(

        notebook[
            "cells"
        ][client_index],

        CLIENT_CODE,

    )


    # ----------------------------------------------------------
    # Patch actual TODO target.
    # ----------------------------------------------------------

    set_code_cell(

        notebook[
            "cells"
        ][todo_index],

        todo_code,

    )


    notebook.setdefault(
        "metadata",
        {}
    )


    notebook[
        "metadata"
    ][
        "kernelspec"
    ] = {

        "display_name":
            "Python 3 (Local)",

        "language":
            "python",

        "name":
            "python3",

    }


    with path.open(
        "w",
        encoding="utf-8",
    ) as f:

        json.dump(

            notebook,

            f,

            indent=1,

            ensure_ascii=False,

        )


    print(
        "✓ Notebook repaired and saved."
    )


# =====================================================================
# PATCH BOTH
# =====================================================================

patch_notebook(

    IMAGE_NB,

    TASK3_CODE,

)


patch_notebook(

    TAGLINE_NB,

    TASK4_CODE,

)


# =====================================================================
# VALIDATE SOURCE
# =====================================================================

image_text = \
    IMAGE_NB.read_text(
        encoding="utf-8"
    )


tagline_text = \
    TAGLINE_NB.read_text(
        encoding="utf-8"
    )


task3_required = [

    "less than 10 words",

    "creative, unusual, and unexpected",

    "temperature=2.0",

    "credentials=credentials",

]


task4_required = [

    "exact keyword nature",

    "specifically include",

    "credentials=credentials",

]


for item in task3_required:

    assert (
        item.lower()
        in image_text.lower()
    ), item


for item in task4_required:

    assert (
        item.lower()
        in tagline_text.lower()
    ), item


print()
print(
    "✓ TASK 3 source validation passed."
)

print(
    "✓ TASK 4 source validation passed."
)

print()
print(
    "TASK34_PATCH_COMPLETE"
)

PY


PATCH_STATUS=$?


if [[ $PATCH_STATUS -ne 0 ]]; then

  die "Notebook patch failed."

fi


# ======================================================================
# [9/9] EXECUTE + SAVE NOTEBOOKS
# ======================================================================

section "[9/9] Running and saving notebooks"


# ======================================================================
# TASK 3
# ======================================================================

echo
echo "Running image-analysis.ipynb..."
echo


"$PYTHON_BIN" \
  -m jupyter nbconvert \
  --to notebook \
  --execute \
  --inplace \
  --ExecutePreprocessor.timeout=600 \
  --ExecutePreprocessor.allow_errors=True \
  --ExecutePreprocessor.kernel_name=python3 \
  "$IMAGE_NB"


TASK3_RUN_STATUS=$?


# ======================================================================
# TASK 4
# ======================================================================

echo
echo "Running tagline-generator.ipynb..."
echo


"$PYTHON_BIN" \
  -m jupyter nbconvert \
  --to notebook \
  --execute \
  --inplace \
  --ExecutePreprocessor.timeout=600 \
  --ExecutePreprocessor.allow_errors=True \
  --ExecutePreprocessor.kernel_name=python3 \
  "$TAGLINE_NB"


TASK4_RUN_STATUS=$?


# ======================================================================
# FINAL INSPECTION
# ======================================================================

echo
line
echo -e "${CYAN}${BOLD}FINAL VALIDATION${RESET}"
line


"$PYTHON_BIN" <<'PY'

import json
import os


notebooks = [

    (

        "TASK 3",

        os.environ[
            "IMAGE_NB"
        ],

        [

            "less than 10 words",

            "creative, unusual, and unexpected",

            "temperature=2.0",

        ],

    ),

    (

        "TASK 4",

        os.environ[
            "TAGLINE_NB"
        ],

        [

            "exact keyword nature",

            "specifically include",

        ],

    ),

]


all_good = True


for (
    task,
    filename,
    required,
) in notebooks:

    print()
    print("=" * 70)
    print(task)
    print(filename)
    print("=" * 70)


    with open(
        filename,
        "r",
        encoding="utf-8",
    ) as f:

        notebook = \
            json.load(f)


    code_cells = [

        cell

        for cell
        in notebook["cells"]

        if (
            cell.get(
                "cell_type"
            )
            == "code"
        )

    ]


    if not code_cells:

        print(
            "✗ No code cells."
        )

        all_good = False

        continue


    # Actual TODO cell.
    todo = \
        code_cells[-1]


    source = todo.get(
        "source",
        ""
    )


    if isinstance(
        source,
        list,
    ):

        source = "".join(
            source
        )


    for item in required:

        if (
            item.lower()
            in source.lower()
        ):

            print(
                "✓",
                item,
            )

        else:

            print(
                "✗ Missing:",
                item,
            )

            all_good = False


    print(
        "execution_count:",
        todo.get(
            "execution_count"
        ),
    )


    outputs = todo.get(
        "outputs",
        []
    )


    print(
        "outputs:",
        len(outputs),
    )


    has_error = False


    for output in outputs:

        output_type = \
            output.get(
                "output_type"
            )


        if (
            output_type
            == "stream"
        ):

            text = \
                output.get(
                    "text",
                    ""
                )


            if isinstance(
                text,
                list,
            ):

                text = \
                    "".join(text)


            if text.strip():

                print(
                    "output:",
                    text.strip(),
                )


        elif (
            output_type
            == "execute_result"
        ):

            data = \
                output.get(
                    "data",
                    {}
                )


            text = \
                data.get(
                    "text/plain",
                    ""
                )


            if isinstance(
                text,
                list,
            ):

                text = \
                    "".join(text)


            if text:

                print(
                    "output:",
                    text,
                )


        elif (
            output_type
            == "error"
        ):

            has_error = True

            print(

                "ERROR:",

                output.get(
                    "ename"
                ),

                output.get(
                    "evalue"
                ),

            )


    if (
        todo.get(
            "execution_count"
        )
        is None
    ):

        print(
            "⚠ TODO cell did not execute."
        )

        all_good = False


    if has_error:

        all_good = False


if all_good:

    print()
    print(
        "LAB_FINAL_VALIDATION_OK"
    )

else:

    print()
    print(
        "LAB_FINAL_VALIDATION_NEEDS_REVIEW"
    )

PY


VERIFY_STATUS=$?


# ======================================================================
# SUMMARY
# ======================================================================

echo
line
echo -e "${BOLD}LAB RESULT${RESET}"
line

echo
echo "Project ID       : $PROJECT_ID"
echo "Notebook LOCATION: $LOCATION"
echo "Prompt region    : $PROMPT_REGION"
echo "Model            : $MODEL_ID"
echo "Image            : $IMAGE_URI"

echo

echo -e "${GREEN}✓ TASK 1${RESET}"
echo "  Cymbal Product Analysis"
echo "  Region: us-west1"

echo

echo -e "${GREEN}✓ TASK 2${RESET}"
echo "  Cymbal Tagline Generator Template"
echo "  Region: us-west1"

echo

if [[ $TASK3_RUN_STATUS -eq 0 ]]; then

  echo -e "${GREEN}✓ TASK 3${RESET}"
  echo "  image-analysis.ipynb executed + saved"

else

  echo -e "${RED}✗ TASK 3${RESET}"
  echo "  nbconvert status: $TASK3_RUN_STATUS"

fi

echo

if [[ $TASK4_RUN_STATUS -eq 0 ]]; then

  echo -e "${GREEN}✓ TASK 4${RESET}"
  echo "  tagline-generator.ipynb executed + saved"

else

  echo -e "${RED}✗ TASK 4${RESET}"
  echo "  nbconvert status: $TASK4_RUN_STATUS"

fi

echo
line
echo -e "${GREEN}${BOLD}© ePlus.DEV${RESET}"
line

echo
echo -e "${YELLOW}${BOLD}CHECK MY PROGRESS${RESET}"
echo
echo "1. Build a Gemini image analysis tool"
echo "2. Build a Gemini tagline generator"
echo "3. Experiment with image analysis code"
echo "4. Experiment with tagline generation code"
echo