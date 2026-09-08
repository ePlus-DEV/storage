#!/bin/bash

set -Eeuo pipefail

# ============================================================
# COLORS
# ============================================================
BLACK=$'\033[0;90m'
RED=$'\033[0;91m'
GREEN=$'\033[0;92m'
YELLOW=$'\033[0;93m'
BLUE=$'\033[0;94m'
MAGENTA=$'\033[0;95m'
CYAN=$'\033[0;96m'
WHITE=$'\033[0;97m'

BOLD=$'\033[1m'
RESET=$'\033[0m'

# ============================================================
# ERROR HANDLER
# ============================================================
trap 'echo; echo "${RED}${BOLD}✗ Script failed at line $LINENO${RESET}"' ERR

clear

echo
echo "${MAGENTA}${BOLD}============================================================${RESET}"
echo "${MAGENTA}${BOLD}        GSP761 - SERVERLESS CLOUD RUN DEVELOPMENT           ${RESET}"
echo "${MAGENTA}${BOLD}                       © ePlus.DEV                           ${RESET}"
echo "${MAGENTA}${BOLD}============================================================${RESET}"
echo

# ============================================================
# PROJECT / REGION
# ============================================================

PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
    PROJECT_ID="$(gcloud projects list \
        --filter='projectId:qwiklabs-gcp' \
        --format='value(projectId)' \
        | head -n1)"
fi

if [[ -z "$PROJECT_ID" ]]; then
    echo "${RED}Unable to detect Qwiklabs project.${RESET}"
    exit 1
fi

gcloud config set project "$PROJECT_ID" >/dev/null

# This lab specifically requires us-west1.
# Try metadata first, then fall back to lab-required region.
REGION="$(
    gcloud compute project-info describe \
        --format="value(commonInstanceMetadata.items[google-compute-default-region])" \
        2>/dev/null || true
)"

if [[ -z "$REGION" ]]; then
    REGION="us-west1"
fi

# GSP761 currently requires us-west1 even if metadata is unusual.
if [[ "$REGION" != "us-west1" ]]; then
    echo "${YELLOW}Lab requires us-west1. Overriding detected region: $REGION${RESET}"
    REGION="us-west1"
fi

export PROJECT_ID
export GOOGLE_CLOUD_PROJECT="$PROJECT_ID"

echo "${CYAN}${BOLD}Project :${RESET} $PROJECT_ID"
echo "${CYAN}${BOLD}Region  :${RESET} $REGION"
echo

# ============================================================
# ENABLE APIs
# ============================================================

echo "${YELLOW}${BOLD}[1/9] Enabling required APIs...${RESET}"

gcloud services enable \
    cloudbuild.googleapis.com \
    run.googleapis.com \
    artifactregistry.googleapis.com \
    firestore.googleapis.com \
    storage.googleapis.com \
    --project="$PROJECT_ID" \
    --quiet

echo "${GREEN}✓ APIs enabled${RESET}"
echo

# ============================================================
# PREPARE SOURCE
# ============================================================

echo "${YELLOW}${BOLD}[2/9] Preparing Pet Theory source...${RESET}"

cd "$HOME"

if [[ -d pet-theory ]]; then
    echo "${CYAN}Existing pet-theory directory found. Removing it...${RESET}"
    rm -rf pet-theory
fi

git clone -q https://github.com/rosera/pet-theory.git

cd "$HOME/pet-theory/lab08"

echo "${GREEN}✓ Source ready${RESET}"
echo

# ============================================================
# ARTIFACT REGISTRY
# ============================================================

echo "${YELLOW}${BOLD}[3/9] Preparing Artifact Registry...${RESET}"

if ! gcloud artifacts repositories describe my-repo \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1; then

    gcloud artifacts repositories create my-repo \
        --repository-format=docker \
        --location="$REGION" \
        --description="Docker repository for REST API" \
        --project="$PROJECT_ID" \
        --quiet
else
    echo "${CYAN}Artifact Registry repository my-repo already exists.${RESET}"
fi

IMAGE_BASE="${REGION}-docker.pkg.dev/${PROJECT_ID}/my-repo/rest-api"

echo "${GREEN}✓ Repository ready${RESET}"
echo

# ============================================================
# TASK 2 - VERSION 0.1
# ============================================================

