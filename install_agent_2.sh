#!/bin/bash
set -e

AGENT_DIR="/var/www/backup-agent"
CONFIG_JSON="$1"

echo "[*] Checking Docker installation..."

if ! command -v docker >/dev/null 2>&1; then
  echo "[*] Docker not found. Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  echo "[*] Docker installed."
else
  echo "[*] Docker already installed."
fi

echo "[*] Checking restic installation..."

if ! command -v restic >/dev/null 2>&1; then
  echo "[*] Restic not found. Installing restic..."
  curl -s https://restic.net/scripts/install-restic.sh | sudo bash
  echo "[*] Restic installed."
else
  echo "[*] Restic already installed."
fi

echo "[*] Creating agent directory at $AGENT_DIR..."
mkdir -p "$AGENT_DIR"

echo "[*] Writing config.json..."
echo "$CONFIG_JSON" > "$AGENT_DIR/config.json"

echo "[*] Pulling agent Docker image..."
docker pull phantomfaith/re-agent:latest

echo "[*] Stopping existing agent container if running..."
docker rm -f backup-agent || true

echo "[*] Starting agent container..."
docker run -d \
  --name backup-agent \
  --restart always \
  -v "$AGENT_DIR:/data" \
  -v /:/host:ro \
  -v /usr/bin/restic:/usr/bin/restic:ro \
  -v /var/backup/restic-repo:/var/backup/restic-repo:rw \
  -p 8080:8080 \
  phantomfaith/re-agent:latest

echo "[+] Backup agent installed and running on port 8080."
