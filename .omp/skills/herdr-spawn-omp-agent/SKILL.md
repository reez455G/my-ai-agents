---
name: herdr-spawn-omp-agent
description: "Spawn, dispatch tasks to, monitor, and read output from OMP agents inside herdr panes"
---

# Spawn & Orchestrate OMP Agents via herdr

Use when spawning OMP agent instances inside herdr panes and dispatching tasks to them.

## Prerequisites
- herdr server running: `herdr status`
- Know the target model in `provider/model` format
- Check available models: `omp models antigravity`

## Key Constraints
- herdr spawned pane PATH is limited (`/usr/bin:/bin` etc) — `~/.bun/bin` is NOT included. Always use the **full binary path** for `omp`.
- `herdr agent send` writes text into the input buffer but does NOT press Enter. OMP auto-submits after a moment, OR send a follow-up `herdr pane run <pane_id> ""` to force Enter.
- Use `--source visible` to detect if agent is working vs idle (look for `Working…` in screen text).
- Use `--source recent-unwrapped` to read the full clean response after completion.

## 1. Spawn Agents

```bash
# Agent 1 — split right in current workspace tab
herdr agent start omp-agent-1 \
  --cwd ~/my-ai-agents \
  --split right \
  --env PATH="/home/efsatu/.bun/bin:/home/efsatu/.local/bin:/home/efsatu/.nvm/versions/node/v24.14.0/bin:/usr/local/bin:/usr/bin:/bin" \
  -- /home/efsatu/.bun/bin/omp --model google-antigravity/gemini-2.5-flash

# Agent 2 — split down
herdr agent start omp-agent-2 \
  --cwd ~/my-ai-agents \
  --split down \
  --env PATH="/home/efsatu/.bun/bin:/home/efsatu/.local/bin:/home/efsatu/.nvm/versions/node/v24.14.0/bin:/usr/local/bin:/usr/bin:/bin" \
  -- /home/efsatu/.bun/bin/omp --model google-antigravity/gemini-2.5-flash

# Verify both running
herdr agent get omp-agent-1
herdr agent get omp-agent-2
```

## 2. Dispatch Tasks (parallel)

```bash
herdr agent send omp-agent-1 "Your task for agent 1 here"
herdr agent send omp-agent-2 "Your task for agent 2 here"
```

OMP auto-submits the input. If it doesn't start working within ~3s, force Enter:
```bash
herdr pane run <pane_id> ""
```

## 3. Monitor Until Done

```bash
for i in $(seq 1 36); do
  s1=$(herdr agent read omp-agent-1 --source visible --lines 5 2>/dev/null | \
    python3 -c "import sys,json; t=json.load(sys.stdin)['result']['read']['text']; print('working' if 'Working' in t else 'done')" 2>/dev/null)
  s2=$(herdr agent read omp-agent-2 --source visible --lines 5 2>/dev/null | \
    python3 -c "import sys,json; t=json.load(sys.stdin)['result']['read']['text']; print('working' if 'Working' in t else 'done')" 2>/dev/null)
  echo "[$(date +%H:%M:%S)] agent-1=$s1 | agent-2=$s2"
  [ "$s1" = "done" ] && [ "$s2" = "done" ] && echo "=== DONE ===" && break
  sleep 10
done
```

## 4. Read Output

```bash
# Clean unwrapped text (best for parsing)
herdr agent read omp-agent-1 --source recent-unwrapped --lines 200 2>&1 | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['result']['read']['text'])"

herdr agent read omp-agent-2 --source recent-unwrapped --lines 200 2>&1 | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['result']['read']['text'])"
```

## 5. Send Follow-up Tasks

```bash
herdr agent send omp-agent-1 "Next task..."
```

## Provider Model Reference

| Provider flag | Model name | Format |
|---|---|---|
| antigravity | gemini-2.5-flash | `google-antigravity/gemini-2.5-flash` |
| antigravity | gemini-2.5-pro | `google-antigravity/gemini-2.5-pro` |
| antigravity | claude-sonnet-4-6 | `google-antigravity/claude-sonnet-4-6` |

Discover more: `omp models antigravity`

## Typical Timing
- Spawn: instant
- Task completion (web search + response): ~10–30s depending on model and task
- Poll interval: 10s is safe
