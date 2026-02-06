provider "google" {
  project = "[PROJECT_ID]"
  region  = "asia-southeast1"
  zone    = "asia-southeast1-c"
}

# 1. แยก boot disk ออกมาเป็น resource
resource "google_compute_disk" "minecraft_boot" {
  name  = "minecraft-boot-disk"
  zone  = "asia-southeast1-c"
  type  = "pd-balanced"
  size  = 20              # GB ปรับได้ตามต้องการ

  image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
}

# 2. VM ใช้ boot disk จาก resource ด้านบน
resource "google_compute_instance" "vm_instance" {
  name         = "minecraft-vm"
  zone         = "asia-southeast1-c"
  machine_type = "e2-standard-2"

  boot_disk {
    source      = google_compute_disk.minecraft_boot.id
    auto_delete = true   # ถ้า destroy VM แล้วอยากให้ดิสก์หายด้วย -> true
                          # ถ้าอยากเก็บดิสก์ไว้แม้ลบ VM -> false
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
