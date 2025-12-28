#!/usr/bin/env bash

# Copyright (c) 2021-2025 Mr-R-b0t
# Author: Mr-R-b0t
# License: MIT
# Source: https://github.com/cstaelen/tidarr

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "==> Updating system"
apt-get update
apt-get upgrade -y

echo "==> Installing dependencies"
apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release

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
mkdir -p /opt/tidarr/{config,music}
chmod 755 /opt/tidarr /opt/tidarr/config /opt/tidarr/music

cat >/opt/tidarr/Dockerfile <<'EOF'
FROM cstaelen/tidarr:latest
RUN (command -v apt-get >/dev/null 2>&1 && apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*) || \
    (command -v apk >/dev/null 2>&1 && apk add --no-cache curl) || \
    (command -v microdnf >/dev/null 2>&1 && microdnf install -y curl && microdnf clean all) || \
    true
EOF

cat >/opt/tidarr/compose.yml <<'EOF'
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
      - /opt/tidarr/music:/music
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

echo "==> Starting Tidarr"
cd /opt/tidarr
docker compose up -d --build

echo "==> Cleaning up"
apt-get -y autoremove
apt-get -y autoclean

echo "==> Done!"
