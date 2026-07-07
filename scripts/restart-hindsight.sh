#!/usr/bin/env bash
#
# restart-hindsight.sh
# Safe restart: bypass VPN → restart container → wait for healthy.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== 1. Bypass VPN routes ==="
bash "$SCRIPT_DIR/bypass-vpn.sh"

echo ""
echo "=== 2. Restart container ==="
cd "$REPO_DIR"
docker compose restart hindsight 2>&1 || docker restart hindsight 2>&1
echo "Container restarted at $(date +%H:%M:%S)"

echo ""
echo "=== 3. Waiting for healthy (max 15 min) ==="
for i in $(seq 1 30); do
  health=$(curl -sf --max-time 5 http://localhost:8890/health 2>/dev/null || true)
  if [ -n "$health" ]; then
    echo "[$i] ✅ $health"
    echo ""
    echo "Hindsight ready!"
    exit 0
  fi
  echo "[$i] $(date +%H:%M:%S) waiting..."
  sleep 30
done

echo "❌ Not healthy after 15 min. Check: docker logs hindsight"
exit 1
