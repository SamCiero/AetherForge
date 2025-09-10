# file: tests/test_cache_ttl.py
import time
from aetherforge.tools.web import cache_clear, cache_get, cache_put, is_fresh

def test_cache_roundtrip_and_freshness():
    cache_clear()
    url = "https://example.com/page"
    now = int(time.time())
    cache_put(url, {
        "fetched_at": now,
        "status": 200,
        "title": "Example",
        "text": "Hello cache",
        "meta": {"k": "v"},
    })
    row = cache_get(url)
    assert row is not None
    assert row["title"] == "Example"
    assert row["text"] == "Hello cache"
    # freshness
    assert is_fresh(now, max_age_sec=5)
    assert not is_fresh(now - 10, max_age_sec=5)
