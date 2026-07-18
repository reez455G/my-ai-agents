#!/usr/bin/env bash
# ============================================================
# usage-monitor.sh — Parse omp usage dan output structured data
# Usage: ./usage-monitor.sh [--json] [--watch N]
# ============================================================
set -euo pipefail

OMP_BIN="${OMP_BIN:-/home/efsatu/.bun/bin/omp}"
THRESHOLD_WARN=70   # % warn
THRESHOLD_STOP=85   # % hard pause
THRESHOLD_CRIT=95   # % critical

parse_usage() {
  local raw
  raw=$("$OMP_BIN" usage 2>/dev/null) || { echo '{"error":"omp usage failed"}'; return; }

  python3 - "$raw" <<'PYEOF'
import sys, re, json

text = sys.argv[1]
result = {"providers": {}, "alerts": []}

# ---- Anthropic ----
anthr = {"accounts": []}
for block in re.finditer(
    r'●\s+([\w.@\-]+).*?\n((?:\s+[●○].*\n)*)',
    text
):
    acc_email = block.group(1)
    lines = block.group(2)
    limits = {}
    for line in lines.splitlines():
        m = re.search(r'[●○]\s+(.+?)\s+[█░·]+\s+([\d.]+)%\s+used', line)
        if m:
            name = m.group(1).strip()
            pct  = float(m.group(2))
            reset_m = re.search(r'resets in\s+([\dhm ]+)', line)
            reset = reset_m.group(1).strip() if reset_m else "unknown"
            limits[name] = {"used_pct": pct, "resets_in": reset}
    if lines.strip():
        anthr["accounts"].append({"email": acc_email, "limits": limits})

result["providers"]["anthropic"] = anthr

# ---- Google Antigravity ----
# Find section after "Google Antigravity"
ag_section = text[text.find("Google Antigravity"):]
ag = {"accounts": []}
for block in re.finditer(
    r'●\s+([\w.@\-]+).*?\n((?:\s+[●○].*\n)*)',
    ag_section
):
    acc_email = block.group(1)
    lines = block.group(2)
    limits = {}
    for line in lines.splitlines():
        m = re.search(r'[●○]\s+(.+?)\s+[█░·]+\s+([\d.]+)%\s+used', line)
        if m:
            name = m.group(1).strip()
            pct  = float(m.group(2))
            reset_m = re.search(r'resets in\s+([\dhm ]+)', line)
            reset = reset_m.group(1).strip() if reset_m else "unknown"
            limits[name] = {"used_pct": pct, "resets_in": reset}
    if lines.strip():
        ag["accounts"].append({"email": acc_email, "limits": limits})

result["providers"]["google-antigravity"] = ag

# ---- Build alerts ----
WARN  = float(sys.argv[2]) if len(sys.argv) > 2 else 70
STOP  = float(sys.argv[3]) if len(sys.argv) > 3 else 85
CRIT  = float(sys.argv[4]) if len(sys.argv) > 4 else 95

for pname, pdata in result["providers"].items():
    for acc in pdata.get("accounts", []):
        for lname, ldata in acc.get("limits", {}).items():
            pct = ldata["used_pct"]
            level = None
            if pct >= CRIT:
                level = "CRITICAL"
            elif pct >= STOP:
                level = "STOP"
            elif pct >= WARN:
                level = "WARN"
            if level:
                result["alerts"].append({
                    "level": level,
                    "provider": pname,
                    "account": acc["email"],
                    "limit": lname,
                    "used_pct": pct,
                    "resets_in": ldata["resets_in"]
                })

print(json.dumps(result, indent=2))
PYEOF
}

