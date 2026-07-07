---
id: program
title: Arsitektur & Kontrak Program my-ai-agent
tags: [program, arsitektur, kontrak, core]
---
# Arsitektur & Kontrak Program my-ai-agent

> **Dokumen ini adalah kontrak resmi.** Isinya **tidak boleh diubah atau dihapus** — hanya boleh **ditambah (append)**.

---

## 1. Mapping Penyimpanan

| Jenis Konten | Simpan di | Alasan |
|---|---|---|
| CLAUDE.md / AGENTS.md (konvensi project, rules, constraints) | OKF (`knowledge/`) | Statis, jarang berubah, perlu dicari by tag/id. Ini "kebijakan" buat agent. |
| Skills (prosedur repeatable, workflow) | OKF (`knowledge/`) | Statis, bisa dicari by tag. Frontmatter `tags: [skill, debugging, deploy]` bikin searchable. |
| Percakapan & keputusan yang terjadi selama pakai skill | Hindsight (`retain`) | Dinamis, kontekstual, perlu recall semantik. "Kapan terakhir kali kita pakai skill X dan apa hasilnya?" |

---

## 2. Struktur Direktori

```
knowledge/
├── index.md                   ← indeks semua knowledge
├── panduan_layanan.md         ← kebijakan domain
├── skema_database.md          ← referensi teknis
├── skills/                    ← backup skills (modular, plug & play)
│   ├── meridian.md
│   ├── agent-skills.md
│   ├── poly-engine-fullstack.md
│   ├── poly-engine-manager.md
│   └── ...
└── agent-rules/               ← backup CLAUDE.md / AGENTS.md
    ├── meridian-claude.md
    ├── agent-skills-repo-agents.md
    ├── agent-skills-repo-claude.md
    ├── hermes-agent-agents.md
    ├── hermes-agents.md
    ├── codex-agents.md
    └── ...
```

Setiap file **wajib** punya frontmatter OKF:

```markdown
---
id: <unique-id>
title: <judul deskriptif>
tags: [<tag1>, <tag2>, ...]
source: <path asal file>
imported_at: <tanggal import YYYY-MM-DD>
---
```

---

## 3. Cara Query di agent.py

```python
# Semua skills
cari_by_tag("skill")

# Skills terkait docker
cari_by_tag("docker")

# Semua agent rules
cari_by_tag("agent-rules")

# Rules dari project tertentu
cari_by_tag("meridian")

# Recall dinamis (Hindsight)
tarik_ingatan_lama(bank_id, "kapan terakhir pakai skill docker?")
```

---

## 4. Yang TIDAK Cocok di OKF

- **Memory percakapan** → tetap Hindsight
- **Data yang sering berubah** → tetap Hindsight
- **Preferensi user yang ditemukan saat percakapan** → Hindsight retain

---

## 5. Kontrak Append-Only

### Aturan Mutlak

1. **DILARANG mengubah** isi file yang sudah ada di `knowledge/` — baik konten maupun frontmatter.
2. **DILARANG menghapus** file apapun dari `knowledge/`.
3. **HANYA BOLEH menambah (append)**:
   - File baru ke `knowledge/`, `knowledge/skills/`, atau `knowledge/agent-rules/`.
   - Baris baru di akhir file yang sudah ada (jika relevan).
   - Entry baru di `knowledge/index.md`.
4. **Setiap penambahan** harus mengikuti format frontmatter OKF di atas.
5. **Setiap file baru** harus didaftarkan di `knowledge/index.md`.

### Alasan

- Menjaga integritas knowledge base sebagai **single source of truth**.
- Mencegah kehilangan data akibat edit atau delete yang tidak disengaja.
- Mendukung prinsip **modular / plug & play** — tambah modul baru tanpa merusak yang sudah ada.
- Audit trail: semua knowledge punya `source` dan `imported_at` di frontmatter.

---

## 6. Prinsip Modular / Plug & Play

- Setiap file di `knowledge/` adalah **modul mandiri** — bisa ditambah, dibaca, atau di-query secara independen.
- Menambah skill baru = drop file `.md` baru ke `knowledge/skills/` + daftarkan di `index.md`.
- Menambah agent rules = drop file `.md` baru ke `knowledge/agent-rules/` + daftarkan di `index.md`.
- Tidak perlu mengubah kode `knowledge_okf.py` — loader otomatis scan semua `*.md` di `knowledge/`.
- Format frontmatter yang konsisten memungkinkan pencarian lintas modul via `cari_by_tag()` dan `cari_by_id()`.