echo "${YELLOW}${BOLD}[4/9] Building REST API revision 0.1...${RESET}"

cat > main.go <<'EOF'
package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	http.HandleFunc("/v1/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "{status: 'running'}")
	})

	log.Println("Pets REST API listening on port", port)

	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("Error launching Pets REST API server: %v", err)
	}
}
EOF

cat > Dockerfile <<'EOF'
FROM gcr.io/distroless/base-debian12
WORKDIR /usr/src/app
COPY server .
CMD [ "/usr/src/app/server" ]
EOF

echo "${CYAN}Compiling Go binary...${RESET}"

go build -o server

echo "${CYAN}Building container image 0.1...${RESET}"

gcloud builds submit \
    --tag "${IMAGE_BASE}:0.1" \
    --project="$PROJECT_ID" \
    --quiet

echo "${CYAN}Deploying Cloud Run revision 0.1...${RESET}"

gcloud run deploy rest-api \
    --image="${IMAGE_BASE}:0.1" \
    --platform=managed \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --allow-unauthenticated \
    --max-instances=2 \
    --quiet

SERVICE_URL="$(
    gcloud run services describe rest-api \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format='value(status.url)'
)"

echo
echo "${GREEN}✓ Revision 0.1 deployed${RESET}"
echo "${CYAN}Service URL:${RESET}"
echo "${WHITE}${SERVICE_URL}/v1/${RESET}"
echo

echo "${CYAN}Testing revision 0.1...${RESET}"

curl -fsS "${SERVICE_URL}/v1/" || {
    echo "${RED}Revision 0.1 endpoint test failed.${RESET}"
    exit 1
}

echo
echo
echo "${GREEN}✓ REST API 0.1 is working${RESET}"
echo

# ============================================================
# TASK 3 - FIRESTORE
# ============================================================

echo "${YELLOW}${BOLD}[5/9] Preparing Firestore database...${RESET}"

CURRENT_LOCATION="$(
    gcloud firestore databases describe \
        --database='(default)' \
        --project="$PROJECT_ID" \
        --format='value(locationId)' \
        2>/dev/null || true
)"

if [[ -n "$CURRENT_LOCATION" && "$CURRENT_LOCATION" != "$REGION" ]]; then

    echo "${RED}Existing Firestore database is in wrong location:${RESET}"
    echo "  Current : $CURRENT_LOCATION"
    echo "  Required: $REGION"
    echo
    echo "${YELLOW}Deleting incorrect Firestore database...${RESET}"

    gcloud firestore databases update \
        --database='(default)' \
        --no-delete-protection \
        --project="$PROJECT_ID" \
        --quiet \
        >/dev/null 2>&1 || true

    gcloud firestore databases delete \
        --database='(default)' \
        --project="$PROJECT_ID" \
        --quiet

    echo "${CYAN}Waiting until '(default)' database ID can be reused...${RESET}"
fi

# ------------------------------------------------------------
# CREATE FIRESTORE
# ------------------------------------------------------------

CURRENT_LOCATION="$(
    gcloud firestore databases describe \
        --database='(default)' \
        --project="$PROJECT_ID" \
        --format='value(locationId)' \
        2>/dev/null || true
)"

if [[ "$CURRENT_LOCATION" != "$REGION" ]]; then

    echo "${CYAN}Creating Firestore Native database in $REGION...${RESET}"

    CREATED=0

    for ATTEMPT in {1..40}; do

        if gcloud firestore databases create \
            --database='(default)' \
            --location="$REGION" \
            --type=firestore-native \
            --edition=standard \
            --project="$PROJECT_ID" \
            --quiet 2>/tmp/firestore-create.log; then

            CREATED=1
            break
        fi

        if grep -qiE \
            'recently deleted|cannot be reused|already exists|retry|precondition' \
            /tmp/firestore-create.log; then

            echo "${YELLOW}Firestore ID not reusable yet. Retrying... ($ATTEMPT/40)${RESET}"
            sleep 10
        else
            cat /tmp/firestore-create.log
            exit 1
        fi
    done

    if [[ "$CREATED" -ne 1 ]]; then
        echo "${RED}Unable to recreate Firestore database.${RESET}"
        exit 1
    fi

