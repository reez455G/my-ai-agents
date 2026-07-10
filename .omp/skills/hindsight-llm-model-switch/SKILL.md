---
name: hindsight-llm-model-switch
description: "Switching the Hindsight container's LLM provider/model in ~/my-ai-agent (NVIDIA model naming/compat, Hindsight-shaped probing, docker compose recreate pitfalls, model-failover.py)"
---

# Switching the Hindsight LLM model (~/my-ai-agent)

## Key facts
- Model config lives in `~/my-ai-agent/.env` → `HINDSIGHT_API_LLM_MODEL`; `docker-compose.yml` passes it through as `${HINDSIGHT_API_LLM_MODEL}`.
- **NVIDIA API (`integrate.api.nvidia.com/v1`) model IDs are namespaced**: `google/gemma-4-31b-it` works, bare `gemma-2-2b-it` → 404.
- NVIDIA 429s can be **model-specific quota** (deepseek-v4-pro exhausted while gemma on the same key returns 200) — don't conclude the key is dead from one model's 429.
- **A plain "ping" probe is NOT sufficient.** Hindsight's fact extraction sends `response_format: {"type":"json_object"}` and large `max_tokens`. Some endpoints (NVIDIA `google/gemma-2-2b-it`) return 200 on plain chat but **422** on the real payload (`response_format` = extra_forbidden, `max_tokens` le=4096) → retain fails in production. Always probe with:
  ```
  curl -s https://integrate.api.nvidia.com/v1/chat/completions \
    -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
    -d '{"model":"<ID>","messages":[{"role":"user","content":"Balas JSON: {\"ok\":true}"}],"max_tokens":8192,"response_format":{"type":"json_object"}}'
  ```
- Verified compatible on this account (2026-07): `google/gemma-4-31b-it`, `meta/llama-3.1-8b-instruct`. NOT usable: `google/gemma-2-2b-it` (422), `google/gemma-3-4b-it`/`gemma-3-12b-it` (404 for account), `gemma-3n-e4b-it` (timeout).

## Procedure
1. Strict-probe candidate model ID(s) (above) — expect 200.
2. Edit `HINDSIGHT_API_LLM_MODEL` in `.env`.
3. `cd ~/my-ai-agent && docker compose stop -t 120 && docker compose up -d` — graceful stop avoids SIGKILL → pg0 WAL crash-recovery. **Timeout ≥1800s**; an interrupted recreate leaves a name conflict (`42ee..._hindsight` temp container): fix with `docker rm -f hindsight <temp>` then `up -d`.
4. Boot is VERY slow when the host is loaded (QuestDB + trading bots pin both cores of the i3; load avg ~11): `/health` can take 20+ min. Poll `curl -s http://localhost:8890/health` every 10-15s; healthy = `{"status":"healthy","database":"connected"}`. `hindsight-api` in `D` state with growing RSS = progressing, not wedged.
5. Verify env landed: `docker exec hindsight sh -c 'env | grep HINDSIGHT_API_LLM_MODEL'`.
6. End-to-end proof: `client.retain(...)` to a scratch bank must succeed (uses the LLM synchronously); recall alone does NOT prove the LLM works (embedding path survives LLM outages). Delete the scratch bank after.
7. Avoid `docker exec ... find/python-import` diagnostics while the host is loaded — they time out (>120s).

## Failover tooling
- `~/my-ai-agent/model-failover.py` (stdlib-only, executable): probes the primary with the Hindsight-shaped payload; on failure runs `hermes-model-check --json`, ranks OK chat candidates (`--prefer` substrings then latency), strict-verifies each against the gateway, rewrites `.env` (backup `.env.bak.<ts>`, gateway URL mapped `localhost` → `host.docker.internal` — extra_hosts already in docker-compose.yml), restarts and polls health. Flags: `--check-only`, `--force`, `--prefer`, `--filter`, `--no-restart`, `--health-wait`.
- `hermes-model-check` (`~/.local/bin`, stdlib-only) probes all models on the local Hermes gateway (`~/.hermes/config.yaml`, `http://localhost:20128/v1`, 213 models). `--json` emits `{base_url, checked, counts, results:[{model, kind, status: OK|FAIL|TIMEOUT|RATE|SKIP, latency_s, note, aliases}]}`. Its plain-ping probe does NOT check `response_format` compat — hence the strict re-verify step.
