# Leveraging Verifiable Credentials and Zero-Knowledge Proofs with Sindri - GSP1302

## Overview

This lab demonstrates digital university degree credentials and zero-knowledge proofs. The issuer signs a degree claim; the holder produces a presentation; the verifier checks the claim without receiving the original signature. The implementation uses the public Sindri codelab, its Go-based BLS signer/verifier, and the Sindri proof service.

There are **five official Tasks and four graded checkpoints** worth 30/20/25/25 points. The Sindri API key and Cloud Storage bucket are assigned by the active lab. Never publish those values.

The official [credential lifecycle and presentation diagrams](https://www.skills.google/focuses/118451?parent=catalog) are linked rather than copied because image embedding rights have not been confirmed.

### What you'll do

- Install Sindri CLI and save its version.
- Clone the upstream issuer/verifier example and upload the first checkpoint artifacts.
- Sign a degree credential and save its BLS witness.
- Clone the public zero-knowledge circuit and generate a proof.
- Verify the proof with Go and upload the verification result.

## Setup and requirements

### Before you click the Start Lab button

Open [the official GSP1302 lab](https://www.skills.google/focuses/118451?parent=catalog) and start it when you have time for all tasks. Use a private browser and the **temporary student account** supplied by the active lab, not a personal Google Cloud account. Do not copy the session's username, password, project ID, API key, or other credentials into GitHub.

Record the lab-provided **Sindri API key** and **Cloud Storage bucket name** from the active lab panel. The API key authenticates with the Sindri service; the bucket stores grader artifacts.

### Activate Cloud Shell

Activate Cloud Shell in the Google Cloud console, authorize the temporary account, and verify the project and tools:

```bash
gcloud auth list
gcloud config get-value project
for tool in gcloud gsutil git go npm jq; do command -v "$tool" || exit 1; done
```

Provide the Sindri key privately without printing it:

```bash
read -r -s -p "Sindri API key from the active lab: " SINDRI_API_KEY
printf '\n'
export SINDRI_API_KEY
```

Identify the lab-provided bucket (do not create a replacement bucket). Use the name shown in the lab panel:

```bash
export PROJECT_ID="$(gcloud config get-value project)"
gcloud storage buckets list --project="$PROJECT_ID"
read -r -p "Lab bucket name (without gs://): " GCS_BUCKET
export GCS_BUCKET
gsutil ls -b "gs://$GCS_BUCKET"
```

## Task 1. Install the Sindri CLI

Install the published Sindri CLI, then record the version in the home directory. The original lab uses `@latest`; the automation pins the publicly published `0.0.1-alpha.73` release to reduce changes between runs.

```bash
npm install -g sindri@0.0.1-alpha.73
sindri --version | tee "$HOME/sindri.txt"
test -s "$HOME/sindri.txt"
```

The version text varies by release. The grader expects a `sindri.txt` object in the lab bucket.

## Task 2. Clone the Source Repository

Clone the upstream example, then inspect the issuer and verifier files:

```bash
cd "$HOME"
git clone https://github.com/Sindri-Labs/verifiable-credentials-codelab.git
cd verifiable-credentials-codelab
test -s issuer/issuer.go
test -s issuer/credential.json
test -s verifier/bls-verify.go
```

On reruns, verify an existing checkout's origin instead of deleting or overwriting it:

```bash
git -C "$HOME/verifiable-credentials-codelab" remote get-url origin
```

Upload the two artifacts required by the first checkpoint and check their presence:

```bash
gsutil cp "$HOME/sindri.txt" "gs://$GCS_BUCKET/sindri.txt"
gsutil cp "$HOME/verifiable-credentials-codelab/issuer/issuer.go" "gs://$GCS_BUCKET/issuer.go"
gsutil stat "gs://$GCS_BUCKET/sindri.txt"
gsutil stat "gs://$GCS_BUCKET/issuer.go"
```

### Test completed task

Click **Check my progress** for **Install the Sindri CLI and Clone the Source Repository** (30 points). The uploaded objects can be inspected with `gsutil stat`, but their presence does not establish a grader PASS.

## Task 3. Issue a Verifiable Credential

The example issuer reads `credential.json`, creates or reuses a local private signing key, and signs the `BachelorDegree` claim. It writes a signed credential and a separate witness containing the BLS group elements.

```bash
cd "$HOME/verifiable-credentials-codelab/issuer"
go run issuer.go issuer_sk.txt credential.json
```

The private signing key `issuer_sk.txt` stays local. Do **not** upload it to Cloud Storage or GitHub.

| Output artifact | Meaning |
|---|---|
| `credential-signed.json` | Degree credential with issuer signature metadata |
| `credential-witness-1-degreeType.json` | Witness containing `Sig`, `G2`, `Hm` and `Pk` |

Verify and upload the expected files:

```bash
jq -e '.credentialSubject.degreeType == "BachelorDegree"' credential-signed.json
jq -e '.Sig != null and .G2 != null and .Hm != null and .Pk != null' credential-witness-1-degreeType.json
gsutil cp credential-signed.json "gs://$GCS_BUCKET/credential-signed.json"
gsutil cp credential-witness-1-degreeType.json "gs://$GCS_BUCKET/credential-witness-1-degreeType.json"
```

The issuer signs the claim, not the entire identity of the holder. The next task uses the witness to prove the signature relationship without exposing the signature itself.

### Test completed task

Click **Check my progress** for **Issue a Verifiable Credential** (20 points). Check that both files exist in the lab bucket.

## Task 4. Build a Verifiable Presentation

The holder's presentation contains a zero-knowledge proof. Clone the exact public Sindri circuit identified in the official instructions:

```bash
cd "$HOME/verifiable-credentials-codelab"
sindri clone 42543290-0746-48d5-998a-e39197e5cf79 holder
test -s holder/sindri.json
```

If `holder` already exists, inspect `holder/sindri.json` and reuse the directory instead of overwriting it. The `codelab` tag selects the published circuit build.

Generate the proof from Task 3's witness:

```bash
cd "$HOME/verifiable-credentials-codelab/holder"
sindri proof create --tag codelab \
  --input ../issuer/credential-witness-1-degreeType.json \
  > credential-proof.json
jq -e '(.proof.proof | type) == "string" and (.verification_key.verifying_key | type) == "string"' credential-proof.json
gsutil cp credential-proof.json "gs://$GCS_BUCKET/credential-proof.json"
```

The proof response contains a proof, public inputs, and a verification key. The original private signature is not supposed to be disclosed as the presentation. See the [official illustration of a credential versus a presentation](https://www.skills.google/focuses/118451?parent=catalog); image reuse rights have not been verified.

### Test completed task

Click **Check my progress** for **Build a Verifiable Presentation** (25 points). An accepted Sindri API request does not automatically imply a grader PASS.

## Task 5. Verify the Presentation

The upstream verifier checks the proof against a pinned verification key and public inputs. Run the actual Go source file `bls-verify.go`:

```bash
cd "$HOME/verifiable-credentials-codelab/verifier"
go run bls-verify.go ../holder/credential-proof.json | tee verify_response.txt
grep -F 'Proof verified successfully.' verify_response.txt
gsutil cp verify_response.txt "gs://$GCS_BUCKET/verify_response.txt"
gsutil stat "gs://$GCS_BUCKET/verify_response.txt"
```

The public verifier prints the following when verification succeeds:

```plaintext
Proof verified successfully.
```

If the verifier fails, inspect the proof response, the circuit identifier, and the pinned key; do not upload a fabricated success message.

### Test completed task

Click **Check my progress** for **Verify the Presentation** (25 points). All four checkpoints total 100 points (30 + 20 + 25 + 25). This guide does not claim any actual grader result.

---

## Solution of Lab

### Quick

These two commands are intended for the **temporary Google Skills Cloud Shell**. The URL deliberately points to `main` and **will only work after the Draft PR is merged**. The script privately prompts for the Sindri key and, if necessary, the lab bucket name.

```bash
curl -LO https://raw.githubusercontent.com/ePlus-DEV/storage/refs/heads/main/labs/GSP1302/lab.sh
source lab.sh
```

The script checks prerequisites, detects the project and existing bucket, executes Tasks 1–5, and checks the required output objects. It does not run Google Skills' Check my progress buttons.

### Manual

Chưa tìm thấy video YouTube hướng dẫn thủ công đã xác minh cho lab này.

Use the complete manual commands in Tasks 1–5 above and the [official GSP1302 instructions](https://www.skills.google/focuses/118451?parent=catalog).

## Sources and verification status

- [Google Skills — GSP1302 official lab](https://www.skills.google/focuses/118451?parent=catalog), last tested February 19, 2025.
- [Sindri-Labs/verifiable-credentials-codelab](https://github.com/Sindri-Labs/verifiable-credentials-codelab) — public upstream issuer and verifier, used at runtime, not copied into this repository.
- [Sindri-Labs/sindri-js](https://github.com/Sindri-Labs/sindri-js) — public CLI implementation and command flags.
- [Sindri npm package](https://www.npmjs.com/package/sindri) — published CLI version.
- [Cloud Storage gsutil documentation](https://cloud.google.com/storage/docs/gsutil/commands/cp).

**static validated only; runtime/grader unverified.** The latest PR head must pass GitHub CI Bash syntax and ShellCheck severity error. The Sindri service, circuit accessibility, lab-issued key, and grader behavior have not been tested with authorized credentials. No private signing keys or temporary credentials are included. This Markdown has not been published to Hashnode.

Copyright (c) 2026 ePlus.DEV | Unlicense — original automation and explanatory prose.
