#!/bin/bash

LOGFILE="/tmp/install_agent.log"

# Log function to capture output to both logfile and console
log() {
    echo "$(date) - $1" | tee -a "$LOGFILE"
}

# Execute a command and log its output
run_and_log() {
    log "$1"
    shift
    "$@" >> "$LOGFILE" 2>&1
    if [ $? -ne 0 ]; then
        log "Error: Command failed - $*"
        exit 1
    fi
}

log "Starting installation..."

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    log "Docker is not installed. Installing Docker..."

    run_and_log "Updating apt..." sudo apt-get update
    run_and_log "Installing dependencies..." sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    run_and_log "Adding Docker GPG key..." curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    run_and_log "Adding Docker repository..." sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    run_and_log "Updating apt after adding Docker repo..." sudo apt-get update
    run_and_log "Installing Docker CE..." sudo apt-get install -y docker-ce
    run_and_log "Starting Docker service..." sudo systemctl start docker
    run_and_log "Enabling Docker service..." sudo systemctl enable docker

    log "Docker installed successfully."
else
    log "Docker is already installed."
fi

# Test Docker installation
log "Testing Docker installation..."
run_and_log "Checking Docker version..." sudo docker --version

# Create backup directory on host (Option 2: direct host path)
HOST_BACKUP_DIR="/var/backup_app/backups"
log "Ensuring host backup directory exists at $HOST_BACKUP_DIR"
run_and_log "Creating backup directory..." sudo mkdir -p "$HOST_BACKUP_DIR"
run_and_log "Setting permissions on backup directory..." sudo chmod 755 "$HOST_BACKUP_DIR"

# Pull the Docker image
log "Pulling the Docker image..."
run_and_log "Pulling phantomfaith/backup-agent-api..." sudo docker pull phantomfaith/backup-agent-api:latest

# Check if the container is already running
if ! sudo docker ps -q -f name=backup-agent > /dev/null; then
    # Run the Docker container
    log "Running the Docker container with APP_KEY and host backup mount..."
    run_and_log "Starting container..." sudo docker run -d \
        -p 8080:8080 \
        -v /:/host:ro \
        --name backup-agent \
        -e APP_KEY="$APP_KEY" \
        phantomfaith/backup-agent-api:latest
else
    log "Backup agent is already running."
fi

log "Docker container is running on port 8080."
log "Installation complete."
