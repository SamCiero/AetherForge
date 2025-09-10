# file: scripts/run_browse.sh
#!/usr/bin/env bash
set -euo pipefail
if [ -d ".venv" ]; then . .venv/bin/activate; fi
export PYTHONPATH=src
PROMPT="${*:-Summarize the latest guidance on Llama 3.1 licensing and give links.}"
python - <<'PY'
import os, sys
from dotenv import load_dotenv
from openai import OpenAI
from aetherforge.agent import chat_with_tools

load_dotenv()
base_url = os.getenv("BASE_URL", "http://localhost:11434/v1")
model    = os.getenv("MODEL_NAME", "llama3.1:8b")
client   = OpenAI(base_url=base_url, api_key=os.getenv("API_KEY","local"))

prompt = " ".join(sys.argv[1:]) if len(sys.argv)>1 else os.getenv("AF_PROMPT","")
answer, sources = chat_with_tools(client, model, prompt or "Browse a tech topic and cite sources.")
print(answer)
if sources:
    print("\nSources:")
    for u in dict.fromkeys(sources):
        print("-", u)
PY