else
    echo "${CYAN}Firestore already exists in $REGION.${RESET}"
fi

echo "${GREEN}✓ Firestore database ready${RESET}"
echo

# ============================================================
# IMPORT TEST DATA
# ============================================================

echo "${YELLOW}${BOLD}[6/9] Importing customer test data...${RESET}"

BUCKET="${PROJECT_ID}-customer"

if ! gcloud storage buckets describe "gs://${BUCKET}" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1; then

    gcloud storage buckets create "gs://${BUCKET}" \
        --project="$PROJECT_ID" \
        --location="$REGION" \
        --default-storage-class=STANDARD \
        --quiet
else
    echo "${CYAN}Bucket gs://${BUCKET} already exists.${RESET}"
fi

echo "${CYAN}Copying Firestore export files...${RESET}"

gcloud storage cp -r \
    "gs://spls/gsp645/2019-10-06T20:10:37_43617" \
    "gs://${BUCKET}/" \
    --quiet

echo "${CYAN}Importing records into Firestore...${RESET}"

gcloud firestore import \
    "gs://${BUCKET}/2019-10-06T20:10:37_43617/" \
    --database='(default)' \
    --project="$PROJECT_ID" \
    --quiet

echo "${GREEN}✓ Customer data imported${RESET}"
echo

# ============================================================
# TASK 4 - FIRESTORE REST API
# ============================================================

echo "${YELLOW}${BOLD}[7/9] Creating Firestore-enabled REST API...${RESET}"

cat > main.go <<'EOF'
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"

	"cloud.google.com/go/firestore"
	"github.com/gorilla/handlers"
	"github.com/gorilla/mux"
	"google.golang.org/api/iterator"
)

var client *firestore.Client

func main() {
	var err error
	ctx := context.Background()

	projectID := os.Getenv("PROJECT_ID")

	if projectID == "" {
		log.Fatal("PROJECT_ID environment variable is not set")
	}

	client, err = firestore.NewClient(ctx, projectID)

	if err != nil {
		log.Fatalf("Error initializing Cloud Firestore client: %v", err)
	}

	defer client.Close()

	port := os.Getenv("PORT")

	if port == "" {
		port = "8080"
	}

	r := mux.NewRouter()

	r.HandleFunc("/v1/", rootHandler).Methods("GET")
	r.HandleFunc("/v1/customer/{id}", customerHandler).Methods("GET")

	log.Println("Pets REST API listening on port", port)

	cors := handlers.CORS(
		handlers.AllowedHeaders(
			[]string{
				"X-Requested-With",
				"Authorization",
				"Origin",
			},
		),
		handlers.AllowedOrigins(
			[]string{
				"https://storage.googleapis.com",
			},
		),
		handlers.AllowedMethods(
			[]string{
				"GET",
				"HEAD",
				"POST",
				"OPTIONS",
				"PATCH",
				"CONNECT",
			},
		),
	)

	if err := http.ListenAndServe(":"+port, cors(r)); err != nil {
		log.Fatalf("Error launching Pets REST API server: %v", err)
	}
}

func rootHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprint(w, `{"status":"running"}`)
}

func customerHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	id := mux.Vars(r)["id"]
	ctx := context.Background()

	customer, err := getCustomer(ctx, id)

	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)

		_ = json.NewEncoder(w).Encode(
			map[string]interface{}{
				"status": "fail",
				"data":   err.Error(),
			},
		)

		return
	}

	if customer == nil {
		w.WriteHeader(http.StatusNotFound)

		_ = json.NewEncoder(w).Encode(
			map[string]interface{}{
				"status": "fail",
				"data": map[string]string{
					"title": fmt.Sprintf(
						"Customer %q not found",
						id,
					),
				},
			},
		)

		return
	}

	amount, err := getAmounts(ctx, customer)

	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)

		_ = json.NewEncoder(w).Encode(
			map[string]interface{}{
				"status": "fail",
				"data": fmt.Sprintf(
					"Unable to fetch amounts: %s",
					err,
				),
			},
		)

		return
	}

	_ = json.NewEncoder(w).Encode(
		map[string]interface{}{
			"status": "success",
			"data":   amount,
		},
	)
}

type Customer struct {
	Email string `firestore:"email"`
	ID    string `firestore:"id"`
	Name  string `firestore:"name"`
	Phone string `firestore:"phone"`
}

