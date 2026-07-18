#!/usr/bin/env bash
# ============================================================
# watchdog.sh — Continuous monitoring daemon
#   - Polls usage setiap N detik
#   - Deteksi limit → pause agent sebelum kehabisan
#   - Deteksi agent mati → respawn otomatis
#   - Monitor context usage → compact
#   - Log semua events ke WORK_CONTRACT
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMP_BIN="${OMP_BIN:-/home/efsatu/.bun/bin/omp}"
OMP_PATH_ENV="PATH=/home/efsatu/.bun/bin:/home/efsatu/.local/bin:/home/efsatu/.nvm/versions/node/v24.14.0/bin:/usr/local/bin:/usr/bin:/bin"
HERDR_BIN="${HERDR_BIN:-/home/efsatu/.local/bin/herdr}"
CONTRACT_FILE="$SCRIPT_DIR/WORK_CONTRACT.md"
STATE_DIR="$SCRIPT_DIR/.state"
LOG_FILE="$SCRIPT_DIR/watchdog.log"

POLL_SEC="${WATCHDOG_POLL:-30}"      # poll interval
WARN_THRESHOLD=70
PAUSE_THRESHOLD=82    # pause agents at this %
COMPACT_KB=500        # compact context above this KB

mkdir -p "$STATE_DIR"

