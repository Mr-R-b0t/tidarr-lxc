#!/usr/bin/env bash

# Copyright (c) 2021-2025 Mr-R-b0t
# Author: Mr-R-b0t
# License: MIT
# Source: https://github.com/cstaelen/tidarr

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Media storage path (external mount)
MUSIC_PATH="/mnt/data/media/music"

# Permission mapping for container processes
PUID= 999
PGID= 990
GROUP_NAME="tidarr"
USER_NAME="tidarr"

# Set umask so new files inherit group and have group write permission
umask 0002

echo "==> Setting root password"
echo "root:tidarr" | chpasswd
echo "Root password set to: tidarr (change it after first login!)"

echo "==> Updating system"
apt-get update
apt-get upgrade -y

echo "==> Installing dependencies"
apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  cron

echo "==> Creating service user/group"
groupadd -g "$PGID" "$GROUP_NAME" 2>/dev/null || true
if ! id -u "$USER_NAME" >/dev/null 2>&1; then
  useradd -u "$PUID" -g "$PGID" -M -s /usr/sbin/nologin "$USER_NAME"
fi

echo "==> Preparing media directory"
mkdir -p "$MUSIC_PATH"
chown "$USER_NAME":"$GROUP_NAME" "$MUSIC_PATH"
chmod -r 775 "$MUSIC_PATH"

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

echo "==> Setting up Tidarr"
mkdir -p /opt/tidarr/config
chown -R "$USER_NAME":"$GROUP_NAME" /opt/tidarr
chmod 755 /opt/tidarr
chmod 2775 /opt/tidarr/config

cat >/opt/tidarr/Dockerfile <<'EOF'
FROM cstaelen/tidarr:latest
RUN (command -v apt-get >/dev/null 2>&1 && apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*) || \
    (command -v apk >/dev/null 2>&1 && apk add --no-cache curl) || \
    (command -v microdnf >/dev/null 2>&1 && microdnf install -y curl && microdnf clean all) || \
    true
EOF

cat >/opt/tidarr/compose.yml <<EOF
services:
  tidarr:
    build:
      context: .
      dockerfile: Dockerfile
    image: tidarr-with-healthcheck:latest
    container_name: tidarr
    ports:
      - "8484:8484"
    volumes:
      - /opt/tidarr/config:/shared
      - ${MUSIC_PATH}:/music
    restart: unless-stopped
    labels:
      - "com.centurylinklabs.watchtower.enable=true"
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:8484/ >/dev/null || exit 1"]
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
chown -R "$USER_NAME":"$GROUP_NAME" /opt/tidarr

echo "==> Starting Tidarr"
cd /opt/tidarr
docker compose up -d --build

echo "==> Cleaning up"
apt-get -y autoremove
apt-get -y autoclean

echo "==> Done!"
echo ""
echo "Login credentials: root / tidarr"
echo "Music will be saved to: $MUSIC_PATH"
