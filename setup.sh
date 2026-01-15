# 1. ลง Docker และ Git
sudo apt-get update -y
sudo apt-get install -y docker.io git

# 2. เริ่ม Docker
sudo systemctl start docker
sudo systemctl enable docker

# 3. ดึงโค้ดทั้งโปรเจกต์ลงมา
git clone https://github.com/Kantaphong007/SDA-minecraft-server-application /home/ubuntu/project

# 4. เข้าไปสร้าง Docker Image และรัน
cd /home/ubuntu/project
sudo docker build -t my-webapp .
sudo docker run -d -p 80:80 --name webserver my-webapp