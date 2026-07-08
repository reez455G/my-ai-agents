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

## Quick Start

### 1. Clone & Setup

```bash
git clone git@github.com:reez455G/my-ai-agents.git
cd my-ai-agents
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

### 2. Environment Variables

```bash
cp .env.example .env
nano .env   # isi API key dan token
```

| Variable | Keterangan |
|---|---|
| `HINDSIGHT_API_LLM_PROVIDER` | `openai` (untuk NVIDIA/OpenAI-compatible) |
| `HINDSIGHT_API_LLM_API_KEY` | API key dari provider LLM |
| `HINDSIGHT_API_LLM_BASE_URL` | Endpoint LLM (contoh: `https://integrate.api.nvidia.com/v1`) |
| `HINDSIGHT_API_LLM_MODEL` | Model (contoh: `deepseek-ai/deepseek-v4-pro`) |
| `HINDSIGHT_API_WORKER_ID` | Worker identity (contoh: `hindsight-prod`) |
| `HINDSIGHT_API_URL` | URL Hindsight dari host (default: `http://localhost:8890`) |
| `HINDSIGHT_API_TOKEN` | Token autentikasi — generate: `openssl rand -hex 32` |

### 3. Jalankan Hindsight

```bash
docker compose up -d
# Tunggu ~3-10 menit untuk startup (tergantung hardware)
curl http://localhost:8890/health
```

### 4. Test

```bash
# Verifikasi lengkap
bash verify.sh

# Atau test manual
.venv/bin/python src/agent.py
```

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
