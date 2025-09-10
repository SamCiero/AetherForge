#!/usr/bin/env bash
# file: scripts/summarize_urls.sh
# Usage:
#   scripts/summarize_urls.sh [--debug] [-o OUT.md] [--no-cite] [--max-chars N] [--cache-dir DIR] "<question>" <url1> [url2 ...]
# Examples:
#   scripts/summarize_urls.sh "Summarize the main points." https://example.com/a https://example.com/b
#   scripts/summarize_urls.sh -o out/notes.md "Key findings" https://site/doc
#   scripts/summarize_urls.sh --debug "Impact of X" https://a https://b
#   scripts/summarize_urls.sh --no-cite "Explain the algorithm simply" https://doc
#
# Env:
#   BASE_URL=http://HOST:11434/v1   # OpenAI-compatible endpoint (Ollama/vLLM)
#   MODEL=llama3.1:8b               # Model id at that endpoint
#   STRICT=1                        # exit non-zero if citation format invalid (default 0)
#
# Flags:
#   --debug          Print raw JSON (no post-processing)
#   -o, --out PATH   Also write Markdown to PATH
#   --no-cite        Do not enforce bracketed [ids]; prints bullets without citation checks
#   --max-chars N    Max characters per source fed to the model (default 5000)
#   --cache-dir DIR  Cache fetched HTML under DIR (speeds iteration)

set -euo pipefail

MODE="answer"    # answer | debug
OUT=""
NO_CITE=0
MAX_CHARS=5000
CACHE_DIR=""

# Parse flags
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) MODE="debug"; shift ;;
    -o|--out)
      [[ $# -ge 2 ]] || { echo "Missing argument for $1" >&2; exit 2; }
      OUT="$2"; shift 2 ;;
    --no-cite) NO_CITE=1; shift ;;
    --max-chars)
      [[ $# -ge 2 ]] || { echo "Missing N for --max-chars" >&2; exit 2; }
      MAX_CHARS="$2"; shift 2 ;;
    --cache-dir)
      [[ $# -ge 2 ]] || { echo "Missing DIR for --cache-dir" >&2; exit 2; }
      CACHE_DIR="$2"; shift 2 ;;
    --) shift; break ;;
    -h|--help)
      sed -n '2,80p' "$0"; exit 0 ;;
    *)
      ARGS+=("$1"); shift ;;
  esac
done
ARGS+=("$@")

