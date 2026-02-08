terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.16.0, < 8.0.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 7.16.0, < 8.0.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Cloud Functions Gen2 บาง resource ชัวร์สุดใช้ google-beta
provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# ทำ suffix กันชื่อ bucket ชน (global unique)
resource "random_id" "suffix" {
  byte_length = 3
}

# ----------------------------
# 1) เปิด API ที่จำเป็น (ใส่ project ชัด ๆ)
# ----------------------------
resource "google_project_service" "services" {
  project = var.project_id

  for_each = toset([
    "serviceusage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudfunctions.googleapis.com",
    "run.googleapis.com",
    "eventarc.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false
}

# ----------------------------
# 2) Bucket เก็บ zip source (ชื่อ unique)
# ----------------------------
resource "google_storage_bucket" "fn_bucket" {
  name                        = "${var.project_id}-mc-snap-fn-src-${random_id.suffix.hex}"
  location                    = "ASIA"
  uniform_bucket_level_access = true
  force_destroy               = true

  depends_on = [google_project_service.services]
}

# ----------------------------
# 3) Zip source ของ function
# ----------------------------
data "archive_file" "fn_zip" {
  type       = "zip"
  source_dir = "${path.module}/snapshot_fn"

  # อย่าใช้ folder ที่อาจไม่มี
  output_path = "${path.module}/snapshot_fn.zip"
}

resource "google_storage_bucket_object" "fn_object" {
  name   = "snapshot_fn.zip"
  bucket = google_storage_bucket.fn_bucket.name
  source = data.archive_file.fn_zip.output_path

  depends_on = [google_storage_bucket.fn_bucket]
}

# ----------------------------
# 4) Service Account สำหรับ Function + สิทธิ์
# ----------------------------
resource "google_service_account" "fn_sa" {
  account_id   = "mc-snapshot-fn"
  display_name = "Minecraft snapshot function"

  depends_on = [google_project_service.services]
}

# ให้สิทธิ์สร้าง/ลบ snapshot (เลือกให้ชัด ๆ)
resource "google_project_iam_member" "fn_sa_compute_storage" {
  project    = var.project_id
  role       = "roles/compute.storageAdmin"
  member     = "serviceAccount:${google_service_account.fn_sa.email}"
  depends_on = [google_project_service.services]
}

# ----------------------------
# 5) Cloud Functions Gen2
# ----------------------------
resource "google_cloudfunctions2_function" "mc_snapshot" {
  provider = google-beta

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
    available_memory      = "256M"
    timeout_seconds       = 60
    service_account_email = google_service_account.fn_sa.email

    environment_variables = {
      PROJECT_ID        = var.project_id
      ZONE              = var.zone
      DISK_NAME         = var.disk_name
      RETENTION_MINUTES = tostring(var.retention_minutes)
    }
  }

  depends_on = [
    google_project_service.services,
    google_project_iam_member.fn_sa_compute_storage,
    google_project_iam_member.fn_sa_compute_snapshot,
    google_storage_bucket_object.fn_object
  ]
}

# ----------------------------
# 6) Service Account สำหรับ Scheduler (OIDC)
# ----------------------------
resource "google_service_account" "scheduler_sa" {
  account_id   = "mc-snapshot-scheduler"
  display_name = "Minecraft snapshot scheduler"

  depends_on = [google_project_service.services]
}

# ให้ Scheduler เรียก service (Cloud Run backend ของ Function Gen2)
resource "google_cloud_run_v2_service_iam_member" "allow_invoker" {
  provider = google-beta

  location = google_cloudfunctions2_function.mc_snapshot.location
  name     = google_cloudfunctions2_function.mc_snapshot.service_config[0].service
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler_sa.email}"

  depends_on = [google_project_service.services, google_cloudfunctions2_function.mc_snapshot]
}

resource "google_service_account_iam_member" "allow_scheduler_token_creator" {
  service_account_id = google_service_account.scheduler_sa.name
  role               = "roles/iam.serviceAccountTokenCreator"

  # Cloud Scheduler Service Agent ของโปรเจกต์นี้
  member = "serviceAccount:service-${data.google_project.p.number}@gcp-sa-cloudscheduler.iam.gserviceaccount.com"

  depends_on = [google_project_service.services]
}

# ----------------------------
# 7) Cloud Scheduler Job: ทุก 5 นาที ที่นาที 1,6,11,... (เผื่อ flush นาที 0,5,10,...)
# ----------------------------
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

  depends_on = [
    google_project_service.services,
    google_cloud_run_v2_service_iam_member.allow_invoker,
    google_service_account_iam_member.allow_scheduler_token_creator
  ]
}

output "snapshot_function_url" {
  value = google_cloudfunctions2_function.mc_snapshot.service_config[0].uri
}
