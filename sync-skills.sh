#!/usr/bin/env bash
# sync-skills.sh — full .omp/skills/ sync + commit (program.md §9/§11/§12):
#   1. ~/.omp/agent/managed-skills/* -> .omp/skills/  (manage_skill output)
#   2. knowledge/{skills,agent-rules}/*.md -> .omp/skills/ for embedded-class
#      sources only (sync-okf-skills.py; bare-class sources are never touched)
#   3. knowledge/**/*.md -> Hindsight bank (ingest-okf-to-hindsight.py), so
#      recall()/reflect() surface OKF content, not just the native skill
#      provider (program.md §12); best-effort, never blocks the git push.
# Run after every manage_skill create/update, or after editing knowledge/.
set -euo pipefail
cd "$(dirname "$0")"
SRC="$HOME/.omp/agent/managed-skills"
DEST=".omp/skills"
[ -d "$SRC" ] || { echo "Tidak ada managed-skills di $SRC"; exit 0; }
mkdir -p "$DEST"
MANIFEST="$DEST/.managed-skill-names"
: > "$MANIFEST.tmp"
for d in "$SRC"/*/; do
    name="$(basename "$d")"
    [ -f "$d/SKILL.md" ] || continue
    mkdir -p "$DEST/$name"
    cp "$d/SKILL.md" "$DEST/$name/SKILL.md"
    echo "$name" >> "$MANIFEST.tmp"
    echo "synced: $name"
done
sort -u "$MANIFEST.tmp" > "$MANIFEST" && rm -f "$MANIFEST.tmp"

echo "--- knowledge/ -> .omp/skills/ (embedded-class only) ---"
python3 sync-okf-skills.py

echo "--- knowledge/ -> Hindsight (recall/reflect visibility, program.md §12) ---"
.venv/bin/python ingest-okf-to-hindsight.py || echo "WARN: OKF->Hindsight ingestion gagal (Hindsight down?), lanjut tanpa ini"

if [ -n "$(git status --porcelain .omp/skills)" ]; then
    git add .omp/skills
    git commit -m "Auto-sync managed skills [$(date -u +"%Y-%m-%dT%H:%M:%SZ")]"
    git push origin main
    echo "Successfully pushed new skills to origin/main"
else
    echo "No changes detected in .omp/skills, nothing to push."
fi
