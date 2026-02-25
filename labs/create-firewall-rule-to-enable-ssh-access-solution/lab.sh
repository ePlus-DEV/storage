
VPC=$(gcloud compute instances describe $(gcloud compute instances list --format="value(name)") --zone=$(gcloud compute instances list --format="value(zone)") --format="value(networkInterfaces[0].network.basename())"); gcloud compute firewall-rules create allow-ssh --network=$VPC --allow=tcp:22 --source-ranges=0.0.0.0/0 --target-tags=http-server # drabhishek ji ka code copy karta hu mai
