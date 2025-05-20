#!/bin/bash
set -e

echo "🔄 Updating system..."
apt update && apt upgrade -y

# Check and remove conflicting containerd package if present
if dpkg -l | grep -qw containerd; then
    echo "❌ Removing conflicting containerd package..."
    apt remove -y containerd
fi

echo "📦 Ensuring dependencies are installed..."
apt install -y curl gnupg lsb-release ca-certificates apt-transport-https software-properties-common

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "🐳 Installing Docker..."

    # Add Docker GPG key if not already added
    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
        echo "🔐 Adding Docker GPG key..."
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
            gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
    fi

    # Add Docker repo if not present
    if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
        echo "📂 Adding Docker APT repository..."
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
          https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | \
          tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt update
    fi

    # Install Docker packages
    apt install -y docker-ce docker-ce-cli containerd.io
else
    echo "✅ Docker is already installed."
fi

# Check if Restic is installed
if ! command -v restic &> /dev/null; then
    echo "💾 Installing Restic..."
    apt install -y restic
else
    echo "✅ Restic is already installed."
fi

# Pull Docker image only if not present
if ! docker image inspect phantomfaith/re-agent:latest &> /dev/null; then
    echo "📥 Pulling re-agent Docker image..."
    docker pull phantomfaith/re-agent:latest
else
    echo "✅ re-agent image already present."
fi

# Remove old container if it exists
if docker ps -a --format '{{.Names}}' | grep -Eq "^re-agent$"; then
    echo "🧹 Cleaning up existing re-agent container..."
    docker stop re-agent || true
    docker rm re-agent || true
fi

# Start container only if not running
if ! docker ps --format '{{.Names}}' | grep -Eq "^re-agent$"; then
    echo "🚀 Starting re-agent container..."
    docker run -d \
      --name re-agent \
      --restart unless-stopped \
      -v /:/host \
      -v /usr/bin/restic:/usr/bin/restic:ro \
      -p 8081:8080 \
      phantomfaith/re-agent:latest
else
    echo "✅ re-agent container is already running."
fi

echo "🎉 Agent installation complete and running."
