#!/bin/bash
set -e

echo "Updating system..."
apt update && apt upgrade -y

echo "Removing conflicting containerd package..."
apt remove -y containerd || true

echo "Installing dependencies..."
apt install -y curl gnupg lsb-release ca-certificates apt-transport-https software-properties-common

echo "Installing Docker (official repository)..."

# Add Docker GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repo
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
apt install -y docker-ce docker-ce-cli containerd.io

echo "Installing restic..."
apt install -y restic

echo "Pulling agent image..."
docker pull phantomfaith/re-agent:latest

# Clean up old container if exists
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
  -p 8080:8080 \
  phantomfaith/re-agent:latest

echo "✅ Agent installed and running."
