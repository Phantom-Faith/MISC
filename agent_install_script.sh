#!/bin/bash

LOGFILE="/tmp/install_agent.log"

# Log function to capture output
log() {
    echo "$(date) - $1" >> $LOGFILE
}

log "Starting installation..."

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    log "Docker is not installed. Installing Docker..."

    # Update apt and install required dependencies
    sudo apt-get update >> $LOGFILE 2>&1
    sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common >> $LOGFILE 2>&1

    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - >> $LOGFILE 2>&1

    # Add Docker repository
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" >> $LOGFILE 2>&1

    # Update apt and install Docker CE (Community Edition)
    sudo apt-get update >> $LOGFILE 2>&1
    sudo apt-get install -y docker-ce >> $LOGFILE 2>&1

    # Start and enable Docker service
    sudo systemctl start docker >> $LOGFILE 2>&1
    sudo systemctl enable docker >> $LOGFILE 2>&1

    log "Docker installed successfully."
else
    log "Docker is already installed."
fi

# Test Docker installation
log "Testing Docker..."
sudo docker --version >> $LOGFILE 2>&1

# Pull the Docker image from Docker Hub
log "Pulling the Docker image..."
sudo docker pull phantomfaith/backup-agent-api:latest >> $LOGFILE 2>&1

# Check if the container is already running
if ! sudo docker ps -q -f name=backup-agent; then
    # Run the Docker container
    log "Running the Docker container..."
    sudo docker run -d -p 8080:8080 -v /:/host --name backup-agent phantomfaith/backup-agent-api:latest >> $LOGFILE 2>&1
else
    log "Backup agent is already running."
fi

log "Docker container is running on port 8080."
log "Installation complete."
