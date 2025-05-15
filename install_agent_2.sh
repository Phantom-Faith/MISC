#!/bin/bash

set -e

echo "[*] Installing dependencies"
apt update && apt install -y restic

echo "[*] Deploying agent"
cp /tmp/agent_binary /usr/local/bin/backup-agent
chmod +x /usr/local/bin/backup-agent
cp /tmp/config.json /etc/backup-agent.json

echo "[*] Creating systemd service"
cat <<EOF >/etc/systemd/system/backup-agent.service
[Unit]
Description=Backup Agent
After=network.target

[Service]
ExecStart=/usr/local/bin/backup-agent --config /etc/backup-agent.json
Restart=always

[Install]
WantedBy=multi-user.target
EOF

echo "[*] Enabling and starting agent"
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable backup-agent
systemctl start backup-agent

echo "[+] Agent installed and started successfully"
