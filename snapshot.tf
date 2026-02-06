terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.5"
    }
  }
}

variable "project_id" { type = string }
variable "zone"       { type = string  default = "asia-southeast1-c" }
variable "disk_name"  { type = string }
variable "retention_minutes" {
  type    = number
  default = 1440    # 1 วัน
}

# เปิด API ที่ต้องใช้
resource "google_project_service" "services" {
  for_each = toset([
    "compute.googleapis.com",
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

# bucket สำหรับเก็บ zip source
resource "google_storage_bucket" "fn_bucket" {
  name                        = "${var.project_id}-mc-snap-fn-src"
  location                    = "ASIA"
  uniform_bucket_level_access = true
  force_destroy               = true
  depends_on                  = [google_project_service.services]
}

data "archive_file" "fn_zip" {
  type        = "zip"
  source_dir  = "${path.module}/snapshot_fn"
  output_path = "${path.module}/.terraform-build/snapshot_fn.zip"
}

resource "google_storage_bucket_object" "fn_object" {
  name   = "snapshot_fn.zip"
  bucket = google_storage_bucket.fn_bucket.name
  source = data.archive_file.fn_zip.output_path
}

# service account สำหรับ function
resource "google_service_account" "fn_sa" {
  account_id   = "mc-snapshot-fn"
  display_name = "Minecraft snapshot function"
}

resource "google_project_iam_member" "fn_sa_compute" {
  role   = "roles/compute.storageAdmin"
  member = "serviceAccount:${google_service_account.fn_sa.email}"
  depends_on = [google_project_service.services]
}

# Cloud Functions Gen2
resource "google_cloudfunctions2_function" "mc_snapshot" {
  name     = "mc-snapshot"
  location = var.region

  build_config {
    runtime     = "python311"
    entry_point = "snapshot"
    source {
      storage_source {
        bucket = google_storage_bucket.fn_bucket.name
        object = google_storage_bucket_object.fn_object.name
      }
    }
  }

  service_config {
    available_memory       = "256M"
    timeout_seconds        = 60
    service_account_email  = google_service_account.fn_sa.email

    environment_variables = {
      PROJECT_ID        = var.project_id
      ZONE              = var.zone
      DISK_NAME         = var.disk_name
      RETENTION_MINUTES = tostring(var.retention_minutes)
    }
  }

  depends_on = [google_project_service.services]
}

# service account สำหรับ scheduler (ใช้ OIDC)
resource "google_service_account" "scheduler_sa" {
  account_id   = "mc-snapshot-scheduler"
  display_name = "Minecraft snapshot scheduler"
}

# อนุญาตให้ scheduler เรียก Cloud Run ที่อยู่เบื้องหลัง Function
resource "google_cloud_run_v2_service_iam_member" "allow_invoker" {
  location = google_cloudfunctions2_function.mc_snapshot.location
  name     = google_cloudfunctions2_function.mc_snapshot.service_config[0].service
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler_sa.email}"
  depends_on = [google_project_service.services]
}

# Scheduler: ทุก 5 นาที แต่ตั้งให้ “ช้ากว่า flush 1 นาที”
# flush (VM cron) จะรันที่นาที 0,5,10,...
# snapshot จะรันที่นาที 1,6,11,... เพื่อให้ flush เขียนดิสก์ก่อน
resource "google_cloud_scheduler_job" "mc_snap" {
  name      = "mc-snap-5min"
  region    = var.region
  schedule  = "1-59/5 * * * *"
  time_zone = "Asia/Bangkok"

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.mc_snapshot.service_config[0].uri

    oidc_token {
      service_account_email = google_service_account.scheduler_sa.email
      audience              = google_cloudfunctions2_function.mc_snapshot.service_config[0].uri
    }
  }

  depends_on = [google_project_service.services]
}

output "snapshot_function_url" {
  value = google_cloudfunctions2_function.mc_snapshot.service_config[0].uri
}
