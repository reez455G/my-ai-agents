import atexit
import os
import socket
from datetime import datetime, timezone

from hindsight_client import Hindsight
from dotenv import load_dotenv

load_dotenv()

client = Hindsight(
    base_url=os.getenv("HINDSIGHT_API_URL", "http://localhost:8890"),
    api_key=os.getenv("HINDSIGHT_API_TOKEN", ""),
)
atexit.register(client.close)

# Kalibrasi recall: low = tercepat, high = terdalam
RECALL_BUDGET = os.getenv("HINDSIGHT_RECALL_BUDGET", "mid")
RECALL_MAX_TOKENS = int(os.getenv("HINDSIGHT_RECALL_MAX_TOKENS", "2048"))

# False setelah exception pertama ke server Hindsight → agent tahu mode DEGRADED
HINDSIGHT_OK = True


def _mark_down(op: str, exc: Exception) -> None:
    global HINDSIGHT_OK
    HINDSIGHT_OK = False
    print(f"[WARN] Hindsight {op} gagal: {exc}")


# --- Identitas -------------------------------------------------------------

def get_brain_id() -> str:
    return os.getenv("AGENT_BRAIN_ID", "unknown")


def get_device_id() -> str:
    return socket.gethostname()


def new_session_id() -> str:
    return f"{get_brain_id()}-{get_device_id()}-{datetime.now(timezone.utc):%Y%m%d-%H%M%S}"


def identity_tags(extra: list[str] | None = None) -> list[str]:
    return [f"brain:{get_brain_id()}", f"device:{get_device_id()}"] + (extra or [])


def identity_metadata(session_id: str | None = None) -> dict[str, str]:
    meta = {
        "brain": get_brain_id(),
        "device": get_device_id(),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    if session_id:
        meta["session"] = session_id
    return meta


# --- API memori ------------------------------------------------------------
# Content SELALU kalimat natural; identitas masuk metadata/tags.

def ingat_percakapan(bank_id: str, pesan_user: str, respon_ai: str,
                     session_id: str | None = None) -> None:
    try:
        client.retain(
            bank_id=bank_id,
            content=f"User: {pesan_user}\nAI: {respon_ai}",
            metadata=identity_metadata(session_id),
            tags=identity_tags(),
            context="percakapan agent",
        )
    except Exception as e:
        _mark_down("retain percakapan", e)


def ingat_kejadian(bank_id: str, content: str, tags: list[str] | None = None,
                   document_id: str | None = None, context: str | None = None,
                   update_mode: str | None = None) -> None:
    try:
        client.retain(
            bank_id=bank_id,
            content=content,
            metadata=identity_metadata(),
            tags=identity_tags(tags),
            document_id=document_id,
            context=context,
            update_mode=update_mode,
        )
    except Exception as e:
        _mark_down("retain kejadian", e)


def tarik_ingatan_lama(bank_id: str, query: str,
                       tags: list[str] | None = None) -> list[str]:
    try:
        results = client.recall(
            bank_id=bank_id,
            query=query,
            budget=RECALL_BUDGET,
            max_tokens=RECALL_MAX_TOKENS,
            tags=tags,
            tags_match="any_strict" if tags else "any",
        )
        return [r.text for r in results.results]
    except Exception as e:
        _mark_down("recall", e)
        return []


def reflect_ingatan(bank_id: str, query: str) -> str:
    try:
        return client.reflect(bank_id=bank_id, query=query, budget="low").text
    except Exception as e:
        _mark_down("reflect", e)
        return "(memori dinamis tidak tersedia)"


def catat_skill_usage(bank_id: str, skill_id: str, repo: str, hasil: str) -> None:
    ingat_kejadian(
        bank_id,
        content=f"Skill {skill_id} dipakai di repo {repo}. Hasil: {hasil}",
        tags=["skill-usage", f"skill:{skill_id}", f"repo:{repo}"],
        context="pemakaian skill",
    )


def skill_pernah_dipakai(bank_id: str, skill_id: str | None = None,
                         repo: str | None = None) -> list[str]:
    tags = ["skill-usage"]
    if skill_id:
        tags.append(f"skill:{skill_id}")
    if repo:
        tags.append(f"repo:{repo}")
    return tarik_ingatan_lama(bank_id, "riwayat pemakaian skill", tags=tags)


def pastikan_profil_bank(bank_id: str, profil: str) -> None:
    try:
        client.create_bank(
            bank_id,
            reflect_mission=profil,
            retain_mission=(
                "Prioritaskan fakta tentang: workflow yang dikerjakan, "
                "skill yang dipakai, keputusan teknis, status build/deploy "
                "per repo dan device."
            ),
        )
    except Exception as e:
        _mark_down("create_bank", e)


def pastikan_mental_model(bank_id: str) -> None:
    try:
        models = client.list_mental_models(bank_id)
        existing = models.items or []
        for m in existing:
            if getattr(m, "id", None) == "project-status":
                return
        client.create_mental_model(
            bank_id,
            id="project-status",
            name="Status Project",
            source_query=(
                "Ringkas status terkini semua project/workflow: task terakhir, "
                "repo, device, otak yang mengerjakan, dan langkah berikutnya"
            ),
            trigger={"refresh_after_consolidation": True},
        )
    except Exception as e:
        _mark_down("mental model", e)
