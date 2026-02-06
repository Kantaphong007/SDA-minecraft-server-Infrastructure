provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# 1. แยก boot disk ออกมา
resource "google_compute_disk" "minecraft_boot" {
  name  = "minecraft-boot-disk"
  zone  = var.zone
  type  = "pd-balanced"
  size  = 20

  image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
}

# 2. VM ใช้ดิสก์นี้เป็น boot disk
resource "google_compute_instance" "vm_instance" {
  name         = "minecraft-vm"
  zone         = var.zone
  machine_type = "e2-standard-2"

  boot_disk {
    source      = google_compute_disk.minecraft_boot.id
    auto_delete = true
  }

  network_interface {
    network = "default"
    access_config {}
  }

  metadata_startup_script = file("${path.module}/setup.sh")

  tags = ["http-server"]
}

resource "google_compute_firewall" "default" {
  name    = "minecraft-allow-ports"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80", "25565"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server"]
}

output "ip" {
  value = google_compute_instance.vm_instance.network_interface[0].access_config[0].nat_ip
}

output "boot_disk_name" {
  value = google_compute_disk.minecraft_boot.name
}
