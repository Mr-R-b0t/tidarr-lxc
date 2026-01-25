#!/usr/bin/env bash

# Copyright (c) 2021-2025 Mr-R-b0t
# Author: Mr-R-b0t
# License: MIT
# Source: https://github.com/Maintainerr/Maintainerr

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Permission mapping for container processes
PUID=999
PGID=990
GROUP_NAME="maintainerr"
USER_NAME="maintainerr"

echo "==> Setting root password"
echo "root:maintainerr" | chpasswd
echo "Root password set to: maintainerr (change it after first login!)"

echo "==> Updating system"
apt-get update
apt-get upgrade -y

echo "==> Installing dependencies"
apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release

echo "==> Creating service user/group"
groupadd -g "$PGID" "$GROUP_NAME" 2>/dev/null || true
if ! id -u "$USER_NAME" >/dev/null 2>&1; then
  useradd -u "$PUID" -g "$PGID" -M -s /usr/sbin/nologin "$USER_NAME"
fi

echo "==> Setting up Docker repository"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" >/etc/apt/sources.list.d/docker.list
apt-get update

echo "==> Installing Docker"
apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin
systemctl enable --now docker

echo "==> Setting up Maintainerr"
mkdir -p /opt/maintainerr/data
chown -R "$USER_NAME":"$GROUP_NAME" /opt/maintainerr
chmod 755 /opt/maintainerr
chmod 2775 /opt/maintainerr/data

cat >/opt/maintainerr/compose.yml <<EOF
services:
  maintainerr:
    image: ghcr.io/maintainerr/maintainerr:latest
    container_name: maintainerr
    user: ${PUID}:${PGID}
    ports:
      - "6246:6246"
    volumes:
      - /opt/maintainerr/data:/opt/data
    environment:
      - TZ=Europe/Paris
    restart: unless-stopped
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:6246/api/health || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 30s

  watchtower:
    image: containrrr/watchtower:latest
    container_name: watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command:
      - --label-enable
      - --cleanup
      - --schedule
      - "0 0 4 * * *"
EOF

echo "==> Fixing final permissions"
chown -R "$USER_NAME":"$GROUP_NAME" /opt/maintainerr

echo "==> Starting Maintainerr"
cd /opt/maintainerr
docker compose up -d

echo "==> Cleaning up"
apt-get -y autoremove
apt-get -y autoclean

echo "==> Done!"
echo ""
echo "Login credentials: root / maintainerr"
echo "Maintainerr is available at: http://<container-ip>:6246"
echo ""
echo "Next steps:"
echo "1. Open the web UI and complete the initial setup"
echo "2. Connect your Plex server"
echo "3. Connect Sonarr/Radarr if needed"
echo "4. Configure your media cleanup rules"
