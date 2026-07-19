#!/usr/bin/env bash
# ============================================================
# reset-ping.sh — Kirim ping minimal ("hai") ke agent lokal
# model anthropic/claude-sonnet-5 pada jam sepi (04:00 WIB)
# untuk memicu reset window rate-limit 5-hour Anthropic
# lebih awal, di luar jam pemakaian utama.
#
# CATATAN: Sengaja BYPASS provider-segregation guard di orc.sh
# (yang memblokir spawn anthropic/* langsung untuk worker agent)
# karena tujuan skrip ini justru memakai kuota anthropic secara
# sadar & minimal (1 pesan pendek) pada jam agent utama tidak
# aktif — bukan worker yang bersaing kuota dengan main agent.
# Bukan celah keamanan yang lupa ditutup — ini pengecualian
# eksplisit yang diminta pemilik fleet.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERDR_BIN="${HERDR_BIN:-/home/efsatu/.local/bin/herdr}"
OMP_BIN="${OMP_BIN:-/home/efsatu/.bun/bin/omp}"
OMP_PATH_ENV="PATH=/home/efsatu/.bun/bin:/home/efsatu/.local/bin:/home/efsatu/.nvm/versions/node/v24.14.0/bin:/usr/local/bin:/usr/bin:/bin"
CONTRACT_FILE="$SCRIPT_DIR/WORK_CONTRACT.md"
AGENT_NAME="reset-ping"
MODEL="anthropic/claude-sonnet-5"

ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
contract_append() {
  local type="$1"; shift
  printf "| %-22s | %-12s | %s |\n" "$(ts)" "$type" "$*" >> "$CONTRACT_FILE"
}

agent_status() {
  local raw
  raw="$("$HERDR_BIN" agent get "$AGENT_NAME" 2>/dev/null)" || true
  printf '%s' "$raw" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    print(d['result']['agent'].get('agent_status','unknown'))
except Exception:
    print('missing')
"
}

status="$(agent_status)"

if [[ "$status" == "missing" ]]; then
  echo "[$(ts)] Agent '$AGENT_NAME' tidak ada — spawn baru dengan model $MODEL"
  "$HERDR_BIN" agent start "$AGENT_NAME" \
    --cwd "$HOME/my-ai-agents" \
    --split right \
    --env "$OMP_PATH_ENV" \
    -- "$OMP_BIN" --model "$MODEL" 2>/dev/null
  contract_append "SPAWN" "agent=$AGENT_NAME model=$MODEL reason=scheduled_5h_reset_ping cron=04:00_WIB"
  sleep 5
else
  echo "[$(ts)] Agent '$AGENT_NAME' sudah ada (status=$status) — reuse"
fi

pane_id="$("$HERDR_BIN" agent get "$AGENT_NAME" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
print(d['result']['agent'].get('pane_id',''))
" 2>/dev/null || echo "")"

if [[ -z "$pane_id" ]]; then
  echo "[$(ts)] ERROR: gagal resolve pane_id untuk $AGENT_NAME" >&2
  contract_append "RESET_PING_FAIL" "agent=$AGENT_NAME reason=no_pane_id"
  exit 1
fi

"$HERDR_BIN" agent send "$AGENT_NAME" "hai" 2>/dev/null
sleep 1
"$HERDR_BIN" pane run "$pane_id" "" 2>/dev/null

contract_append "RESET_PING" "agent=$AGENT_NAME model=$MODEL pane=$pane_id message=hai reason=trigger_anthropic_5h_window_reset"
echo "[$(ts)] Ping terkirim ke $AGENT_NAME (pane=$pane_id)"
