#!/usr/bin/env bash
#
# bypass-vpn.sh
# Bypass VPN (ppp0) untuk domain yang dibutuhkan Hindsight container.
# Jalankan sebelum docker compose up, atau pasang di cron @reboot.
#
# Usage:
#   ./scripts/bypass-vpn.sh
#   sudo crontab -e → @reboot /home/efsatu/my-ai-agent/scripts/bypass-vpn.sh
#
set -euo pipefail

GATEWAY="192.168.1.1"
IFACE="enp2s0"

DOMAINS=(
  "integrate.api.nvidia.com"
  "ghcr.io"
  "pkg-containers.githubusercontent.com"
)

for domain in "${DOMAINS[@]}"; do
  for ip in $(dig +short "$domain" 2>/dev/null); do
    # Skip non-IP results (CNAME, etc)
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    sudo ip route replace "$ip/32" via "$GATEWAY" dev "$IFACE" 2>/dev/null && \
      echo "[bypass] $domain → $ip via $GATEWAY" || true
  done
done
