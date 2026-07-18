#!/usr/bin/env bash
# ============================================================
# orc.sh — Master AI Agent Orchestrator CLI
# Entry point tunggal untuk semua operasi orchestration
#
# Usage: orc.sh <command> [args...]
#
# Commands:
#   status              → overview semua agent + usage + recommended model
#   usage               → detailed provider usage
#   agents              → detail agents: nama, model, status, pane, usage%
#   dispatch <agent> <"task"> [model]  → kirim task dengan auto-fallback
#   route <"task">                     → auto-route task (task-dispatcher pilih agent)
#   plan <agent> <"task">              → dispatch ke planner dengan claude-fable-5
#   spawn <name> [model]               → spawn agent baru (blok direct anthropic)
#   compact <agent>                    → trigger /compact
#   goal <agent> <"goal">              → set /goal
#   loop <agent> ["task"]              → set /loop
#   pause <agent>                      → pause agent (manual)
#   resume <agent>                     → resume paused agent
#   read <agent>                       → baca output terbaru agent
#   watch                              → live usage monitor
#   watchdog start|stop|list           → kelola daemon watchdog
#   contract                           → tampilkan WORK_CONTRACT log
#   retain <"fact">                    → simpan ke hindsight memory
#   recall <"query">                   → query hindsight memory
#   best-provider                      → tampilkan best model saat ini
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMP_BIN="${OMP_BIN:-/home/efsatu/.bun/bin/omp}"
OMP_PATH_ENV="PATH=/home/efsatu/.bun/bin:/home/efsatu/.local/bin:/home/efsatu/.nvm/versions/node/v24.14.0/bin:/usr/local/bin:/usr/bin:/bin"
HERDR_BIN="${HERDR_BIN:-/home/efsatu/.local/bin/herdr}"
CONTRACT_FILE="$SCRIPT_DIR/WORK_CONTRACT.md"
STATE_DIR="$SCRIPT_DIR/.state"
WATCHDOG_PID_FILE="$STATE_DIR/watchdog.pid"
WATCHDOG_LOG="$SCRIPT_DIR/watchdog.log"

mkdir -p "$STATE_DIR"

ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

contract_append() {
  local type="$1"; shift
  printf "| %-22s | %-12s | %s |\n" "$(ts)" "$type" "$*" >> "$CONTRACT_FILE"
}

# ============================================================
# status — full overview
# ============================================================
cmd_status() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║          🤖 AI AGENT ORCHESTRATOR — STATUS                  ║"
  echo "║          $(date '+%d %b %Y %H:%M:%S %Z')                        ║"
  echo "╠══════════════════════════════════════════════════════════════╣"

  echo ""
  echo "  ▌AGENTS"
  "$HERDR_BIN" pane list 2>/dev/null | python3 -c "
import sys, json, os
d = json.load(sys.stdin)
panes = d['result']['panes']
for p in panes:
    agent  = p.get('agent', '—')
    status = p.get('agent_status', '?')
    pane   = p.get('pane_id','?')
    name   = p.get('name','')
    cwd    = p.get('foreground_cwd','')
    icon   = {'working':'🟡','idle':'🟢','unknown':'⚪'}.get(status,'❓')
    label  = name if name else agent
    print(f'  {icon} {label:<18} {status:<8} {pane:<10} {cwd}')
