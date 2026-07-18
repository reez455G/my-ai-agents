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

---

## 12. Integrasi OMP↔Hindsight↔OKF & Keandalan LLM Backend (2026-07-14)

### 12.1 OMP (Server A/B/lainnya) → Hindsight: sudah tersambung, bukan gap baru

Cross-device sudah bekerja by design sejak §8/§9: satu instance Hindsight (`hindsight.efsatu.my.id`, juga `localhost:8890` di Server A), satu bank (`my-ai-agent`), config disebar via `setup-new-device.sh` + `omp-config.template.yml` — device baru tinggal isi token yang sama. Ini BUKAN pekerjaan integrasi yang belum ada.

**Koreksi atas §8 poin 2:** env `AGENT_BRAIN_ID` yang disebut "wajib di-set oleh otak yang terpasang" ternyata **tidak perlu diset manual** — verifikasi API (`GET .../tags`) menunjukkan tag `brain:claude` dan `device:parrot` sudah ada di bank meski `AGENT_BRAIN_ID` tidak pernah di-set di `.env`/shell rc manapun di Server A. Native harness `omp` sendiri yang otomatis menyuntikkan atribusi brain (dari model role aktif) dan device (dari hostname) ke setiap `retain()`. §8 poin 2 keliru menganggap ini perlu konfigurasi eksplisit — dibiarkan sebagai catatan sejarah, tidak dihapus (kontrak append-only), dikoreksi di sini.

**Gap nyata yang ditemukan:** dari 1497 total nodes di bank, hanya 13 yang punya tag `brain:`/`device:` — mayoritas mutlak entry historis tidak teratribusi (ditulis sebelum fitur auto-tagging harness ada, atau oleh jalur non-`retain()` seperti ingestion manual). Tidak ada tindakan diambil untuk data lama (di luar scope hari ini); entry BARU otomatis teratribusi tanpa perlu perubahan apapun.

### 12.2 OKF → Hindsight: `ingest-okf-to-hindsight.py`

Sebelumnya OKF (`knowledge/`) hanya bisa diakses lewat native skill provider `omp` (cwd-scoped ke repo ini, load seluruh `SKILL.md`, bukan pencarian semantik per-fakta) — `recall()`/`reflect()` Hindsight tidak pernah melihat isi OKF sama sekali. Hindsight API ternyata sudah punya primitif yang cocok (`POST .../memories` dengan `document_id`/`tags`/`timestamp: "unset"` untuk konten statis) — tidak perlu infrastruktur baru.

`ingest-okf-to-hindsight.py` (root repo, stdlib + `python-frontmatter`):
- Scan `knowledge/**/*.md` (kecuali `index.md`), tiap file OKF valid jadi satu Hindsight document dengan `document_id=f"okf:{id}"`, tag `source:okf` + `project:my-ai-agents` + `okf-tag:<tag asli>`, `timestamp: "unset"`.
- Idempoten by design: `knowledge/` append-only (§5) → isi file tidak pernah berubah setelah ter-ingest, jadi cukup skip `document_id` yang sudah ada di bank (di-query lewat `GET .../documents`, bukan state lokal — supaya device manapun yang menjalankannya melihat status bank yang sama).
- **Retain sinkron (`async: false`), bukan async** — pilihan sadar: versi async awal punya race (script re-run sebelum batch async selesai diproses tidak melihat document baru sebagai "sudah ada" → double-submit). Sinkron menghilangkan race ini sepenuhnya karena proses tidak return sampai retain benar-benar selesai.
- Dipanggil otomatis dari `sync-skills.sh` (best-effort, `|| echo WARN` — Hindsight down tidak boleh menggagalkan commit+push `.omp/skills`).
- OKF (`knowledge/`) TETAP sumber kebenaran git-tracked; ingestion ke Hindsight adalah salinan read-optimized untuk `recall()`/`reflect()`, sama seperti `.omp/skills/` adalah salinan read-optimized untuk native skill provider. Tiga representasi, satu sumber.

### 12.3 Keandalan LLM backend Hindsight — root cause "model kurang pintar merusak memory"

Investigasi `GET .../stats` menemukan 78 failed operations + 45 failed consolidation (dari total ~350) di bank produksi — SEMUA gagal karena masalah LLM backend Hindsight sendiri (`HINDSIGHT_API_LLM_MODEL`), bukan konten yang ditulis salah:
- 3x HTTP 500 `"System role not supported"` — `google/gemma-4-31b-it` (model lama) menolak system-role message yang dikirim Hindsight secara struktural.
- 5x HTTP 429 rate-limit, sisanya timeout — beban `consolidation_llm_parallelism: 4` / `batch_size: 8` terlalu agresif untuk tier API yang dipakai.

**Percobaan pertama (SALAH, sempat menyalahkan kontensi CPU host/`questdb`):** ganti ke `nvidia/llama-3.3-nemotron-super-49b-v1.5` — model *reasoning*. Terbukti lewat test langsung (curl berulang ke NVIDIA API): model ini menghabiskan SELURUH `max_completion_tokens` budget (100 token, dipakai keras oleh kode verifikasi boot Hindsight) untuk `reasoning_content` tersembunyi sebelum sempat menjawab — `finish_reason: length`, `content: null` di 3/4 percobaan. Tidak ada parameter (`chat_template_kwargs.thinking=false`, `reasoning_effort=none`, dll — semua dicoba) yang berhasil menonaktifkan reasoning lewat API call biasa; hanya system-role `/no_think` yang manjur, dan itu tidak bisa disuntik ke internal call Hindsight.

