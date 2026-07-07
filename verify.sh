#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "=== 1. Docker Container Status ==="
docker compose ps
echo

echo "=== 2. Health Check ==="
curl -sf http://localhost:8888/health && echo " ✅ Hindsight healthy" || echo " ❌ Hindsight not responding"
echo

echo "=== 3. Knowledge OKF Validation ==="
.venv/bin/python -c "
import sys; sys.path.insert(0, 'src')
from knowledge_okf import load_all
docs = load_all()
ok = all(d['id'] and d['title'] for d in docs)
print(f'  {len(docs)} docs, all valid: {ok}')
for d in docs:
    print(f'    - {d[\"id\"]}: {d[\"title\"]} tags={d[\"tags\"]}')
"
echo

echo "=== 4. .env NOT tracked by git ==="
if git rev-parse --git-dir > /dev/null 2>&1; then
    git status --porcelain .env 2>/dev/null | grep -q '.env' && echo "  ⚠️  .env visible to git" || echo "  ✅ .env not tracked"
else
    echo "  (no git repo yet — skip)"
fi
echo

echo "=== 5. End-to-End Test ==="
cd src && ../.venv/bin/python agent.py && echo "  ✅ agent.py ran OK" || echo "  ❌ agent.py failed"
echo

echo "=== 6. Control Plane UI ==="
echo "  Open http://localhost:9999 in browser to check bank 'budi'"
echo
echo "=== Done ==="
