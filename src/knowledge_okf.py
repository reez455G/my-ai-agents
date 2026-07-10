import frontmatter
from pathlib import Path

KNOWLEDGE_DIR = Path(__file__).parent.parent / "knowledge"

def load_all():
    docs = []
    for f in KNOWLEDGE_DIR.rglob("*.md"):
        post = frontmatter.load(f)
        docs.append({
            "id": post.get("id"),
            "title": post.get("title"),
            "tags": post.get("tags", []),
            "content": post.content,
            "path": str(f),
        })
    return docs

def cari_by_tag(tag: str):
    return [d for d in load_all() if tag in d["tags"]]

def cari_by_id(doc_id: str):
    for d in load_all():
        if d["id"] == doc_id:
            return d
    return None

def catalog_skills() -> list[dict]:
    return [{"id": d["id"], "title": d["title"], "tags": d["tags"]}
            for d in cari_by_tag("skill")]


def get_profile() -> dict | None:
    return cari_by_id("miftahudin-profile")
