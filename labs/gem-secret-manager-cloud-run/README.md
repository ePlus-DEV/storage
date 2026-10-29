# Developer Essentials: Application Development with Secret Manager

- [Published lab task list and example values](https://eplus.dev/developer-essentials-application-development-with-secret-manager-gem-secret-manager-cloud-run)
- [Google Cloud official Cloud Run secrets guidance](https://docs.cloud.google.com/run/docs/configuring/services/secrets)
- [Google Cloud official Cloud Build Dockerfile instructions](https://docs.cloud.google.com/run/docs/building/containers)
- License: [Unlicense](../../LICENSE).

The original script contained raw Dockerfile directives inside Bash (which fail as shell commands), never defined `PROJECT_ID` inside the generated Flask application, hardcoded a previous lab project in the IAM binding, mixed `us-west1` with the detected region, blocked on foreground `docker run`, and deployed an **unauthenticated endpoint returning the secret value**.

This replacement covers the lab's five tasks: enable APIs; create the `arcade-secret` and an enabled version; build the Python Secret Manager client application with Cloud Build into `arcade-images`; create the `arcade-service` service account, grant secret-level accessor and deploy Cloud Run; verify the authenticated endpoint without printing the secret. The application is private by default (`--no-allow-unauthenticated`) because it returns the demonstration secret.

```bash
PROJECT_ID=your-temporary-lab-project REGION=your-lab-region bash lab.sh
```

When the secret has no enabled version, the script prompts for the demonstration value without echoing it, or reads `LAB_SECRET_VALUE` from the environment. Use only the value provided in your lab; do not enter production secrets. Existing enabled versions are preserved on reruns. The current user's identity must have Cloud Run Invoker permission to perform the final HTTP check; if not, the script exits with a clear error rather than claiming verification.

**Static validated only; runtime/grader unverified.** The published task example uses `--allow-unauthenticated`, but this repair deliberately keeps the secret-returning endpoint private; the Google Skills grader's expectations for this security choice have not been verified. Current focus URL and October game membership are also unverified.
