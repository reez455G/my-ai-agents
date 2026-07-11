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

---

## 7. Validasi Kontrak (ditambahkan 2026-07-10)

- `src/validate_okf.py` menegakkan §2 & §5: frontmatter wajib, id unik, registrasi di `knowledge/index.md`. Dijalankan otomatis oleh `verify.sh`.
- `index.md` dikecualikan dari `tags`/`source`/`imported_at` (berfungsi sebagai indeks).
- File pra-kontrak `panduan_layanan.md` dan `skema_database.md` di-grandfather (tanpa `source`/`imported_at`) karena §5.1 melarang edit frontmatter existing. Semua file baru wajib frontmatter lengkap.

---

## 8. Protokol Memori Lintas-Otak

Kontrak yang mengikat SEMUA otak (antigravity, claude, codex, glm, ...) yang terpasang via omp.

### Taksonomi Tag (Hindsight)

| Tag | Arti |
|---|---|
| `brain:<id>` | Otak yang menulis memori (dari env `AGENT_BRAIN_ID`) |
| `device:<hostname>` | Device/PC tempat memori ditulis (`socket.gethostname()`) |
| `session-snapshot` | Snapshot state akhir sesi (ditulis otomatis saat exit) |
| `skill-usage` | Catatan pemakaian skill di suatu repo |
| `skill:<id>` | Skill spesifik yang dipakai (id dari frontmatter OKF) |
| `repo:<nama>` | Repo/workflow tempat skill dipakai |
| `skill-catalog` | Katalog skill OKF yang tersedia (di-replace tiap startup) |

### Aturan

1. **Content selalu kalimat natural** — identitas (brain, device, session, timestamp) masuk `metadata=`/`tags=`, BUKAN JSON di dalam content. JSON di content mengotori ekstraksi fakta LLM Hindsight.
2. Env `AGENT_BRAIN_ID` **wajib di-set oleh otak yang terpasang** (fallback `unknown` tetap berfungsi tapi memori kehilangan atribusi otak).
3. Bank tunggal lintas-project: `AGENT_BANK_ID` (default `efsatu-my-ai-agent`) — samakan di semua device dan dengan `HINDSIGHT_BANK_ID` (dipakai `omp-config.template.yml`); scoping per-project via tag `repo:<nama>`.
4. Kalibrasi recall via env: `HINDSIGHT_RECALL_BUDGET` (low=tercepat, mid=seimbang, high=terdalam) dan `HINDSIGHT_RECALL_MAX_TOKENS`.
5. Semua panggilan Hindsight menelan exception → degradasi anggun ke OKF-only dengan `[WARN]`; agent tidak boleh crash karena server memori mati.
6. Koreksi (menggantikan poin 3 di atas): bank kanonik adalah `my-ai-agent`, BUKAN `efsatu-my-ai-agent` — bank itu sudah tidak dipakai (dihapus, isinya cuma data test), digantikan `my-ai-agent` yang sudah berisi histori nyata lintas project (9 mental model, dipakai omp sejak awal).
7. Koreksi susulan atas poin 6: eksekusi plan re-verifikasi `efsatu-my-ai-agent` sebelum delete (2026-07-10) menemukan bank itu TIDAK kosong lagi (2 entry `skill-catalog` baru, mental model `project-status` masih ada) — bank BATAL dihapus sesuai kontrak abort-on-unexpected-content di plan, hanya migrasi konfigurasi (`AGENT_BANK_ID`/`HINDSIGHT_BANK_ID` → `my-ai-agent`) yang dieksekusi. Bank lama masih ada di disk, tidak lagi menerima tulisan baru dari konfigurasi manapun.

---

## 9. Sinkronisasi Skill Lintas-Device

`~/.omp/agent/managed-skills/` (dibuat oleh tool `manage_skill`) adalah direktori lokal, tidak di-git-track, dan tidak punya mekanisme sync — device baru yang di-clone dari repo ini tidak akan punya skill tersebut sama sekali. Solusinya: `.omp/skills/<name>/SKILL.md` di-git-track dan otomatis di-scan oleh native skill provider omp.

1. `.omp/skills/<name>/SKILL.md` di-git-track dan auto-discovered oleh native provider omp (prioritas tertinggi, 100) setiap kali `omp` dijalankan dari dalam repo ini atau subdirektorinya — tidak perlu perubahan config apapun.
2. `sync-skills.sh` (di root repo) wajib dijalankan setiap kali selesai `manage_skill create`/`update`, lalu hasilnya di-commit dan di-push — karena tool itu hanya pernah menulis ke `~/.omp/agent/managed-skills` lokal, tidak pernah langsung ke `.omp/skills/`.
3. Entry dengan nama sama di `.omp/skills/` selalu menang dibanding salinan lokal basi di `~/.omp/agent/managed-skills` (prioritas native provider 100 mengalahkan prioritas provider `omp-managed` 5), jadi `git pull` di device manapun selalu memberi versi terbaru.

