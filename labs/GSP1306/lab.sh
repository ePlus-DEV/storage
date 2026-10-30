#!/usr/bin/env bash
# GSP1306 — Retrieving Credentials from Secret Manager with Spring Boot
# Copyright (c) 2026 ePlus.DEV | Unlicense
# static validated only; runtime/grader unverified
set -Eeuo pipefail
umask 077
if [[ -n "${NO_COLOR+x}" ]]; then C='' G='' Y='' R='';
elif [[ -t 1 || "${FORCE_COLOR:-0}" == 1 ]]; then
  C=$'\033[36m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[0m'
else C='' G='' Y='' R=''; fi
info(){ printf '%s[INFO]%s %s\n' "$C" "$R" "$*"; }
ok(){ printf '%s[OK]%s %s\n' "$G" "$R" "$*"; }
warn(){ printf '%s[WARN]%s %s\n' "$Y" "$R" "$*" >&2; }
die(){ printf '[ERROR] %s\n' "$*" >&2; exit 1; }
trap 'warn "Stopped near line $LINENO; grader PASS has not been verified."' ERR
printf '%sePlus.DEV – Starting Execution%s\n' "$C" "$R"
printf 'Copyright (c) 2026 ePlus.DEV | Unlicense\n'
for cmd in gcloud curl unzip python3 grep; do command -v "$cmd" >/dev/null || die "Missing $cmd"; done
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != '(unset)' ]] || die 'Choose the temporary lab project.'
REGION="${REGION:-$(gcloud config get-value compute/region 2>/dev/null)}"
if [[ -z "$REGION" || "$REGION" == '(unset)' ]]; then
  ZONE="$(gcloud config get-value compute/zone 2>/dev/null)"
  [[ -n "$ZONE" && "$ZONE" != '(unset)' ]] || die 'Set REGION from the active lab panel.'
  REGION="${ZONE%-*}"
