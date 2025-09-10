# file: tests/test_summarize_urls.py
# -*- coding: utf-8 -*-
import os
import sys
import json
import re
import time
import socket
import threading
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse
from pathlib import Path

# Paths
REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts" / "summarize_urls.sh"


# ---- Tiny test HTTP server (docs + chat completions stub) ----
class _Handler(BaseHTTPRequestHandler):
    # We'll attach these on the server instance:
    #   self.server.mode = "good" | "bad"
    #   self.server.docs = {"/doc/a.html": "<html>..", "/doc/b.html": "<html>.."}
    def log_message(self, fmt, *args):  # silence test noise
        return

    def do_GET(self):
        path = urlparse(self.path).path
        if path in self.server.docs:
            body = self.server.docs[path].encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_error(404, "Not Found")

    def do_POST(self):
        path = urlparse(self.path).path
        if path == "/v1/chat/completions":
            # Read request (not used deeply; we stub a deterministic answer)
            length = int(self.headers.get("Content-Length", "0"))
            _ = self.rfile.read(length)

            if self.server.mode == "good":
                # Two bullet lines with correct bracketed ids [1] and [2]
                content = "• Alpha point supported by doc A. [1]\n• Beta point supported by doc B. [2]"
            else:
                # Bad: one bullet missing id, one with invalid id
                content = "• Alpha point with no cite.\n• Beta point with wrong id. [9]"

            data = {
                "id": "chatcmpl-test",
                "object": "chat.completion",
                "created": int(time.time()),
                "model": "stub-model",
                "system_fingerprint": "fp_test",
                "choices": [
                    {"index": 0, "message": {"role": "assistant", "content": content}, "finish_reason": "stop"}
                ],
                "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
            }
            payload = json.dumps(data).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return

        self.send_error(404, "Not Found")


class StubServer:
    def __init__(self, mode="good"):
        self.mode = mode
        self.thread = None
        self.httpd = None
        self.port = None

    def __enter__(self):
        # Bind to an ephemeral port on localhost
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.bind(("127.0.0.1", 0))
        addr, self.port = sock.getsockname()
        sock.close()

        self.httpd = HTTPServer(("127.0.0.1", self.port), _Handler)
        # Attach server state
        self.httpd.mode = self.mode
        self.httpd.docs = {
            "/doc/a.html": """
                <html><head><title>Alpha Doc</title></head>
                <body><article><h1>A</h1><p>Alpha content.</p></article></body></html>
            """,
            "/doc/b.html": """
                <html><head><title>Beta Doc</title></head>
                <body><article><h1>B</h1><p>Beta content.</p></article></body></html>
            """,
        }
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()
        return self

    def __exit__(self, exc_type, exc, tb):
        if self.httpd:
            self.httpd.shutdown()
            self.httpd.server_close()
        if self.thread:
            self.thread.join(timeout=2)


# ---- Helpers ----
def _run_script(question, urls, base_url, strict=False):
    """Run scripts/summarize_urls.sh with a stub BASE_URL and return (rc, stdout, stderr)."""
    env = os.environ.copy()
    env["BASE_URL"] = f"http://127.0.0.1:{base_url}/v1"
    env["MODEL"] = "stub-model"
    env["PYTHON"] = sys.executable  # force using current interpreter
    env["LANG"] = "en_US.UTF-8"
    env.pop("LC_ALL", None)  # avoid locale override in CI
    if strict:
        env["STRICT"] = "1"

    cmd = ["bash", str(SCRIPT), question] + urls
    proc = subprocess.run(cmd, capture_output=True, text=True, env=env, cwd=str(REPO_ROOT), timeout=20)
    return proc.returncode, proc.stdout.strip(), proc.stderr.strip()


# ---- Tests ----
def test_summarize_urls_happy_path():
    """Bullets with [ids] + Sources appended exactly mapping to provided URLs."""
    with StubServer(mode="good") as srv:
        q = "Give me two supported points."
        url1 = f"http://127.0.0.1:{srv.port}/doc/a.html"
        url2 = f"http://127.0.0.1:{srv.port}/doc/b.html"
        rc, out, err = _run_script(q, [url1, url2], srv.port, strict=True)

    assert rc == 0, f"non-zero exit: {rc}, stderr={err}"
    # Bullets present and end with [1] and [2]
    lines = [ln for ln in out.splitlines() if ln.strip()]
    bullet_lines = [ln for ln in lines if ln.strip().startswith(("•", "-", "*"))]
    assert any(ln.rstrip().endswith("[1]") or ln.rstrip().endswith("[1].") for ln in bullet_lines)
    assert any(ln.rstrip().endswith("[2]") or ln.rstrip().endswith("[2].") for ln in bullet_lines)

    # Sources block appended by the script (not by model)
    assert "\nSources:\n" in out
    # Match by id + em dash + exact URL, ignore variable title content
    assert re.search(rf'^\[1\]\s+.+\s—\s{re.escape(url1)}$', out, re.M), out
    assert re.search(rf'^\[2\]\s+.+\s—\s{re.escape(url2)}$', out, re.M), out


def test_summarize_urls_strict_fails_on_bad_citations():
    """STRICT=1 should fail if bullets lack proper trailing [ids] or cite unknown ids."""
    with StubServer(mode="bad") as srv:
        q = "Give me points."
        url1 = f"http://127.0.0.1:{srv.port}/doc/a.html"
        url2 = f"http://127.0.0.1:{srv.port}/doc/b.html"
        rc, out, err = _run_script(q, [url1, url2], srv.port, strict=True)

    assert rc == 2, f"expected STRICT failure (2), got {rc}. stdout={out} stderr={err}"
    assert "non-compliant" in err or "unknown ids" in err or "missing trailing" in err
