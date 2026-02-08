#!/bin/bash
set -e

APP_REPO="https://github.com/Kantaphong007/SDA-minecraft-server-application"
APP_DIR="/home/ubuntu/project"
AUTHME_JAR_URL="https://github.com/AuthMe/AuthMeReloaded/releases/download/5.6.0/AuthMe-5.6.0.jar"

# 1) ติดตั้งเครื่องมือที่ต้องใช้
sudo apt-get update -y
sudo apt-get install -y docker.io git docker-compose make cron wget google-cloud-cli python3 python3-pip
sudo pip3 install psutil

# 2) start services
sudo systemctl enable --now docker
sudo systemctl enable --now cron

# 3) ดึงโค้ดแอป
if [ ! -d "$APP_DIR" ]; then
  git clone "$APP_REPO" "$APP_DIR"
else
  cd "$APP_DIR"
  git pull
fi

# 4) วาง AuthMe ลง plugins (เพราะ compose mount ./data -> /data)
mkdir -p "$APP_DIR/data/plugins"
cd "$APP_DIR/data/plugins"

# ดาวน์โหลดเฉพาะเมื่อยังไม่มีไฟล์
if [ ! -f "AuthMe-5.6.0.jar" ]; then
  wget -O AuthMe-5.6.0.jar "$AUTHME_JAR_URL"
fi

# 5) สตาร์ทเซิร์ฟเวอร์
cd "$APP_DIR"
sudo make deploy

# 6) ตั้ง cron ให้ flush ทุก 5 นาที
( sudo crontab -l 2>/dev/null; echo "*/5 * * * * docker exec mc-server rcon-cli save-all flush >>/var/log/mc-flush.log 2>&1" ) | sudo crontab -

# 7. ตั้ง cron backup รายวัน
( sudo crontab -l 2>/dev/null; echo "10 3 * * * bash /home/ubuntu/project/backup.sh >>/var/log/mc-backup.log 2>&1" ) | sudo crontab -

echo "=== Create systemd service for mc_monitor ==="

cat <<EOF >/etc/systemd/system/mc-monitor.service
[Unit]
Description=Minecraft Performance Monitor
After=docker.service
Wants=docker.service

[Service]
ExecStart=/usr/bin/python3 /home/ubuntu/project/mc_monitor.py
Restart=always
RestartSec=3
User=root
WorkingDirectory=/home/ubuntu/project

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mc-monitor
systemctl start mc-monitor
