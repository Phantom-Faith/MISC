#!/bin/bash

LOGFILE="/tmp/install_agent.log"
HOST_BACKUP_DIR="/var/backup_app/backups"
CONTAINER_NAME="backup-agent"
PORT=8080

# Generate a random word and get the server IP dynamically
SERVER_IP=$(curl -s http://icanhazip.com)  # Get the public IP address
RANDOM_WORD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 8)  # Generate a random 8-character string

# Construct the dynamic domain name
DOMAIN="${RANDOM_WORD}-${SERVER_IP}.sslip.io"

log "Generated dynamic domain: $DOMAIN"

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

# Step 1: Install Docker if not already installed
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

# Step 2: Test Docker
run_and_log "Checking Docker version..." sudo docker --version

# Step 3: Ensure backup directory exists
log "Ensuring backup directory exists at $HOST_BACKUP_DIR"
run_and_log "Creating backup dir..." sudo mkdir -p "$HOST_BACKUP_DIR"
run_and_log "Setting permissions..." sudo chmod 755 "$HOST_BACKUP_DIR"

# Step 4: Pull Docker image for the backup agent
log "Pulling Docker image..."
run_and_log "Pulling phantomfaith/backup-agent-api..." sudo docker pull phantomfaith/backup-agent-api:latest

# Step 5: Stop/remove any existing container
if sudo docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log "Stopping and removing existing container..."
    sudo docker stop "$CONTAINER_NAME" >> "$LOGFILE" 2>&1 || true
    sudo docker rm "$CONTAINER_NAME" >> "$LOGFILE" 2>&1 || true
fi

# Step 6: Run the Backup Agent container
log "Starting Docker container with TLS..."
run_and_log "Starting container..." sudo docker run -d \
    -p ${PORT}:${PORT} \
    -v /:/host:ro \
    -v "$HOST_BACKUP_DIR":/host/var/backup_app/backups \
    -e APP_KEY="$APP_KEY" \
    --name "$CONTAINER_NAME" \
    phantomfaith/backup-agent-api:latest

# Step 7: Set up Nginx as a reverse proxy with SSL using Certbot
log "Setting up Nginx reverse proxy..."

# Step 7.1: Pull Nginx Docker image
run_and_log "Pulling Nginx image..." sudo docker pull nginx:latest

# Step 7.2: Create a Nginx configuration file for the reverse proxy
NGINX_CONF="/etc/nginx/sites-available/backup-api"

cat <<EOF | sudo tee "$NGINX_CONF"
server {
    listen 80;
    server_name $DOMAIN;

    # Redirect HTTP to HTTPS
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    # SSL configuration (could be enhanced)
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384';

    location / {
        proxy_pass http://localhost:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Step 7.3: Create a symbolic link to enable Nginx config
log "Enabling Nginx site configuration..."
run_and_log "Creating symlink for Nginx configuration..." sudo ln -s "$NGINX_CONF" /etc/nginx/sites-enabled/

# Step 7.4: Install Certbot and obtain SSL certificates
log "Installing Certbot..."
run_and_log "Installing Certbot..." sudo apt-get install -y certbot python3-certbot-nginx
log "Obtaining SSL certificates..."
run_and_log "Obtaining SSL certificates for domain $DOMAIN..." sudo certbot --nginx -d "$DOMAIN" --agree-tos --no-eff-email --email your-email@example.com

# Step 8: Test Nginx configuration for errors
log "Testing Nginx configuration..."
sudo nginx -t || exit 1

# Step 9: Restart Nginx to apply the configuration
log "Restarting Nginx..."
run_and_log "Restarting Nginx..." sudo systemctl restart nginx

# Final Message
log "Nginx is set up with SSL/TLS, and the backup agent is running on https://$DOMAIN."
log "Installation complete."
