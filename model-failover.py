#!/usr/bin/env python3
"""model-failover — jaga LLM provider Hindsight tetap hidup.

Probe model utama di .env (HINDSIGHT_API_LLM_*). Jika mati (429 / timeout /
5xx / connection error), cari kandidat sehat via `hermes-model-check --json`
(gateway Hermes lokal), tulis ulang .env, dan restart container hindsight.

Pemakaian:
  ./model-failover.py                    # probe utama; failover otomatis jika mati
  ./model-failover.py --check-only       # hanya lapor status, tanpa mengubah apapun
  ./model-failover.py --force            # paksa failover walau utama sehat
  ./model-failover.py --prefer nvidia/ --prefer gemini   # urutan preferensi kandidat
  ./model-failover.py --filter nvidia/   # batasi hermes-model-check ke satu provider
  ./model-failover.py --no-restart       # tulis .env saja, restart manual
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request

REPO = os.path.dirname(os.path.abspath(__file__))
ENV_PATH = os.path.join(REPO, ".env")
HERMES_CONFIG = os.path.expanduser("~/.hermes/config.yaml")
HEALTH_URL = "http://localhost:8890/health"
# Dari dalam container, gateway lokal terlihat sebagai host.docker.internal
# (docker-compose.yml sudah punya extra_hosts: host-gateway).
CONTAINER_HOST = "host.docker.internal"

ENV_KEYS = ("HINDSIGHT_API_LLM_PROVIDER", "HINDSIGHT_API_LLM_API_KEY",
            "HINDSIGHT_API_LLM_BASE_URL", "HINDSIGHT_API_LLM_MODEL")


def read_env() -> dict:
    vals = {}
    with open(ENV_PATH) as f:
        for line in f:
            m = re.match(r"^([A-Z0-9_]+)=(.*)$", line.strip())
            if m and m.group(1) in ENV_KEYS:
                vals[m.group(1)] = m.group(2)
    missing = [k for k in ENV_KEYS if k not in vals]
    if missing:
        sys.exit(f"error: {ENV_PATH} tidak punya: {', '.join(missing)}")
    return vals


def write_env(updates: dict) -> str:
    backup = f"{ENV_PATH}.bak.{time.strftime('%Y%m%d-%H%M%S')}"
    shutil.copy2(ENV_PATH, backup)
    with open(ENV_PATH) as f:
        lines = f.readlines()
    for i, line in enumerate(lines):
        m = re.match(r"^([A-Z0-9_]+)=", line.strip())
        if m and m.group(1) in updates:
            lines[i] = f"{m.group(1)}={updates[m.group(1)]}\n"
    with open(ENV_PATH, "w") as f:
        f.writelines(lines)
    return backup


def probe_chat(base_url: str, api_key: str, model: str, timeout: float):
    """Return (ok: bool, note: str).

    Payload meniru fact extraction Hindsight (response_format JSON +
    max_tokens besar) — probe "ping" polos bisa lolos di model yang
    ternyata 422 saat dipakai Hindsight (kasus gemma-2-2b-it di NVIDIA:
    response_format extra_forbidden, max_tokens le=4096).
    """
    req = urllib.request.Request(
        f"{base_url.rstrip('/')}/chat/completions",
        data=json.dumps({
            "model": model,
            "messages": [{"role": "user",
                          "content": 'Balas JSON: {"ok": true}'}],
            "max_tokens": 8192,
            "response_format": {"type": "json_object"},
        }).encode(),
        headers={"Authorization": f"Bearer {api_key}",
                 "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            json.load(r)
        return True, "200 OK"
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read().decode(errors="replace")[:120]
        except OSError:
            pass
        return False, f"HTTP {e.code}: {body}"
    except TimeoutError:
        return False, f"timeout {timeout}s"
    except (urllib.error.URLError, OSError) as e:
        return False, f"{e.__class__.__name__}: {e}"


def gateway_credentials():
    """base_url + api_key gateway Hermes lokal dari ~/.hermes/config.yaml."""
    with open(HERMES_CONFIG) as f:
        text = f.read()
    entries = re.findall(r"base_url:\s*(\S+)\s*\n\s*api_key:\s*(\S+)", text)
    local = [(b, k) for b, k in entries if "localhost" in b or "127.0.0.1" in b]
    if not local:
        sys.exit(f"error: tidak ada provider localhost di {HERMES_CONFIG}")
    return local[0]


def healthy_candidates(filter_str: str, timeout: float) -> list[dict]:
    cmd = ["hermes-model-check", "--json", "--timeout", str(timeout)]
    if filter_str:
        cmd += ["--filter", filter_str]
    out = subprocess.run(cmd, capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"error: hermes-model-check gagal: {out.stderr.strip()[:300]}")
    report = json.loads(out.stdout)
    return [r for r in report["results"]
            if r["status"] == "OK" and r["kind"] == "chat"]


def rank(candidates: list[dict], prefer: list[str]) -> list[dict]:
    def key(r):
        for i, p in enumerate(prefer):
            if p in r["model"]:
                return (i, r["latency_s"])
        return (len(prefer), r["latency_s"])
    return sorted(candidates, key=key)


def restart_and_wait(max_wait: float) -> bool:
    subprocess.run(["docker", "compose", "up", "-d", "--force-recreate"],
                   cwd=REPO, check=True)
    print(f"Menunggu health (maks {max_wait:.0f}s — boot bisa lambat "
          "karena recovery pg0)...")
    deadline = time.monotonic() + max_wait
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(HEALTH_URL, timeout=5) as r:
                body = json.load(r)
            if body.get("status") == "healthy":
                return True
        except (urllib.error.URLError, OSError, ValueError):
            pass
        time.sleep(10)
    return False


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check-only", action="store_true",
                    help="hanya lapor status model utama")
    ap.add_argument("--force", action="store_true",
                    help="failover walau model utama sehat")
    ap.add_argument("--prefer", action="append", default=[],
                    help="substring model yang diprioritaskan (bisa berulang)")
    ap.add_argument("--filter", default="",
                    help="diteruskan ke hermes-model-check --filter")
    ap.add_argument("--no-restart", action="store_true",
                    help="tulis .env saja, jangan restart container")
    ap.add_argument("--timeout", type=float, default=20,
                    help="timeout probe per request (s)")
    ap.add_argument("--health-wait", type=float, default=900,
                    help="maks tunggu health setelah restart (s)")
    args = ap.parse_args()

    env = read_env()
    ok, note = probe_chat(env["HINDSIGHT_API_LLM_BASE_URL"],
                          env["HINDSIGHT_API_LLM_API_KEY"],
                          env["HINDSIGHT_API_LLM_MODEL"], args.timeout)
    print(f"Utama : {env['HINDSIGHT_API_LLM_MODEL']} @ "
          f"{env['HINDSIGHT_API_LLM_BASE_URL']} -> "
          f"{'SEHAT' if ok else 'MATI'} ({note})")

    if args.check_only:
        sys.exit(0 if ok else 1)
    if ok and not args.force:
        return

    print("Mencari kandidat sehat via hermes-model-check...")
    candidates = rank(healthy_candidates(args.filter, args.timeout), args.prefer)
    if not candidates:
        sys.exit("error: tidak ada model chat OK di gateway — tidak ada fallback.")

    gw_base, gw_key = gateway_credentials()
    # Verifikasi ketat: hermes-model-check probe pakai "ping" polos;
    # kandidat harus lolos payload gaya Hindsight juga.
    chosen = None
    for cand in candidates[:10]:
        c_ok, c_note = probe_chat(gw_base, gw_key, cand["model"], args.timeout)
        print(f"  kandidat {cand['model']}: {'lolos' if c_ok else f'gagal ({c_note})'}")
        if c_ok:
            chosen = cand
            break
    if chosen is None:
        sys.exit("error: tidak ada kandidat yang lolos payload gaya Hindsight "
                 "(response_format + max_tokens 8192).")
    # localhost host -> host.docker.internal untuk container
    container_base = re.sub(r"//(localhost|127\.0\.0\.1)", f"//{CONTAINER_HOST}",
                            gw_base)
    print(f"Pilih : {chosen['model']} ({chosen['latency_s']}s) via {container_base}")

    backup = write_env({
        "HINDSIGHT_API_LLM_PROVIDER": "openai",
        "HINDSIGHT_API_LLM_BASE_URL": container_base,
        "HINDSIGHT_API_LLM_API_KEY": gw_key,
        "HINDSIGHT_API_LLM_MODEL": chosen["model"],
    })
    print(f".env ditulis (backup: {os.path.basename(backup)})")

    if args.no_restart:
        print("Lewati restart. Jalankan manual: docker compose up -d --force-recreate")
        return
    if restart_and_wait(args.health_wait):
        print("Hindsight healthy dengan model fallback.")
    else:
        sys.exit(f"error: health belum muncul setelah {args.health_wait:.0f}s — "
                 f"cek `docker logs hindsight`. Rollback: cp {backup} {ENV_PATH}")


if __name__ == "__main__":
    main()
