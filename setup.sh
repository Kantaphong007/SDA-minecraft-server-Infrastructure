# 1. ลง Docker และ Git
sudo apt-get update -y
sudo apt-get install -y docker.io git docker-compose make

# 2. เริ่ม Docker
sudo systemctl start docker
sudo systemctl enable docker

# 3. ดึงโค้ดทั้งโปรเจกต์ลงมา
git clone https://github.com/Kantaphong007/SDA-minecraft-server-application /home/ubuntu/project

# 4. Run container
cd /home/ubuntu/project
sudo make deploy

# 5. ตั้ง cron ให้ flush ทุก 5 นาที
( sudo crontab -l 2>/dev/null; echo "*/5 * * * * docker exec mc-server rcon-cli save-all flush >>/var/log/mc-flush.log 2>&1" ) | sudo crontab -
