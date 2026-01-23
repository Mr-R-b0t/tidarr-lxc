#!/usr/bin/env bash

# Copyright (c) 2021-2025 Mr-R-b0t
# Author: Mr-R-b0t
# License: MIT
# Source: https://github.com/Kometa-Team/Quickstart

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Configuration
KOMETA_USER="kometa"
KOMETA_GROUP="kometa"
KOMETA_HOME="/opt/kometa"
CONFIG_PATH="${KOMETA_HOME}/config"
LOGS_PATH="${KOMETA_HOME}/logs"
PUID=100999
PGID=100990

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
  lsb-release \
  python3 \
  python3-pip \
  python3-venv \
  git

echo "==> Creating service user/group"
groupadd -g "$PGID" "$KOMETA_GROUP" 2>/dev/null || true
if ! id -u "$KOMETA_USER" >/dev/null 2>&1; then
  useradd -u "$PUID" -g "$PGID" -d "$KOMETA_HOME" -m -s /bin/bash "$KOMETA_USER"
fi

echo "==> Setting up Kometa directories"
mkdir -p "$CONFIG_PATH" "$LOGS_PATH"
chown -R "$KOMETA_USER":"$KOMETA_GROUP" "$KOMETA_HOME"
chmod 755 "$KOMETA_HOME"
chmod 775 "$CONFIG_PATH" "$LOGS_PATH"

echo "==> Installing Kometa"
su - "$KOMETA_USER" -c "python3 -m venv ${KOMETA_HOME}/venv"
su - "$KOMETA_USER" -c "${KOMETA_HOME}/venv/bin/pip install --upgrade pip"
su - "$KOMETA_USER" -c "${KOMETA_HOME}/venv/bin/pip install kometa"

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
  chown "$KOMETA_USER":"$KOMETA_GROUP" "$CONFIG_PATH/config.yml"
  chmod 664 "$CONFIG_PATH/config.yml"
  echo "Created sample config.yml - please edit with your values"
fi

echo "==> Creating systemd service"
cat >/etc/systemd/system/kometa.service <<EOF
[Unit]
Description=Kometa
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$KOMETA_USER
Group=$KOMETA_GROUP
WorkingDirectory=$KOMETA_HOME
Environment="PATH=${KOMETA_HOME}/venv/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=${KOMETA_HOME}/venv/bin/kometa --config ${CONFIG_PATH}/config.yml --run
Restart=on-failure
RestartSec=10
StandardOutput=append:${LOGS_PATH}/kometa.log
StandardError=append:${LOGS_PATH}/kometa-error.log

[Install]
WantedBy=multi-user.target
EOF

echo "==> Creating run script for manual execution"
cat >"${KOMETA_HOME}/run.sh" <<EOF
#!/bin/bash
cd ${KOMETA_HOME}
${KOMETA_HOME}/venv/bin/kometa --config ${CONFIG_PATH}/config.yml --run
EOF
chmod +x "${KOMETA_HOME}/run.sh"
chown "$KOMETA_USER":"$KOMETA_GROUP" "${KOMETA_HOME}/run.sh"

echo "==> Creating systemd timer for scheduled runs"
cat >/etc/systemd/system/kometa.timer <<'EOF'
[Unit]
Description=Run Kometa daily at 3 AM

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

echo "==> Enabling and starting Kometa timer"
systemctl daemon-reload
systemctl enable kometa.timer
systemctl start kometa.timer

echo "==> Cleaning up"
apt-get -y autoremove
apt-get -y autoclean

echo "==> Done!"
echo ""
echo "Login credentials: root / kometa"
echo ""
echo "IMPORTANT: Edit the configuration file:"
echo "  ${CONFIG_PATH}/config.yml"
echo ""
echo "You need to add:"
echo "  - Plex URL and Token"
echo "  - TMDb API Key"
echo "  - Configure your libraries"
echo ""
echo "Kometa is configured to run daily at 3 AM via systemd timer."
echo ""
echo "Useful commands:"
echo "  Run manually:       systemctl start kometa"
echo "  View logs:          journalctl -u kometa -f"
echo "  Check timer:        systemctl status kometa.timer"
echo "  Disable timer:      systemctl disable kometa.timer"
echo ""
echo "Or run manually as kometa user:"
echo "  su - kometa -c '${KOMETA_HOME}/run.sh'"