" 2>/dev/null || echo "  (herdr not reachable)"

  echo ""
  echo "  ▌PAUSED AGENTS"
  local any_paused=0
  for f in "$STATE_DIR"/*.paused; do
    [[ -f "$f" ]] || continue
    any_paused=1
    name=$(basename "$f" .paused)
    reason=$(cat "$f")
    echo "  ⏸️  $name — $reason"
  done
  [[ $any_paused -eq 0 ]] && echo "  (none)"

  echo ""
  echo "  ▌USAGE"
  "$SCRIPT_DIR/usage-monitor.sh" 2>/dev/null | grep -v "^╔\|^╠\|^╚\|^║.*MONITOR\|^║.*2026" || true

  echo ""
  echo "  ▌WATCHDOG"
  if [[ -f "$WATCHDOG_PID_FILE" ]]; then
    local wdpid
    wdpid=$(cat "$WATCHDOG_PID_FILE")
    if kill -0 "$wdpid" 2>/dev/null; then
      echo "  🟢 Running (PID $wdpid)"
    else
      echo "  🔴 Dead (PID $wdpid stale)"
      rm -f "$WATCHDOG_PID_FILE"
    fi
  else
    echo "  ⚪ Not running"
  fi

  echo ""
  echo "  ▌QUEUED TASKS"
  local any_queued=0
  for f in "$STATE_DIR"/queued_*.task; do
    [[ -f "$f" ]] || continue
    any_queued=1
    tid=$(basename "$f" .task | sed 's/queued_//')
    agent_f="$STATE_DIR/queued_${tid}.agent"
    agent_name=$([[ -f "$agent_f" ]] && cat "$agent_f" || echo "?")
    echo "  📋 task_id=$tid agent=$agent_name"
  done
  [[ $any_queued -eq 0 ]] && echo "  (none)"

  echo ""
  echo "  ▌RECOMMENDED MODEL (next task)"
  local best_model
  best_model=$("$SCRIPT_DIR/agent-router.sh" best-provider 2>/dev/null) || best_model="(unavailable)"
  echo "  🎯 $best_model"

  echo ""
  echo "╚══════════════════════════════════════════════════════════════╝"
}

# ============================================================
# agents — detailed list with model + provider usage
# ============================================================
cmd_agents() {
  local reg_file="$STATE_DIR/registered_agents.txt"
  local usage_json
  usage_json=$("$SCRIPT_DIR/usage-monitor.sh" --json 2>/dev/null || echo '{}')

  echo ""
  echo "  ▌HERDR AGENTS (detailed)"
  echo ""

  (
    export ORC_REG_FILE="$reg_file"
    export ORC_USAGE_JSON="$usage_json"
    "$HERDR_BIN" pane list 2>/dev/null | python3 -c "
import sys, json, os

d = json.load(sys.stdin)
panes = d.get('result', {}).get('panes', [])

# Load agent→model map from registered_agents.txt
reg_file = os.environ.get('ORC_REG_FILE', '')
agent_map = {}
if reg_file and os.path.exists(reg_file):
    for line in open(reg_file):
        line = line.strip()
        if '|' in line:
            n, m = line.split('|', 1)
            agent_map[n.strip()] = m.strip()

# Parse provider usage from usage-monitor --json
usage_data = {}
try:
    usage_data = json.loads(os.environ.get('ORC_USAGE_JSON', '{}'))
except Exception:
    pass

# Extract per-provider usage percentage
provider_usage = {}
if isinstance(usage_data, dict):
    provs = usage_data.get('providers', usage_data)
    for prov, info in provs.items():
        if not isinstance(info, dict):
            continue
        # Try aggregate percent or first account limit
        pct = info.get('percent') or info.get('usage_pct') or info.get('pct')
        if pct is None:
            for acc in info.get('accounts', []):
                for lname, ld in acc.get('limits', {}).items():
                    if isinstance(ld, dict) and 'used_pct' in ld:
                        pct = ld['used_pct']
                        break
                if pct is not None:
                    break
        if pct is not None:
            provider_usage[prov] = pct

print('  %-20s %-42s %-10s %-12s %s' % ('NAME', 'MODEL', 'STATUS', 'PANE', 'USAGE%'))
print('  %-20s %-42s %-10s %-12s %s' % ('-'*20, '-'*42, '-'*10, '-'*12, '-'*7))
for p in panes:
    agent  = p.get('agent', '')
    status = p.get('agent_status', '?')
    pane   = p.get('pane_id', '?')
    name   = p.get('name', '') or agent
    icon   = {'working':'🟡','idle':'🟢','unknown':'⚪'}.get(status,'❓')
    model  = agent_map.get(name, agent_map.get(agent, '-'))
    prov   = model.split('/')[0] if '/' in model else model
    pct    = provider_usage.get(prov) or provider_usage.get(model)
    ustr   = ('%.1f%%' % float(pct)) if pct is not None else '-'
    print('  %s %-18s %-42s %-10s %-12s %s' % (icon, name, model, status, pane, ustr))
" 2>/dev/null || echo "  (herdr not reachable)"
  )
  echo ""
}

# ============================================================
# route — auto-route task to best available agent
# ============================================================
cmd_route() {
  local task="${1:?Usage: orc.sh route <task_text>}"
  "$SCRIPT_DIR/task-dispatcher.sh" route "$task"
}

# ============================================================
# plan — dispatch planning task forced to claude-fable-5
# ============================================================
cmd_plan() {
  local agent="${1:?Usage: orc.sh plan <agent> <task>}"
  local task="${2:?Usage: orc.sh plan <agent> <task>}"
  if [[ "$agent" != *planner* ]]; then
    echo "[WARN] Agent '$agent' does not contain 'planner' — verify this is a planner agent" >&2
  fi
  contract_append "PLAN_DISPATCH" "agent=$agent model=anthropic/claude-fable-5 task=${task:0:100}"
  "$SCRIPT_DIR/task-dispatcher.sh" dispatch "$agent" "$task" "anthropic/claude-fable-5" "$(date +%s)"
}

# ============================================================
# read agent output
# ============================================================
cmd_read() {
  local agent="${1:?Usage: orc.sh read <agent-name>}"
  local lines="${2:-100}"
  "$HERDR_BIN" agent read "$agent" --source recent-unwrapped --lines "$lines" 2>/dev/null | \
    python3 -c "import sys,json; print(json.load(sys.stdin)['result']['read']['text'])" 2>/dev/null
}

# ============================================================
# watchdog management
# ============================================================
cmd_watchdog() {
  local action="${1:-status}"
  case "$action" in
    start)
      if [[ -f "$WATCHDOG_PID_FILE" ]]; then
        local old_pid
        old_pid=$(cat "$WATCHDOG_PID_FILE")
        if kill -0 "$old_pid" 2>/dev/null; then
          echo "Watchdog already running (PID $old_pid)"
          return
        fi
      fi
      echo "Starting watchdog daemon..."
      WATCHDOG_POLL="${2:-30}" nohup "$SCRIPT_DIR/watchdog.sh" run \
        >> "$WATCHDOG_LOG" 2>&1 &
      echo $! > "$WATCHDOG_PID_FILE"
      echo "✅ Watchdog started (PID $(cat "$WATCHDOG_PID_FILE"))"
      contract_append "WATCHDOG_START" "pid=$(cat "$WATCHDOG_PID_FILE") poll=${2:-30}s"
      ;;
    stop)
      if [[ -f "$WATCHDOG_PID_FILE" ]]; then
        local pid
        pid=$(cat "$WATCHDOG_PID_FILE")
        kill "$pid" 2>/dev/null && echo "✅ Watchdog stopped (PID $pid)" || echo "Already dead"
        rm -f "$WATCHDOG_PID_FILE"
        contract_append "WATCHDOG_STOP" "pid=$pid"
      else
        echo "Watchdog not running"
      fi
      ;;
    restart)
      cmd_watchdog stop
      sleep 1
      cmd_watchdog start "${2:-30}"
      ;;
    list)
      "$SCRIPT_DIR/watchdog.sh" list
      ;;
    register)
      "$SCRIPT_DIR/watchdog.sh" register "${2:?}" "${3:?}"
      ;;
    unregister)
      "$SCRIPT_DIR/watchdog.sh" unregister "${2:?}"
      ;;
    status|*)
      if [[ -f "$WATCHDOG_PID_FILE" ]] && kill -0 "$(cat "$WATCHDOG_PID_FILE")" 2>/dev/null; then
        echo "🟢 Watchdog running (PID $(cat "$WATCHDOG_PID_FILE"))"
      else
        echo "⚪ Watchdog not running"
      fi
      echo ""
      echo "Last 10 watchdog log lines:"
      tail -10 "$WATCHDOG_LOG" 2>/dev/null || echo "(no log yet)"
      ;;
  esac
}

# ============================================================
# retain / recall via OMP memory
# ============================================================
cmd_retain() {
  local fact="${1:?Usage: orc.sh retain <fact>}"
  "$OMP_BIN" --print "retain this fact to memory: $fact" 2>/dev/null || \
    echo "[WARN] Could not retain via omp --print; fact: $fact"
  contract_append "RETAIN" "fact=${fact:0:150}"
}

cmd_recall() {
  local query="${1:?Usage: orc.sh recall <query>}"
  "$OMP_BIN" --print "recall from memory: $query" 2>/dev/null || echo "(no result)"
}

# ============================================================
# contract view
# ============================================================
cmd_contract() {
  local lines="${1:-50}"
  if [[ -f "$CONTRACT_FILE" ]]; then
    echo "=== WORK CONTRACT (last $lines entries) ==="
    tail -"$lines" "$CONTRACT_FILE"
  else
    echo "(contract not initialized yet)"
  fi
}

# ============================================================
# Dispatch with self-monitoring
# ============================================================
cmd_dispatch() {
  local agent="${1:?}"
  local task="${2:?}"
  local model="${3:-}"
  "$SCRIPT_DIR/task-dispatcher.sh" dispatch "$agent" "$task" "$model" "$(date +%s)"
}

# ============================================================
# Entry point
# ============================================================
case "${1:-status}" in
  status)
    cmd_status
    ;;
  usage)
    "$SCRIPT_DIR/usage-monitor.sh"
    ;;
  watch)
    "$SCRIPT_DIR/usage-monitor.sh" --watch "${2:-30}"
    ;;
  agents)
    cmd_agents
    ;;
  dispatch)
    shift; cmd_dispatch "$@"
    ;;
  route)
    cmd_route "${2:?Usage: orc.sh route <task_text>}"
    ;;
  plan)
    cmd_plan "${2:?Usage: orc.sh plan <agent> <task>}" "${3:?Usage: orc.sh plan <agent> <task>}"
    ;;
  spawn)
    _spawn_model="${3:-google-antigravity/gemini-2.5-flash}"
    _spawn_name="${2:?Usage: orc.sh spawn <name> [model]}"
    _force="${4:-}"

    # Guard 1: block direct anthropic (same provider as main agent)
    if [[ "$_spawn_model" == *anthropic* ]] && [[ "$_spawn_model" != *antigravity* ]]; then
      echo "⛔ Provider sama dengan main agent — gunakan google-antigravity atau provider lain" >&2
      exit 1
    fi

    # Guard 2: pre-spawn reuse check — show existing compatible agents
    if [[ "$_force" != "--force" ]]; then
      _existing=$("$HERDR_BIN" agent list 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
agents=[a for a in d['result']['agents'] if a.get('agent_status') in ('idle','working') and a.get('name')]
if agents:
    print('EXISTING_AGENTS:')
    for a in agents:
        print(f\"  {a['name']:<22} {a['agent_status']:<8} pane={a['pane_id']}\")
else:
    print('NONE')
" 2>/dev/null || echo "NONE")
      if [[ "$_existing" != "NONE" ]]; then
        echo "⚠️  Ada agent yang sudah berjalan — pertimbangkan reuse sebelum spawn baru:" >&2
        echo "$_existing" >&2
        echo "" >&2
        echo "Gunakan 'orc dispatch <agent> <task>' untuk reuse." >&2
        echo "Jika memang perlu spawn baru, tambahkan --force: orc spawn $_spawn_name $_spawn_model --force" >&2
        exit 1
      fi
    fi

    "$SCRIPT_DIR/task-dispatcher.sh" spawn "$_spawn_name" "$_spawn_model"
    ;;
  compact)
    "$SCRIPT_DIR/agent-router.sh" compact "${2:?}"
    ;;
  goal)
    "$SCRIPT_DIR/task-dispatcher.sh" set-goal "${2:?}" "${3:?}"
    ;;
  loop)
    "$SCRIPT_DIR/task-dispatcher.sh" set-loop "${2:?}" "${3:-60}" "${4:-}"
    ;;
  pause)
    "$SCRIPT_DIR/agent-router.sh" pause "${2:?}" "${3:-manual}"
    ;;
  resume)
    "$SCRIPT_DIR/agent-router.sh" resume "${2:?}"
    ;;
  read)
    shift; cmd_read "$@"
    ;;
  watchdog)
    shift; cmd_watchdog "$@"
    ;;
  contract)
    cmd_contract "${2:-50}"
    ;;
  retain)
    cmd_retain "${2:?}"
    ;;
  recall)
    cmd_recall "${2:?}"
    ;;
  best-provider)
    "$SCRIPT_DIR/agent-router.sh" best-provider
    ;;
  help|--help|-h)
    cat <<'HELP'
orc.sh — AI Agent Orchestrator

  status                            Full overview: agents, usage, recommended model
  usage                             Detailed provider usage with alerts
  watch [interval_sec]              Live usage monitor (default 30s)
  agents                            Detailed list: name, model, status, pane, usage%
  dispatch <agent> <"task"> [model] Send task with auto-fallback
  route <"task">                    Auto-route task to best available agent
  plan <agent> <"task">             Dispatch planning task with claude-fable-5
                                    (warns if agent name does not contain 'planner')
  spawn <name> [model]              Spawn new OMP agent
                                    (blocks direct anthropic/* unless via antigravity)
  compact <agent>                   Trigger /compact on agent
  goal <agent> <"goal">             Set /goal on agent
  loop <agent> ["task"]             Set /loop on agent
  pause <agent> [reason]            Manually pause agent
  resume <agent>                    Resume paused agent
  read <agent> [lines]              Read latest agent output
  watchdog start|stop|restart|list|register|unregister|status
  contract [lines]                  View WORK_CONTRACT log
  retain <"fact">                   Store fact to Hindsight memory
  recall <"query">                  Query Hindsight memory
  best-provider                     Print current best model
HELP
    ;;
  *)
    echo "Unknown command: $1. Run 'orc.sh help' for usage."
    exit 1
    ;;
esac
