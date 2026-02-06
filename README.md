# 🎮 Minecraft Server Infrastructure

โปรเจกต์นี้ใช้ **Terraform** สำหรับสร้าง Minecraft Server บน **Google Cloud Platform (GCP)** โดยอัตโนมัติ

---

## 📋 สิ่งที่ต้องเตรียม

1. **Google Cloud Account** พร้อม Project ที่ตั้งค่าไว้แล้ว
2. **Terraform** ติดตั้งบนเครื่อง ([วิธีติดตั้ง](https://developer.hashicorp.com/terraform/install))
3. **gcloud CLI** ติดตั้งและ login แล้ว ([วิธีติดตั้ง](https://cloud.google.com/sdk/docs/install))

---

## 🚀 วิธีสร้าง Minecraft Server

### ขั้นตอนที่ 1: โคลนโปรเจกต์

```bash
# โคลนไฟล์ Infrastructure จาก GitHub
git clone https://github.com/Kantaphong007/SDA-minecraft-server-application.git

# เข้าไปในโฟลเดอร์ terraform
cd SDA-minecraft-server-application/terraform
```

> 📁 โฟลเดอร์นี้จะมีไฟล์ `main.tf` และ `setup.sh` ที่จำเป็นสำหรับสร้าง Server

### ขั้นตอนที่ 2: ตั้งค่า Google Cloud

```bash
# Login เข้า Google Cloud
gcloud auth login

# ตั้งค่า Application Default Credentials
gcloud auth application-default login

# ตั้งค่า Project (เปลี่ยนเป็น Project ID ของคุณ)
gcloud config set project [PROJECT_ID]

# เปิดใช้งาน Compute Engine API
gcloud services enable compute.googleapis.com
```

### ขั้นตอนที่ 3: แก้ไขค่าใน `terraform.tfvars`

เปิดไฟล์ `terraform.tfvars` และแก้ไขค่าต่อไปนี้ตามที่ต้องการ:

```
project_id = "[PROJECT_ID]"         # เปลี่ยนเป็น Project ID ของคุณ
region     = "asia-southeast1"      # เปลี่ยน Region (ถ้าต้องการ)
zone       = "asia-southeast1-c"    # เปลี่ยน Zone (ถ้าต้องการ)
disk_name  = "minecraft-boot-disk"  # เปลี่ยนชื่อ disk (ถ้าต้องการ)
retention_minutes = 1440            # เปลี่ยน retention minutes (ถ้าต้องการ)
```

### ขั้นตอนที่ 4: รัน Terraform

```bash
# เริ่มต้น Terraform
terraform init

# ดูว่า Terraform จะสร้างอะไรบ้าง
terraform plan

# สร้าง Infrastructure
terraform apply
```

พิมพ์ `yes` เมื่อ Terraform ถามยืนยัน

### ขั้นตอนที่ 5: รอและเชื่อมต่อ

หลังจากรัน `terraform apply` สำเร็จ จะแสดง **IP Address** ของ Server:

```
Outputs:

ip = "xxx.xxx.xxx.xxx"
```

⏳ **รอประมาณ 2-3 นาที** ให้ Server ติดตั้ง Docker และ Minecraft Server เสร็จสมบูรณ์

จากนั้นเปิด Minecraft แล้วเชื่อมต่อด้วย:
```
IP Address  = xxx.xxx.xxx.xxx
```

---

## 🛠️ คำสั่งที่มีประโยชน์

### ดู IP Address ของ Server
```bash
terraform output ip
```

### SSH เข้า Server
```bash
gcloud compute ssh minecraft-vm --zone=asia-southeast1-c
```

### ลบ Server (ประหยัดค่าใช้จ่าย)
```bash
terraform destroy
```

---


## 💻 Spec ของ Server

- **Machine Type:** e2-standard-2 (2 vCPU, 8 GB RAM)
- **OS:** Ubuntu 22.04 LTS
- **Region:** asia-southeast1 (Singapore)
- **Ports:** 80 (HTTP), 25565 (Minecraft)

---
