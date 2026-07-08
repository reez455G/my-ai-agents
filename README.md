# my-ai-agents

Aplikasi modular AI agent dengan **dual memory system**: pengetahuan statis (OKF) + memori dinamis (Hindsight).

```
┌──────────────────────────────────────────────────┐
│                  my-ai-agents                    │
│                                                  │
│   📚 OKF (knowledge/)          💭 Hindsight      │
│   Pengetahuan & Skills         Memori Percakapan │
│   ─ Agent rules                ─ retain()        │
│   ─ Skills library             ─ recall()        │
│   ─ Domain knowledge           ─ reflect()       │
│                                                  │
│   🤖 agent.py                                    │
│   Gabungkan keduanya → respons cerdas            │
└──────────────────────────────────────────────────┘
```

## Arsitektur

| Komponen | Fungsi | Sifat |
|---|---|---|
| **OKF** (`knowledge/`) | Pengetahuan statis — rules, skills, kebijakan | Append-only, versioned di git |
| **Hindsight** (Docker) | Memori dinamis — percakapan, keputusan, konteks | Semantik, auto-learn via LLM |
| **agent.py** | Orkestrasi — query OKF + recall Hindsight → prompt LLM | Stateless, pluggable |

## Struktur Direktori

```
my-ai-agents/
├── program.md                    # Kontrak arsitektur (append-only)
├── docker-compose.yml            # Hindsight server
├── requirements.txt              # Python dependencies
├── .env.example                  # Template environment variables
├── omp-config.template.yml       # Template config untuk device baru
├── setup-new-devise.sh           # Onboarding script device baru
├── verify.sh                     # Checklist verifikasi
│
├── src/
│   ├── agent.py                  # Main agent — gabungkan OKF + Hindsight
│   ├── knowledge_okf.py          # OKF loader (auto-scan knowledge/*.md)
│   └── memory_hindsight.py       # Hindsight client (retain/recall/reflect)
│
└── knowledge/                    # OKF Knowledge Base (append-only!)
    ├── index.md                  # Indeks semua knowledge
    ├── panduan_layanan.md        # Domain: kebijakan layanan
    ├── skema_database.md         # Domain: referensi teknis
    ├── agent-rules/              # 6 files — konvensi dari berbagai project
    │   ├── meridian-claude.md
    │   ├── hermes-agent-agents.md
    │   ├── hermes-agents.md
    │   ├── agent-skills-repo-agents.md
    │   ├── agent-skills-repo-claude.md
    │   └── codex-agents.md
    └── skills/                   # 27 files — skill library
        ├── meridian.md
        ├── poly-engine-fullstack.md
        ├── poly-engine-manager.md
        ├── agent-skills.md
        └── repo-*.md             # 23 skills dari agent-skills-repo
```

## Deploy

Ada **2 metode deploy** — pilih salah satu sesuai kebutuhan:

```
┌─────────────────────────────────────────────────────────────┐
│                     METODE DEPLOY                           │
│                                                             │
│   Mode A: Self-Hosted (Lokal)     Mode B: Existing Server   │
│   ┌─────────────────────┐        ┌─────────────────────┐   │
│   │  Device ini         │        │  Device ini         │   │
│   │  ├── agent.py       │        │  ├── agent.py       │   │
│   │  ├── knowledge/     │        │  ├── knowledge/     │   │
│   │  └── Hindsight 🐳   │        │  └── .env (remote)  │   │
│   │      localhost:8890  │        │                     │   │
│   └─────────────────────┘        └────────┬────────────┘   │
│                                           │                │
│                                    ┌──────▼──────────┐     │
│                                    │ Server Existing  │     │
│                                    │ Hindsight 🐳     │     │
│                                    │ host:8890        │     │
│                                    └─────────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

---

### Mode A: Self-Hosted (Hindsight Lokal)

Hindsight jalan di device yang sama sebagai Docker container. Cocok untuk:
- Laptop/PC utama yang selalu on (server 24/7)
- Development & testing
- Tidak tergantung koneksi internet untuk memori

#### 1. Clone & Setup

```bash
git clone git@github.com:reez455G/my-ai-agents.git
cd my-ai-agents
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

#### 2. Environment Variables

```bash
cp .env.example .env
nano .env
```

Isi semua variable:

| Variable | Contoh | Keterangan |
|---|---|---|
| `HINDSIGHT_API_LLM_PROVIDER` | `openai` | Provider LLM (openai, anthropic, ollama, gemini, dll) |
| `HINDSIGHT_API_LLM_API_KEY` | `nvapi-xxx` | API key provider |
| `HINDSIGHT_API_LLM_BASE_URL` | `https://integrate.api.nvidia.com/v1` | Endpoint LLM |
| `HINDSIGHT_API_LLM_MODEL` | `deepseek-ai/deepseek-v4-pro` | Model yang dipakai |
| `HINDSIGHT_API_WORKER_ID` | `hindsight-prod` | Worker identity |
| `HINDSIGHT_API_URL` | `http://localhost:8890` | URL Hindsight dari host |
| `HINDSIGHT_API_TOKEN` | `openssl rand -hex 32` | Token autentikasi |

#### 3. Jalankan Hindsight

```bash
docker compose up -d

# Tunggu ~3-10 menit untuk startup (tergantung hardware)
# Monitor:
watch -n 10 'curl -sf http://localhost:8890/health && echo OK || echo waiting...'
```

#### 4. Verifikasi

```bash
curl http://localhost:8890/health
bash verify.sh
```

---

### Mode B: Hindsight Existing (Remote Server)

