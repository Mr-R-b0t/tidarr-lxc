#!/usr/bin/env bash

# Copyright (c) 2021-2025 Mr-R-b0t
# Author: Mr-R-b0t
# License: MIT
# Source: https://github.com/cstaelen/tidarr

set -euo pipefail

# =========================
# Colors & Formatting
# =========================
RD=$(echo "\033[01;31m")
YW=$(echo "\033[33m")
GN=$(echo "\033[1;92m")
CL=$(echo "\033[m")
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"

# =========================
# Configuration
# =========================
APP="Tidarr"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/Mr-R-b0t/tidarr-lxc/main/install/tidarr-install.sh"

# =========================
# Helper Functions
# =========================
msg_info() { echo -e " [...] ${YW}$1${CL}"; }
msg_ok() { echo -e " ${CM} ${GN}$1${CL}"; }
msg_error() { echo -e " ${CROSS} ${RD}$1${CL}"; }

header_info() {
  clear
  cat <<"EOF"
  _______ _     __
 /_  __(_) |___/ /___ ___________
  / / / / / __  / __ `/ ___/ ___/
 / / / / / /_/ / /_/ / /  / /
/_/ /_/_/\__,_/\__,_/_/  /_/

EOF
  echo -e "${YW}Tidarr LXC Container Creator${CL}\n"
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
    msg_error "This script must be run as root"
    exit 1
  fi
}

check_proxmox() {
  if ! command -v pct &>/dev/null || ! command -v pveam &>/dev/null; then
    msg_error "This script must be run on a Proxmox host"
    exit 1
  fi
}

get_next_ctid() {
  local ctid=150
  # Check both LXC containers (pct) and VMs (qm)
  while pct status "$ctid" &>/dev/null || qm config "$ctid" &>/dev/null; do
    ((ctid++))
  done
  echo "$ctid"
}

get_default_storage() {
  local storage_list
  storage_list=$(pvesm status -content rootdir | awk 'NR>1 {print $1}' | head -1)
  
  if [[ -z "$storage_list" ]]; then
    msg_error "No storage available for containers"
    exit 1
  fi
  
  echo "$storage_list"
}

get_template() {
  local template_storage="${1:-local}"
  local os="${2:-debian}"
  local version="${3:-12}"
  
  pveam available -section system | grep -i "${os}-${version}" | head -1 | awk '{print $2}'
}

download_template() {
  local template_storage="${1:-local}"
  local template="$2"
  
  msg_info "Updating template list"
  pveam update
  msg_ok "Updated template list"
  
  if ! pveam list "$template_storage" | grep -q "$template"; then
    msg_info "Downloading template: $template"
    pveam download "$template_storage" "$template"
    msg_ok "Downloaded template"
  else
    msg_ok "Template already available: $template"
  fi
}

# =========================
# Main Script
# =========================
header_info
check_root
check_proxmox

# Auto-detect values
CTID=$(get_next_ctid)
HOSTNAME="tidarr"
STORAGE=$(get_default_storage)
NET_CONFIG="name=eth0,bridge=vmbr0,ip=dhcp"
TEMPLATE_NAME=$(get_template "local" "$var_os" "$var_version")
TEMPLATE="local:vztmpl/${TEMPLATE_NAME}"

if [[ -z "$TEMPLATE_NAME" ]]; then
  msg_error "No template found for ${var_os}-${var_version}"
  exit 1
fi

echo -e "${YW}Creating LXC container for ${APP} with the following settings:${CL}"
echo -e "  CTID:     ${GN}$CTID${CL}"
echo -e "  Hostname: ${GN}$HOSTNAME${CL}"
echo -e "  Storage:  ${GN}$STORAGE${CL}"
echo -e "  CPU:      ${GN}$var_cpu cores${CL}"
echo -e "  RAM:      ${GN}$var_ram MB${CL}"
echo -e "  Disk:     ${GN}$var_disk GB${CL}"
echo -e "  Network:  ${GN}DHCP${CL}"
echo -e "  Template: ${GN}$TEMPLATE_NAME${CL}"
echo ""

# Download template if needed
download_template "local" "$TEMPLATE_NAME"

msg_info "Creating LXC container $CTID"
pct create "$CTID" "$TEMPLATE" \
  --hostname "$HOSTNAME" \
  --cores "$var_cpu" \
  --memory "$var_ram" \
  --swap 512 \
  --rootfs "${STORAGE}:${var_disk}" \
  --net0 "$NET_CONFIG" \
  --unprivileged 0 \
  --features "nesting=1,keyctl=1" \
  --onboot 1
msg_ok "Created LXC container $CTID"

msg_info "Configuring container for Docker"
# Add Docker-friendly settings to LXC config
cat >> /etc/pve/lxc/${CTID}.conf <<EOF
lxc.apparmor.profile: unconfined
lxc.cap.drop: 
EOF
msg_ok "Configured container for Docker"

msg_info "Starting container"
pct start "$CTID"
msg_ok "Started container"

msg_info "Waiting for network"
for i in {1..30}; do
  if pct exec "$CTID" -- ping -c1 1.1.1.1 &>/dev/null; then
    msg_ok "Network is up"
    break
  fi
  echo -e "  Waiting... ($i/30)"
  sleep 2
done

msg_info "Running installation script (this may take a few minutes)"
echo ""
pct exec "$CTID" -- bash -c "$(curl -fsSL $INSTALL_SCRIPT_URL)"
echo ""
msg_ok "Installation complete"

# Get container IP
msg_info "Getting container IP address"
sleep 3
CONTAINER_IP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')
msg_ok "Container IP: $CONTAINER_IP"

echo ""
echo -e "═══════════════════════════════════════════════════════════"
msg_ok "Completed Successfully!"
echo -e "═══════════════════════════════════════════════════════════"
echo ""
echo -e "${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${YW}Access it using the following URL:${CL}"
echo -e "  ${GN}http://${CONTAINER_IP}:8484${CL}"
echo ""
echo -e "${YW}Useful commands:${CL}"
echo -e "  pct exec $CTID -- docker ps"
echo -e "  pct exec $CTID -- bash -c 'cd /opt/tidarr && docker compose logs -f'"
