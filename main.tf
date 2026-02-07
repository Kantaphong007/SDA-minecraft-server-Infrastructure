provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# 1. เปิด APIs ที่จำเป็น
resource "google_project_service" "services" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "dns.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
    "eventarc.googleapis.com",
    "cloudscheduler.googleapis.com",
    "iam.googleapis.com",
    "storage.googleapis.com",
  ])
  service            = each.value
  disable_on_destroy = false
}

# 2. จอง Static IP สำหรับ Load Balancer
resource "google_compute_address" "mc_static_ip" {
  name         = "minecraft-static-ip"
  region       = var.region
  depends_on   = [google_project_service.services]
}

# 3. สร้าง GKE Autopilot Cluster
resource "google_container_cluster" "primary" {
  name     = "minecraft-cluster"
  location = var.region 

  enable_autopilot = true
  deletion_protection = false 

  depends_on = [google_project_service.services]
}

resource "google_compute_firewall" "default" {
  name    = "minecraft-allow-ports-k8s"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["25565"]
  }

  source_ranges = ["0.0.0.0/0"]
}

# --- OUTPUTS ---
output "load_balancer_ip" {
  value = google_compute_address.mc_static_ip.address
}

output "gke_cluster_name" {
  value = google_container_cluster.primary.name
}
