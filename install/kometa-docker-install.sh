#!/usr/bin/env bash

# Copyright (c) 2021-2025 Mr-R-b0t
# Author: Mr-R-b0t
# License: MIT
# Source: https://github.com/Kometa-Team/Quickstart

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Configuration paths
CONFIG_PATH="/opt/kometa/config"
LOGS_PATH="/opt/kometa/logs"

echo "==> Setting root password"
echo "root:kometa" | chpasswd
echo "Root password set to: kometa (change it after first login!)"

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

echo "==> Setting up Kometa"
mkdir -p "$CONFIG_PATH" "$LOGS_PATH"
chmod 755 /opt/kometa "$CONFIG_PATH" "$LOGS_PATH"

cat >/opt/kometa/compose.yml <<'EOF'
services:
  kometa:
    image: kometateam/kometa:latest
    container_name: kometa
    restart: unless-stopped
    environment:
      - KOMETA_TIME=03:00
      - KOMETA_RUN=True
      - TZ=America/New_York
    volumes:
      - /opt/kometa/config:/config
      - /opt/kometa/logs:/logs
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

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

# Create sample config if it doesn't exist
if [[ ! -f "$CONFIG_PATH/config.yml" ]]; then
  cat >"$CONFIG_PATH/config.yml" <<'EOF'
## This file is a template. Please fill in your actual values.
## Full documentation: https://kometa.wiki/en/latest/config/configuration/

# Plex Configuration
plex:
  url: http://plex.example.com:32400
  token: YOUR_PLEX_TOKEN
  timeout: 60
  clean_bundles: false
  empty_trash: false
  optimize: false

# TMDb Configuration (Required)
tmdb:
  apikey: YOUR_TMDB_API_KEY
  language: en

# Settings
settings:
  cache: true
  cache_expiration: 60
  asset_directory: config/assets
  asset_folders: true
  asset_depth: 0
  create_asset_folders: false
  prioritize_assets: false
  dimensional_asset_rename: false
  download_url_assets: false
  show_missing_season_assets: false
  show_missing_episode_assets: false
  show_asset_not_needed: true
  sync_mode: append
  minimum_items: 1
  delete_below_minimum: false
  delete_not_scheduled: false
  run_again_delay: 2
  missing_only_released: false
  only_filter_missing: false
  show_unmanaged: true
  show_unconfigured: true
  show_filtered: false
  show_options: false
  show_missing: true
  save_report: false
  tvdb_language: eng
  ignore_ids:
  ignore_imdb_ids:
  playlist_sync_to_users: all
  verify_ssl: true

# Libraries
libraries:
  Movies:
    collection_files:
      - default: basic
      - default: imdb
    overlay_files:
      - default: ribbon
EOF
  echo "Created sample config.yml - please edit with your values"
fi

echo "==> Starting Kometa"
cd /opt/kometa
docker compose up -d

echo "==> Cleaning up"
apt-get -y autoremove
apt-get -y autoclean

echo "==> Done!"
echo ""
echo "Login credentials: root / kometa"
echo ""
echo "IMPORTANT: Edit the configuration file:"
echo "  /opt/kometa/config/config.yml"
echo ""
echo "You need to add:"
echo "  - Plex URL and Token"
echo "  - TMDb API Key"
echo "  - Configure your libraries"
echo ""
echo "After editing, restart Kometa:"
echo "  cd /opt/kometa && docker compose restart"
echo ""
echo "View logs:"
echo "  cd /opt/kometa && docker compose logs -f"
