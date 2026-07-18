#!/usr/bin/env bash
# ============================================================
# agent-router.sh — Provider routing + fallback + context guard
# Usage:
#   ./agent-router.sh best-provider
#   ./agent-router.sh check-agent <name>
#   ./agent-router.sh compact <name>
#   ./agent-router.sh switch-provider <agent-name> <new-model>
#   ./agent-router.sh pause <agent-name> <reason>
#   ./agent-router.sh resume <agent-name>
# ============================================================
set -euo pipefail

OMP_BIN="${OMP_BIN:-/home/efsatu/.bun/bin/omp}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT_FILE="$SCRIPT_DIR/WORK_CONTRACT.md"
STATE_DIR="$SCRIPT_DIR/.state"
mkdir -p "$STATE_DIR"

log_contract() {
  local type="$1"; shift
  echo "| $(date -u '+%Y-%m-%dT%H:%M:%SZ') | $type | $* |" >> "$CONTRACT_FILE"
}

# ---- Get best available provider ----
best_provider() {
  local usage_json
  usage_json=$("$SCRIPT_DIR/usage-monitor.sh" --json 2>/dev/null)

  python3 - "$usage_json" <<'PYEOF'
import sys, json

data = json.loads(sys.argv[1])
STOP = 85.0

candidates = []

# Anthropic accounts
for acc in data["providers"].get("anthropic", {}).get("accounts", []):
    usages = acc.get("limits", {})
    # Check 5h limit specifically
    for lname, ld in usages.items():
        if "5 Hour" in lname or "5h" in lname.lower():
            if ld["used_pct"] < STOP:
                candidates.append({
                    "model": "anthropic/claude-sonnet-4-6",
                    "account": acc["email"],
                    "used_pct": ld["used_pct"],
                    "resets_in": ld.get("resets_in", "?"),
                    "priority": 2  # lower priority (save for fallback)
                })
            break

# Antigravity accounts
for acc in data["providers"].get("google-antigravity", {}).get("accounts", []):
    # Check if weekly Google quota is exhausted
    weekly_blocked = any(
        "Weekly" in k and "Google" in k and v["used_pct"] >= 100
        for k, v in acc.get("limits", {}).items()
    )
    if weekly_blocked:
        continue

    for lname, ld in acc.get("limits", {}).items():
        if ("Daily" in lname or "5h" in lname.lower()) and "Google" in lname:
            if ld["used_pct"] < STOP:
                candidates.append({
                    "model": "google-antigravity/gemini-2.5-flash",
                    "account": acc["email"],
                    "used_pct": ld["used_pct"],
                    "resets_in": ld.get("resets_in", "?"),
                    "priority": 1  # prefer antigravity (higher)
                })
            break

if not candidates:
    # Find earliest reset
    earliest = None
    for pname, pdata in data["providers"].items():
        for acc in pdata.get("accounts", []):
            for lname, ld in acc.get("limits", {}).items():
                rst = ld.get("resets_in", "")
                if rst and rst != "unknown":
                    if earliest is None:
                        earliest = (rst, pname)
    if earliest:
        print(f"NONE|earliest_reset={earliest[0]}|provider={earliest[1]}")
    else:
        print("NONE|no_reset_info")
    sys.exit(0)

# Sort: priority first, then lowest usage
candidates.sort(key=lambda x: (x["priority"], x["used_pct"]))
best = candidates[0]
print(f"{best['model']}|used={best['used_pct']:.1f}%|resets={best['resets_in']}|account={best['account']}")
PYEOF
}

# ---- Check agent context usage ----
check_agent_context() {
  local agent_name="$1"
  local screen
  screen=$(herdr agent read "$agent_name" --source visible --lines 5 2>/dev/null | \
    python3 -c "import sys,json; print(json.load(sys.stdin)['result']['read']['text'])" 2>/dev/null || echo "")

  # Check for context warning indicators in OMP output
  if echo "$screen" | grep -qiE "context|compact|limit|truncat"; then
    echo "HIGH"
  else
    # Read session file size as proxy
    local session_path
    session_path=$(herdr agent get "$agent_name" 2>/dev/null | \
      python3 -c "
import sys,json
d=json.load(sys.stdin)
sess=d['result']['agent'].get('agent_session',{})
print(sess.get('value',''))
" 2>/dev/null || echo "")

    if [[ -n "$session_path" && -f "$session_path" ]]; then
      local size_kb
      size_kb=$(du -k "$session_path" 2>/dev/null | cut -f1 || echo "0")
      if [[ "$size_kb" -gt 500 ]]; then
        echo "HIGH"
      elif [[ "$size_kb" -gt 200 ]]; then
        echo "MEDIUM"
      else
        echo "LOW"
      fi
    else
      echo "UNKNOWN"
    fi
  fi
}

# ---- Trigger compact on agent ----
compact_agent() {
  local agent_name="$1"
  echo "📦 Compacting context for $agent_name..."
  herdr agent send "$agent_name" "/compact" 2>/dev/null
  sleep 3
  log_contract "COMPACT" "agent=$agent_name action=compact_triggered"
  echo "✅ Compact sent to $agent_name"
}

# ---- Pause agent ----
pause_agent() {
  local agent_name="$1"
  local reason="${2:-rate_limit}"
  echo "⏸️  Pausing $agent_name (reason: $reason)..."
  echo "$reason" > "$STATE_DIR/${agent_name}.paused"
  log_contract "PAUSE" "agent=$agent_name reason=$reason"
  echo "✅ $agent_name marked as paused"
}

# ---- Resume agent ----
resume_agent() {
  local agent_name="$1"
  if [[ -f "$STATE_DIR/${agent_name}.paused" ]]; then
    rm "$STATE_DIR/${agent_name}.paused"
    log_contract "RESUME" "agent=$agent_name"
    echo "▶️  $agent_name resumed"
  else
    echo "ℹ️  $agent_name was not paused"
  fi
}

# ---- Is agent paused? ----
is_paused() {
  local agent_name="$1"
  [[ -f "$STATE_DIR/${agent_name}.paused" ]]
}

# ---- Dispatch command ----
case "${1:-help}" in
  best-provider)
    result=$(best_provider)
    echo "$result"
    ;;
  check-agent)
    agent="${2:?Usage: check-agent <name>}"
    ctx=$(check_agent_context "$agent")
    paused=""
    is_paused "$agent" && paused="[PAUSED:$(cat "$STATE_DIR/${agent}.paused")]"
    echo "agent=$agent context=$ctx $paused"
    ;;
  compact)
    compact_agent "${2:?Usage: compact <agent-name>}"
    ;;
  pause)
    pause_agent "${2:?Usage: pause <agent-name> [reason]}" "${3:-manual}"
    ;;
  resume)
    resume_agent "${2:?Usage: resume <agent-name>}"
    ;;
  status)
    echo "=== Agent Router Status ==="
    for f in "$STATE_DIR"/*.paused; do
      [[ -f "$f" ]] || continue
      name=$(basename "$f" .paused)
      reason=$(cat "$f")
      echo "  ⏸️  $name — paused ($reason)"
    done
    echo ""
    echo "=== Best Provider ==="
    best_provider
    ;;
  help|*)
    echo "Usage: agent-router.sh <command>"
    echo "  best-provider              → print best model string"
    echo "  check-agent <name>         → check context level + pause state"
    echo "  compact <name>             → trigger /compact on agent"
    echo "  pause <name> [reason]      → mark agent as paused"
    echo "  resume <name>              → mark agent as resumed"
    echo "  status                     → overview of all paused agents + best provider"
    ;;
esac
