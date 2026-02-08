#!/bin/bash
set -e

APP_REPO="https://github.com/Kantaphong007/SDA-minecraft-server-application"
APP_DIR="/home/ubuntu/project"
AUTHME_JAR_URL="https://github.com/AuthMe/AuthMeReloaded/releases/download/5.6.0/AuthMe-5.6.0.jar"

# 1) tools
sudo apt-get update -y
sudo apt-get install -y \
  docker.io docker-compose git make cron wget \
  python3 python3-psutil \
  google-cloud-cli gettext-base

# 2) services
sudo systemctl enable --now docker
sudo systemctl enable --now cron

# 3) clone app
if [ ! -d "$APP_DIR" ]; then
  sudo git clone "$APP_REPO" "$APP_DIR"
else
  cd "$APP_DIR"
  sudo git pull
fi

# 4) AuthMe
mkdir -p "$APP_DIR/data/plugins"
cd "$APP_DIR/data/plugins"
[ ! -f AuthMe-5.6.0.jar ] && wget -O AuthMe-5.6.0.jar "$AUTHME_JAR_URL"

# 5) start minecraft (K8s / docker แล้วแต่ branch)
cd "$APP_DIR"
make deploy

# 6) save flush ทุก 5 นาที
( sudo crontab -l 2>/dev/null; \
  echo "*/5 * * * * docker exec mc-server rcon-cli save-all flush >>/var/log/mc-flush.log 2>&1" \
) | sudo crontab -

# 7) daily backup
( sudo crontab -l 2>/dev/null; \
  echo "10 3 * * * bash $APP_DIR/backup.sh >>/var/log/mc-backup.log 2>&1" \
) | sudo crontab -

# 8) mc_monitor service
cat <<EOF | sudo tee /etc/systemd/system/mc-monitor.service
[Unit]
Description=Minecraft Performance Monitor
After=docker.service
Wants=docker.service

[Service]
ExecStart=/usr/bin/python3 $APP_DIR/mc_monitor.py
Restart=always
RestartSec=3
User=root
WorkingDirectory=$APP_DIR

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable --now mc-monitor
