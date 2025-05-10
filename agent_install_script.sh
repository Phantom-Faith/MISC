#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

LOGFILE="/tmp/install_agent.log"
exec > >(tee -a "$LOGFILE") 2>&1

HOST_BACKUP_DIR="/var/backup_app/backups"
CONTAINER_NAME="backup-agent"
PORT=8080
EMAIL="phantomFaith4@gmail.com"

echo "=== System Update ==="
apt-get update -qq
apt-get upgrade -y -qq
echo "✓ System packages updated"

get_server_ip() {
    ip=$(hostname -I | awk '{print $1}')
    echo "$ip"
}

domain="agent.$(get_server_ip).sslip.io"

detect_web_server() {
    is_service_active() {
        systemctl is-active --quiet "$1"
    }

    if (command -v apache2 >/dev/null 2>&1 || command -v httpd >/dev/null 2>&1) && \
       (is_service_active apache2 || is_service_active httpd || pgrep -x apache2 >/dev/null || pgrep -x httpd >/dev/null); then
        echo "apache"
    elif command -v nginx >/dev/null 2>&1 && \
         (is_service_active nginx || pgrep -x nginx >/dev/null); then
        echo "nginx"
    elif command -v caddy >/dev/null 2>&1 && \
         (is_service_active caddy || pgrep -x caddy >/dev/null); then
        echo "caddy"
    else
        echo "none"
    fi
}

install_certbot() {
    apt-get install -y -qq certbot python3-certbot-apache python3-certbot-nginx
    echo "✓ Certbot installed"
}

get_cert_apache() {
    echo "Obtaining SSL certificate for $domain with Apache..."
    certbot --apache -d "$domain" --non-interactive --agree-tos --email "$EMAIL"
    echo "✓ SSL certificate obtained via Apache"
}

append_apache_conf() {
    local file="/etc/apache2/sites-available/agent.conf"
    cat <<EOF > "$file"
<VirtualHost *:80>
    ServerName $domain

    ProxyPreserveHost On

    ProxyPass /ws/ ws://localhost:$PORT/
    ProxyPassReverse /ws/ ws://localhost:$PORT/

    ProxyPass / http://localhost:$PORT/
    ProxyPassReverse / http://localhost:$PORT/

    ErrorLog ${APACHE_LOG_DIR}/$domain-error.log
    CustomLog ${APACHE_LOG_DIR}/$domain-access.log combined
</VirtualHost>
EOF

    a2enmod proxy proxy_http ssl headers rewrite > /dev/null 2>&1 || true
    a2ensite agent.conf > /dev/null 2>&1
    systemctl reload apache2 || systemctl restart apache2
    echo "✓ Apache site configured for $domain"
}

append_nginx_conf() {
    mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled

    echo "Stopping potential port 80 conflicts..."
    systemctl stop apache2 2>/dev/null || true
    systemctl disable apache2 2>/dev/null || true
    systemctl stop httpd 2>/dev/null || true
    systemctl disable httpd 2>/dev/null || true
    pkill -f apache2 || true
    pkill -f httpd || true

    echo "Killing any process using port 80..."
    fuser -k 80/tcp || true

    echo "Writing Nginx config..."
    local file="/etc/nginx/sites-available/agent.conf"
    cat <<EOF > "$file"
server {
    listen 80;
    server_name $domain;

    location / {
        proxy_pass http://localhost:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

      
        # WebSocket configuration
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade; 
        proxy_set_header Connection 'upgrade';
    }

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
}
EOF

    ln -sf "$file" /etc/nginx/sites-enabled/agent.conf

    echo "Starting Nginx..."
    systemctl daemon-reexec
    systemctl restart nginx || journalctl -xeu nginx
    echo "✓ Nginx site configured for $domain"
}

get_cert_nginx() {
    echo "Obtaining SSL certificate for $domain with Nginx..."
    certbot --nginx -d "$domain" --non-interactive --agree-tos --email "$EMAIL"
    echo "✓ SSL certificate obtained via Nginx"
}

install_caddy() {
    apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https curl gnupg2
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
    apt-get update -qq
    apt-get install -y -qq caddy
    echo "✓ Caddy installed"
}

append_caddyfile() {
    local file="/etc/caddy/Caddyfile"
    cat <<EOF > "$file"
$domain {
    reverse_proxy localhost:$PORT
}
EOF
    systemctl enable caddy > /dev/null 2>&1
    systemctl restart caddy
    echo "✓ Caddy config applied for $domain"
}

install_certbot_if_needed() {
    if ! command -v certbot > /dev/null 2>&1; then
        install_certbot
    fi
}

install_proxy_server() {
    server=$(detect_web_server)

    case "$server" in
        apache)
            echo "Apache detected"
            append_apache_conf
            install_certbot_if_needed
            get_cert_apache
            ;;
        nginx)
            echo "Nginx detected"
            append_nginx_conf
            install_certbot_if_needed
            get_cert_nginx
            ;;
        caddy)
            echo "Caddy detected"
            append_caddyfile
            ;;
        *)
            echo "No known web server found, installing Caddy"
            install_caddy
            append_caddyfile
            ;;
    esac
}

install_proxy_server

echo
echo "=== Docker Check ==="

install_docker_fallback() {
    echo "Installing Docker using fallback method (docker.io)..."
    apt-get install -y -qq docker.io
    systemctl enable docker > /dev/null 2>&1
    systemctl start docker > /dev/null 2>&1
    echo "✓ Docker installed via fallback"
}

if ! command -v docker > /dev/null 2>&1; then
    echo "Installing Docker..."

    apt-get install -y -qq ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    codename=$(lsb_release -cs)

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $codename stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null

    apt-get update -qq

    if apt-cache policy docker-ce | grep -q 'Candidate: (none)'; then
        install_docker_fallback
    else
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        echo "✓ Docker installed"
    fi
else
    echo "✓ Docker already installed on system"
fi

echo
echo "=== Backup Agent Container ==="

# Clean up any old failed containers
if [ "$(docker ps -aq -f name=^/${CONTAINER_NAME}$)" ]; then
    echo "Found existing container named '${CONTAINER_NAME}'. Checking status..."

    if [ "$(docker inspect -f '{{.State.Running}}' ${CONTAINER_NAME})" = "true" ]; then
        echo "✓ Container '${CONTAINER_NAME}' is already running"
    else
        echo "⚠️ Container exists but not running. Removing and restarting..."
        docker rm -f "$CONTAINER_NAME"
    fi
fi

# Run container if not already running
if ! docker ps -q -f name=^/${CONTAINER_NAME}$ > /dev/null; then
    echo "Running container '${CONTAINER_NAME}' on port $PORT..."
    docker run -d \
        -p ${PORT}:${PORT} \
        -v /:/host:ro \
        -v "$HOST_BACKUP_DIR":/host/var/backup_app/backups \
        --name "$CONTAINER_NAME" \
        phantomfaith/backup-agent-api:latest

    if [ $? -eq 0 ]; then
        echo "✓ Container '${CONTAINER_NAME}' started successfully"
    else
        echo "❌ Failed to start container '${CONTAINER_NAME}'. Please check Docker logs."
        exit 1
    fi
else
    echo "✓ Container '${CONTAINER_NAME}' is already running"
fi

echo
echo "=== Script Complete ==="
