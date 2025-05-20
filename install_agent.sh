#!/bin/bash

set -e

echo "Updating system..."
apt update && apt upgrade -y

echo "Installing required packages..."
apt install -y curl docker.io restic

echo "Pulling agent image..."
docker pull phantomfaith/re-agent:latest

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
  -v /usr/bin/restic:/usr/bin/restic:ro \
  -p 8081:8080 \
  phantomfaith/re-agent:latest

echo "Agent installed and running."
