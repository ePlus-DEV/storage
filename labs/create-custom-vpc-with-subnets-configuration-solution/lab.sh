
gcloud compute firewall-rules list --filter="network=default" --format="value(name)" | xargs -r -I {} gcloud compute firewall-rules delete {} --quiet && \
gcloud compute networks delete default --quiet && \
gcloud compute networks create custom-vpc --subnet-mode=custom && \
gcloud compute networks subnets create custom-subnet-us --network=custom-vpc --region=us-central1 --range=10.0.1.0/24 && \
gcloud compute networks subnets create custom-subnet-asia --network=custom-vpc --region=asia-southeast1 --range=10.0.2.0/24