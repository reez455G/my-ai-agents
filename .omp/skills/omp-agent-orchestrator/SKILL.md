---
name: omp-agent-orchestrator
description: "Full AI agent orchestration system for herdr+OMP: provider segregation, task routing, usage monitoring, watchdog daemon, and append-only work contract logging"
---

# OMP Agent Orchestrator

Use when managing multiple OMP agents via herdr with production-grade reliability.

## Location
```
~/my-ai-agents/orchestrator/
├── orc.sh              ← master CLI  (also at ~/.local/bin/orc)
├── usage-monitor.sh    ← parse `omp usage` → JSON + human display
├── agent-router.sh     ← provider routing, pause/resume, compact
├── task-dispatcher.sh  ← dispatch + route_task + provider segregation
├── watchdog.sh         ← 30s daemon: usage, context guard, Hindsight check
├── burn-test.sh        ← full cycle test: burn → pause → wait → resume
├── WORK_CONTRACT.md    ← append-only audit log
└── .state/             ← runtime state (PID, registered agents, paused flags)
```

## ⚠️ CRITICAL: Provider Segregation Rule
**Spawned worker agents MUST use a different provider from the main agent.**
- Main agent = `anthropic/claude-sonnet-4-6`
- Workers MUST use `google-antigravity/gemini-*` or other non-Anthropic providers
- `orc.sh spawn` blocks direct `anthropic/*` with a WARNING and exit 1
- Exception: `anthropic/claude-fable-5` allowed ONLY for the planner-agent role

Reason: if workers and main agent share the same provider and hit the limit,
the orchestrator itself goes blind and cannot monitor or dispatch anything.

## Fleet Layout (correct as of 2026-07-16)
```
main agent      → anthropic/claude-sonnet-4-6  (orchestrator — never burn this)
planner-agent   → anthropic/claude-fable-5     (plan/design/architecture ONLY)
worker-agent-1  → google-antigravity/gemini-2.5-flash  (heavy execution)
worker-agent-2  → google-antigravity/gemini-2.5-pro    (heavy execution)
omp-agent-1/2   → google-antigravity/gemini-2.5-flash  (general workers)
```

## Task Routing (auto via `orc route` or `orc dispatch`)
| Keywords in task | → Model |
|---|---|
| plan, design, architect, analisa, rancang, sistem, adr, evaluasi | `anthropic/claude-fable-5` |
| code, implement, buat, build, fix, debug, test, tulis kode | `google-antigravity/gemini-2.5-flash` |
| (default) | `google-antigravity/gemini-2.5-flash` |

## Daily commands
```bash
orc status                          # full overview + recommended model
orc usage                           # provider usage bars + alerts
orc agents                          # detail: name, model, pane, usage%
orc route "task text"               # what model would handle this task?
orc dispatch worker-agent-1 "task"  # send task (auto-routes if no model)
orc plan planner-agent "design X"   # force fable-5 + warn if not planner
orc spawn myagent gemini-2.5-flash  # safe spawn (antigravity OK, direct anthropic blocked)
orc compact agent-name              # trigger /compact
orc goal agent-name "goal text"     # set /goal
orc loop agent-name "task"          # set /loop
orc watchdog start|stop|restart
orc contract [N]                    # view audit log
```

## CRITICAL: herdr dispatch pattern
```bash
herdr agent send <name> "task text"   # puts text in buffer only
sleep 1
herdr pane run <pane_id> ""           # REQUIRED: press Enter to submit
# OMP does NOT auto-submit without Enter!
```

## OMP active state detection (all active states show [esc])
```bash
herdr agent read <name> --source visible --lines 15 | \
  python3 -c "import sys,json; t=json.load(sys.stdin)['result']['read']['text']; \
  print('busy' if '[esc]' in t or 'Thinking' in t else 'idle')"
```

## Watchdog behaviors (2026-07-16 config)
- COMPACT_KB = 500 (not 200 — was over-aggressive)
- Compact skipped if agent is working (`[esc]` detected) → logs COMPACT_SKIPPED
- `check_hindsight_health()` every 10 cycles → logs HINDSIGHT_DOWN if fails
- Pause threshold = 82%, checks antigravity Daily and anthropic 5 Hour
- Respawn dead agents not in paused state

## WORK_CONTRACT event types
SESSION_OPEN, SPAWN, DISPATCH, COMPLETE, TIMEOUT, COMPACT, COMPACT_SKIPPED,
PAUSE, RESUME, FALLBACK, LIMIT_HIT, THRESHOLD_HIT, AGENTS_PAUSED,
WAIT_RESET_START, RESET_DETECTED, AGENTS_RESUMED, VERIFY_RESULT,
HEARTBEAT, HINDSIGHT_DOWN, PROVIDER_OVERRIDE, PLAN_DISPATCH,
BURN_TEST_SUCCESS, ARCH_DECISION, RULE, BUG_NOTED, FLEET_UPDATED
