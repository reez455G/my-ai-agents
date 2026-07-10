import json
import os
import urllib.error
import urllib.request

from knowledge_okf import cari_by_tag
from memory_hindsight import ingat_percakapan, tarik_ingatan_lama


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


def proses_pesan(bank_id: str, pesan: str, tag: str | None = None) -> str:
    tag = tag or os.getenv("AGENT_OKF_TAG", "refund")

    # 1. Ingatan dinamis (Hindsight)
    try:
        konteks_dinamis = tarik_ingatan_lama(bank_id, pesan)
    except Exception as e:
        print(f"[WARN] recall gagal (bank mungkin belum ada): {e}")
        konteks_dinamis = []

    # 2. Pengetahuan statis (OKF)
    konteks_statis = cari_by_tag(tag)

    # 3. Prompt gabungan → LLM
    prompt = f"""
Ingatan sebelumnya: {konteks_dinamis}
Kebijakan resmi: {[d['content'] for d in konteks_statis]}
Pertanyaan user: {pesan}
"""
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
    try:
        ingat_percakapan(bank_id, pesan, respon)
    except Exception as e:
        print(f"[WARN] retain gagal (cek koneksi/token Hindsight di .env): {e}")

    return respon


if __name__ == "__main__":
    bank = os.getenv("AGENT_BANK_ID", "budi")
    print(proses_pesan(bank_id=bank, pesan="Bagaimana cara refund?"))
