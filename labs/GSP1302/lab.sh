#!/usr/bin/env bash
# GSP1302 — Leveraging Verifiable Credentials and Zero-Knowledge Proofs with Sindri
# Copyright (c) 2026 ePlus.DEV | Unlicense
# static validated only; runtime/grader unverified
set -Eeuo pipefail
umask 077

if [[ -n "${NO_COLOR+x}" ]]; then
  CYAN='' GREEN='' YELLOW='' RESET=''
elif [[ -t 1 || "${FORCE_COLOR:-0}" == 1 ]]; then
  CYAN=$'\033[36m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
  CYAN='' GREEN='' YELLOW='' RESET=''
fi
info() { printf '%s[INFO]%s %s\n' "$CYAN" "$RESET" "$*"; }
ok() { printf '%s[OK]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }
trap 'warn "Execution failed near line $LINENO; inspect the preceding error (no grader PASS is implied)."' ERR
printf '%sePlus.DEV – Starting Execution%s\n' "$CYAN" "$RESET"
printf 'Copyright (c) 2026 ePlus.DEV | Unlicense\n'

for tool in gcloud gsutil git go npm jq; do
  command -v "$tool" >/dev/null 2>&1 || die "Missing required tool: $tool"
done
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != '(unset)' ]] || die 'Select the temporary Google Skills lab project.'
info "Using lab project: $PROJECT_ID"

# The Sindri API key is supplied by the active lab panel. Never print or commit it.
if [[ -z "${SINDRI_API_KEY:-}" ]]; then
  [[ -t 0 ]] || die 'Set SINDRI_API_KEY from the active lab panel (no interactive stdin).'
  printf 'Paste the Sindri API key from the active lab panel (input hidden): ' >&2
  IFS= read -r -s SINDRI_API_KEY
  printf '\n' >&2
fi
[[ -n "$SINDRI_API_KEY" ]] || die 'SINDRI_API_KEY is empty.'
export SINDRI_API_KEY

