#!/usr/bin/env bash
#
# setup-new-device.sh
# Otomatisasi onboarding device baru untuk my-ai-agent (OKF + Hindsight + omp).
# Jalankan dari dalam folder repo yang sudah di-clone, atau beri URL repo sebagai argumen.
#
# Usage:
#   ./setup-new-device.sh                              # jika sudah di dalam folder repo
#   ./setup-new-device.sh git@github.com:user/my-ai-agent.git   # clone dulu, lalu setup
#
set -euo pipefail

REPO_DIR_NAME="my-ai-agents"    # WAJIB konsisten di semua device
OMP_CONFIG_DIR="$HOME/.omp/agent"
OMP_CONFIG_FILE="$OMP_CONFIG_DIR/config.yml"
TOKEN_ENV_FILE="$HOME/.omp/agent/.env"   # tidak pernah di-commit ke git

log()  { printf "\033[1;36m[setup]\033[0m %s\n" "$1"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$1"; }
err()  { printf "\033[1;31m[error]\033[0m %s\n" "$1" >&2; }

# ── 1. Clone repo jika diberi URL, atau pastikan sudah berada di folder yang benar ──
if [ "$#" -eq 1 ]; then
    REPO_URL="$1"
    TARGET="$HOME/$REPO_DIR_NAME"
    if [ -d "$TARGET" ]; then
        warn "Folder $TARGET sudah ada, skip clone."
    else
        log "Cloning $REPO_URL ke $TARGET (nama folder dipin agar konsisten lintas device)..."
        git clone "$REPO_URL" "$TARGET"
    fi
    cd "$TARGET"
else
    CURRENT_DIR_NAME="$(basename "$PWD")"
    if [ "$CURRENT_DIR_NAME" != "$REPO_DIR_NAME" ]; then
        warn "Nama folder saat ini ('$CURRENT_DIR_NAME') beda dari '$REPO_DIR_NAME'."
        warn "Ini bisa bikin memori Hindsight ter-fragmentasi (scoping per-project-tagged pakai nama folder)."
        read -rp "Lanjutkan tetap di folder ini? [y/N] " ans
        [[ "$ans" =~ ^[Yy]$ ]] || { err "Dibatalkan. Rename/clone ulang ke folder '$REPO_DIR_NAME'."; exit 1; }
    fi
fi

if [ ! -f "omp-config.template.yml" ]; then
    err "omp-config.template.yml tidak ditemukan di $(pwd). Jalankan script ini dari root repo."
    exit 1
fi

# ── 2. Cek dependency dasar ──
for cmd in git curl omp; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        warn "'$cmd' belum terinstall di PATH. Pastikan terpasang sebelum lanjut memakai omp."
    fi
done

if command -v tailscale >/dev/null 2>&1; then
    if ! tailscale status >/dev/null 2>&1; then
        warn "Tailscale terpasang tapi belum aktif. Jalankan: sudo tailscale up"
    fi
else
    warn "Tailscale belum terinstall. apiUrl di config perlu bisa dijangkau lewat cara lain."
fi

# ── 3. Minta token Hindsight secara aman (tidak pernah masuk git) ──
mkdir -p "$OMP_CONFIG_DIR"
if [ -f "$TOKEN_ENV_FILE" ] && grep -q "HINDSIGHT_API_TOKEN=" "$TOKEN_ENV_FILE"; then
    log "HINDSIGHT_API_TOKEN sudah ada di $TOKEN_ENV_FILE, skip input."
else
    read -rsp "Masukkan HINDSIGHT_API_TOKEN (dari password manager): " HINDSIGHT_API_TOKEN
    echo
    [ -n "$HINDSIGHT_API_TOKEN" ] || { err "Token kosong, dibatalkan."; exit 1; }
    echo "export HINDSIGHT_API_TOKEN=\"$HINDSIGHT_API_TOKEN\"" >> "$TOKEN_ENV_FILE"
    chmod 600 "$TOKEN_ENV_FILE"
    log "Token disimpan di $TOKEN_ENV_FILE (chmod 600, tidak di-commit)."
fi

# shellcheck disable=SC1090
source "$TOKEN_ENV_FILE"

if grep -q "HINDSIGHT_API_URL=" "$TOKEN_ENV_FILE"; then
    log "HINDSIGHT_API_URL sudah ada di $TOKEN_ENV_FILE, skip input."
else
    read -rp "Masukkan HINDSIGHT_API_URL [https://hindsight.efsatu.my.id]: " HINDSIGHT_API_URL
    HINDSIGHT_API_URL="${HINDSIGHT_API_URL:-https://hindsight.efsatu.my.id}"
    echo "export HINDSIGHT_API_URL=\"$HINDSIGHT_API_URL\"" >> "$TOKEN_ENV_FILE"
fi
# shellcheck disable=SC1090
source "$TOKEN_ENV_FILE"
export HINDSIGHT_API_URL HINDSIGHT_API_TOKEN

# ── 3b. Pilih bank memori omp: lanjut bank existing atau fresh ──
if grep -q "HINDSIGHT_BANK_ID=" "$TOKEN_ENV_FILE"; then
    log "HINDSIGHT_BANK_ID sudah ada di $TOKEN_ENV_FILE, skip input."
else
    log "Mengambil daftar bank dari $HINDSIGHT_API_URL ..."
    BANKS_JSON="$(curl -fsS -H "Authorization: Bearer $HINDSIGHT_API_TOKEN" "$HINDSIGHT_API_URL/v1/default/banks" 2>/dev/null || true)"
    if [ -n "$BANKS_JSON" ]; then
        echo "Bank existing di server (pilih salah satu untuk LANJUT memori lama):"
        printf '%s' "$BANKS_JSON" | python3 -c '
import json, sys
for b in json.load(sys.stdin).get("banks", []):
    print("  - %s (%s facts, terakhir %s)" % (b["bank_id"], b.get("fact_count", 0), (b.get("updated_at") or "?")[:10]))
' || printf '%s\n' "$BANKS_JSON"
    else
        warn "Tidak bisa ambil daftar bank dari server — ketik manual."
    fi
    read -rp "Bank ID omp (nama existing = LANJUT, nama baru = FRESH; bank dibuat otomatis saat write pertama) [my-ai-agent]: " HINDSIGHT_BANK_ID
    HINDSIGHT_BANK_ID="${HINDSIGHT_BANK_ID:-my-ai-agent}"
    echo "export HINDSIGHT_BANK_ID=\"$HINDSIGHT_BANK_ID\"" >> "$TOKEN_ENV_FILE"
fi
# shellcheck disable=SC1090
source "$TOKEN_ENV_FILE"
export HINDSIGHT_BANK_ID

# ── 4. Terapkan config template ──
log "Menerapkan omp-config.template.yml -> $OMP_CONFIG_FILE"
RENDERED="$(envsubst < omp-config.template.yml)"
if [ ! -f "$OMP_CONFIG_FILE" ]; then
    printf '%s\n' "$RENDERED" > "$OMP_CONFIG_FILE"
elif ! grep -q '^hindsight:' "$OMP_CONFIG_FILE"; then
    printf '\n%s\n' "$RENDERED" >> "$OMP_CONFIG_FILE"
else
    warn "config.yml sudah punya blok 'hindsight:' — tidak diubah. Config hasil render:"
    printf '%s\n' "$RENDERED"
fi

if [ ! -d .venv ]; then
    log "Membuat venv + install dependencies..."
    python3 -m venv .venv 2>/dev/null || {
        python3 -m venv --without-pip .venv
        curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py
        .venv/bin/python /tmp/get-pip.py -q
    }
    .venv/bin/pip install -q -r requirements.txt
fi
if [ ! -f .env ]; then
    log "Membuat .env dari .env.example..."
    cp .env.example .env
    sed -i "s|^HINDSIGHT_API_URL=.*|HINDSIGHT_API_URL=$HINDSIGHT_API_URL|; s|^HINDSIGHT_API_TOKEN=.*|HINDSIGHT_API_TOKEN=$HINDSIGHT_API_TOKEN|" .env
fi

# ── 4b. Pasang git hooks + import skill ke managed-skills lokal (aman diulang) ──
log "Memasang git hooks (core.hooksPath -> githooks/) agar 'git pull' otomatis meng-import skill baru..."
git config core.hooksPath githooks
chmod +x githooks/post-merge githooks/post-checkout import-learned-skills.sh sync-skills.sh sync-okf-skills.py 2>/dev/null || true
log "Import awal skill repo -> ~/.omp/agent/managed-skills (skill lokal yang sudah ada tidak akan ditimpa)..."
./import-learned-skills.sh

# ── 5. Auto-load token env di shell rc (opsional, sekali saja) ──
SHELL_RC="$HOME/.bashrc"
[ -n "${ZSH_VERSION:-}" ] && SHELL_RC="$HOME/.zshrc"
SOURCE_LINE="[ -f \"$TOKEN_ENV_FILE\" ] && source \"$TOKEN_ENV_FILE\""
if ! grep -qF "$TOKEN_ENV_FILE" "$SHELL_RC" 2>/dev/null; then
    echo "$SOURCE_LINE" >> "$SHELL_RC"
    log "Menambahkan auto-load token ke $SHELL_RC"
fi

# ── 5b. Alias 'omp' + 'omp-sync' (skill sync via Syncthing, bukan git — program.md §13) ──
OMP_BIN="$(type -P omp || echo "$HOME/.bun/bin/omp")"
ALIAS_OMP="alias omp=\"$OMP_BIN\""
if grep -qF "alias omp=" "$SHELL_RC" 2>/dev/null; then
    if grep -qF "$ALIAS_OMP" "$SHELL_RC" 2>/dev/null; then
        log "Alias 'omp' sudah terpasang dan up-to-date di $SHELL_RC"
    else
        log "Mendeteksi versi alias 'omp' lama/berbeda (mis. auto git-pull/sync-skills) di $SHELL_RC. Memperbarui..."
        grep -v "alias omp=" "$SHELL_RC" > "$SHELL_RC.tmp" || true
        mv "$SHELL_RC.tmp" "$SHELL_RC"
        echo "$ALIAS_OMP" >> "$SHELL_RC"
        log "Alias 'omp' berhasil diperbarui di $SHELL_RC"
    fi
else
    echo "$ALIAS_OMP" >> "$SHELL_RC"
    log "Menambahkan alias 'omp' ke $SHELL_RC"
fi

ALIAS_SYNC="alias omp-sync=\"cd $PWD && git pull origin main && git push origin main\""
if grep -qF "alias omp-sync=" "$SHELL_RC" 2>/dev/null; then
    if grep -qF "$ALIAS_SYNC" "$SHELL_RC" 2>/dev/null; then
        log "Alias 'omp-sync' sudah terpasang dan up-to-date di $SHELL_RC"
    else
        grep -v "alias omp-sync=" "$SHELL_RC" > "$SHELL_RC.tmp" || true
        mv "$SHELL_RC.tmp" "$SHELL_RC"
        echo "$ALIAS_SYNC" >> "$SHELL_RC"
        log "Alias 'omp-sync' berhasil diperbarui di $SHELL_RC"
    fi
else
    echo "$ALIAS_SYNC" >> "$SHELL_RC"
    log "Menambahkan alias 'omp-sync' (manual pull+push untuk knowledge/, src/, program.md) ke $SHELL_RC"
fi

# ── 5c. Setup Syncthing untuk .omp/skills/ (sync real-time, bukan git — program.md §13) ──
if ! command -v syncthing >/dev/null 2>&1; then
    if command -v apt >/dev/null 2>&1; then
        log "Syncthing belum terinstall. Menginstall (butuh sudo)..."
        sudo apt update && sudo apt install -y syncthing
    else
        warn "Syncthing belum terinstall dan package manager selain apt terdeteksi — install manual: https://syncthing.net/downloads/"
    fi
fi

if command -v syncthing >/dev/null 2>&1; then
    systemctl --user enable --now syncthing 2>/dev/null || warn "Gagal enable syncthing service — jalankan manual: systemctl --user enable --now syncthing"
    sleep 2
    ST_DEVICE_ID="$(syncthing --device-id 2>/dev/null || true)"
    ST_CONFIG="$HOME/.config/syncthing/config.xml"
    [ -f "$ST_CONFIG" ] || ST_CONFIG="$HOME/.local/state/syncthing/config.xml"

    echo
    log "Syncthing aktif. Device ID device ini:"
    echo "    $ST_DEVICE_ID"
    log "Folder yang perlu di-share: omp-skills -> $PWD/.omp/skills (folder ID harus identik di semua device)."
    log "Detail cara pairing (web UI :8384 atau REST API buat device CLI-only): README.md § 'Sinkronisasi .omp/skills/ via Syncthing'."

    read -rp "Ada Device ID device lain buat di-pairing sekarang lewat REST API? (kosongkan untuk skip) [Device ID]: " PEER_ID
    if [ -n "$PEER_ID" ]; then
        ST_API_KEY="$(grep -oP '(?<=<apikey>).*(?=</apikey>)' "$ST_CONFIG" 2>/dev/null || true)"
        if [ -n "$ST_API_KEY" ]; then
            curl -fsS -X PUT -H "X-API-Key: $ST_API_KEY" -H "Content-Type: application/json" \
                "http://localhost:8384/rest/config/devices/$PEER_ID" \
                -d "{\"deviceID\": \"$PEER_ID\", \"name\": \"peer\", \"addresses\": [\"dynamic\"]}" >/dev/null \
                && log "Device $PEER_ID ditambahkan di sisi ini." || warn "Gagal menambahkan device $PEER_ID — cek manual via UI (:8384)."
            curl -fsS -X PUT -H "X-API-Key: $ST_API_KEY" -H "Content-Type: application/json" \
                "http://localhost:8384/rest/config/folders/omp-skills" \
                -d "{\"id\": \"omp-skills\", \"label\": \"omp skills\", \"path\": \"$PWD/.omp/skills\", \"type\": \"sendreceive\", \"devices\": [{\"deviceID\": \"$PEER_ID\"}]}" >/dev/null \
                && log "Folder omp-skills di-share ke $PEER_ID." || warn "Gagal share folder — cek manual via UI (:8384)."
            warn "Sisi ini selesai. Device $PEER_ID WAJIB juga menambahkan Device ID device ini ($ST_DEVICE_ID) dan share folder omp-skills balik, baru koneksi dua arah jalan."
        else
            warn "Tidak bisa baca API key Syncthing di $ST_CONFIG — pairing lewat UI manual saja."
        fi
    else
        log "Skip pairing otomatis. Pairing manual belakangan lewat UI (:8384) atau REST API — lihat README."
    fi
else
    warn "Syncthing tidak terinstall — .omp/skills/ tidak akan tersinkron otomatis ke/dari device ini. Install manual lalu ikuti README."
fi

# ── 6. Test konektivitas ke Hindsight server ──
HINDSIGHT_URL="$(grep -oP '(?<=apiUrl: ).*' "$OMP_CONFIG_FILE" | head -1)"
if [ -n "$HINDSIGHT_URL" ]; then
    log "Cek koneksi ke $HINDSIGHT_URL/health ..."
    if curl -fsS -H "Authorization: Bearer $HINDSIGHT_API_TOKEN" "${HINDSIGHT_URL}/health" >/dev/null 2>&1; then
        log "✅ Hindsight server terjangkau dan sehat."
    else
        warn "Tidak bisa reach $HINDSIGHT_URL/health — cek Tailscale aktif & server hidup di laptop 24/7."
    fi
else
    warn "Tidak bisa parse apiUrl dari config. Cek isi $OMP_CONFIG_FILE secara manual."
fi

echo
log "Setup selesai. Jalankan 'omp' di dalam folder repo untuk mulai sesi (mental model & histori akan auto-recall)."
log "Ingat: 'omp-sync' untuk pull/push manual knowledge/, src/, program.md — .omp/skills/ sudah otomatis via Syncthing kalau pairing di atas berhasil."
