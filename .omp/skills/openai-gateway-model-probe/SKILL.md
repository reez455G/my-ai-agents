---
name: openai-gateway-model-probe
description: "Health-check all models on an OpenAI-compatible gateway/proxy in parallel to find which ones actually respond — use when a user wants to audit a model catalog (LiteLLM, Hermes gateway, NIM proxy, etc.) instead of testing models one by one."
---

# Probing an OpenAI-compatible model catalog

A working reference implementation lives at `/home/efsatu/.local/bin/hermes-model-check` (stdlib-only Python). Reuse or adapt it rather than rewriting.

## Procedure

1. **Discover endpoint + key** from the product's config first (e.g. `~/.hermes/config.yaml` → `custom_providers` with a localhost `base_url`). Verify with `GET /v1/models`.
2. **Dedupe before probing**: exact duplicate ids AND alias prefixes (`cx/`==`codex/`, `gh/`==`github/`). Halves request count on gateways that mirror prefixes.
3. **Classify by id heuristics** and route the probe accordingly:
   - `embed|bge|nvclip` → `POST /embeddings` with `{model, input: "ping"}`
   - `rerank`, `whisper|asr|tts|fastpitch|tacotron`, `reward|parse|deplot|gliner` → **SKIP with reason** (not probeable via chat; marking them FAIL is a false negative)
   - everything else → `POST /chat/completions`, 1 short user message, `max_tokens: 16`, `stream: false`
4. **Parallelize with two limits**: global thread pool (~16–24) plus a per-provider semaphore (~4, provider = id prefix before first `/`). Without the per-provider cap one backend rate-limits and pollutes results with bogus 429s.
5. **Auto-adapt on 400s** (retry same request once, modified):
   - error mentions `max_tokens`/`max_completion_tokens` → drop `max_tokens`, send `max_completion_tokens: 64` (GPT-5.x reasoning models)
   - embeddings error mentions `input_type` → add `"input_type": "query"` (NVIDIA NIM asymmetric embedders)
6. **Status taxonomy**: `OK` (content or finish_reason in stop/length), `FAIL` (HTTP error + first 140 chars of `error.message`), `TIMEOUT`, `RATE` (429 = model likely alive, quota exhausted — don't call it broken), `SKIP`. Retry once on 5xx/timeout/connection error.
7. **Report**: per-model status + latency + short error, summary counts, `--json` for machine output, `--fail-only` filter.

## Gotchas observed
- Gateways may return 502 "Provider returned empty content" — genuine backend failure, report as FAIL.
- A huge catalog (200+) can be mostly dead (404 "Function not found" on NIM = model undeployed); the catalog listing proves nothing about availability.
- Empty content with `finish_reason: length` still means the model is alive.