func getCustomer(
	ctx context.Context,
	id string,
) (*Customer, error) {

	query := client.Collection("customers").Where("id", "==", id)

	iter := query.Documents(ctx)
	defer iter.Stop()

	doc, err := iter.Next()

	if err == iterator.Done {
		return nil, nil
	}

	if err != nil {
		return nil, err
	}

	var customer Customer

	if err := doc.DataTo(&customer); err != nil {
		return nil, err
	}

	return &customer, nil
}

func getAmounts(
	ctx context.Context,
	customer *Customer,
) (map[string]int64, error) {

	if customer == nil {
		return nil, fmt.Errorf("customer must not be nil")
	}

	result := map[string]int64{
		"proposed": 0,
		"approved": 0,
		"rejected": 0,
	}

	iter := client.
		Collection("customers").
		Doc(customer.Email).
		Collection("treatments").
		Documents(ctx)

	defer iter.Stop()

	for {
		doc, err := iter.Next()

		if err == iterator.Done {
			break
		}

		if err != nil {
			return nil, err
		}

		treatment := doc.Data()

		status, ok := treatment["status"].(string)

		if !ok {
			continue
		}

		switch cost := treatment["cost"].(type) {
		case int64:
			result[status] += cost

		case float64:
			result[status] += int64(cost)
		}
	}

	return result, nil
}
EOF

# Make sure Go dependencies are present
go mod tidy

echo "${CYAN}Compiling revision 0.2...${RESET}"

go build -o server

echo "${GREEN}✓ Revision 0.2 compiled successfully${RESET}"
echo

# ============================================================
# TASK 7 - BUILD + DEPLOY 0.2
# ============================================================

echo "${YELLOW}${BOLD}[8/9] Building and deploying revision 0.2...${RESET}"

gcloud builds submit \
    --tag "${IMAGE_BASE}:0.2" \
    --project="$PROJECT_ID" \
    --quiet

gcloud run deploy rest-api \
    --image="${IMAGE_BASE}:0.2" \
    --platform=managed \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --allow-unauthenticated \
    --max-instances=2 \
    --set-env-vars="PROJECT_ID=${PROJECT_ID}" \
    --quiet

SERVICE_URL="$(
    gcloud run services describe rest-api \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format='value(status.url)'
)"

echo "${GREEN}✓ Revision 0.2 deployed${RESET}"
echo

# ============================================================
# VERIFY
# ============================================================

echo "${YELLOW}${BOLD}[9/9] Verifying lab endpoints...${RESET}"
echo

echo "${CYAN}1. Health endpoint:${RESET}"
echo "${WHITE}${SERVICE_URL}/v1/${RESET}"

curl -fsS "${SERVICE_URL}/v1/"
echo
echo

echo "${CYAN}2. Customer 22530:${RESET}"
echo "${WHITE}${SERVICE_URL}/v1/customer/22530${RESET}"

CUSTOMER_RESPONSE="$(
    curl -fsS "${SERVICE_URL}/v1/customer/22530"
)"

echo "$CUSTOMER_RESPONSE"
echo

if echo "$CUSTOMER_RESPONSE" | grep -q '"proposed":1602'; then
    echo "${GREEN}✓ Customer data successfully returned${RESET}"
else
    echo "${YELLOW}⚠ API responded, but expected proposed=1602 was not found.${RESET}"
fi

echo
echo "${CYAN}Additional tests:${RESET}"
echo "  ${SERVICE_URL}/v1/customer/34216"
echo "  ${SERVICE_URL}/v1/customer/70156"
echo "  ${SERVICE_URL}/v1/customer/12345"

echo
echo "${MAGENTA}${BOLD}============================================================${RESET}"
echo "${GREEN}${BOLD}              LAB EXECUTION COMPLETED                       ${RESET}"
echo "${MAGENTA}${BOLD}                       © ePlus.DEV                           ${RESET}"
echo "${MAGENTA}${BOLD}============================================================${RESET}"
echo
echo "${CYAN}Cloud Run:${RESET}"
echo "$SERVICE_URL"
echo
echo "${CYAN}Required customer test:${RESET}"
echo "${SERVICE_URL}/v1/customer/22530"
echo