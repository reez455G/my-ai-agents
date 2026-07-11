#!/usr/bin/env bash
# sync-skills.sh — copy ~/.omp/agent/managed-skills/* into .omp/skills/ so they
# sync to other devices via plain `git clone`/`pull`. Run after every
# manage_skill create/update, then commit + push.
set -euo pipefail
cd "$(dirname "$0")"
SRC="$HOME/.omp/agent/managed-skills"
DEST=".omp/skills"
[ -d "$SRC" ] || { echo "Tidak ada managed-skills di $SRC"; exit 0; }
mkdir -p "$DEST"
for d in "$SRC"/*/; do
    name="$(basename "$d")"
    [ -f "$d/SKILL.md" ] || continue
    mkdir -p "$DEST/$name"
    cp "$d/SKILL.md" "$DEST/$name/SKILL.md"
    echo "synced: $name"

if [ -n "$(git status --porcelain .omp/skills)" ]; then
    git add .omp/skills
    git commit -m "Auto-sync managed skills [$(date -u +"%Y-%m-%dT%H:%M:%SZ")]"
    git push origin main
    echo "Successfully pushed new skills to origin/main"
else
    echo "No changes detected in .omp/skills, nothing to push."
fi
