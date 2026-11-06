# Configure Secure CORS for Cloud Storage (Solution)

- [Published lab challenge and requirements](https://eplus.dev/configure-secure-cors-for-cloud-storage-solution)
- [Google Cloud official CORS setup and read-back documentation](https://docs.cloud.google.com/storage/docs/using-cors)
- [Google Cloud official CORS JSON shape](https://docs.cloud.google.com/storage/docs/cors-configurations)
- License: [Unlicense](../../LICENSE).

The challenge asks for **GET only** from `http://example.com` on the lab's existing `<project>-bucket`. This script refuses to create an unexpected bucket, uses a temporary JSON file rather than overwriting `cors.json` in the user's working directory, and reads the applied configuration back.

```bash
PROJECT_ID=your-temporary-lab-project bash lab.sh
# Optional only when your lab provides a different existing bucket:
BUCKET_NAME=your-existing-lab-bucket bash lab.sh
```

**Static validation only; runtime/Google Skills grader unverified.** The source article reproduces the task; the current Google Skills focus URL and October game membership have not been independently verified. CORS update replaces the bucket's CORS rules: run only in the temporary lab bucket after checking the task. The script does not change bucket IAM or object permissions.
