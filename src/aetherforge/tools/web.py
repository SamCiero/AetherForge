# file: src/aetherforge/tools/web.py
"""
Simple web utilities for AetherForge:
- clean_html(html, url=None) -> {title, text}
- fetch_url(url, *, timeout=15, use_cache=True, max_age_sec=86400) -> {url, status, title, text, fetched_at}
- cache_get(url), cache_put(url, data), cache_clear()
- web_search(query) -> demo stub returning high-signal sources

Note: fetch_url does real HTTP; unit tests should target clean_html() and cache_* helpers to stay offline.
"""
from __future__ import annotations

import json
import sqlite3
import time
from pathlib import Path
from typing import Any, Dict, Optional

import requests
import trafilatura

# ---------- Cache (SQLite in .cache/) ----------
CACHE_DIR = Path(".cache")
CACHE_DB = CACHE_DIR / "aetherforge_cache.sqlite"


def _db() -> sqlite3.Connection:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(CACHE_DB)
    con.execute(
        """
        CREATE TABLE IF NOT EXISTS cached_pages (
            url TEXT PRIMARY KEY,
            fetched_at INTEGER NOT NULL,
            status INTEGER NOT NULL,
            title TEXT,
            text TEXT,
            meta_json TEXT
        )
        """
    )
    return con


def cache_get(url: str) -> Optional[Dict[str, Any]]:
    con = _db()
    cur = con.execute(
        "SELECT url, fetched_at, status, title, text, meta_json FROM cached_pages WHERE url=?",
        (url,),
    )
    row = cur.fetchone()
    if not row:
        return None
    meta = json.loads(row[5]) if row[5] else {}
    return {
        "url": row[0],
        "fetched_at": row[1],
        "status": row[2],
        "title": row[3] or "",
        "text": row[4] or "",
        "meta": meta,
    }


def cache_put(url: str, data: Dict[str, Any]) -> None:
    con = _db()
    con.execute(
        "INSERT OR REPLACE INTO cached_pages(url, fetched_at, status, title, text, meta_json) VALUES (?,?,?,?,?,?)",
        (
            url,
            int(data.get("fetched_at", time.time())),
            int(data.get("status", 200)),
            data.get("title", "")[:512],
            data.get("text", ""),
            json.dumps(data.get("meta", {})) if data.get("meta") else None,
        ),
    )
    con.commit()


def cache_clear() -> None:
    if CACHE_DB.exists():
        CACHE_DB.unlink()


def is_fresh(fetched_at: int, max_age_sec: int) -> bool:
    return (time.time() - fetched_at) < max_age_sec


# ---------- HTML cleaning ----------
def clean_html(html: str, url: Optional[str] = None) -> Dict[str, str]:
    """
    Convert raw HTML into (title, text) using trafilatura.
    Works offline if you pass sample HTML; perfect for unit tests.
    """
    # Title: try trafilatura first, then <title> fallback
    title = trafilatura.extract_title(html) or ""
    if not title:
        # lightweight fallback
        start = html.find("<title>")
        end = html.find("</title>")
        if 0 <= start < end:
            title = html[start + 7 : end].strip()

    text = trafilatura.extract(html, url=url) or ""
    return {"title": title.strip(), "text": text.strip()}


# ---------- Fetcher ----------
_UA = "AetherForge/0.1 (+local; https://github.com/your-user/AetherForge)"


def fetch_url(
    url: str,
    *,
    timeout: int = 15,
    use_cache: bool = True,
    max_age_sec: int = 24 * 3600,
) -> Dict[str, Any]:
    """
    Fetch a URL and return cleaned text with basic caching.
    Returns: {url, status, title, text, fetched_at}
    """
    if use_cache:
        cached = cache_get(url)
        if cached and is_fresh(cached["fetched_at"], max_age_sec):
            return cached

    try:
        r = requests.get(url, timeout=timeout, headers={"User-Agent": _UA})
        status = r.status_code
        cleaned = clean_html(r.text, url=url)
        data = {
            "url": url,
            "status": status,
            "title": cleaned.get("title", ""),
            "text": cleaned.get("text", ""),
            "fetched_at": int(time.time()),
            "meta": {"headers": dict(r.headers)},
        }
        if use_cache and status == 200 and data["text"]:
            cache_put(url, data)
        return data
    except Exception as e:
        return {
            "url": url,
            "status": 0,
            "title": "",
            "text": "",
            "fetched_at": int(time.time()),
            "meta": {"error": str(e)},
        }


# ---------- Demo search stub ----------
def web_search(query: str) -> list[dict]:
    """
    Minimal, ToS-friendly demo. Replace later with Brave/Serper/Tavily.
    """
    from urllib.parse import quote_plus

    return [
        {
            "title": "Wikipedia search",
            "url": f"https://en.wikipedia.org/w/index.php?search={quote_plus(query)}",
        },
        {
            "title": "Hacker News (Algolia) search",
            "url": f"https://hn.algolia.com/?q={quote_plus(query)}",
        },
    ]