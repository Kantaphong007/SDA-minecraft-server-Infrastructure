provider "google" {
  project = "minecraft-484404"
  region  = "asia-southeast1"
  zone    = "asia-southeast1-c"
}

resource "google_compute_instance" "vm_instance" {
  name         = "minecraft-vm"
  machine_type = "e2-standard-2"

  boot_disk {
    initialize_params {
      image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
    }
  }

  network_interface {
    network = "default"
    access_config {
    }
  }

  metadata_startup_script = file("setup.sh")

  tags = ["http-server"]
}

resource "google_compute_firewall" "default" {
  name    = "allow-http"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80,25565"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server"]
}

output "ip" {
  value = google_compute_instance.vm_instance.network_interface.0.access_config.0.nat_ip
}