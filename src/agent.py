from memory_hindsight import tarik_ingatan_lama, ingat_percakapan, reflect_ingatan
from knowledge_okf import cari_by_tag

def proses_pesan(bank_id: str, pesan: str) -> str:
    # 1. Ingatan dinamis (Hindsight)
    try:
        konteks_dinamis = tarik_ingatan_lama(bank_id, pesan)
    except Exception as e:
        print(f"[WARN] recall gagal (bank mungkin belum ada): {e}")
        konteks_dinamis = []

    # 2. Pengetahuan statis (OKF) — sesuaikan tag pencarian dengan kebutuhan
    konteks_statis = cari_by_tag("refund")

    # 3. Susun prompt gabungan ke LLM kamu (ganti bagian ini sesuai provider)
    prompt = f"""
Ingatan sebelumnya: {konteks_dinamis}
Kebijakan resmi: {[d['content'] for d in konteks_statis]}
Pertanyaan user: {pesan}
"""
    respon = "TODO: panggil LLM di sini dengan prompt di atas"

    # 4. Simpan ingatan baru
    try:
        ingat_percakapan(bank_id, pesan, respon)
    except Exception as e:
        print(f"[WARN] retain gagal (cek API key LLM di .env): {e}")

    return respon

if __name__ == "__main__":
    print(proses_pesan(bank_id="budi", pesan="Bagaimana cara refund?"))
