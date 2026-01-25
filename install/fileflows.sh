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

echo "==> Setting root password"
echo "root:fileflows" | chpasswd
echo "Root password set to: fileflows (change it after first login!)"

echo "==> Updating system"
apt-get update
apt-get upgrade -y

echo "==> Installing Dependencies"
apt-get install -y \
  ca-certificates \
  curl \
  ffmpeg \
  jq \
  unzip
echo "✓ Installed Dependencies"

echo "==> Creating service user/group"
groupadd -g "$PGID" "$FILEFLOWS_GROUP" 2>/dev/null || true
if ! id -u "$FILEFLOWS_USER" >/dev/null 2>&1; then
  useradd -u "$PUID" -g "$PGID" -d "$FILEFLOWS_HOME" -m -s /bin/bash "$FILEFLOWS_USER"
fi
echo "✓ Created service user/group"

echo "==> Installing ASP.NET Core Runtime 8.0"
apt-get install -y --no-install-recommends \
  dotnet-runtime-8.0 || apt-get install -y --no-install-recommends aspnetcore-runtime-8.0
echo "✓ Installed ASP.NET Core Runtime 8.0"

echo "==> Setup FileFlows (NODE)"
mkdir -p "$FILEFLOWS_HOME"
temp_file=$(mktemp)

curl -fsSL https://fileflows.com/downloads/zip -o "$temp_file"
unzip -o -d "$FILEFLOWS_HOME" "$temp_file"

# Set proper permissions
chown -R "$FILEFLOWS_USER":"$FILEFLOWS_GROUP" "$FILEFLOWS_HOME"
chmod -R 755 "$FILEFLOWS_HOME"

# Create symlinks for ffmpeg/ffprobe if they exist
if command -v ffmpeg &>/dev/null; then
  ln -svf "$(command -v ffmpeg)" /usr/local/bin/ffmpeg || true
fi
if command -v ffprobe &>/dev/null; then
  ln -svf "$(command -v ffprobe)" /usr/local/bin/ffprobe || true
fi

# Install NODE as a systemd service (headless worker)
if [ -f "$FILEFLOWS_HOME/Node/FileFlows.Node.dll" ]; then
  bash -c "cd $FILEFLOWS_HOME/Node && dotnet FileFlows.Node.dll --systemd install --root true" || true
  
  # Start/enable service
  systemctl enable -q --now fileflows-node || systemctl enable -q --now fileflows || true
fi

rm -f "$temp_file"
echo "✓ Setup FileFlows (NODE)"

echo ""
echo "==> Configuring SSH"
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
systemctl restart ssh
echo "✓ Configured SSH"

echo ""
echo "==> FileFlows installation complete!"
echo "Access FileFlows at: http://<container-ip>:5000"
echo "SSH: root@<container-ip>"
echo "SSH password: fileflows"