**Fix final:** `HINDSIGHT_API_LLM_MODEL=meta/llama-3.1-70b-instruct` — model instruct biasa (non-reasoning), terverifikasi 3x call berturut-turut <1 detik, `finish_reason: stop` bersih. Plus `HINDSIGHT_API_LLM_TIMEOUT=300` (env baru, default kode 120s) dan `consolidation_llm_parallelism: 2` / `batch_size: 4` (turun dari 4/8, patch via `PATCH .../config`) untuk redam tekanan rate-limit. Semua 78+45 operasi gagal lama di-retry (`POST .../operations/{id}/retry`, `POST .../consolidation/recover`) — hasil akhir `failed_operations: 0`, `failed_consolidation: 0`.

**Pelajaran untuk pemilihan model LLM backend Hindsight ke depan:** Hindsight memakai model untuk ekstraksi fakta terstruktur dengan token budget KETAT (chunked, per-call kecil) — model *reasoning* (nemotron, gemma-thinking, dst.) buruk untuk pola ini kecuali ada jalur eksplisit menonaktifkan reasoning yang bisa disuntik Hindsight sendiri (belum ada). Pilih model instruct non-reasoning yang stabil; jangan asumsikan "model lebih besar/canggih = lebih baik" untuk workload ini — `meta/llama-3.1-70b-instruct` (non-reasoning) mengalahkan `nemotron-super-49b` (reasoning) justru karena LEBIH SEDERHANA perilakunya, bukan karena lebih pintar.

**Ditolak eksplisit:** OmniRoute (`localhost:20128`, dipakai coding-agent `omp`) sebagai provider LLM Hindsight — modelnya (`gemini-cli/*`, `codex/*`, `antigravity/*`) semua backed sesi OAuth CLI interaktif, bukan API key stabil; test langsung `POST /v1/chat/completions` timeout total (8-18 detik tanpa respons) — tidak layak untuk service headless 24/7.

---

## 13. Migrasi `.omp/skills/` dari Git ke Syncthing (2026-07-18)

**Perubahan:** `.omp/skills/` **tidak lagi di-git-track**. §9 poin 1 dan §11 (tabel "Managed/learned skills") yang menyatakan "`.omp/skills/` di-git-track" **superseded** oleh entri ini — dibiarkan sebagai catatan sejarah (kontrak append-only), bukan lagi kondisi aktual sejak commit `7eb0a6c`.

**Alasan:** alias `omp` lama (`git pull -q && omp && ./sync-skills.sh`) membuat setiap start/exit sesi jadi titik konflik git (commit race antar-device kalau dua device jalan bersamaan) dan menahan startup di belakang `git pull`. Sync real-time via Syncthing menghilangkan konflik itu — perubahan skill nongol di device lain dalam hitungan detik tanpa commit manual.

**Mekanisme baru:**
- `git rm -r --cached .omp/skills` + `.omp/skills/` masuk `.gitignore` — file tetap ada di disk, hanya berhenti dilacak git ke depan.
- Syncthing (folder ID `omp-skills`, sama persis di semua device) mensinkronkan `.omp/skills/` secara real-time, dua-arah, antar device yang di-pairing.
- **Pairing headless via REST API** (bukan cuma web UI `:8384`): device tanpa GUI/browser bisa pairing 100% lewat `curl` ke `/rest/config/devices/<id>` (PUT) dan `/rest/config/folders/omp-skills` (PUT) di kedua sisi, pakai API key dari `<apikey>` di `~/.config/syncthing/config.xml` (atau `~/.local/state/syncthing/config.xml`). Tidak perlu SSH tunnel ke `:8384` kalau device CLI-only.
- `knowledge/`, `src/`, `program.md` TETAP di git seperti biasa (append-only contract §5 tidak berubah, hanya berlaku pada arsip sumber, bukan `.omp/skills/`).
- Alias `omp` disederhanakan jadi langsung `/path/to/omp` (tanpa git pull/push/sync-skills otomatis). Alias baru `omp-sync` (`git pull && git push` manual) dipakai kapan pun ada perubahan di `knowledge/`/`src/`/`program.md` yang perlu disebar.

**Implikasi ke `sync-skills.sh` (§9 poin 2):** bagian akhir script yang melakukan `git add .omp/skills && git commit && git push` sekarang **no-op diam-diam** (path itu di-gitignore, `git status --porcelain .omp/skills` selalu kosong) — bukan error, tapi juga tidak lagi berfungsi. Bagian penyalinan `~/.omp/agent/managed-skills/` → `.omp/skills/` dan `knowledge/` → `.omp/skills/` (embedded-class) TETAP relevan dan tetap harus dijalankan; Syncthing yang mengambil alih distribusi ke device lain, bukan git, begitu file mendarat di disk.

**Onboarding device baru (pelengkap `setup-new-device.sh`):** script itu tidak tahu apa-apa soal Syncthing (tidak diubah, di luar scope migrasi ini) dan bagian alias-nya (baris "5b") masih menulis alias lama berbasis git — kalau dijalankan di device baru, alias hasil generate script itu harus ditimpa manual sesuai poin alias di atas. Instalasi + pairing Syncthing tetap langkah manual terpisah, tidak terintegrasi ke script onboarding ini.
