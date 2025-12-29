#!/usr/bin/env bash

# Copyright (c) 2021-2025 Mr-R-b0t
# Author: Mr-R-b0t
# License: MIT
# Source: https://github.com/cstaelen/tidarr

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# NFS Configuration
NFS_SERVER="10.1.1.16"
NFS_SHARE="/mnt/data"
NFS_MOUNT="/mnt/data"
NFS_OPTIONS="rsize=1048576,wsize=1048576,hard,noatime,nodiratime,timeo=600,retrans=5"
MUSIC_PATH="/mnt/data/media/tidarr"

# User/Group configuration (match NFS server)
PUID=0
PGID=1000
GROUP_NAME="poulette"

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
  nfs-common \
  cron

echo "==> Creating group ${GROUP_NAME} with GID ${PGID}"
groupadd -g "$PGID" "$GROUP_NAME" 2>/dev/null || true

echo "==> Setting up NFS mount"
mkdir -p "$NFS_MOUNT"

# Add to fstab if not already present
if ! grep -q "$NFS_SERVER:$NFS_SHARE" /etc/fstab; then
  echo "${NFS_SERVER}:${NFS_SHARE} ${NFS_MOUNT} nfs4 ${NFS_OPTIONS} 0 0" >> /etc/fstab
  echo "Added NFS mount to /etc/fstab"
fi

# Mount NFS
echo "==> Mounting NFS share"
mount -a
echo "NFS mounted successfully"

# Create music directory on NFS if it doesn't exist
mkdir -p "$MUSIC_PATH"
# Set setgid bit so new files inherit group ownership
chown root:"$GROUP_NAME" "$MUSIC_PATH"
chmod 2775 "$MUSIC_PATH"

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
chmod 755 /opt/tidarr /opt/tidarr/config

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
    user: "0:${PGID}"
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

# Create a systemd override to fix permissions after tidarr creates files
cat >/opt/tidarr/fix-permissions.sh <<'FIXPERM'
#!/bin/bash
# Fix permissions on music directory
find /mnt/data/media/tidarr -type d ! -perm 2775 -exec chmod 2775 {} \;
find /mnt/data/media/tidarr -type f ! -perm 664 -exec chmod 664 {} \;
chown -R root:poulette /mnt/data/media/tidarr
FIXPERM
chmod +x /opt/tidarr/fix-permissions.sh

# Add cron job to fix permissions every 5 minutes
echo "*/5 * * * * root /opt/tidarr/fix-permissions.sh >/dev/null 2>&1" > /etc/cron.d/tidarr-permissions
chmod 644 /etc/cron.d/tidarr-permissions

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