Hindsight sudah jalan di server lain (laptop utama, VPS, dll). Device ini hanya perlu connect. Cocok untuk:
- Device tambahan (laptop kedua, PC kantor)
- Shared memory antar device via Tailscale/VPN
- Tidak perlu Docker di device ini

#### 1. Clone & Setup

```bash
git clone git@github.com:reez455G/my-ai-agents.git
cd my-ai-agents
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

#### 2. Environment Variables

```bash
cp .env.example .env
nano .env
```

Yang berbeda dari Mode A — **tidak perlu LLM config** (sudah dihandle server):

| Variable | Contoh | Keterangan |
|---|---|---|
| `HINDSIGHT_API_URL` | `http://laptop-server.tail1234.ts.net:8890` | URL Hindsight di server |
| `HINDSIGHT_API_TOKEN` | `(sama dengan token di server)` | Token autentikasi — minta dari admin server |

Variable LLM (`HINDSIGHT_API_LLM_*`) bisa dikosongkan — hanya diperlukan di server yang menjalankan container.

#### 3. Test Konektivitas

```bash
# Pastikan server reachable
curl -sf http://<HOSTNAME_SERVER>:8890/health && echo "OK" || echo "Server unreachable"

# Test agent
.venv/bin/python src/agent.py
```

#### 4. Docker Tidak Diperlukan

Di mode ini, `docker-compose.yml` tidak perlu dijalankan. Cukup `.env` yang mengarah ke server existing.

---

### Perbandingan Mode

| | Mode A: Self-Hosted | Mode B: Existing |
|---|---|---|
| Docker di device ini | ✅ Wajib | ❌ Tidak perlu |
| LLM API key di `.env` | ✅ Wajib | ❌ Tidak perlu |
| Perlu koneksi ke server | ❌ Lokal | ✅ Via Tailscale/VPN/LAN |
| Startup time | ~3-10 menit | Instan |
| Memori disimpan di | Device ini | Server |
| Dashboard (port 9999) | `localhost:9999` | `<server>:9999` |
| Cocok untuk | Server utama | Device tambahan |

---

### Setup via Script (kedua mode)

```bash
bash setup-new-devise.sh
```

Script akan mendeteksi mode berdasarkan `omp-config.template.yml` dan memandu setup.

## Cara Pakai OKF

### Query Knowledge

```python
from knowledge_okf import load_all, cari_by_tag, cari_by_id

# Semua dokumen
load_all()                        # → 36 docs

# By tag
cari_by_tag("skill")              # → 27 skills
cari_by_tag("agent-rules")        # → 6 rules
cari_by_tag("meridian")           # → 2 docs (rules + skill)
cari_by_tag("testing")            # → TDD, browser-testing
cari_by_tag("security")           # → security-and-hardening

# By ID
cari_by_id("skill-meridian")      # → 1 doc langsung
```

### Tambah Knowledge Baru

Drop file `.md` baru ke `knowledge/skills/` atau `knowledge/agent-rules/` dengan frontmatter:

```markdown
---
id: skill-nama-unik
title: Judul Deskriptif
tags: [skill, domain, subdomain]
source: ~/path/ke/file/asli
imported_at: 2026-07-07
---

# Konten skill di sini...
```

Lalu daftarkan di `knowledge/index.md`. Tidak perlu ubah kode — `knowledge_okf.py` auto-scan semua `*.md`.

## Cara Pakai Hindsight

```python
from memory_hindsight import ingat_percakapan, tarik_ingatan_lama, reflect_ingatan

# Simpan memori
ingat_percakapan("bank-user", "pertanyaan user", "respons agent")

# Recall memori relevan
tarik_ingatan_lama("bank-user", "kata kunci")

# Refleksi — simpulkan pola dari banyak memori
reflect_ingatan("bank-user", "apa pola pertanyaan user?")
```

## Kontrak Append-Only

Didefinisikan di `program.md`:

- **DILARANG** mengubah atau menghapus file di `knowledge/`
- **HANYA BOLEH** menambah file baru + entry di `index.md`
- Setiap file wajib punya frontmatter OKF (id, title, tags, source, imported_at)
- Menjaga integritas knowledge base sebagai single source of truth

## Onboarding Device Baru

```bash
# Clone repo
git clone git@github.com:reez455G/my-ai-agents.git
cd my-ai-agents

# Jalankan setup
bash setup-new-devise.sh
```

Script akan: clone repo → setup venv → minta token → apply omp config → test konektivitas.

## Port & Infra

| Service | Port | Keterangan |
|---|---|---|
| Hindsight API | `8890` | Host port (mapped ke container 8888) |
| Control Plane UI | `9999` | Dashboard visual memori bank |

## Backup & Restore

```bash
# Backup volume Hindsight
docker run --rm -v my-ai-agent_hindsight-data:/data -v $(pwd):/backup alpine \
  tar czf /backup/hindsight-backup-$(date +%F).tar.gz /data

# Restore
docker run --rm -v my-ai-agent_hindsight-data:/data -v $(pwd):/backup alpine \
  tar xzf /backup/hindsight-backup-YYYY-MM-DD.tar.gz -C /

# Knowledge base
# Sudah di git — clone ulang = restore otomatis
```

## Token Rotation

Jika `HINDSIGHT_API_TOKEN` bocor:

```bash
cd ~/my-ai-agents
NEW_TOKEN=$(openssl rand -hex 32)
sed -i "s/^HINDSIGHT_API_TOKEN=.*/HINDSIGHT_API_TOKEN=$NEW_TOKEN/" .env
docker compose down && docker compose up -d
```
