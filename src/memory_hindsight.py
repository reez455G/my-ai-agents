import os
import atexit
from hindsight_client import Hindsight
from dotenv import load_dotenv

load_dotenv()

client = Hindsight(
    base_url=os.getenv("HINDSIGHT_API_URL", "http://localhost:8890"),
    api_key=os.getenv("HINDSIGHT_API_TOKEN", ""),
)
atexit.register(client.close)

def ingat_percakapan(bank_id: str, pesan_user: str, respon_ai: str):
    client.retain(
        bank_id=bank_id,
        content=f"User: {pesan_user}\nAI: {respon_ai}",
    )

def tarik_ingatan_lama(bank_id: str, query: str):
    results = client.recall(bank_id=bank_id, query=query)
    return [r.text for r in results.results]

def reflect_ingatan(bank_id: str, query: str):
    return client.reflect(bank_id=bank_id, query=query).text