fi
[[ "$REGION" =~ ^[a-z]+-[a-z0-9]+[0-9]$ ]] || die 'Invalid region.'
BUCKET_NAME="${BUCKET_NAME:-}"
if [[ -z "$BUCKET_NAME" ]]; then
  mapfile -t buckets < <(gcloud storage buckets list --project="$PROJECT_ID" \
    --format='value(name)' | sed -E 's#^gs://##;s#/$##' | sed '/^$/d')
  (( ${#buckets[@]} == 1 )) ||
    die 'Set BUCKET_NAME from the lab panel; bucket discovery is ambiguous.'
  BUCKET_NAME="${buckets[0]}"
fi
BUCKET_NAME="${BUCKET_NAME#gs://}"; BUCKET_NAME="${BUCKET_NAME%/}"
gcloud storage buckets describe "gs://$BUCKET_NAME" --project="$PROJECT_ID" >/dev/null ||
  die 'Lab bucket is not accessible.'
APP_DIR="${APP_DIR:-$HOME/hello-secret-manager}"
RUN_SA="hello-secret-manager-run-sa@$PROJECT_ID.iam.gserviceaccount.com"
info "Project=$PROJECT_ID Region=$REGION Bucket=gs://$BUCKET_NAME"
retry(){ local count="$1" delay="$2" i; shift 2
  for ((i=1;i<=count;i++)); do
    if "$@"; then return 0; fi
    if ((i<count)); then warn "Retry $i/$count"; sleep "$delay"; fi
  done; return 1; }
upload(){ local source="$1" object="$2"
  [[ -s "$source" ]] || die "Missing checkpoint artifact: $source"
  retry 3 5 gcloud storage cp "$source" "gs://$BUCKET_NAME/$object" --quiet ||
    die "Cannot upload $object"
  gcloud storage objects describe "gs://$BUCKET_NAME/$object" >/dev/null ||
    die "Cannot verify $object"
}
test_local(){ local expected="$1" logfile="$2" pid response ready=0 i
  if curl -fsS --max-time 2 http://127.0.0.1:8080/ >/dev/null 2>&1; then
    die 'Port 8080 is already occupied; stop the other app first.'
  fi
  (
    cd "$APP_DIR"
    timeout --signal=INT 180s ./mvnw -DskipTests spring-boot:run
  ) > "$logfile" 2>&1 &
  pid="$!"
  for ((i=1;i<=36;i++)); do
    response="$(curl -fsS --max-time 2 http://127.0.0.1:8080/ 2>/dev/null || true)"
    if [[ "$response" == "$expected" ]]; then ready=1; break; fi
    sleep 5
  done
  kill -INT "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  (( ready == 1 )) || die "Local Spring Boot did not return $expected; inspect $logfile"
}

info 'Task 1: create the Spring Boot service and verify its initial response'
if [[ ! -f "$APP_DIR/pom.xml" ]]; then
  [[ ! -e "$APP_DIR" ]] || die 'APP_DIR exists without pom.xml; refusing to overwrite it.'
  zip_file="$HOME/hello-secret-manager-gsp1306.zip"
  retry 3 5 curl -fL --retry 3 https://start.spring.io/starter.zip \
    -d type=maven-project -d packaging=jar -d bootVersion=4.0.1 \
    -d dependencies=web,cloud-gcp -d javaVersion=21 \
    -d name=HelloSecretManager -d artifactId=HelloSecretManager \
    -o "$zip_file" || die 'Spring Initializr could not generate the official starter.'
  mkdir -p "$APP_DIR"
  unzip -q "$zip_file" -d "$APP_DIR"
fi
[[ -s "$APP_DIR/pom.xml" && -s "$APP_DIR/mvnw" ]] ||
  die 'Spring starter is incomplete.'
chmod +x "$APP_DIR/mvnw"
controller="$APP_DIR/src/main/java/com/example/HelloSecretManager/HelloSecretManagerController.java"
mkdir -p "$(dirname "$controller")"
if [[ ! -e "$controller" ]]; then
  cat > "$controller" <<'JAVA'
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
JAVA
fi
if [[ -d /usr/lib/jvm/java-21-openjdk-amd64 ]]; then
  export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
fi
if [[ ! -s "$APP_DIR/verify_response.txt" ]]; then
  test_local 'Hi World!' "$APP_DIR/verify_response.txt"
fi
upload "$APP_DIR/verify_response.txt" 'verify_response.txt'
upload "$APP_DIR/pom.xml" 'pom.xml'
ok 'Checkpoint: Create a new Spring Boot REST service (30 points)'

info 'Task 2: create the lab-only sample greeting secret'
gcloud services enable secretmanager.googleapis.com --project="$PROJECT_ID" --quiet
if ! gcloud secrets describe greeting --project="$PROJECT_ID" >/dev/null 2>&1; then
  printf '%s' 'Hello' | gcloud secrets create greeting \
    --project="$PROJECT_ID" --replication-policy=automatic --data-file=-
fi
gcloud secrets describe greeting --project="$PROJECT_ID" >/dev/null
ok 'Checkpoint: Configure a secret in Secret Manager (20 points)'

info 'Task 3: configure Spring Cloud GCP Secret Manager'
python3 - "$APP_DIR" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
pom = root / "pom.xml"
xml = pom.read_text()
starter = "<artifactId>spring-cloud-gcp-starter-secretmanager</artifactId>"
if starter not in xml:
    dependency = """
        <dependency>
            <groupId>com.google.cloud</groupId>
            <artifactId>spring-cloud-gcp-starter-secretmanager</artifactId>
        </dependency>
"""
    if xml.count("</dependencies>") != 1:
        raise SystemExit("Unexpected pom.xml dependency layout")
    pom.write_text(xml.replace("</dependencies>", dependency + "    </dependencies>"))
props = root / "src/main/resources/application.properties"
text = props.read_text() if props.exists() else ""
for line in ("spring.config.import=sm://",):
    if line not in text.splitlines():
        text += "\n" + line + "\n"
props.write_text(text)
PY
cat > "$controller" <<'JAVA'
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
JAVA
if [[ ! -s "$APP_DIR/verify_test_response.txt" ]]; then
  test_local 'Hello World!' "$APP_DIR/verify_test_response.txt"
fi
upload "$APP_DIR/verify_test_response.txt" 'verify_test_response.txt'
upload "$controller" 'HelloSecretManagerController.java'
ok 'Checkpoint: Update the app to use the secret greeting (25 points)'

info 'Task 4: deploy the sample app to Cloud Run using the pre-provisioned service account'
gcloud services enable run.googleapis.com cloudbuild.googleapis.com --project="$PROJECT_ID" --quiet
gcloud iam service-accounts describe "$RUN_SA" --project="$PROJECT_ID" >/dev/null ||
  die 'Pre-provisioned Cloud Run service account not found.'
gcloud secrets add-iam-policy-binding greeting --project="$PROJECT_ID" \
  --member="serviceAccount:$RUN_SA" --role=roles/secretmanager.secretAccessor --quiet >/dev/null
props="$APP_DIR/src/main/resources/application.properties"
grep -Fxq 'server.port=${PORT:8080}' "$props" ||
  printf '%s\n' 'server.port=${PORT:8080}' >> "$props"
cat > "$APP_DIR/project.toml" <<'TOML'
[[build.env]]
name = "GOOGLE_RUNTIME_VERSION"
value = "21"
TOML
latest="$(gcloud secrets versions access latest --secret=greeting --project="$PROJECT_ID" 2>/dev/null || true)"
if [[ "$latest" != Greetings ]]; then
  printf '%s' 'Greetings' | gcloud secrets versions add greeting --project="$PROJECT_ID" --data-file=-
fi
(
  cd "$APP_DIR"
  retry 3 15 gcloud run deploy hello-secret-manager --project="$PROJECT_ID" \
    --region="$REGION" --allow-unauthenticated --service-account="$RUN_SA" \
    --source=. --quiet
)
service_url="$(gcloud run services describe hello-secret-manager --project="$PROJECT_ID" \
  --region="$REGION" --format='value(status.url)')"
[[ "$service_url" == https://* ]] || die 'Cloud Run service URL is missing.'
ready=0
for ((i=1;i<=18;i++)); do
  response="$(curl -fsS --max-time 10 "$service_url" 2>/dev/null || true)"
  if [[ "$response" == 'Greetings World!' ]]; then ready=1; break; fi
  sleep 10
done
(( ready == 1 )) || die 'Cloud Run did not return the expected lab-only greeting.'
ok 'Checkpoint: Deploy the app to Cloud Run (25 points)'
info 'Do not use real secrets with this intentionally public demo endpoint.'
info 'static validated only; runtime/grader unverified'
