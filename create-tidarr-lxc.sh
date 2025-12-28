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
BFR="\\r\\033[K"
HOLD=" "
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"

# =========================
# Configuration
# =========================
APP="Tidarr"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-16}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/Mr-R-b0t/tidarr-lxc/main/install/tidarr-install.sh"

# =========================
# Helper Functions
# =========================
msg_info() { echo -ne " ${HOLD} ${YW}$1...${CL}"; }
msg_ok() { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; }

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
  local ctid=100
  while pct status "$ctid" &>/dev/null; do
    ((ctid++))
  done
  echo "$ctid"
}

select_storage() {
  local storage_list
  storage_list=$(pvesm status -content rootdir | awk 'NR>1 {print $1}')
  
  if [[ -z "$storage_list" ]]; then
    msg_error "No storage available for containers"
    exit 1
  fi
  
  echo -e "${YW}Available storage pools:${CL}"
  echo "$storage_list" | nl -w2 -s'. '
  
  local default_storage
  default_storage=$(echo "$storage_list" | head -1)
  
  read -rp "Select storage (default: $default_storage): " STORAGE
  STORAGE="${STORAGE:-$default_storage}"
}

get_template() {
  local template_storage="${1:-local}"
  local os="${2:-debian}"
  local version="${3:-12}"
  
  msg_info "Updating template list"
  pveam update &>/dev/null
  msg_ok "Updated template list"
  
  local template
  template=$(pveam available -section system | grep -i "${os}-${version}" | head -1 | awk '{print $2}')
  
  if [[ -z "$template" ]]; then
    msg_error "No template found for ${os}-${version}"
    exit 1
  fi
  
  if ! pveam list "$template_storage" | grep -q "$template"; then
    msg_info "Downloading template: $template"
    pveam download "$template_storage" "$template" &>/dev/null
    msg_ok "Downloaded template"
  fi
  
  echo "${template_storage}:vztmpl/${template}"
}

# =========================
# Main Script
# =========================
header_info
check_root
check_proxmox

echo -e "${YW}This will create a new LXC container for ${APP}${CL}\n"

# Get CTID
DEFAULT_CTID=$(get_next_ctid)
read -rp "Container ID (default: $DEFAULT_CTID): " CTID
CTID="${CTID:-$DEFAULT_CTID}"

if pct status "$CTID" &>/dev/null; then
  msg_error "Container ID $CTID already exists"
  exit 1
fi

# Get hostname
read -rp "Hostname (default: tidarr): " HOSTNAME
HOSTNAME="${HOSTNAME:-tidarr}"

# Select storage
select_storage

# Get network config
read -rp "Use DHCP? (y/n, default: y): " USE_DHCP
USE_DHCP="${USE_DHCP:-y}"

if [[ "${USE_DHCP,,}" == "n" ]]; then
  read -rp "IP Address (CIDR, e.g., 10.1.1.50/24): " IP_ADDR
  read -rp "Gateway: " GATEWAY
  NET_CONFIG="name=eth0,bridge=vmbr0,ip=${IP_ADDR},gw=${GATEWAY}"
else
  NET_CONFIG="name=eth0,bridge=vmbr0,ip=dhcp"
fi

# Get template
TEMPLATE=$(get_template "local" "$var_os" "$var_version")

echo ""
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
  --onboot 1 &>/dev/null
msg_ok "Created LXC container $CTID"

msg_info "Configuring container for Docker"
pct set "$CTID" -lxc.apparmor.profile unconfined &>/dev/null
pct set "$CTID" -lxc.cap.drop "" &>/dev/null
msg_ok "Configured container"

msg_info "Starting container"
pct start "$CTID"
sleep 5
msg_ok "Started container"

msg_info "Waiting for network"
for i in {1..30}; do
  if pct exec "$CTID" -- ping -c1 1.1.1.1 &>/dev/null; then
    break
  fi
  sleep 1
done
msg_ok "Network is up"

msg_info "Running installation script (this may take a few minutes)"
pct exec "$CTID" -- bash -c "$(curl -fsSL $INSTALL_SCRIPT_URL)" &>/dev/null
msg_ok "Installation complete"

# Get container IP
CONTAINER_IP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')

echo ""
msg_ok "Completed Successfully!"
echo ""
echo -e "${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${YW}Access it using the following URL:${CL}"
echo -e "  ${GN}http://${CONTAINER_IP}:8484${CL}"
echo ""
echo -e "${YW}Useful commands:${CL}"
echo -e "  pct exec $CTID -- docker ps"
echo -e "  pct exec $CTID -- bash -c 'cd /opt/tidarr && docker compose logs -f'"
