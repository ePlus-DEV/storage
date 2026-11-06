# Retrieving Credentials from Secret Manager with Spring Boot - GSP1306

## Overview

This lab builds a Spring Boot REST application, stores a **demonstration greeting** in Google Cloud Secret Manager, reads the value through Spring Cloud GCP, and deploys the app to Cloud Run. The sample greeting is not a real credential. Never expose actual passwords or API keys through this public demo endpoint.

The official lab has **four Tasks and four checkpoints** worth 30/20/25/25 points. Its [console screenshots and diagrams](https://www.skills.google/focuses/121708?parent=catalog) are linked rather than embedded because reuse rights have not been verified.

### What you'll do

- Generate and test a Java 21 Spring Boot REST service.
- Create a lab-only `greeting` secret.
- Configure Spring Cloud GCP Secret Manager and verify the updated app.
- Deploy the service to Cloud Run with a scoped service account.

## Setup and requirements

### Before you click the Start Lab button

Open [the official GSP1306 lab](https://www.skills.google/focuses/121708?parent=catalog) and start it when ready. Use a private browser and the temporary student account from the lab panel. Do not use a personal Google Cloud project or publish any session credentials.

The lab provides a Cloud Storage bucket and a service account named `hello-secret-manager-run-sa`. The region and bucket must come from the active lab, not an example.

### Activate Cloud Shell

Activate Cloud Shell and authorize the lab account. Confirm the active project and assigned region:

```bash
gcloud auth list
export PROJECT_ID="$(gcloud config get-value project)"
export REGION="$(gcloud config get-value compute/region)"
gcloud storage buckets list --project="$PROJECT_ID"
```

If the region is unset, use the value shown by the lab panel. Set the existing bucket name:

```bash
read -r -p "Lab bucket name (without gs://): " BUCKET_NAME
export BUCKET_NAME
gcloud storage buckets describe "gs://$BUCKET_NAME"
```

## Task 1. Create a new Spring Boot REST service

### Generate the Maven project

The official lab requests Spring Boot `4.0.1`, Java `21`, and the `web,cloud-gcp` dependencies from Spring Initializr. The same official page's explanation mentions Boot 3.3.5; this inconsistency must be reviewed, not silently ignored.

```bash
cd "$HOME"
curl -fL --retry 3 https://start.spring.io/starter.zip \
  -d type=maven-project -d packaging=jar \
  -d bootVersion=4.0.1 -d dependencies=web,cloud-gcp \
  -d javaVersion=21 -d name=HelloSecretManager \
  -d artifactId=HelloSecretManager -o hello-secret-manager.zip
mkdir -p hello-secret-manager
unzip -q hello-secret-manager.zip -d hello-secret-manager
cd hello-secret-manager
chmod +x mvnw
```

Inspect `pom.xml` and the Maven wrapper. If Initializr rejects this dependency combination, stop and confirm a compatible version rather than inventing a result.

### Add the REST controller

Save this code as `src/main/java/com/example/HelloSecretManager/HelloSecretManagerController.java`:

```java
package com.example.HelloSecretManager;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HelloSecretManagerController {
    String greeting = "Hi";

    @GetMapping("/")
    public String hello() {
        return greeting + " World!";
    }
}
```

Use Java 21 and run the application:

```bash
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
./mvnw -DskipTests spring-boot:run | tee verify_response.txt
```

In Cloud Shell select **Web Preview → Preview on port 8080**. The initial response should be `Hi World!`. Stop the local server after verifying it. Upload the actual Maven log and POM to the lab bucket:

```bash
gcloud storage cp verify_response.txt "gs://$BUCKET_NAME/"
gcloud storage cp pom.xml "gs://$BUCKET_NAME/"
```

### Test completed task

Click **Check my progress** for **Create a new Spring Boot REST service** (30 points). Do not fabricate a run log if the application fails.

## Task 2. Configure a secret in Secret Manager

Enable the API and create the lab's sample `greeting` secret with public demonstration text `Hello`:

```bash
gcloud services enable secretmanager.googleapis.com
printf '%s' 'Hello' | gcloud secrets create greeting \
  --replication-policy=automatic --data-file=-
gcloud secrets list
gcloud secrets describe greeting
```

On reruns, inspect an existing `greeting` secret rather than creating a duplicate. This public demo value must never be replaced with a real password.

### Test completed task

Click **Check my progress** for **Configure a secret in Secret Manager** (20 points).

## Task 3. Update the app to use the secret greeting

### Add the Secret Manager dependency

Within `pom.xml`, add the dependency below if it is not already present:

```xml
<dependency>
    <groupId>com.google.cloud</groupId>
    <artifactId>spring-cloud-gcp-starter-secretmanager</artifactId>
</dependency>
```

Verify that the project's dependency management resolves a compatible Spring Cloud GCP version.

### Configure application properties

In `src/main/resources/application.properties` add:

```properties
spring.config.import=sm://
```

The lab uses `sm://` syntax. Newer Spring Cloud GCP releases also document `sm@`; test against the actual generated dependency version.

### Replace the controller

Update the Java controller to read the secret rather than use a hardcoded greeting:

```java
package com.example.HelloSecretManager;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HelloSecretManagerController {
    @Value("${sm://greeting}")
    String greeting;

    @GetMapping("/")
    public String hello() {
        return greeting + " World!";
    }
}
```

Restart the service and use Web Preview to check that it now returns `Hello World!`:

```bash
cd "$HOME/hello-secret-manager"
./mvnw -DskipTests spring-boot:run | tee verify_test_response.txt
```

Stop the service after the check. Upload the new run log and the controller:

```bash
gcloud storage cp verify_test_response.txt "gs://$BUCKET_NAME/"
gcloud storage cp src/main/java/com/example/HelloSecretManager/HelloSecretManagerController.java \
  "gs://$BUCKET_NAME/HelloSecretManagerController.java"
```

### Test completed task

Click **Check my progress** for **Update the app to use the secret greeting** (25 points). A genuine Secret Manager-backed response is required.

## Task 4. Deploy the app to Cloud Run

### Enable Cloud Run and Cloud Build

```bash
gcloud services enable run.googleapis.com cloudbuild.googleapis.com
```

Add the Cloud Run port property to `application.properties`:

```properties
server.port=${PORT:8080}
```

Create `project.toml` in the app root to specify Java 21 for the buildpack:

```toml
[[build.env]]
name = "GOOGLE_RUNTIME_VERSION"
value = "21"
```

### Grant least-privilege Secret Manager access

The Cloud Run service account is pre-provisioned. Grant it access to the specific `greeting` secret rather than every secret in the project:

```bash
export RUN_SA="hello-secret-manager-run-sa@$PROJECT_ID.iam.gserviceaccount.com"
gcloud iam service-accounts describe "$RUN_SA"
gcloud secrets add-iam-policy-binding greeting \
  --member="serviceAccount:$RUN_SA" \
  --role=roles/secretmanager.secretAccessor
```

### Add the final demo value and deploy

Create a new version of the public demo greeting:

```bash
printf '%s' 'Greetings' | gcloud secrets versions add greeting --data-file=-
```

Deploy the application from source to Cloud Run:

```bash
cd "$HOME/hello-secret-manager"
gcloud run deploy hello-secret-manager \
  --region="$REGION" \
  --allow-unauthenticated \
  --service-account="$RUN_SA" \
  --source=.
```

The lab intentionally makes the demonstration endpoint public. **Never put real credentials in this greeting secret.** Retrieve the URL from the deployed service:

```bash
export SERVICE_URL="$(gcloud run services describe hello-secret-manager \
  --region="$REGION" --format='value(status.url)')"
curl -fsS "$SERVICE_URL"
```

The expected response is `Greetings World!`. If it fails, inspect Cloud Run revision logs, Secret Manager IAM, and dependency compatibility rather than claiming completion.

### Test completed task

Click **Check my progress** for **Deploy the app to Cloud Run** (25 points). The checkpoints total 100 points; no grader result is asserted.

---

## Solution of Lab

### Quick

Use the following two commands in the **authorized temporary lab Cloud Shell**. The URL always points to `main` and will only work **after the Draft PR has been merged**.

```bash
curl -LO https://raw.githubusercontent.com/ePlus-DEV/storage/refs/heads/main/labs/GSP1306/lab.sh
source lab.sh
```

The script detects the project and region, uses the existing lab bucket, generates the Spring Boot app, tests both local responses, configures the sample secret, and deploys Cloud Run. It does not press Google Skills grader buttons.

### Manual

Chưa tìm thấy video YouTube hướng dẫn thủ công đã xác minh cho lab này.

Follow Tasks 1–4 above and consult the [official Google Skills instructions](https://www.skills.google/focuses/121708?parent=catalog).

## Sources and verification status

- [Google Skills GSP1306 official lab](https://www.skills.google/focuses/121708?parent=catalog), last tested August 27, 2026.
- [Spring Initializr](https://start.spring.io/).
- [Spring Framework on Google Cloud — Secret Manager](https://googlecloudplatform.github.io/spring-cloud-gcp/reference/html/index.html).
- [Secret Manager documentation](https://cloud.google.com/secret-manager/docs).
- [Cloud Run source deployment](https://cloud.google.com/run/docs/deploying-source-code).

**static validated only; runtime/grader unverified.** The official lab's Spring Boot version discrepancy (4.0.1 in the command versus 3.3.5 in its explanation) requires review. Maven compatibility, Secret Manager configuration, the pre-provisioned service account, and grader acceptance have not been tested with an authorized lab. Bash syntax and ShellCheck require latest-head GitHub CI. No real credentials are included. This Markdown has not been published to Hashnode.

Copyright (c) 2026 ePlus.DEV | Unlicense — original automation and explanatory prose.
