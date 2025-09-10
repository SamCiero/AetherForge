# file: tests/test_clean_html.py
import textwrap
from aetherforge.tools.web import clean_html

def test_clean_html_extracts_title_and_text():
    html = textwrap.dedent("""
        <html>
          <head><title>Test Page</title></head>
          <body>
            <article>
              <h1>Hello World</h1>
              <p>This is a tiny sample paragraph used for testing.</p>
            </article>
          </body>
        </html>
    """)
    out = clean_html(html, url="https://example.com")
    assert "Test Page" in out["title"]
    assert "Hello World" in out["text"]
    assert "sample paragraph" in out["text"]
