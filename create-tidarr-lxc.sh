#!/usr/bin/env bash
set -euo pipefail

# =========================
# CONFIG (EDIT THESE)
# =========================
CTID="${CTID:-120}"
HOSTNAME="${HOSTNAME:-tidarr}"
STORAGE="${STORAGE:-local-lvm}"     # e.g. local-lvm, local-zfs, etc.
DISK_SIZE_GB="${DISK_SIZE_GB:-16}"
MEMORY_MB="${MEMORY_MB:-2048}"
CORES="${CORES:-2}"
BRIDGE="${BRIDGE:-vmbr0}"

# Static IP config (CHANGE!)
IP_CIDR="${IP_CIDR:-192.168.1.50/24}"
GATEWAY="${GATEWAY:-192.168.1.1}"
DNS_SERVER="${DNS_SERVER:-1.1.1.1}"

# LXC template (Ubuntu)
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"
TEMPLATE_FILE="${TEMPLATE_FILE:-ubuntu-22.04-standard_22.04-1_amd64.tar.zst}"

# App ports
TIDARR_PORT="${TIDARR_PORT:-8484}"

# Watchtower schedule (cron with seconds)
# Example: daily at 04:00
WATCHTOWER_SCHEDULE="${WATCHTOWER_SCHEDULE:-0 0 4 * * *}"

# Privileged container switch:
# 1 = privileged, 0 = unprivileged
PRIVILEGED="${PRIVILEGED:-1}"

# Tidarr paths inside the LXC
TIDARR_BASE="${TIDARR_BASE:-/opt/tidarr}"
TIDARR_CONFIG="${TIDARR_CONFIG:-/opt/tidarr/config}"
TIDARR_MUSIC="${TIDARR_MUSIC:-/opt/tidarr/music}"
# =========================

need_cmd() { command -v "$1" >/dev/null 2>&1; }

if ! need_cmd pct || ! need_cmd pveam; then
  echo "ERROR: This script must be run on a Proxmox host (pct/pveam not found)."
  exit 1
fi

if pct status "$CTID" >/dev/null 2>&1; then
  echo "ERROR: CTID $CTID already exists."
  exit 1
fi

echo "==> Updating template list"
pveam update

echo "==> Ensuring template exists: ${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE_FILE}"
if ! pveam list "$TEMPLATE_STORAGE" | awk '{print $1}' | grep -q "^vztmpl/${TEMPLATE_FILE}$"; then
  echo "==> Downloading template..."
  pveam download "$TEMPLATE_STORAGE" "$TEMPLATE_FILE"
fi

UNPRIV_FLAG="--unprivileged 1"
if [[ "$PRIVILEGED" == "1" ]]; then
  UNPRIV_FLAG="--unprivileged 0"
fi

echo "==> Creating LXC CTID=$CTID hostname=$HOSTNAME (privileged=$PRIVILEGED) with static IP $IP_CIDR"
pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE_FILE}" \
  --hostname "$HOSTNAME" \
  --cores "$CORES" \
  --memory "$MEMORY_MB" \
  --swap 512 \
  --rootfs "${STORAGE}:${DISK_SIZE_GB}" \
  --net0 "name=eth0,bridge=${BRIDGE},ip=${IP_CIDR},gw=${GATEWAY}" \
  --nameserver "$DNS_SERVER" \
  $UNPRIV_FLAG \
  --features "nesting=1,keyctl=1" \
  --onboot 1

echo "==> Setting Docker-friendly LXC settings"
# Docker-in-LXC is much easier in privileged containers, but these help either way.
pct set "$CTID" -lxc.apparmor.profile unconfined
pct set "$CTID" -lxc.cap.drop ""

echo "==> Starting container"
pct start "$CTID"

echo "==> Waiting for container network..."
sleep 10

echo "==> Installing Docker + deploying Tidarr + Watchtower + Healthcheck"
pct exec "$CTID" -- bash -lc "
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release openssl

# Docker repo
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \$(. /etc/os-release && echo \$VERSION_CODENAME) stable\" \
  > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker

mkdir -p '${TIDARR_BASE}' '${TIDARR_CONFIG}' '${TIDARR_MUSIC}'
chmod 755 '${TIDARR_BASE}' '${TIDARR_CONFIG}' '${TIDARR_MUSIC}'

# Build a tiny wrapper image that guarantees curl exists for healthchecks.
cat > '${TIDARR_BASE}/Dockerfile' << 'DOCKERFILE'
FROM cstaelen/tidarr:latest
# best-effort install curl depending on base image
RUN (command -v apt-get >/dev/null 2>&1 && apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*) || \
    (command -v apk >/dev/null 2>&1 && apk add --no-cache curl) || \
    (command -v microdnf >/dev/null 2>&1 && microdnf install -y curl && microdnf clean all) || \
    true
DOCKERFILE

# Compose
cat > '${TIDARR_BASE}/compose.yml' << 'COMPOSE'
services:
  tidarr:
    build:
      context: .
      dockerfile: Dockerfile
    image: tidarr-with-healthcheck:latest
    container_name: tidarr
    ports:
      - \"8484:8484\"
    volumes:
      - /opt/tidarr/config:/shared
      - /opt/tidarr/music:/music
    restart: unless-stopped
    labels:
      - \"com.centurylinklabs.watchtower.enable=true\"
    healthcheck:
      test: [\"CMD-SHELL\", \"curl -fsS http://127.0.0.1:8484/ >/dev/null || exit 1\"]
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
      - \"0 0 4 * * *\"
COMPOSE

# Inject schedule from script variable (replace the default)
sed -i \"s|0 0 4 \\* \\* \\*|${WATCHTOWER_SCHEDULE//|/\\\\|}|\" '${TIDARR_BASE}/compose.yml'

cd '${TIDARR_BASE}'
docker compose up -d --build

echo
echo '==> Containers:'
docker ps
"

echo
echo "✅ Done."
echo "Tidarr should be reachable at: http://${IP_CIDR%/*}:${TIDARR_PORT}"
echo
echo "Useful commands:"
echo "  pct exec $CTID -- docker ps"
echo "  pct exec $CTID -- bash -lc 'cd /opt/tidarr && docker compose logs -f --tail=200'"