---

## 10. Koreksi Susulan (2026-07-11): §3 Superseded, Migrasi ke `.omp/skills/`

1. **§3 "Cara Query di agent.py" sudah usang.** `agent.py`, `knowledge_okf.py`, dan `memory_hindsight.py` dihapus dari repo ini (digantikan eksekusi native OMP — lihat §9). Fungsi `cari_by_tag()`/`tarik_ingatan_lama()` yang dicontohkan di §3 tidak lagi ada; jangan diikuti sebagai kode aktif.
2. Seluruh isi `knowledge/` (34 file: 27 skill + 7 agent-rules) sudah dimigrasikan/disalin ke `.omp/skills/<name>/SKILL.md` agar bisa di-scan native oleh `omp` (mekanisme sama seperti §9, prioritas provider 100). `knowledge/` tetap dipertahankan sebagai arsip sumber append-only (kontrak §5 tetap berlaku di sana) — `.omp/skills/` adalah salinan siap-pakai untuk konsumsi native, bukan pengganti arsip.
3. **Belum ada mekanisme otomatis** yang menyalin penambahan baru di `knowledge/skills/` atau `knowledge/agent-rules/` ke `.omp/skills/` (beda dengan `sync-skills.sh` yang meng-cover `~/.omp/agent/managed-skills/`). Setiap kali menambah file OKF baru di `knowledge/`, salin juga manual ke `.omp/skills/<name>/SKILL.md` agar konsisten dengan §9 poin 3, atau perluas `sync-skills.sh` untuk meng-cover kedua sumber.

---

## 11. Desain Sinkronisasi Otomatis Penuh (Fase 1, 2026-07-11)

Menyelesaikan gap di §10 poin 3. Ditulis SEBELUM implementasi (kontrak Fase 1 tugas plug&play), berdasarkan audit Fase 0 yang mengoreksi dua asumsi:

### 11.1 Koreksi asumsi dari brief tugas

- **`.omp/` SUDAH ter-track penuh di `origin/main`** (diverifikasi via `git ls-tree` lokal DAN GitHub REST API langsung, commit `c31974b`) — klaim sebaliknya di brief tugas keliru.
- **`setup-new-devise.sh` (typo) tidak pernah ada** — riwayat git menunjukkan file sudah bernama `setup-new-device.sh` sejak commit `cecd29b` ("Fix onboarding: rename to setup-new-device.sh"), sebelum sesi ini. Tidak ada rename yang perlu dilakukan.
- **Symlink tidak layak untuk satupun dari 34 file OKF** (0/34 identik byte-per-byte ke sumber utuh) — sesuai logika kondisional di brief tugas sendiri, ini memilih jalur generator.

### 11.2 Reproducibility 34 file OKF tidak seragam — ini mengubah desain "gitignore build artifact"

- **26 file kelas EMBEDDED** (sudah punya frontmatter native `name:`/`description:` tertanam di sumber `knowledge/`): body identik 100% dengan sumber setelah wrapper OKF di-strip. **Sepenuhnya reproducible secara mekanis** oleh generator.
- **8 file kelas BARE** (`meridian`, `agent-skills-repo-agent-rules`, `agent-skills-repo-conventions`, `codex-codegraph-rules`, `hermes-agent-framework-guide`, `hermes-runtime-rules`, `meridian-bot-engineering-manual`, `miftahudin-admin-profile`): frontmatter disintesis manual, dan 2 di antaranya (`agent-skills-repo-agent-rules`, `hermes-runtime-rules`) punya perbaikan konten manual (heading ditambahkan, smart-quote diperbaiki) yang **tidak ada di sumber `knowledge/`**. Generator yang regenerate file ini dari `knowledge/` akan **menghapus perbaikan tersebut** — tidak reproducible dengan aman.
- **Keputusan (deviasi dari instruksi literal "`.omp/skills/` di-gitignore sebagai artefak build"):** `.omp/skills/` TETAP di-git-track, bukan digitignore. Alasan: memperlakukannya sebagai artefak build murni hanya valid jika 100% reproducible dari sumber; karena 8/34 file tidak, gitignore akan membuat konten itu hilang permanen begitu ada device yang hanya mengandalkan generator tanpa riwayat git yang membawa versi lama. Sebagai gantinya, generator bersifat **fill-gap, bukan overwrite-all**: hanya menulis entry yang belum ada di `.omp/skills/`, tidak pernah menimpa entry yang sudah ada di sana.

