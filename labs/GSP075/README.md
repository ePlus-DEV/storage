# GSP075 — Extract, Analyze, and Translate Text from Images with the Cloud ML APIs

Official lab: https://www.skills.google/focuses/1836

Arcade game: [Arcade Adventure: Google Cloud ML APIs (October 2026)](https://www.skills.google/games/7496).

Run **only in the temporary Google Skills lab project**:

```bash
bash lab.sh
```

The standalone script covers all six tasks: restricted API key; bucket + official sample image and **object-only** public-read ACL required by the lab; Vision OCR request; OCR call; English translation; Natural Language entity analysis.

Configuration: `PROJECT_ID`, `REGION`, `BUCKET_NAME`, `WORKDIR`, `API_KEY` are optional environment variables. The script detects the project and region from the lab environment/gcloud config where possible and prompts for missing values when interactive. It does not print the API key.

**Important:** The lab explicitly requires public-read access to `sign.jpg`; the script does not grant public access to the bucket or other objects. Use only a disposable lab project and verify the three official **Check my progress** checkpoints. An organization policy blocking public access will cause an explicit error rather than a policy bypass.

Validation: static Bash syntax checked; **runtime and grader unverified** without authorized lab access. ShellCheck must pass in PR CI before merging.

References: [official Google Skills instructions](https://www.skills.google/focuses/1836), [Google Cloud CLI API key creation](https://docs.cloud.google.com/sdk/gcloud/reference/services/api-keys/create), [Cloud Storage bucket flags](https://docs.cloud.google.com/sdk/gcloud/reference/storage/buckets/create), [object ACL reference](https://docs.cloud.google.com/sdk/gcloud/reference/storage/objects/update).

Code authored for ePlus.DEV; repository license: [Unlicense](../../LICENSE).