ts()  { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
log() {
  local msg="[$(ts)] WATCHDOG: $*"
  echo "$msg" | tee -a "$LOG_FILE" >&2
}

contract_append() {
  local type="$1"; shift
  printf "| %-22s | %-12s | %s |\n" "$(ts)" "$type" "$*" >> "$CONTRACT_FILE"
}

# Registered agents file
AGENTS_FILE="$STATE_DIR/registered_agents.txt"

register_agent() {
  local name="$1" model="$2"
  grep -qF "$name" "$AGENTS_FILE" 2>/dev/null || echo "$name|$model" >> "$AGENTS_FILE"
}

unregister_agent() {
  local name="$1"
  sed -i "/^${name}|/d" "$AGENTS_FILE" 2>/dev/null || true
}

get_registered_agents() {
  cat "$AGENTS_FILE" 2>/dev/null || true
}

# ---- Check single provider status ----
check_provider_pct() {
  local provider="$1"  # "anthropic" or "antigravity"
  "$SCRIPT_DIR/usage-monitor.sh" --json 2>/dev/null | python3 - "$provider" <<'PYEOF'
import sys, json
data = json.loads(sys.stdin.read())
provider = sys.argv[1]

if "antigravity" in provider:
    for acc in data["providers"].get("google-antigravity", {}).get("accounts", []):
        for k, v in acc.get("limits", {}).items():
            if "Daily" in k and "Google" in k:
                print(f"{v['used_pct']:.1f}")
                sys.exit(0)
elif "anthropic" in provider:
    for acc in data["providers"].get("anthropic", {}).get("accounts", []):
        for k, v in acc.get("limits", {}).items():
            if "5 Hour" in k:
                print(f"{v['used_pct']:.1f}")
                sys.exit(0)
print("0")
PYEOF
}

# ---- Check Hindsight health ----
check_hindsight_health() {
  local status
  status=$(curl -sf --max-time 3 http://localhost:8890/health 2>/dev/null \
    || curl -sf --max-time 3 http://localhost:8890/api/health 2>/dev/null \
    || echo "DOWN")
  if [[ "$status" == "DOWN" ]]; then
    log "⚠️  Hindsight unreachable"
    contract_append "HINDSIGHT_DOWN" "url=http://localhost:8890/health ts=$(ts)"
  fi
}

# ---- Main watchdog loop ----
watchdog_loop() {
  log "Watchdog started (poll=${POLL_SEC}s, pause_threshold=${PAUSE_THRESHOLD}%)"
  contract_append "WATCHDOG_START" "poll=${POLL_SEC}s pause_at=${PAUSE_THRESHOLD}% compact_kb=${COMPACT_KB}"

  while true; do
    # 1. Check usage for all providers
    local usage_json
    usage_json=$("$SCRIPT_DIR/usage-monitor.sh" --json 2>/dev/null || echo "{}")

    local ag_pct anthr_pct
    ag_pct=$(echo "$usage_json" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for acc in d['providers'].get('google-antigravity',{}).get('accounts',[]):
    for k,v in acc.get('limits',{}).items():
        if 'Daily' in k and 'Google' in k:
            print(v['used_pct']); exit()
print(0)
" 2>/dev/null || echo "0")

    anthr_pct=$(echo "$usage_json" | python3 -c "
import sys,json
d=json.load(sys.stdin)
for acc in d['providers'].get('anthropic',{}).get('accounts',[]):
    for k,v in acc.get('limits',{}).items():
        if '5 Hour' in k:
            print(v['used_pct']); exit()
print(0)
" 2>/dev/null || echo "0")

    # 2. Evaluate each registered agent
    while IFS='|' read -r agent_name agent_model; do
      [[ -z "$agent_name" ]] && continue

      # Check if agent exists in herdr
      local exists
      exists=$("$HERDR_BIN" agent get "$agent_name" 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print('yes' if 'agent' in d.get('result',{}) else 'no')" 2>/dev/null || echo "no")

      if [[ "$exists" == "no" ]]; then
        # Check if it should be paused or needs respawn
        if [[ -f "$STATE_DIR/${agent_name}.paused" ]]; then
          local pause_reason
          pause_reason=$(cat "$STATE_DIR/${agent_name}.paused")

          # Check if we should resume (limit reset)
          if [[ "$pause_reason" == "rate_limit_antigravity" ]]; then
            local current_pct="${ag_pct%.*}"
            if [[ "$current_pct" -lt 20 ]]; then
              log "Rate limit reset detected for antigravity. Resuming $agent_name"
              rm "$STATE_DIR/${agent_name}.paused"
              # Respawn
              "$HERDR_BIN" agent start "$agent_name" \
                --cwd "$HOME/my-ai-agents" --split right \
                --env "$OMP_PATH_ENV" \
                -- "$OMP_BIN" --model "$agent_model" 2>/dev/null || true
              contract_append "RESUME_RESPAWN" "agent=$agent_name model=$agent_model"
            fi
          elif [[ "$pause_reason" == "rate_limit_anthropic" ]]; then
            local anthr_current="${anthr_pct%.*}"
            if [[ "$anthr_current" -lt 20 ]]; then
              log "Rate limit reset for anthropic. Resuming $agent_name"
              rm "$STATE_DIR/${agent_name}.paused"
              "$HERDR_BIN" agent start "$agent_name" \
                --cwd "$HOME/my-ai-agents" --split right \
                --env "$OMP_PATH_ENV" \
                -- "$OMP_BIN" --model "$agent_model" 2>/dev/null || true
              contract_append "RESUME_RESPAWN" "agent=$agent_name model=$agent_model"
            fi
          fi
        else
          log "⚠️  Agent $agent_name is gone but not marked paused. Will respawn."
          "$HERDR_BIN" agent start "$agent_name" \
            --cwd "$HOME/my-ai-agents" --split right \
            --env "$OMP_PATH_ENV" \
            -- "$OMP_BIN" --model "$agent_model" 2>/dev/null || true
          contract_append "RESPAWN" "agent=$agent_name model=$agent_model reason=agent_gone"
          sleep 3
        fi
        continue
      fi

      # Agent is alive — check its provider usage
      local should_pause=""
      local pause_reason=""

      if [[ "$agent_model" == *"antigravity"* ]]; then
        local pct_int="${ag_pct%.*}"
        if [[ "$pct_int" -ge "$PAUSE_THRESHOLD" ]]; then
          should_pause="yes"
          pause_reason="rate_limit_antigravity"
          log "🟠 Antigravity at ${ag_pct}% — pausing $agent_name before limit"
        fi
      elif [[ "$agent_model" == *"anthropic"* ]]; then
        local pct_int="${anthr_pct%.*}"
        if [[ "$pct_int" -ge "$PAUSE_THRESHOLD" ]]; then
          should_pause="yes"
          pause_reason="rate_limit_anthropic"
          log "🟠 Anthropic at ${anthr_pct}% — pausing $agent_name before limit"
        fi
      fi

      if [[ "$should_pause" == "yes" && ! -f "$STATE_DIR/${agent_name}.paused" ]]; then
        # Try fallback first
        local fallback
        fallback=$("$SCRIPT_DIR/agent-router.sh" best-provider 2>/dev/null | cut -d'|' -f1)
        if [[ "$fallback" != "NONE" && "$fallback" != "$agent_model" ]]; then
          log "🔄 Switching $agent_name from $agent_model → $fallback"
          contract_append "PROVIDER_SWITCH" "agent=$agent_name from=$agent_model to=$fallback"
          # Update registered model
          sed -i "s|^${agent_name}|${agent_name}|" "$AGENTS_FILE" 2>/dev/null || true
          sed -i "s|${agent_name}|${agent_name}|p" "$AGENTS_FILE" 2>/dev/null || true
          # Notify agent (we can't switch model mid-session, but we can log it)
          contract_append "NOTE" "agent=$agent_name manual_action_needed: restart with model=$fallback"
        else
          echo "$pause_reason" > "$STATE_DIR/${agent_name}.paused"
          contract_append "PAUSED" "agent=$agent_name reason=$pause_reason ag_pct=${ag_pct} anthr_pct=${anthr_pct}"
        fi
      fi

      # Check context size
      local session_path
      session_path=$("$HERDR_BIN" agent get "$agent_name" 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result']['agent'].get('agent_session',{}).get('value',''))" 2>/dev/null || echo "")

      if [[ -n "$session_path" && -f "$session_path" ]]; then
        local size_kb
        size_kb=$(du -k "$session_path" 2>/dev/null | cut -f1 || echo "0")
        # Guard: skip compact if agent is currently working ([esc] visible in screen)
        local is_working="no"
        if "$HERDR_BIN" agent screen "$agent_name" 2>/dev/null | grep -qF '[esc]'; then
          is_working="yes"
        fi
        if [[ "$is_working" == "yes" ]]; then
          log "⏭  $agent_name context ${size_kb}KB > ${COMPACT_KB}KB but agent is working — skipping"
          contract_append "COMPACT_SKIPPED" "agent=$agent_name session_kb=$size_kb reason=agent_working"
        else
          log "📦 $agent_name context ${size_kb}KB > ${COMPACT_KB}KB — compacting"
          "$HERDR_BIN" agent send "$agent_name" "/compact" 2>/dev/null || true
          contract_append "COMPACT" "agent=$agent_name session_kb=$size_kb"
          sleep 2
        fi
      fi

    done < <(get_registered_agents)

    # 3. Summary log every 5 cycles
    local cycle_file="$STATE_DIR/cycle_count"
    local cycle=0
    [[ -f "$cycle_file" ]] && cycle=$(cat "$cycle_file")
    cycle=$((cycle + 1))
    echo "$cycle" > "$cycle_file"

    if (( cycle % 5 == 0 )); then
      log "📊 Status: antigravity=${ag_pct}% anthropic=${anthr_pct}%"
      contract_append "HEARTBEAT" "cycle=$cycle ag_daily=${ag_pct}% anthr_5h=${anthr_pct}%"
    fi

    if (( cycle % 10 == 0 )); then
      check_hindsight_health
    fi

    sleep "$POLL_SEC"
  done
}

# ---- CLI ----
case "${1:-run}" in
  run)
    watchdog_loop
    ;;
  register)
    register_agent "${2:?agent name}" "${3:?model}"
    echo "Registered: $2 → $3"
    ;;
  unregister)
    unregister_agent "${2:?}"
    echo "Unregistered: $2"
    ;;
  list)
    echo "=== Registered Agents ==="
    get_registered_agents | while IFS='|' read -r n m; do
      paused=""
      [[ -f "$STATE_DIR/${n}.paused" ]] && paused=" [PAUSED: $(cat "$STATE_DIR/${n}.paused")]"
      echo "  $n → $m$paused"
    done
    ;;
  *)
    echo "Usage: watchdog.sh [run|register <name> <model>|unregister <name>|list]"
    ;;
esac
