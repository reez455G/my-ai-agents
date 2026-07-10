import atexit
import json
import os
import urllib.error
import urllib.request

import memory_hindsight
from memory_hindsight import (
    get_brain_id,
    get_device_id,
    new_session_id,
    ingat_percakapan,
    ingat_kejadian,
    tarik_ingatan_lama,
    reflect_ingatan,
    pastikan_profil_bank,
    pastikan_mental_model,
)
from knowledge_okf import cari_by_tag, catalog_skills, get_profile

_SESSION = {"id": None, "bank_id": None, "interacted": False}
_finalized = False


def panggil_llm(prompt: str) -> str | None:
    """Panggil endpoint chat OpenAI-compatible (OpenAI/NVIDIA/Ollama/dll) dari env.

    Return None jika belum dikonfigurasi. Stdlib-only — tanpa dependency baru.
    """
    base_url = os.getenv("AGENT_LLM_BASE_URL", "").rstrip("/")
    model = os.getenv("AGENT_LLM_MODEL", "")
    api_key = os.getenv("AGENT_LLM_API_KEY", "")
    if not base_url or not model:
        return None
    req = urllib.request.Request(
        f"{base_url}/chat/completions",
        data=json.dumps({
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
        }).encode(),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        body = json.load(resp)
    return body["choices"][0]["message"]["content"]


def init_session(bank_id: str) -> str:
    session_id = new_session_id()
    _SESSION["id"] = session_id
    _SESSION["bank_id"] = bank_id

    # Profil tertanam: semua otak memakai profil yang sama via reflect_mission
    p = get_profile()
    if p:
        pastikan_profil_bank(bank_id, p["content"])

    pastikan_mental_model(bank_id)

    # Katalog skill OKF → Hindsight (replace agar tidak menumpuk tiap startup)
    skills = catalog_skills()
    ingat_kejadian(
        bank_id,
        content="Katalog skill tersedia: " + ", ".join(s["id"] for s in skills),
        tags=["skill-catalog"],
        document_id="skill-catalog",
        update_mode="replace",
        context="katalog skill OKF",
    )

    last = tarik_ingatan_lama(
        bank_id, "status dan task terakhir sesi sebelumnya", tags=["session-snapshot"]
    )

    memori_status = "OK" if memory_hindsight.HINDSIGHT_OK else "DEGRADED (OKF-only)"
    print("=== Agent Status Report ===")
    print(f"Brain      : {get_brain_id()}")
    print(f"Device     : {get_device_id()}")
    print(f"Session    : {session_id}")
    print(f"Skills OKF : {len(skills)}")
    print(f"Agent rules: {len(cari_by_tag('agent-rules'))}")
    print(f"Sesi lalu  : {last[0] if last else 'Tidak ada sesi sebelumnya'}")
    print(f"Memori     : {memori_status}")
    print("===========================")

    atexit.register(finalize_session)
    return session_id


def finalize_session() -> None:
    global _finalized
    if _finalized or not _SESSION["interacted"]:
        return
    _finalized = True
    bank_id = _SESSION["bank_id"]
    ringkasan = reflect_ingatan(
        bank_id,
        "Ringkas status project saat ini: task yang dikerjakan sesi ini, "
        "hasilnya, dan langkah berikutnya",
    )
    ingat_kejadian(
        bank_id,
        content=f"Snapshot akhir sesi {_SESSION['id']}: {ringkasan}",
        tags=["session-snapshot"],
        document_id=f"session-{_SESSION['id']}",
        context="state snapshot akhir sesi",
    )


def proses_pesan(bank_id: str, pesan: str) -> str:
    _SESSION["interacted"] = True

    # 1. Ingatan dinamis (Hindsight) — pencarian umum tanpa filter tag
    konteks_dinamis = tarik_ingatan_lama(bank_id, pesan)

    # 2. Pengetahuan statis (OKF): judul skill + profil
    judul_skill = [d["title"] for d in cari_by_tag("skill")]
    profil = get_profile()

    prompt = f"""
Profil agent: {profil['content'] if profil else '(tidak ada)'}
Ingatan sebelumnya: {konteks_dinamis}
Skill tersedia: {judul_skill}
Pertanyaan user: {pesan}
"""
    # 3. LLM sungguhan (stdlib, OpenAI-compatible) — None jika belum dikonfigurasi
    try:
        respon = panggil_llm(prompt)
    except urllib.error.HTTPError as e:
        return f"[ERROR] LLM HTTP {e.code}: {e.read().decode(errors='replace')[:200]}"
    except Exception as e:
        return f"[ERROR] LLM gagal: {e}"
    if respon is None:
        return ("[LLM belum dikonfigurasi — set AGENT_LLM_BASE_URL, "
                "AGENT_LLM_MODEL, AGENT_LLM_API_KEY di .env]")

    # 4. Simpan ingatan baru (hanya respons asli, bukan pesan error/placeholder)
    ingat_percakapan(bank_id, pesan, respon, session_id=_SESSION["id"])

    return respon


if __name__ == "__main__":
    bank_id = os.getenv("AGENT_BANK_ID", "efsatu-my-ai-agent")
    init_session(bank_id)
    print(proses_pesan(bank_id, "Apa status project dan skill apa yang tersedia?"))
    # Eksplisit: atexit terlalu larut untuk I/O jaringan (executor asyncio sudah
    # shutdown saat interpreter teardown); atexit tetap terdaftar sebagai jaring
    # pengaman dan idempoten via _finalized.
    finalize_session()
