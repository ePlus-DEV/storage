#!/usr/bin/env bash
# ===========================================
# Qwiklabs Terraform Lab - Full Auto Runner
# Language: EN
# ===========================================
set +e  # do NOT exit the shell on single command failures; we recover gracefully

# ---------- Pretty logs ----------
BOLD=$(tput bold 2>/dev/null); RESET=$(tput sgr0 2>/dev/null)
RED=$(tput setaf 1 2>/dev/null); GREEN=$(tput setaf 2 2>/dev/null); YELLOW=$(tput setaf 3 2>/dev/null); MAGENTA=$(tput setaf 5 2>/dev/null)
banner(){ echo -e "\n${BOLD}${MAGENTA}==> $*${RESET}\n"; }
ok(){ echo -e "${GREEN}✔${RESET} $*"; }
warn(){ echo -e "${YELLOW}⚠${RESET} $*"; }
die(){ echo -e "${RED}✖${RESET} $*"; exit 1; }

banner "Starting Execution - ePlus.DEV"

# ---------- Detect environment ----------
PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]] && die "Can't detect PROJECT_ID. Run: gcloud config set project <ID>"

# Zone order: project default zone (metadata) → gcloud config → fallback
ZONE="$(gcloud compute project-info describe --format='value(commonInstanceMetadata.items[google-compute-default-zone])' 2>/dev/null)"
[[ -z "$ZONE" || "$ZONE" == "(unset)" ]] && ZONE="$(gcloud config get-value compute/zone 2>/dev/null)"
[[ -z "$ZONE" || "$ZONE" == "(unset)" ]] && ZONE="us-central1-a"

REGION="${ZONE%-*}"
[[ -z "$REGION" || "$REGION" == "(unset)" ]] && REGION="us-central1"

BUCKET_NAME="${PROJECT_ID}-tf-lab-$(date +%s)"  # ensure global uniqueness

ok "PROJECT_ID = $PROJECT_ID"
ok "REGION     = $REGION"
ok "ZONE       = $ZONE"
ok "BUCKET     = $BUCKET_NAME"

# ---------- Helpers ----------
tf_clean() {
  rm -rf .terraform .terraform.lock.hcl 2>/dev/null
}

tf_init_v3_then_v5() {
  # Try google provider 3.5.0 first (as in the lab docs).
  terraform init
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    warn "terraform init failed (likely due to old lock). Switching provider to ~> 5.0 and upgrading..."
    sed -i 's/version = "3\.5\.0"/version = "~> 5.0"/' main.tf
    terraform init -upgrade -reconfigure || return 1
  fi
  return 0
}

write_tf_task1_vpc() {
cat > main.tf <<EOF
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "3.5.0"
    }
  }
}
provider "google" {
  project = "${PROJECT_ID}"
  region  = "${REGION}"
  zone    = "${ZONE}"
}
resource "google_compute_network" "vpc_network" {
  name = "terraform-network"
}
EOF
}

write_tf_task2_vm_debian() {
  local mode="${1:-no}"
  local TAG_BLOCK=""
  [[ "$mode" == "tags" ]] && TAG_BLOCK='tags = ["web","dev"]'
cat > main.tf <<EOF
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "3.5.0"
    }
  }
}
provider "google" {
  project = "${PROJECT_ID}"
  region  = "${REGION}"
  zone    = "${ZONE}"
}
resource "google_compute_network" "vpc_network" {
  name = "terraform-network"
}
resource "google_compute_instance" "vm_instance" {
  name         = "terraform-instance"
  machine_type = "e2-micro"
  ${TAG_BLOCK}
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }
  network_interface {
    network = google_compute_network.vpc_network.name
    access_config {}
  }
}
EOF
}

write_tf_task2_vm_cos() {
cat > main.tf <<EOF
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "3.5.0"
    }
  }
}
provider "google" {
  project = "${PROJECT_ID}"
  region  = "${REGION}"
  zone    = "${ZONE}"
}
resource "google_compute_network" "vpc_network" {
  name = "terraform-network"
}
resource "google_compute_instance" "vm_instance" {
  name         = "terraform-instance"
  machine_type = "e2-micro"
  tags         = ["web","dev"]
  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
    }
  }
  network_interface {
    network = google_compute_network.vpc_network.name
    access_config {}
  }
}
EOF
}

write_tf_task3_static_ip_phase1() {
# Recreate VM + create static address (not attached yet)
cat > main.tf <<EOF
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "3.5.0"
    }
  }
}
provider "google" {
  project = "${PROJECT_ID}"
  region  = "${REGION}"
  zone    = "${ZONE}"
}
resource "google_compute_network" "vpc_network" {
  name = "terraform-network"
}
resource "google_compute_instance" "vm_instance" {
  name         = "terraform-instance"
  machine_type = "e2-micro"
  tags         = ["web","dev"]
  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
    }
  }
  network_interface {
    network = google_compute_network.vpc_network.name
    access_config {}
  }
}
resource "google_compute_address" "vm_static_ip" {
  name   = "terraform-static-ip"
  region = "${REGION}"
}
EOF
}

