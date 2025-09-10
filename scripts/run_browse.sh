#!/usr/bin/env bash
# file: scripts/run_browse.sh
set -euo pipefail

QUERY="${*:-Summarize Python 3.13 changes in bullets with sources.}"
PYTHON="${PYTHON:-.venv/bin/python}"

# Pass the query via env so the heredoc Python can grab it reliably
QUERY="$QUERY" "$PYTHON" - <<'PY'
import os, json
from pathlib import Path
import requests
from dotenv import load_dotenv, find_dotenv

# Load .env from current working directory (repo root)
env_path = find_dotenv(usecwd=True)
if env_path:
    load_dotenv(env_path)
else:
    # Fallback: explicit .env in CWD
    dot = Path.cwd() / ".env"
    if dot.exists():
        load_dotenv(dot)

base  = os.getenv("BASE_URL", "http://localhost:11434/v1")
model = os.getenv("MODEL", "llama3.1:8b")
query = os.getenv("QUERY", "Say hi in one word.")

payload = {
    "model": model,
    "messages": [
        {"role": "system", "content": "Be concise. Use bullet points. Include sources if mentioned."},
        {"role": "user", "content": query}
    ],
    "max_tokens": 400
}

resp = requests.post(f"{base}/chat/completions", json=payload, timeout=120)
resp.raise_for_status()
data = resp.json()
print(json.dumps(data, indent=2)[:4000])
PY
