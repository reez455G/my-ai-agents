---
name: my-ai-agents-infra-audit
description: "Use when asked to check whether the ~/my-ai-agents modular app/infra (OMP, Hindsight, Hermes gateway, skill auto-sync) is running smoothly, to diagnose/fix sync-automation drift or docker-compose project mislink, to evaluate architecture/content quality gaps, to diagnose Hindsight LLM-backend reliability issues, or to empirically verify Hindsight's memory pipeline (fact extraction, consolidation, graph, entities, reflect). Provides audit checklist, safe fix procedures, gap-analysis checklist, OKF-to-Hindsight ingestion design, and a verification test recipe."
---

# ~/my-ai-agents Infra Audit, Fix, Integration, Gap Analysis & Verification

A plain "is the service up" check misses automation drift in this repo. Run all of these — each one has caught a real issue before.

## 1. Core service health
```bash
cd ~/my-ai-agents && bash verify.sh
```
Also check the Hermes/OmniRoute gateway directly (no `/health` route — 404s to a Next.js page, that's normal):
```bash
curl -sf http://localhost:20128/v1/models | head -c 200
```
**Never use OmniRoute (`localhost:20128`) as an LLM provider for a headless/always-on service.** Verified 2026-07-14: its models (`gemini-cli/*`, `codex/*`, `antigravity/*`) are backed by interactive CLI OAuth sessions; `POST /v1/chat/completions` timed out completely (8-18s, no response) even though `/v1/models` (a static catalog) works fine.

## 2. Git hooks / 3. omp alias drift / 4. docker-compose relink
(unchanged from prior audits — see git history of this skill for full detail if needed: `git config core.hooksPath githooks`; compare `alias omp=` in shell rc against `ALIAS_LINE=` in `setup-new-device.sh`; for compose relink, mark the volume `external: true` pointing at the pre-existing volume name before recreating the container.)

## 5. Hindsight LLM-backend reliability
Check `GET /v1/default/banks/{bank}/stats` for `failed_operations`/`failed_consolidation`, then `GET .../operations?status=failed` for `error_message`. **Test each hypothesis with a raw curl reproducing the exact call shape before concluding cause** — don't default-blame host CPU/network just because something times out while other things are running:
- `"System role not supported"` (HTTP 500) — model structurally rejects system-role messages (seen with Gemma family).
- **Reasoning models silently exhaust the token budget on hidden `reasoning_content`, never emit `content`** (`finish_reason: "length"`, empty content) — verified with `nvidia/llama-3.3-nemotron-super-49b-v1.5` against Hindsight's tight `max_completion_tokens=100` boot check. No API param reliably disables it (`chat_template_kwargs.thinking=false`, `reasoning_effort=none` all failed); only a system-role `/no_think` message works, not injectable into Hindsight's internal calls. **Fix: use a non-reasoning instruct model** (`meta/llama-3.1-70b-instruct` verified: consistently <1s, clean `finish_reason: stop`).
- 429 rate-limit / timeouts under bursty load — tune via `PATCH /v1/default/banks/{bank}/config` (payload MUST be wrapped: `{"updates": {...}}`) — `consolidation_llm_parallelism`, `consolidation_llm_batch_size`. **Once the model itself is confirmed fast/reliable, don't leave concurrency defensively low** — a large pending backlog (e.g. from bulk OKF ingestion) needs real throughput; parallelism=2 was appropriate for a flaky model but became the bottleneck once the model was fixed. Bumped 2→6, batch 4→16 on 2026-07-14 once `meta/llama-3.1-70b-instruct` was confirmed reliable, backlog started draining immediately.
- `HINDSIGHT_API_LLM_TIMEOUT` env (default 120s, `hindsight_api/config.py`) — raise if calls are just slow, not actually failing.
- Recover a backlog: `POST .../operations/{id}/retry` per failed op, `POST .../consolidation/recover` (bulk) for failed consolidations. Confirm via `stats`.
- A parent `batch_retain` operation shows `status: "pending"` even while its `child_operations` are actively `"processing"` — check the child status, not just the parent, when polling for completion.
- **Synchronous on-demand endpoints (`/reflect`, `/memories/dry-run-extract`) can take 60-250s+ under backlog contention** even when the `operations` queue itself looks empty (few `pending`/`processing`) — they seem to compete for the same LLM concurrency pool as the consolidation backlog. Use timeouts of at least 120-240s when calling them synchronously during/after a bulk ingestion; don't assume a >60s hang means the endpoint is broken. (`dry-run-extract` specifically was fully unresponsive even on a trivial 5-word payload during a period of very deep backlog — retest it once the backlog is small before concluding it's actually broken vs just starved.)

