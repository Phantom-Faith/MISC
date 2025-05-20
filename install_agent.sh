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

echo "Installing restic..."
curl -L https://github.com/restic/restic/releases/latest/download/restic_$(uname -s | tr '[:upper:]' '[:lower:]')_amd64.bz2 -o restic.bz2
bunzip2 -f restic.bz2
chmod +x restic
mv -f restic /usr/local/bin/restic

echo "Pulling agent image..."
docker pull phantomfaith/re-agent:latest

# Check if container is running or exists
if docker ps -a --format '{{.Names}}' | grep -Eq "^re-agent$"; then
    echo "Removing existing re-agent container..."
    docker stop re-agent || true
    docker rm re-agent || true
fi

echo "Running agent container..."
docker run -d \
  --name re-agent \
  --restart unless-stopped \
  -v /:/host \
  -v /usr/local/bin/restic:/usr/bin/restic:ro \
  -p 8081:8080 \
  phantomfaith/re-agent:latest

echo "Agent installed and running."
