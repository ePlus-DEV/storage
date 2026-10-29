#!/usr/bin/env bash

# ePlus.DEV console banner. Presentation only; see repository LICENSE (Unlicense).
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then
  _eplus_cyan=$'\033[1;36m'
  _eplus_yellow=$'\033[0;33m'
  _eplus_reset=$'\033[0m'
else
  _eplus_cyan='' _eplus_yellow='' _eplus_reset=''
fi
printf '%s\n' "${_eplus_cyan}==========================================================${_eplus_reset}"
printf '%s\n' "${_eplus_cyan} ePlus.DEV - Starting Execution | Cloud Storage Mini Lab 2${_eplus_reset}"
printf '%s\n' "${_eplus_yellow} Copyright (c) 2026 ePlus.DEV | Unlicense${_eplus_reset}"
printf '%s\n' "${_eplus_cyan}==========================================================${_eplus_reset}"
unset _eplus_cyan _eplus_yellow _eplus_reset

cat > lifecycle.json << EOF
{
    "rule": [
      {
        "action": {
          "storageClass": "NEARLINE",
          "type": "SetStorageClass"
        },
        "condition": {
          "daysSinceNoncurrentTime": 30,
          "matchesPrefix": [
            "/projects/active/"
          ]
        }
      },
      {
        "action": {
          "storageClass": "NEARLINE",
          "type": "SetStorageClass"
        },
        "condition": {
          "daysSinceNoncurrentTime": 90,
          "matchesPrefix": [
            "/archive/"
          ]
        }
      },
      {
        "action": {
          "storageClass": "COLDLINE",
          "type": "SetStorageClass"
        },
        "condition": {
          "daysSinceNoncurrentTime": 180,
          "matchesPrefix": [
            "/archive/"
          ]
        }
      },
      {
        "action": {
          "type": "Delete"
        },
        "condition": {
          "age": 7,
          "matchesPrefix": [
            "/processing/temp_logs/"
          ]
        }
      }
    ]
  }
EOF

export PROJECT_ID=$(gcloud config get-value project)

gsutil lifecycle set lifecycle.json gs://$PROJECT_ID-bucket