## 6. Disk headroom
`docker rmi` unreferenced images, `docker builder prune -f`, confirm orphaned volumes before removing (`docker ps -a --filter volume=<name>` empty + tool's own status command). Never touch other projects' volumes without explicit confirmation.

## 7. OKF ↔ Hindsight integration
`ingest-okf-to-hindsight.py` mirrors `knowledge/**/*.md` into the bank as documents (`document_id=f"okf:{id}"`, `timestamp:"unset"`, tags `source:okf`/`project:<repo>`/`okf-tag:<tag>`). Idempotent (OKF is append-only) via live `GET .../documents` check, not local state. **Must use `async: false`** (sync) — an async version races: re-running before the batch finishes processing doesn't see new documents yet and double-submits. Wired into `sync-skills.sh`, best-effort (`|| echo WARN`, never blocks git push). Full design: `program.md` §12.

## 8. Verifying the memory pipeline actually works (not just "is it up") — recipe used 2026-07-14
Retain a synthetic test paragraph with 3-4 distinct facts + one deliberately irrelevant aside, all tagged with a unique test tag (e.g. `test:verify-<date>`) and distinct `document_id`s, `async: true` (avoids sync-endpoint contention), then poll the operation (check `child_operations` status, not just parent) until `completed`:
1. **Fact extraction**: `GET .../memories/list?document_id=<id>` — compare extracted `text` against the raw input. Confirms real extraction if irrelevant content was dropped and facts were rewritten as clean standalone statements (not verbatim-copied).
2. **Entity resolution**: `GET .../entities?limit=200`, grep for a distinctive fake entity name used across multiple test facts — one canonical entity with `mention_count` > 1 proves cross-document dedup, not just per-call NER.
3. **Graph links**: `GET .../graph?tags=<test tag>&limit=50` — inspect `edges[].data.linkType`/`weight`. Real `temporal`/`semantic` edges with confidence weights (not just 1.0 self-loops) prove relationship-building, not flat storage. `caused_by` edges may require a full consolidation pass to appear even though they exist at bank-scale (verified 224 instances in this bank overall) — small immediate test batches may only show `semantic`/`temporal`/`entity`.
4. **Reflect depends on consolidation, not raw memory**: `reflect()` answers from the CONSOLIDATED mental-model layer, not directly from just-retained raw facts. A `reflect()` query about facts retained seconds ago will correctly say "not found" if those facts haven't been consolidated yet (`consolidated_at: null` on the memory) — this is correct behavior, not a bug, and is useful evidence that reflect() reasons over curated knowledge rather than doing raw keyword lookup (it should give a coherent "I don't know, but here's what I do know that's related" answer, not hallucinate).
5. **Cleanup:** there is no tag-based bulk delete. Soft-retire test memories individually via `PATCH /v1/default/banks/{bank}/memories/{memory_id}` with body `{"state": "invalidated", "reason": "<why>"}` — note the exact field names: `state` value is `"invalidated"` (NOT `"invalid"`), and the field is `reason` (NOT `invalidation_reason` — that's a read-only response field). This is reversible (`state: "valid"` to undo) and is the correct way to retire any bad/test/wrong memory in general, not just test cleanup — prefer it over trying to hard-delete (no per-memory hard-delete endpoint exists; only bulk-by-type `DELETE .../memories?type=`, which is too broad for surgical removal).

## Report format
Split findings into "working" vs "drift/risk" vs "architecture gap". One-line fix per drift item, prioritized by blast radius. For an evaluation-only request, report and wait for the user to prioritize. When the user challenges a diagnosis, re-verify empirically before defending it.
