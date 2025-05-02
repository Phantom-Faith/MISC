#!/bin/bash

LOGFILE="/tmp/install_agent.log"
CERT_DIR="/etc/backup-agent/certs"
HOST_BACKUP_DIR="/var/backup_app/backups"
CONTAINER_NAME="backup-agent"
PORT=8080

# Log function
log() {
    echo "$(date) - $1" | tee -a "$LOGFILE"
}

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

# Check and install Docker
if ! command -v docker &> /dev/null; then
    log "Docker not found. Installing..."
    run_and_log "Updating apt..." sudo apt-get update
    run_and_log "Installing dependencies..." sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
    run_and_log "Adding Docker GPG key..." curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    run_and_log "Adding Docker repo..." sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    run_and_log "Installing Docker..." sudo apt-get update && sudo apt-get install -y docker-ce
    run_and_log "Starting Docker..." sudo systemctl start docker
    run_and_log "Enabling Docker on boot..." sudo systemctl enable docker
else
    log "Docker already installed."
fi

# Test Docker
run_and_log "Checking Docker version..." sudo docker --version

# Ensure backup directory exists
log "Ensuring backup directory exists at $HOST_BACKUP_DIR"
run_and_log "Creating backup dir..." sudo mkdir -p "$HOST_BACKUP_DIR"
run_and_log "Setting permissions..." sudo chmod 755 "$HOST_BACKUP_DIR"

# Generate self-signed certificate
log "Generating self-signed certificate..."
run_and_log "Creating cert dir..." sudo mkdir -p "$CERT_DIR"
sudo openssl req -x509 -newkey rsa:4096 -sha256 -nodes \
    -keyout "$CERT_DIR/server.key" \
    -out "$CERT_DIR/server.crt" \
    -days 365 \
    -subj "/CN=localhost" >> "$LOGFILE" 2>&1

# Pull image
log "Pulling Docker image..."
run_and_log "Pulling phantomfaith/backup-agent-api..." sudo docker pull phantomfaith/backup-agent-api:latest

# Stop/remove any existing container
if sudo docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log "Stopping and removing existing container..."
    sudo docker stop "$CONTAINER_NAME" >> "$LOGFILE" 2>&1 || true
    sudo docker rm "$CONTAINER_NAME" >> "$LOGFILE" 2>&1 || true
fi

# Run container
log "Starting Docker container with TLS..."
run_and_log "Starting container..." sudo docker run -d \
    -p ${PORT}:${PORT} \
    -v /:/host:ro \
    -v "$HOST_BACKUP_DIR":/host/var/backup_app/backups \
    -v "$CERT_DIR":/certs:ro \
    -e APP_KEY="$APP_KEY" \
    --name "$CONTAINER_NAME" \
    phantomfaith/backup-agent-api:latest

log "Container is running on port ${PORT} (HTTPS)."
log "Installation complete."
