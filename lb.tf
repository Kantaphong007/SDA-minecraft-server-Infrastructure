# 1. จอง Static IP สำหรับ Load Balancer
resource "google_compute_address" "lb_ip" {
  name   = "minecraft-lb-static-ip"
  region = var.region
}

# 2. จัดกลุ่ม VM 
resource "google_compute_instance_group" "mc_vms" {
  name        = "mc-instance-group"
  zone        = var.zone
  
  instances   = [google_compute_instance.vm_instance.self_link] 

  named_port {
    name = "mc-port"
    port = 25565
  }
}

# 3. สร้าง Health Check
resource "google_compute_region_health_check" "mc_check" {
  name   = "mc-health-check"
  region = var.region

  tcp_health_check {
    port = "25565"
  }
}

# 4. Backend Service
resource "google_compute_region_backend_service" "mc_backend" {
  name                  = "mc-backend-service"
  region                = var.region
  load_balancing_scheme = "EXTERNAL"
  protocol              = "TCP"
  health_checks         = [google_compute_region_health_check.mc_check.id]

  backend {
    group          = google_compute_instance_group.mc_vms.id
    balancing_mode = "CONNECTION"
  }
}

# 5. Forwarding Rule (ทางเข้าหลัก)
resource "google_compute_forwarding_rule" "mc_lb_rule" {
  name                  = "mc-lb-forwarding-rule"
  region                = var.region
  ip_address            = google_compute_address.lb_ip.address
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "25565"
  backend_service       = google_compute_region_backend_service.mc_backend.id
}

# 6. Firewall เพิ่มเติมสำหรับ Health Check 
resource "google_compute_firewall" "allow_lb_health_check" {
  name          = "allow-lb-health-check"
  network       = "default"
  direction     = "INGRESS"
  source_ranges = ["35.191.0.0/16", "209.85.152.0/22"] 
  
  allow {
    protocol = "tcp"
    ports    = ["25565"]
  }

  target_tags = ["minecraft-server"]
}

# Output เลข IP ของ Load Balancer
output "load_balancer_ip" {
  value = google_compute_address.lb_ip.address
}