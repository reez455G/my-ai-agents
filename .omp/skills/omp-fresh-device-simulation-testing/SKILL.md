---
name: omp-fresh-device-simulation-testing
description: "Simulate a brand-new device for testing omp (Oh My Pi) onboarding scripts, skill discovery, or Hindsight memory persistence, using an isolated HOME directory instead of touching the real device state. Use when verifying a setup-new-device.sh-style script, testing whether skills/config survive a fresh clone, or proving cross-device memory persistence end-to-end."
---

## Setup

```bash
mkdir -p /tmp/fake-home/.omp/agent
# Pre-seed credentials so interactive `read -rp`/`read -rsp` prompts in the
# setup script are skipped (matches the script's own "already exists, skip"
# branches) instead of hanging on stdin in a non-interactive bash tool call:
cat > /tmp/fake-home/.omp/agent/.env <<'EOF'
export HINDSIGHT_API_TOKEN="..."
export HINDSIGHT_API_URL="..."
export HINDSIGHT_BANK_ID="..."
EOF
chmod 600 /tmp/fake-home/.omp/agent/.env

# Clone into a directory whose BASENAME matches what the setup script expects
# (e.g. REPO_DIR_NAME) -- a mismatched folder name trips an interactive
# confirmation prompt ("lanjutkan di folder ini? [y/N]") that hangs
# non-interactively and exits 1.
git clone <repo-url> /tmp/fake-parent/<expected-dir-name>
cd /tmp/fake-parent/<expected-dir-name>
HOME=/tmp/fake-home PATH="$(dirname "$(command -v omp)"):$PATH" bash setup-new-device.sh
```

## Running omp headless afterward (auth gotcha)

A fresh isolated HOME has no LLM auth -> `omp -p` fails with "No models available. Use /login or set an API key environment variable." Copying `~/.omp/agent/agent.db`/`models.db` from the real HOME does NOT reliably work (WAL/lock files, `-shm`/`-wal` companions not copied, DB corruption risk). Instead, extract a live token from the real session and inject it as an env var -- no DB copying needed:

```bash
ANTHROPIC_OAUTH_TOKEN="$(omp token anthropic 2>/dev/null)"
HOME=/tmp/fake-home PATH="..." ANTHROPIC_OAUTH_TOKEN="$ANTHROPIC_OAUTH_TOKEN" \
  omp -p --cwd /tmp/fake-parent/<dir> "..."
```

`omp --help` lists other useful diagnostic subcommands under `token`/`usage`/`auth-broker` for this kind of testing.

## Verifying skill discovery without polluting the prompt

Ask the model directly (it already has the discovered list in its system prompt): `"List every skill name currently discovered in this session's skill catalog (do not use any tools, just answer from what's already in your system prompt). Just the names, one per line, nothing else."`

- Do NOT pass `--no-tools`: the skill list is only injected into the system prompt "if the `read` tool is available" (see skill discovery docs) -- with `--no-tools` the list is silently omitted and every check will show 0 skills, which looks like a failure but is actually a self-inflicted test artifact.
- Cross-check with `sort | uniq -d` for real duplicates, and `grep -c` against your expected name list for completeness.

## Verifying cross-process memory persistence (e.g. Hindsight)

1. In one `omp -p --no-session` call, ask the model to `retain` a freshly-generated unique marker string (e.g. `MARKER-$(date +%s)-$(head -c4 /dev/urandom | xxd -p)`).
2. In a SEPARATE `omp -p --no-session` invocation (new process, same isolated HOME), ask it to `recall` and quote the marker back verbatim.
3. `--no-session` on both ends is important -- it rules out local session-file replay as an explanation for a successful recall, isolating the test to the actual remote memory backend.
4. Long-running LLM/memory calls under host load may need `async: true` + a generous `timeout` (60-180s) rather than a synchronous call; a 90s synchronous call timing out is not necessarily a real failure, retry as background before concluding it broke.

## Critical gotcha: git checkout resets mtimes

Never use `[ -nt ]` / `stat` mtime comparisons to decide "is the repo copy or the local copy newer" in a script meant to run after `git clone`/`pull`. Git sets file mtimes to checkout time, not the original commit's author/commit time -- a file committed weeks ago will always look newer than a local file from yesterday immediately after a fresh clone. Verify with:

```bash
git clone --depth 1 . /tmp/mtime-check && stat -c '%Y %n' /tmp/mtime-check/<file> <local-file>
```

Use content-hash/`cmp -s` comparisons instead, and when direction can't be inferred safely, default to "never overwrite, just report the divergence" rather than guessing.

## Design gotcha: don't blanket-copy repo-scoped content into a global store

When building a "repo -> global local store" import direction (e.g. populating `~/.omp/agent/managed-skills/` from a project's `.omp/skills/`), do NOT copy everything indiscriminately. Distinguish genuinely general-purpose entries from project/domain-specific ones with an explicit provenance manifest (a plain list file written by the export-direction script, naming only what actually originated from the global-scoped source) and scope the import to that manifest. Otherwise the global store gets polluted with project-specific skill descriptions that leak into every unrelated session on the device -- caught and fixed live in this exact scenario (first attempt wrongly imported 34 repo-specific skills into the global managed-skills store; fixed by scoping to a 7-name manifest).