write_tf_task3_static_ip_phase2_attach() {
# Attach the static IP + add bucket + dependent VM
cat > main.tf <<EOF
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "3.5.0"
    }
  }
}
provider "google" {
  project = "${PROJECT_ID}"
  region  = "${REGION}"
  zone    = "${ZONE}"
}
resource "google_compute_network" "vpc_network" {
  name = "terraform-network"
}
resource "google_compute_address" "vm_static_ip" {
  name   = "terraform-static-ip"
  region = "${REGION}"
}
resource "google_compute_instance" "vm_instance" {
  name         = "terraform-instance"
  machine_type = "e2-micro"
  tags         = ["web","dev"]
  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
    }
  }
  network_interface {
    network = google_compute_network.vpc_network.self_link
    access_config {
      nat_ip = google_compute_address.vm_static_ip.address
    }
  }
}
resource "google_storage_bucket" "example_bucket" {
  name     = "${BUCKET_NAME}"
  location = "US"
  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }
}
resource "google_compute_instance" "another_instance" {
  depends_on   = [google_storage_bucket.example_bucket]
  name         = "terraform-instance-2"
  machine_type = "e2-micro"
  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
    }
  }
  network_interface {
    network = google_compute_network.vpc_network.self_link
    access_config {}
  }
}
EOF
}

write_tf_task4_provisioner_local_exec() {
# Add local-exec provisioner to write VM name + public IP to ip_address.txt
cat > main.tf <<'EOF'
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "3.5.0"
    }
  }
}
provider "google" {
  project = "__PROJECT_ID__"
  region  = "__REGION__"
  zone    = "__ZONE__"
}
resource "google_compute_network" "vpc_network" {
  name = "terraform-network"
}
resource "google_compute_address" "vm_static_ip" {
  name   = "terraform-static-ip"
  region = "__REGION__"
}
resource "google_compute_instance" "vm_instance" {
  name         = "terraform-instance"
  machine_type = "e2-micro"
  tags         = ["web","dev"]
  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
    }
  }
  network_interface {
    network = google_compute_network.vpc_network.self_link
    access_config {
      nat_ip = google_compute_address.vm_static_ip.address
    }
  }
  provisioner "local-exec" {
    command = "echo ${self.name}: ${self.network_interface[0].access_config[0].nat_ip} >> ip_address.txt"
  }
}
resource "google_storage_bucket" "example_bucket" {
  name     = "__BUCKET_NAME__"
  location = "US"
  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }
}
resource "google_compute_instance" "another_instance" {
  depends_on   = [google_storage_bucket.example_bucket]
  name         = "terraform-instance-2"
  machine_type = "e2-micro"
  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
    }
  }
  network_interface {
    network = google_compute_network.vpc_network.self_link
    access_config {}
  }
}
EOF
  sed -i "s#__PROJECT_ID__#${PROJECT_ID}#g" main.tf
  sed -i "s#__REGION__#${REGION}#g" main.tf
  sed -i "s#__ZONE__#${ZONE}#g" main.tf
  sed -i "s#__BUCKET_NAME__#${BUCKET_NAME}#g" main.tf
}

# ---------- Execute Flow ----------

# Task 1: VPC
banner "Task 1: Build infrastructure (VPC)"
tf_clean
write_tf_task1_vpc
tf_init_v3_then_v5 || die "terraform init failed"
terraform apply -auto-approve || die "apply failed (Task 1)"
ok "Task 1 done"

# Task 2: Add VM (Debian 11)
banner "Task 2: Create VM (Debian 11)"
write_tf_task2_vm_debian
tf_clean
tf_init_v3_then_v5 || die "terraform init failed"
terraform apply -auto-approve || die "apply failed (Task 2 - create VM)"

# Task 2: Update tags
banner "Task 2: Update VM tags"
write_tf_task2_vm_debian "tags"
tf_clean
tf_init_v3_then_v5 || die "terraform init failed"
terraform apply -auto-approve || die "apply failed (Task 2 - update tags)"

# Task 2: Destructive change (switch to COS)
banner "Task 2: Destructive change (switch to COS)"
write_tf_task2_vm_cos
tf_clean
tf_init_v3_then_v5 || die "terraform init failed"
terraform apply -auto-approve || die "apply failed (Task 2 - switch to COS)"
ok "Task 2 done"

# Destroy per lab flow
banner "Destroy all (per lab step)"
terraform destroy -auto-approve || die "destroy failed"

# Task 3: Create static IP (not attached yet)
banner "Task 3: Static IP (phase 1 - create address only)"
write_tf_task3_static_ip_phase1
tf_clean
tf_init_v3_then_v5 || die "terraform init failed"
terraform plan || warn "plan had warnings"
ok "Phase 1 plan OK"

# Task 3: Attach static IP, add bucket & dependent instance (plan-out/apply)
banner "Task 3: Attach static IP + bucket + dependent instance"
write_tf_task3_static_ip_phase2_attach
tf_clean
tf_init_v3_then_v5 || die "terraform init failed"
terraform plan -out static_ip || die "plan failed (phase 2)"
terraform apply "static_ip" || die "apply plan failed (phase 2)"
ok "Task 3 done"

# Task 4: Provisioner local-exec
banner "Task 4: Provisioner local-exec (write ip_address.txt)"
write_tf_task4_provisioner_local_exec
tf_clean
tf_init_v3_then_v5 || die "terraform init failed"
# Force the provisioner to run again
terraform taint google_compute_instance.vm_instance >/dev/null 2>&1
terraform apply -auto-approve || die "apply failed (Task 4)"
ok "Task 4 done - check file ip_address.txt"

banner "All tasks completed 🎉  - ePlus.DEV"