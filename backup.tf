resource "google_storage_bucket" "backup_bucket" {
  name                        = "${var.project_id}-mc-backups"
  location                    = var.region
  uniform_bucket_level_access = true

  versioning { enabled = true }

  lifecycle_rule {
    condition { age = 2 }   # เก็บ 2 วันแล้วลบทิ้ง
    action    { type = "Delete" }
  }
}
