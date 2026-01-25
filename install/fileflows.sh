#!/usr/bin/env bash

# Copyright (c) 2021-2025 Mr-R-b0t
# Author: Mr-R-b0t
# License: MIT
# Source: https://github.com/fileflows/FileFlows

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Configuration
FILEFLOWS_USER="fileflows"
FILEFLOWS_GROUP="fileflows"
FILEFLOWS_HOME="/opt/fileflows"
PUID=999
PGID=990

# Set umask so new files inherit group and have group write permission
umask 0002

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  ca-certificates \
  curl \
  jq \
  unzip
msg_ok "Installed Dependencies"

msg_info "Creating service user/group"
groupadd -g "$PGID" "$FILEFLOWS_GROUP" 2>/dev/null || true
if ! id -u "$FILEFLOWS_USER" >/dev/null 2>&1; then
  useradd -u "$PUID" -g "$PGID" -d "$FILEFLOWS_HOME" -m -s /bin/bash "$FILEFLOWS_USER"
fi
msg_ok "Created service user/group"

msg_info "Installing ASP.NET Core Runtime 8.0"
$STD apt-get install -y --no-install-recommends \
  dotnet-runtime-8.0
msg_ok "Installed ASP.NET Core Runtime 8.0"

msg_info "Setup FileFlows (NODE)"
mkdir -p /opt/fileflows
temp_file=$(mktemp)
$STD curl -fsSL https://fileflows.com/downloads/zip -o "$temp_file"
$STD unzip -d /opt/fileflows "$temp_file"

# Set proper permissions
$STD chown -R "$FILEFLOWS_USER":"$FILEFLOWS_GROUP" /opt/fileflows
$STD chmod -R 755 /opt/fileflows

# Create symlinks for ffmpeg/ffprobe
if command -v ffmpeg &>/dev/null; then
  $STD ln -svf $(which ffmpeg) /usr/local/bin/ffmpeg || true
fi
if command -v ffprobe &>/dev/null; then
  $STD ln -svf $(which ffprobe) /usr/local/bin/ffprobe || true
fi

# Install NODE as a systemd service (headless worker)
$STD bash -c "cd /opt/fileflows/Node && dotnet FileFlows.Node.dll --systemd install --root true"

# Start/enable service
systemctl enable -q --now fileflows-node || systemctl enable -q --now fileflows || true

rm -f "$temp_file"
msg_ok "Setup FileFlows (NODE)"

motd_ssh
customize
cleanup_lxc