### 11.3 Single source of truth per kelas

| Kelas | Sumber kebenaran | Cara update |
|---|---|---|
| Skill EMBEDDED (26) | `knowledge/skills/*.md` (isi body) | Edit di `knowledge/`, generator mekanis menyalin ke `.omp/skills/` |
| Skill BARE (8) | `.omp/skills/<name>/SKILL.md` itu sendiri | Edit langsung di `.omp/skills/`; `knowledge/` tetap arsip append-only pasif untuk file-file ini (kontrak §5 tidak berubah — tidak diedit/dihapus), tapi bukan lagi sumber regenerasi untuk skill hasil sintesis |
| Managed/learned skills (dari tool `manage_skill`) | `~/.omp/agent/managed-skills/` (device-local, hasil `learn`) | `sync-skills.sh` (sudah ada, tidak perlu script baru bernama `export-learned-skills.sh` — akan jadi duplikasi fungsi yang sudah bekerja) meng-copy ke `.omp/skills/` lalu commit+push |
| Sesi, transkrip, "project" list | `~/.omp/agent/sessions/<cwd-encoded>/*.jsonl`, device-local | **Di luar scope sinkronisasi** — device-local by design di omp, tidak ada mekanisme built-in untuk sync lintas device. Tidak dibangun mekanisme baru untuk ini (di luar permintaan; membangunnya berarti reimplementasi sebagian session-storage omp). |
| Memori jangka panjang (fakta, keputusan, mental model) | Hindsight (`recall`/`retain`/`reflect`, bank `my-ai-agent`) | Native omp tools, sudah cross-device by design selama `HINDSIGHT_API_URL`/`HINDSIGHT_API_TOKEN`/`HINDSIGHT_BANK_ID` di `.env` device baru mengarah ke instance yang sama |

### 11.4 Duplikasi 6→7 managed-skills di dua lokasi: DIPERTAHANKAN, bukan dihilangkan

Instruksi awal ("satu lokasi kanonik saja") dievaluasi ulang: `.omp/skills/` (native, priority 100) hanya aktif ketika `omp` dijalankan di dalam/subdirektori repo `my-ai-agents`. `~/.omp/agent/managed-skills/` (`omp-managed`, priority 5) di-scan **unconditional**, terlepas dari cwd/repo mana pun. Skill umum seperti `agent-troubleshoot` atau `fix-bashrc-compatibility` relevan juga di repo LAIN — menghapus salinannya dari `managed-skills/` demi "satu lokasi" akan membuatnya hilang saat bekerja di luar `my-ai-agents`. Keduanya dipertahankan dengan **arah sinkronisasi jelas**:

- **Export** (managed-skills → repo, existing): `sync-skills.sh`, dijalankan manual/oleh agent setelah `manage_skill create`/`update` (aturan sudah ada di §9.2 — pelanggaran aturan ini pada `okf-to-native-skill-migration` di sesi sebelumnya adalah bukti perlu diperkuat, bukan bukti desainnya salah).
- **Import** (repo → managed-skills device baru, BELUM ADA — bagian dari Fase 2): langkah baru di `setup-new-device.sh` yang menyalin skill dari `.omp/skills/` ke `~/.omp/agent/managed-skills/` jika belum ada secara lokal, dengan pengecekan hash agar tidak menimpa versi lokal yang lebih baru.
- Git hook `post-merge`/`post-checkout` **tidak** dipakai untuk "refresh `.omp/skills/`" seperti disebut di brief tugas — itu sudah otomatis lewat `git pull` biasa karena file di-track git. Hook dipakai untuk memicu ulang langkah **import** di atas setelah `git pull`, supaya skill baru dari teman satu tim ikut ter-import ke `managed-skills/` lokal tanpa perintah tambahan.

### 11.5 Interpretasi Gate B (memory persistence)

"Sesi/workflow/project harus muncul kembali tanpa langkah manual" diinterpretasikan sebagai: **memori semantik Hindsight** (fakta yang ditulis via `retain`, bisa ditarik lewat `recall`/`reflect`) pulih otomatis di clone+setup baru selama kredensial Hindsight sama. Riwayat sesi mentah dan project-list TIDAK diuji untuk "pulih otomatis lintas device" karena §11.3 di atas — bukan kelalaian, tapi batas arsitektur omp yang dikonfirmasi di Fase 0.
