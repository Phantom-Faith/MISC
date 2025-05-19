
#!/bin/bash

set -e

echo "Updating system..."
apt update && apt upgrade -y

echo "Installing Docker if not installed..."
if ! command -v docker &> /dev/null
then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
fi

echo "Pulling agent image..."
docker pull yourdockeruser/agent:latest

echo "Running agent container..."
docker run -d \
  --name agent \
  --restart unless-stopped \
  -v /:/host \
  -p 8081:8080 \
  yourdockeruser/agent:latest

echo "Agent installed and running."
