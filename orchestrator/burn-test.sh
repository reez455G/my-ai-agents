#!/usr/bin/env bash
# ============================================================
# burn-test.sh v2 — Usage limit burn test + pause/resume validation
# Fix: proper dispatch timing, wait-for-working detection
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERDR=/home/efsatu/.local/bin/herdr
OMP=/home/efsatu/.bun/bin/omp
CONTRACT="$SCRIPT_DIR/WORK_CONTRACT.md"
LOG="$SCRIPT_DIR/burn-test.log"
STATE="$SCRIPT_DIR/.state"

AGENT1="anthr-agent-1"
AGENT2="anthr-agent-2"
PAUSE_AT=82
RESUME_BELOW=15
TASK_TIMEOUT=300   # max seconds per task

ts()  { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
log() { echo "[$(ts)] BURN: $*" | tee -a "$LOG"; }

contract() {
  local type="$1"; shift
  printf "| %-22s | %-12s | %s |\n" "$(ts)" "$type" "$*" >> "$CONTRACT"
}

get_anthr_pct() {
  $OMP usage 2>/dev/null | python3 -c "
import sys, re
text = sys.stdin.read()
m = re.search(r'Claude 5 Hour.*?([\d.]+)%\s+used', text, re.S)
print(m.group(1) if m else '0')
" 2>/dev/null || echo "0"
}

get_reset_time() {
  $OMP usage 2>/dev/null | python3 -c "
import sys, re
text = sys.stdin.read()
m = re.search(r'Claude 5 Hour.*?resets in\s+(\d+h\d+m|\d+h|\d+m)', text, re.S)
print(m.group(1).strip() if m else 'unknown')
" 2>/dev/null || echo "unknown"
}

agent_alive() {
  $HERDR agent get "$1" 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    print('yes' if 'agent' in d.get('result',{}) else 'no')
except: print('no')
" 2>/dev/null || echo "no"
}

# Wait for agent to START working (Working... appears)
wait_starts_working() {
  local name="$1" timeout="${2:-20}"
  local elapsed=0
  while [[ $elapsed -lt $timeout ]]; do
    local screen
    screen=$($HERDR agent read "$name" --source visible --lines 15 2>/dev/null | \
      python3 -c "import sys,json; print(json.load(sys.stdin)['result']['read']['text'])" 2>/dev/null || echo "")
    if echo "$screen" | grep -qE "\[esc\]|Working…|Thinking"; then
      return 0
    fi
    sleep 2; elapsed=$((elapsed+2))
  done
  return 1  # didn't start (might have finished instantly or failed)
}

# Wait for agent to FINISH working
wait_idle() {
  local name="$1" timeout="${2:-$TASK_TIMEOUT}"
  local elapsed=0
  while [[ $elapsed -lt $timeout ]]; do
    local screen
    screen=$($HERDR agent read "$name" --source visible --lines 3 2>/dev/null | \
      python3 -c "import sys,json; print(json.load(sys.stdin)['result']['read']['text'])" 2>/dev/null || echo "")
    if ! echo "$screen" | grep -q "Working"; then
      return 0
    fi
    sleep 8; elapsed=$((elapsed+8))
  done
  return 1
}

# Get pane_id for an agent
get_pane_id() {
  $HERDR agent get "$1" 2>/dev/null | python3 -c "
import sys,json
try: print(json.load(sys.stdin)['result']['agent']['pane_id'])
except: print('')
" 2>/dev/null || echo ""
}

# Press Enter on a pane to submit buffered input
press_enter() {
  local pane_id="$1"
  [[ -z "$pane_id" ]] && return 0
  $HERDR pane run "$pane_id" "" 2>/dev/null || true
}

# Dispatch ONE task to ONE agent and confirm submission
dispatch_one() {
  local agent="$1" task="$2" task_label="${3:-task}"
  local pane_id
  pane_id=$(get_pane_id "$agent")
  log "📤 [$task_label] → $agent (pane=$pane_id): ${task:0:70}..."
  $HERDR agent send "$agent" "$task" 2>/dev/null
  sleep 1
  press_enter "$pane_id"   # ← submit the buffered input
  sleep 2
  if wait_starts_working "$agent" 20; then
    log "🟡 [$task_label] $agent working..."
    contract "DISPATCH" "agent=$agent label=$task_label pane=$pane_id"
    return 0
  else
    local screen
    screen=$($HERDR agent read "$agent" --source visible --lines 3 2>/dev/null | \
      python3 -c "import sys,json; print(json.load(sys.stdin)['result']['read']['text'])" 2>/dev/null || echo "")
    log "⚠️  [$task_label] $agent no Working... yet: ${screen:0:50}"
    contract "DISPATCH_PEND" "agent=$agent label=$task_label"
    return 0
  fi
}

# ============================================================
# HEAVY TASKS — designed to generate large outputs = more tokens
# ============================================================
TASKS_A=(
  "Buat implementasi lengkap sistem CRUD REST API dengan FastAPI + SQLAlchemy + PostgreSQL. Include: semua endpoint (GET, POST, PUT, PATCH, DELETE), model database dengan relasi, pydantic schemas, dependency injection, error handling, pagination, filtering, authentication JWT, rate limiting, logging, unit tests dengan pytest. Minimal 500 baris kode dengan penjelasan setiap bagian."
  "Implementasikan dari scratch sebuah mini database engine sederhana di Python: B-Tree untuk indexing, WAL (Write-Ahead Log) untuk durability, transaction management dengan ACID, simple SQL parser untuk SELECT/INSERT/UPDATE/DELETE. Berikan kode lengkap dengan komentar dan contoh penggunaan."
  "Buat framework mini dependency injection di Python mirip FastAPI/Spring DI: decorator-based injection, singleton vs transient lifetime, circular dependency detection, async support, testing utilities. Jelaskan arsitektur, berikan 300+ baris kode lengkap dengan unit tests."
  "Implementasikan sistem message queue sederhana di Python: producer-consumer pattern, persistent queue (SQLite backed), retry with exponential backoff, dead letter queue, metrics, worker pool. Kode lengkap production-ready dengan error handling dan monitoring."
  "Buat komprehensif guide implementasi OAuth2 + OIDC dari scratch: authorization code flow, PKCE, refresh tokens, JWT validation, scope management. Implementasi Python (server) dan contoh client. Jelaskan setiap security consideration dengan kode contoh."
  "Implementasi penuh sistem caching multilayer: L1 in-memory (LRU), L2 Redis, L3 database. Cache invalidation strategies, cache warming, stampede prevention (probabilistic early expiration), distributed locking. Kode Python lengkap dengan benchmark."
  "Buat sistem event sourcing + CQRS lengkap di Python: event store, aggregate root pattern, projection/read model, event replay, snapshot, saga pattern. Gunakan contoh domain e-commerce order management. Minimal 600 baris kode."
  "Implementasi WebSocket server dari scratch (tanpa library WebSocket) di Python menggunakan asyncio: handshake HTTP upgrade, frame parsing, masking, ping/pong, room management, broadcast, reconnection logic. Kode lengkap dengan client HTML."
)

TASKS_B=(
  "Analisis mendalam dan implementasi 15 design patterns GoF di Python dengan contoh real-world: Creational (Factory Method, Abstract Factory, Builder, Prototype, Singleton), Structural (Adapter, Bridge, Composite, Decorator, Facade, Flyweight, Proxy), Behavioral (Chain of Responsibility, Command, Iterator, Mediator, Memento, Observer, State, Strategy, Template Method, Visitor). Setiap pattern: diagram, kode 50+ baris, kapan gunakan, pitfalls."
  "Implementasi interpreter bahasa pemrograman sederhana di Python: lexer (tokenizer), parser (recursive descent), AST, evaluator. Support: variabel, fungsi, kondisional, loop, closure, rekursi. Minimal 700 baris dengan test cases."
  "Buat sistem distributed tracing sederhana di Python: trace context propagation, span creation, baggage, sampling, exporter (ke file/HTTP), correlation ID. Implementasikan middleware untuk FastAPI dan aiohttp. Kode lengkap dengan contoh visualisasi."
  "Implementasi rate limiter production-grade: token bucket, sliding window counter, sliding window log. Distributed implementation dengan Redis. Middleware FastAPI. Granularity per-IP, per-user, per-endpoint. Kode 400+ baris dengan tests."
  "Buat full-featured CLI framework dari scratch di Python: argument parsing, subcommands, help generation, config file integration, environment variable support, plugin system, colored output, progress bars, interactive prompts. Contoh CLI app lengkap."
  "Implementasi consensus algorithm Raft di Python: leader election, log replication, log compaction, membership changes. Multi-node simulation dengan network partition testing. Kode 500+ baris dengan penjelasan setiap phase."
  "Buat komprehensif monitoring dan observability stack di Python: structured logging (JSON), metrics (counter, gauge, histogram), distributed tracing, health checks, SLA tracking, alerting rules. Integration dengan Prometheus exposition format. Kode production-ready."
  "Implementasi full-text search engine sederhana di Python: inverted index, TF-IDF scoring, BM25, phrase search, fuzzy matching, ranking, persistence. Index builder dan query engine. Benchmark dengan dataset Wikipedia 10K articles."
)

# ============================================================
# MAIN
# ============================================================
log "🔥 BURN TEST v2 DIMULAI"

BASELINE=$(get_anthr_pct)
RESET_IN=$(get_reset_time)
log "📊 Baseline: ${BASELINE}% | resets in: ${RESET_IN}"
contract "BURN_V2_START" "baseline=${BASELINE}% resets_in=${RESET_IN} pause_at=${PAUSE_AT}%"

BATCH=0
TASK_A_IDX=0
TASK_B_IDX=0

# ============================================================
# PHASE 1: BURN LOOP
# ============================================================
PAUSE_DETECTED=false
PAUSE_PCT=0

while true; do
  CURRENT_PCT=$(get_anthr_pct)
  RESET_IN=$(get_reset_time)
  CURRENT_INT="${CURRENT_PCT%.*}"
  # Remove decimal for comparison
  CURRENT_INT="${CURRENT_INT%.*}"
  # Force integer
  CURRENT_INT=$(echo "$CURRENT_PCT" | python3 -c "import sys; print(int(float(sys.stdin.read())))")

  log "📊 [loop] Usage=${CURRENT_PCT}% resets=${RESET_IN} batch=${BATCH}"

  # Check threshold
  if [[ "$CURRENT_INT" -ge "$PAUSE_AT" ]]; then
    PAUSE_PCT="$CURRENT_PCT"
    PAUSE_DETECTED=true
    log "🟠 THRESHOLD HIT: ${CURRENT_PCT}% ≥ ${PAUSE_AT}%"
    contract "THRESHOLD_HIT" "pct=${CURRENT_PCT}% threshold=${PAUSE_AT}% batch=${BATCH}"
    echo "rate_limit_anthropic_5h" > "$STATE/${AGENT1}.paused"
    echo "rate_limit_anthropic_5h" > "$STATE/${AGENT2}.paused"
    contract "AGENTS_PAUSED" "agents=${AGENT1},${AGENT2} pct=${CURRENT_PCT}%"
    log "⏸️  Agents paused. Entering wait-for-reset phase."
    break
  fi

  # Check agents alive
  A1_ALIVE=$(agent_alive "$AGENT1")
  A2_ALIVE=$(agent_alive "$AGENT2")

  if [[ "$A1_ALIVE" == "no" && "$A2_ALIVE" == "no" ]]; then
    log "❌ Both agents dead. Aborting."
    exit 1
  fi

  # Pick tasks
  TASK_A="${TASKS_A[$TASK_A_IDX]}"
  TASK_B="${TASKS_B[$TASK_B_IDX]}"
  TASK_A_IDX=$(( (TASK_A_IDX + 1) % ${#TASKS_A[@]} ))
  TASK_B_IDX=$(( (TASK_B_IDX + 1) % ${#TASKS_B[@]} ))
  BATCH=$((BATCH+1))

  # Dispatch agent 1
  if [[ "$A1_ALIVE" == "yes" ]]; then
    dispatch_one "$AGENT1" "$TASK_A" "A${BATCH}"
  fi

  # Dispatch agent 2 (slight offset to avoid race)
  sleep 3
  if [[ "$A2_ALIVE" == "yes" ]]; then
    dispatch_one "$AGENT2" "$TASK_B" "B${BATCH}"
  fi

  # Wait for BOTH to finish (parallel wait)
  log "⏳ Waiting for batch $BATCH..."
  WAIT_START=$(date +%s)

  while true; do
    NOW=$(date +%s)
    ELAPSED=$(( NOW - WAIT_START ))

    SCREEN1=$($HERDR agent read "$AGENT1" --source visible --lines 15 2>/dev/null | \
      python3 -c "import sys,json; print(json.load(sys.stdin)['result']['read']['text'])" 2>/dev/null || echo "")
    SCREEN2=$($HERDR agent read "$AGENT2" --source visible --lines 15 2>/dev/null | \
      python3 -c "import sys,json; print(json.load(sys.stdin)['result']['read']['text'])" 2>/dev/null || echo "")

    # OMP active states all show [esc] in the spinner line (Working/Writing/Coding/etc.)
    A1_WORKING=$(echo "$SCREEN1" | grep -cE "\[esc\]|Working…|Thinking" || true)
    A2_WORKING=$(echo "$SCREEN2" | grep -cE "\[esc\]|Working…|Thinking" || true)

    if [[ "$A1_WORKING" -eq 0 && "$A2_WORKING" -eq 0 ]]; then
      log "✅ Batch $BATCH complete (${ELAPSED}s)"
      contract "BATCH_DONE" "batch=$BATCH elapsed=${ELAPSED}s pct=$(get_anthr_pct)%"
      break
    fi

    if [[ $ELAPSED -ge $TASK_TIMEOUT ]]; then
      log "⚠️  Batch $BATCH timeout after ${TASK_TIMEOUT}s — continuing anyway"
      contract "BATCH_TIMEOUT" "batch=$BATCH"
      break
    fi

    sleep 10
  done

  sleep 2  # brief pause before next batch
done

# ============================================================
# PHASE 2: WAIT FOR RESET
# ============================================================
log ""
log "════════════════════════════════════"
log "PHASE 2: WAITING FOR LIMIT RESET"
log "Paused at: ${PAUSE_PCT}%"
log "Waiting for: < ${RESUME_BELOW}%"
log "════════════════════════════════════"
contract "WAIT_RESET_START" "paused_at=${PAUSE_PCT}% target_below=${RESUME_BELOW}%"

CHECK=0
RESET_DETECTED=false
RESET_PCT=0

while true; do
  CHECK=$((CHECK+1))
  CURRENT_PCT=$(get_anthr_pct)
  RESET_IN=$(get_reset_time)
  CURRENT_INT=$(echo "$CURRENT_PCT" | python3 -c "import sys; print(int(float(sys.stdin.read())))")

  log "⏳ [wait $CHECK] usage=${CURRENT_PCT}% resets_in=${RESET_IN}"

  if [[ "$CURRENT_INT" -lt "$RESUME_BELOW" ]]; then
    RESET_PCT="$CURRENT_PCT"
    RESET_DETECTED=true
    log "✅ RESET DETECTED: ${CURRENT_PCT}% < ${RESUME_BELOW}%"
    contract "RESET_DETECTED" "pct=${CURRENT_PCT}% paused_was=${PAUSE_PCT}%"
    break
  fi

  # Heartbeat every 10 checks
  (( CHECK % 10 == 0 )) && contract "WAIT_HEARTBEAT" "check=${CHECK} pct=${CURRENT_PCT}% resets_in=${RESET_IN}"

  sleep 60
done

# ============================================================
# PHASE 3: RESUME + VERIFY
# ============================================================
log ""
log "════════════════════════════════════"
log "PHASE 3: RESUMING + VERIFYING"
log "════════════════════════════════════"

rm -f "$STATE/${AGENT1}.paused" "$STATE/${AGENT2}.paused"
contract "AGENTS_RESUMED" "pct_at_resume=${RESET_PCT}%"

sleep 3

# Ensure agent 1 alive (respawn if needed)
if [[ "$(agent_alive $AGENT1)" == "no" ]]; then
  log "🔄 $AGENT1 needs respawn..."
  ENVP="PATH=/home/efsatu/.bun/bin:/home/efsatu/.local/bin:/home/efsatu/.nvm/versions/node/v24.14.0/bin:/usr/local/bin:/usr/bin:/bin"
  $HERDR agent start "$AGENT1" --cwd ~/my-ai-agents --split right \
    --env "$ENVP" -- $OMP --model anthropic/claude-sonnet-4-6 2>/dev/null
  sleep 5
  contract "RESPAWN" "agent=${AGENT1}"
fi

VERIFY_TASK="[BURN TEST VERIFICATION] Konfirmasi bahwa kamu berjalan normal setelah rate limit reset. Jawab dengan format persis: [RESUME CONFIRMED] model=<model> timestamp=<waktu sekarang WIB> status=OK"

log "📤 Dispatching verification task to $AGENT1..."
$HERDR agent send "$AGENT1" "$VERIFY_TASK" 2>/dev/null
sleep 1
press_enter "$(get_pane_id "$AGENT1")"
sleep 2
wait_starts_working "$AGENT1" 20 || true
wait_idle "$AGENT1" 60 || true

OUTPUT=$($HERDR agent read "$AGENT1" --source recent-unwrapped --lines 30 2>/dev/null | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['result']['read']['text'])" 2>/dev/null || echo "")

CONFIRMED=$(echo "$OUTPUT" | grep -c "RESUME CONFIRMED" || true)
log "📥 Verification output: ${OUTPUT:0:300}"
contract "VERIFY_RESULT" "agent=${AGENT1} confirmed=${CONFIRMED} output_preview=${OUTPUT:0:100}"

# ============================================================
# FINAL REPORT
# ============================================================
FINAL_PCT=$(get_anthr_pct)
log ""
log "════════════════════════════════════════════════════════"
log "✅  BURN TEST COMPLETE"
log "  Phase 1 — Burn:   Pause triggered at ${PAUSE_PCT}% (≥${PAUSE_AT}%)"
log "  Phase 2 — Wait:   Reset detected at ${RESET_PCT}% (<${RESUME_BELOW}%)"
log "  Phase 3 — Resume: Verification confirmed=${CONFIRMED}"
log "  Final usage:       ${FINAL_PCT}%"
log "  Result: $([ "$CONFIRMED" -gt 0 ] && echo SUCCESS || echo PARTIAL_SUCCESS)"
log "════════════════════════════════════════════════════════"

contract "BURN_TEST_FINAL" "pause_at=${PAUSE_PCT}% reset_at=${RESET_PCT}% final=${FINAL_PCT}% verified=${CONFIRMED} result=$([ "$CONFIRMED" -gt 0 ] && echo SUCCESS || echo PARTIAL)"

echo "BURN_TEST_DONE|pause=${PAUSE_PCT}|reset=${RESET_PCT}|final=${FINAL_PCT}|confirmed=${CONFIRMED}"
exit 0
