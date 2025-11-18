#!/bin/bash

echo "=== Task 0: Cloud Shell Info ==="
gcloud auth list
gcloud config list project

echo "=== Task 2: Named Volumes ==="
docker volume create mydata
docker volume inspect mydata

docker run -it -v mydata:/data alpine ash << 'EOF'
cd /data
echo "Hello from inside the container!" > myfile.txt
exit
EOF

docker stop $(docker ps -aq) 2>/dev/null
docker rm $(docker ps -aq) 2>/dev/null

docker run -it -v mydata:/data alpine ash << 'EOF'
cd /data
ls -l
cat myfile.txt
exit
EOF

docker volume rm mydata

echo "=== Task 3: Bind Mounts ==="
mkdir -p ~/host_data
echo "Hello from the host!" > ~/host_data/hostfile.txt

docker run -it -v /home/$USER/host_data:/data alpine ash << 'EOF'
echo "This line added from container" >> /data/hostfile.txt
cat /data/hostfile.txt
exit
EOF

cat ~/host_data/hostfile.txt
rm -rf ~/host_data

echo "=== Task 4: Docker Compose ==="
mkdir -p docker_compose_app
cd docker_compose_app

cat > docker-compose.yml << 'EOF'
version: "3.3"
services:
  web:
    image: nginx:latest
    ports:
      - "8080:80"
    volumes:
      - web_data:/usr/share/nginx/html
volumes:
  web_data:
EOF

cat > index.html << 'EOF'
<html>
<head>
  <title>Docker Compose Volume Example</title>
</head>
<body>
  <div><strong>Hello from Docker Compose!</strong></div>
  <p>This content is served from a Docker volume.</p>
</body>
</html>
EOF

docker-compose up -d
curl http://localhost:8080
docker-compose down

echo "=== LAB COMPLETED ==="
