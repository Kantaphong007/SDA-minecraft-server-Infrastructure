variable "project_id" {
  type = string
}

variable "zone" {
  type    = string
  default = "asia-southeast1-c"
}

variable "disk_name" {
  type = string
}

variable "retention_minutes" {
  type    = number
  default = 1440
}