recommend_provider() {
  local json_data="$1"
  # Returns best available provider/model combo
  python3 - "$json_data" <<'PYEOF'
import sys, json

data = json.loads(sys.argv[1])
STOP = 85.0

providers_ok = []

# Check Anthropic
for acc in data["providers"].get("anthropic", {}).get("accounts", []):
    for lname, ldata in acc.get("limits", {}).items():
        if ldata["used_pct"] < STOP:
            providers_ok.append({
                "model": "anthropic/claude-sonnet-4-6",
                "account": acc["email"],
                "limit": lname,
                "used_pct": ldata["used_pct"],
                "resets_in": ldata["resets_in"]
            })
            break

# Check Antigravity
for acc in data["providers"].get("google-antigravity", {}).get("accounts", []):
    blocked = False
    for lname, ldata in acc.get("limits", {}).items():
        if "Weekly" in lname and "Google" in lname and ldata["used_pct"] >= 100:
            blocked = True
    if not blocked:
        for lname, ldata in acc.get("limits", {}).items():
            if ldata["used_pct"] < STOP:
                providers_ok.append({
                    "model": "google-antigravity/gemini-2.5-flash",
                    "account": acc["email"],
                    "limit": lname,
                    "used_pct": ldata["used_pct"],
                    "resets_in": ldata["resets_in"]
                })
                break

if providers_ok:
    # Sort by lowest usage
    providers_ok.sort(key=lambda x: x["used_pct"])
    best = providers_ok[0]
    print(f"{best['model']}")
else:
    print("NONE")
PYEOF
}

# ---- Main ----
JSON_MODE=0
WATCH_INTERVAL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_MODE=1 ;;
    --watch) WATCH_INTERVAL="${2:-60}"; shift ;;
  esac
  shift
done

run_once() {
  local data
  data=$(parse_usage "$THRESHOLD_WARN" "$THRESHOLD_STOP" "$THRESHOLD_CRIT")

  if [[ "$JSON_MODE" -eq 1 ]]; then
    echo "$data"
    return
  fi

  # Human-readable summary
  echo "╔══════════════════════════════════════════════════════╗"
  echo "║         PROVIDER USAGE MONITOR · $(date '+%H:%M:%S %d/%m/%Y')     ║"
  echo "╠══════════════════════════════════════════════════════╣"

  python3 - "$data" <<'PYEOF'
import sys, json
data = json.loads(sys.argv[1])

ICONS = {"CRITICAL":"🔴","STOP":"🟠","WARN":"🟡"}
bars  = lambda p: "█"*int(p/4) + "░"*(25-int(p/4))

for pname, pdata in data["providers"].items():
  print(f"\n  ┌─ {pname.upper()}")
  for acc in pdata.get("accounts", []):
    print(f"  │  ● {acc['email']}")
    for lname, ld in acc.get("limits", {}).items():
      pct = ld["used_pct"]
      lvl = "🔴" if pct>=95 else "🟠" if pct>=85 else "🟡" if pct>=70 else "🟢"
      bar = "█"*int(pct/4) + "░"*(25-int(pct/4))
      rst = ld.get("resets_in","?")
      print(f"  │    {lvl} {lname:<35} {bar} {pct:5.1f}%  ↺ {rst}")

if data["alerts"]:
  print("\n  ⚠️  ALERTS:")
  for a in data["alerts"]:
    print(f"     [{a['level']}] {a['provider']} / {a['account']} / {a['limit']} → {a['used_pct']}% (resets: {a['resets_in']})")
else:
  print("\n  ✅ No alerts")

best = None
STOP = 85.0
for pname, pdata in data["providers"].items():
    for acc in pdata.get("accounts", []):
        blocked = any(
            "Weekly" in k and "Google" in k and v["used_pct"] >= 100
            for k, v in acc.get("limits", {}).items()
        )
        if not blocked:
            for lname, ld in acc.get("limits", {}).items():
                if ld["used_pct"] < STOP:
                    model = "google-antigravity/gemini-2.5-flash" if "antigravity" in pname else "anthropic/claude-sonnet-4-6"
                    if best is None or ld["used_pct"] < best[1]:
                        best = (model, ld["used_pct"])
                    break

if best:
    print(f"\n  🎯 RECOMMENDED PROVIDER: {best[0]}  ({best[1]:.0f}% used)")
else:
    print("\n  🚫 NO PROVIDER AVAILABLE — all limits exhausted")
PYEOF

  echo ""
  echo "╚══════════════════════════════════════════════════════╝"
}

if [[ "$WATCH_INTERVAL" -gt 0 ]]; then
  while true; do
    clear
    run_once
    echo ""
    echo "  Refreshing in ${WATCH_INTERVAL}s... (Ctrl+C to stop)"
    sleep "$WATCH_INTERVAL"
  done
else
  run_once
fi