# Expect: first non-flag is question (quoted), rest are URLs
if [[ ${#ARGS[@]} -lt 2 ]]; then
  echo "Usage: $0 [--debug] [-o OUT.md] [--no-cite] [--max-chars N] [--cache-dir DIR] \"<question>\" <url1> [url2 ...]" >&2
  exit 1
fi

QUESTION="${ARGS[0]}"
URLS=( "${ARGS[@]:1}" )
PYTHON="${PYTHON:-.venv/bin/python}"

# Ensure output directory exists if -o was provided
mkdir -p "$(dirname -- "${OUT:-out/.keep}")" 2>/dev/null || true

QUESTION="$QUESTION" MODE="$MODE" OUT="$OUT" NO_CITE="$NO_CITE" MAX_CHARS="$MAX_CHARS" CACHE_DIR="$CACHE_DIR" URLS="$(printf '%s\n' "${URLS[@]}")" "$PYTHON" - <<'PY'
import os, sys, json, re, html, requests, hashlib
from pathlib import Path
from dotenv import load_dotenv, find_dotenv
import trafilatura

# --- Encoding hygiene: keep UTF-8 output clean ---
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

# --- Config / env ---
env_path = find_dotenv(usecwd=True)
if env_path:
    load_dotenv(env_path)
else:
    dot = Path.cwd() / ".env"
    if dot.exists():
        load_dotenv(dot)

BASE     = os.getenv("BASE_URL", "http://localhost:11434/v1")
MODEL    = os.getenv("MODEL", "llama3.1:8b")
QUESTION = os.getenv("QUESTION", "Summarize.")
MODE     = os.getenv("MODE", "answer")
OUT      = os.getenv("OUT", "")
STRICT   = os.getenv("STRICT", "0") == "1"
NO_CITE  = os.getenv("NO_CITE", "0") == "1"
MAX_CHARS = int(os.getenv("MAX_CHARS", "5000"))
CACHE_DIR = os.getenv("CACHE_DIR", "").strip()

URLS = [u.strip() for u in os.getenv("URLS","").splitlines() if u.strip()]
UA = {"User-Agent": "AetherForge/0.1 (+WSL)"}

# --- Fetch & clean (with optional cache) ---
def cache_read(url: str) -> str | None:
    if not CACHE_DIR:
        return None
    h = hashlib.sha1(url.encode()).hexdigest()[:16]
    p = Path(CACHE_DIR) / f"{h}.html"
    if p.exists():
        try:
            return p.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            return None
    return None

def cache_write(url: str, text: str) -> None:
    if not CACHE_DIR:
        return
    Path(CACHE_DIR).mkdir(parents=True, exist_ok=True)
    h = hashlib.sha1(url.encode()).hexdigest()[:16]
    p = Path(CACHE_DIR) / f"{h}.html"
    try:
        p.write_text(text, encoding="utf-8")
    except Exception:
        pass

def html_title(s: str) -> str:
    m = re.search(r'<title[^>]*>(.*?)</title>', s, re.I | re.S)
    return html.unescape(m.group(1).strip()) if m else ""

def fetch_clean(url: str) -> dict:
    raw = cache_read(url)
    if raw is None:
        r = requests.get(url, timeout=45, headers=UA)
        r.raise_for_status()
        raw = r.text
        cache_write(url, raw)

    title, text = "", ""
    j = trafilatura.extract(
        raw, url=url, include_comments=False,
        output_format="json", with_metadata=True
    )
    if j:
        try:
            obj = json.loads(j)
            title = (obj.get("title") or "").strip()
            text  = (obj.get("text") or obj.get("raw_text") or "").strip()
        except Exception:
            pass
    if not title:
        title = html_title(raw) or url
    if not text:
        text = trafilatura.extract(raw, url=url, include_comments=False) or ""
    return {"url": url, "title": title, "text": (text or "")[:MAX_CHARS]}

docs = [fetch_clean(u) for u in URLS]

# --- Prompt building ---
index_lines = [f"[{i+1}] {d['title']} — {d['url']}" for i, d in enumerate(docs)]
sources_index = "\n".join(index_lines)
sources_block = "\n\n".join(
    f"[{i+1}] {d['title']}\nURL: {d['url']}\n\n{d['text']}"
    for i, d in enumerate(docs)
)

format_example_bullets = (
  "• A concise, specific point supported by the sources. [1]\n"
  "• Another clearly supported point (no fluff). [2]"
)

if NO_CITE:
    system = (
      "You are a careful research assistant. Use ONLY the provided sources.\n"
      "Write concise bullet points that directly answer the user's question. Do not include a 'Sources' section."
    )
else:
    system = (
      "You are a careful research assistant. Use ONLY the provided sources.\n"
      f"Valid source ids are 1..{len(docs)} (see SOURCES INDEX). Do NOT invent new ids.\n"
      "Write concise bullet points ONLY. End EACH bullet with bracketed id(s) for support—e.g., [1] or [1][3]. "
      "Bullets may end with punctuation after the brackets. If a claim isn't supported by the sources, omit it.\n"
      "Do NOT output a 'Sources:' section. Match this bullet format strictly:\n\n"
      + format_example_bullets
    )

user = (
  f"{QUESTION}\n\n"
  "== SOURCES INDEX ==\n"
  f"{sources_index}\n\n"
  "== SOURCES CONTENT ==\n"
  f"{sources_block}\n"
)

def call_llm(messages):
    payload = {
        "model": MODEL,
        "messages": messages,
        "max_tokens": 800,
        "temperature": 0.1 if not NO_CITE else 0.2,
        "top_p": 0.9
    }
    resp = requests.post(f"{BASE}/chat/completions", json=payload, timeout=180)
    resp.raise_for_status()
    return resp.json()

def strip_to_bullets(text: str) -> str:
    lines = text.splitlines()
    # Remove any "Sources:" the model tries to add anyway
    for i, ln in enumerate(lines):
        if ln.strip().lower().startswith("sources:"):
            lines = lines[:i]
            break
    bullets = [ln for ln in lines if ln.strip().startswith(('-', '*', '•'))]
    return "\n".join(bullets).strip()

def validate_bullets_with_cites(bullets: str) -> tuple[bool, str]:
    if not bullets:
        return False, "no bullet lines detected"
    valid_ids = {str(i) for i in range(1, len(docs)+1)}
    cited = {m.group(1) for m in re.finditer(r'\[(\d+)\]', bullets)}
    if not cited:
        return False, "no citations found in bullets"
    bad = sorted(cited - valid_ids)
    if bad:
        return False, f"unknown ids cited: {', '.join(bad)} (valid 1..{len(docs)})"
    # Each bullet must end with ...[n][m] optionally followed by punctuation
    tail_ok = all(re.search(r'\[(\d+)\](\[\d+\])*(?:\s*[.,;:?!])?$', ln.rstrip())
                  for ln in bullets.splitlines() if ln.strip())
    if not tail_ok:
        return False, "one or more bullets missing trailing [id] block"
    return True, ""

messages = [{"role":"system","content": system}, {"role":"user","content": user}]
data = call_llm(messages)

if MODE == "debug":
    print(json.dumps(data, indent=2))
    sys.exit(0)

content = (data.get("choices") or [{}])[0].get("message", {}).get("content", "")
if not content:
    print(json.dumps(data, indent=2))
    sys.exit(0)

bullets = strip_to_bullets(content)

if not NO_CITE:
    ok, why = validate_bullets_with_cites(bullets)
    if not ok:
        # Retry once with a sharp reminder + previous answer context
        reminder = (
          "Your previous attempt did not follow the bullet/citation format (" + why + "). "
          "Output ONLY bullet lines, each ending with bracketed id(s). Do NOT output a 'Sources:' section."
        )
        messages = [{"role":"system","content": system + "\n\n" + reminder},
                    {"role":"user","content": user},
                    {"role":"assistant","content": content},
                    {"role":"user","content":"Revise to comply exactly."}]
        data2 = call_llm(messages)
        content2 = (data2.get("choices") or [{}])[0].get("message", {}).get("content", "")
        if content2:
            bullets = strip_to_bullets(content2)
            ok, why = validate_bullets_with_cites(bullets)
        if not ok:
            msg = f"[warn] output still non-compliant: {why}"
            print(msg, file=sys.stderr)
            if STRICT:
                sys.exit(2)

final_text = bullets
# Append canonical Sources (we control this to avoid hallucinated lines)
final_text += "\n\nSources:\n" + sources_index

print(final_text)
if OUT:
    # Save a small heading + the content
    Path(OUT).write_text(final_text, encoding="utf-8")
PY
