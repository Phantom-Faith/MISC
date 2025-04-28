#!/bin/bash

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. Installing Docker..."

    # Update apt and install required dependencies
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common

    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

    # Add Docker repository
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

    # Update apt and install Docker CE (Community Edition)
    sudo apt-get update
    sudo apt-get install -y docker-ce

    # Start and enable Docker service
    sudo systemctl start docker
    sudo systemctl enable docker

    echo "Docker installed successfully."
else
    echo "Docker is already installed."
fi

# Test Docker installation
echo "Testing Docker..."
sudo docker --version

# Pull the Docker image from Docker Hub
echo "Pulling the Docker image..."
sudo docker pull phantomfaith/backup-agent-api:latest


if ! sudo docker ps -q -f name=backup-agent; then
    # Run the Docker container
    echo "Running the Docker container..."
    sudo docker run -d -p 8080:8080 -v /:/host --name backup-agent phantomfaith/backup-agent-api:latest
else
    echo "Backup agent is already running."
fi

echo "Docker container is running on port 8080."