# Use the lab-provisioned bucket, never create an unrelated bucket.
GCS_BUCKET="${GCS_BUCKET:-}"
if [[ -z "$GCS_BUCKET" ]]; then
  mapfile -t bucket_candidates < <(
    gcloud storage buckets list --project="$PROJECT_ID" --format='value(name)' |
      sed -E 's#^gs://##; s#/$##' | sed '/^$/d'
  )
  if (( ${#bucket_candidates[@]} == 1 )); then
    GCS_BUCKET="${bucket_candidates[0]}"
  elif [[ -t 0 ]]; then
    printf 'Enter the lab-provided GCS bucket name (without gs://): ' >&2
    IFS= read -r GCS_BUCKET
  else
    die 'Set GCS_BUCKET from the active lab panel; bucket discovery was ambiguous.'
  fi
fi
GCS_BUCKET="${GCS_BUCKET#gs://}"
GCS_BUCKET="${GCS_BUCKET%/}"
[[ "$GCS_BUCKET" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{1,220}$ ]] || die 'Invalid bucket name.'
gsutil ls -b "gs://$GCS_BUCKET" >/dev/null 2>&1 || die 'The lab bucket is not accessible.'
info "Using existing bucket: gs://$GCS_BUCKET"

retry() {
  local limit="$1" delay="$2" attempt
  shift 2
  for ((attempt=1; attempt<=limit; attempt++)); do
    if "$@"; then return 0; fi
    if ((attempt < limit)); then warn "Attempt $attempt/$limit failed; retrying in ${delay}s."; sleep "$delay"; fi
  done
  return 1
}
upload_artifact() {
  local local_file="$1" object="$2"
  [[ -s "$local_file" ]] || die "Missing or empty artifact: $local_file"
  retry 3 5 gsutil -q cp "$local_file" "gs://$GCS_BUCKET/$object" ||
    die "Upload failed: $object"
  retry 3 5 gsutil -q stat "gs://$GCS_BUCKET/$object" ||
    die "Cannot verify uploaded object: $object"
  ok "Verified gs://$GCS_BUCKET/$object"
}

WORKDIR="${WORKDIR:-$HOME/verifiable-credentials-codelab}"
REPO_URL='https://github.com/Sindri-Labs/verifiable-credentials-codelab.git'
info 'Task 1: install the official Sindri CLI and record its version'
if ! command -v sindri >/dev/null 2>&1; then
  retry 3 5 npm install -g sindri@0.0.1-alpha.73 ||
    die 'Unable to install the published Sindri CLI.'
fi
sindri --version | tee "$HOME/sindri.txt"
[[ -s "$HOME/sindri.txt" ]] || die 'Sindri version file is empty.'

info 'Task 2: clone or verify the public Sindri codelab repository'
if [[ -e "$WORKDIR" ]]; then
  [[ -d "$WORKDIR/.git" ]] || die 'WORKDIR exists but is not a Git checkout; refusing to overwrite it.'
  origin="$(git -C "$WORKDIR" remote get-url origin)"
  [[ "$origin" == "$REPO_URL" || "$origin" == "${REPO_URL%.git}" ]] ||
    die 'WORKDIR has a different Git origin; refusing to modify it.'
else
  git clone --depth 1 "$REPO_URL" "$WORKDIR"
fi
[[ -s "$WORKDIR/issuer/issuer.go" && -s "$WORKDIR/issuer/credential.json" ]] ||
  die 'Required issuer files are absent from the official checkout.'
[[ -s "$WORKDIR/verifier/bls-verify.go" ]] ||
  die 'Required verifier file is absent from the official checkout.'
upload_artifact "$HOME/sindri.txt" 'sindri.txt'
upload_artifact "$WORKDIR/issuer/issuer.go" 'issuer.go'
ok 'Checkpoint: Install the Sindri CLI and Clone the Source Repository (30 points)'

info 'Task 3: issue the verifiable credential and upload both expected artifacts'
(
  cd "$WORKDIR/issuer"
  go run issuer.go issuer_sk.txt credential.json
)
jq -e '.credentialSubject.degreeType == "BachelorDegree" and (.proof != null)' \
  "$WORKDIR/issuer/credential-signed.json" >/dev/null ||
  die 'Signed credential is not valid or lacks the expected claim.'
jq -e '.Sig != null and .G2 != null and .Hm != null and .Pk != null' \
  "$WORKDIR/issuer/credential-witness-1-degreeType.json" >/dev/null ||
  die 'Witness JSON lacks BLS fields.'
upload_artifact "$WORKDIR/issuer/credential-signed.json" 'credential-signed.json'
upload_artifact "$WORKDIR/issuer/credential-witness-1-degreeType.json" 'credential-witness-1-degreeType.json'
ok 'Checkpoint: Issue a Verifiable Credential (20 points)'

info 'Task 4: obtain the official public circuit and generate a presentation'
CIRCUIT_ID='42543290-0746-48d5-998a-e39197e5cf79'
if [[ -e "$WORKDIR/holder" ]]; then
  [[ -s "$WORKDIR/holder/sindri.json" ]] ||
    die 'holder exists without a Sindri manifest; refusing to overwrite it.'
else
  retry 2 8 sindri clone "$CIRCUIT_ID" "$WORKDIR/holder" ||
    die 'Cannot clone the public Sindri circuit with the lab API key.'
fi
(
  cd "$WORKDIR/holder"
  retry 2 10 sindri proof create --tag codelab \
    --input "$WORKDIR/issuer/credential-witness-1-degreeType.json" \
    > "$WORKDIR/holder/credential-proof.json"
)
jq -e '(.proof.proof | type) == "string" and
       (.verification_key.verifying_key | type) == "string" and
       (.public != null)' "$WORKDIR/holder/credential-proof.json" >/dev/null ||
  die 'Sindri response does not contain a complete proof and verification key.'
upload_artifact "$WORKDIR/holder/credential-proof.json" 'credential-proof.json'
ok 'Checkpoint: Build a Verifiable Presentation (25 points)'

info 'Task 5: verify the proof locally using the public Go verifier'
(
  cd "$WORKDIR/verifier"
  go run bls-verify.go "$WORKDIR/holder/credential-proof.json" |
    tee "$WORKDIR/verifier/verify_response.txt"
)
grep -Fq 'Proof verified successfully.' "$WORKDIR/verifier/verify_response.txt" ||
  die 'The verifier did not confirm the proof.'
upload_artifact "$WORKDIR/verifier/verify_response.txt" 'verify_response.txt'
ok 'Checkpoint: Verify the Presentation (25 points)'
info 'All four checkpoint artifacts are present. Use Check my progress in Google Skills.'
info 'static validated only; runtime/grader unverified'
