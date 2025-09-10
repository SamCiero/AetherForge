# file: Makefile
PYTHON ?= python3
VENV ?= .venv
PY   = $(VENV)/bin/python
PIP  = $(PY) -m pip

.PHONY: bootstrap dev lint test detect-host summarize

bootstrap:
	$(PYTHON) -m venv $(VENV)
	$(PIP) install -U pip
	$(PIP) install -r requirements.txt -r requirements-dev.txt

dev:
	PYTHONPATH=src $(PY) -m aetherforge.main

lint:
	PYTHONPATH=src $(PY) -m ruff check src tests

test:
	PYTHONPATH=src $(PY) -m pytest -q

detect-host:
	@set -e; \
	if curl -fsS http://localhost:11434/v1/models >/dev/null 2>&1; then \
	  URL=http://localhost:11434/v1; \
	elif WINHOST=$$(ip route | awk '/^default/ {print $$3; exit}'); \
	     curl -fsS "http://$$WINHOST:11434/v1/models" >/dev/null 2>&1; then \
	  URL=http://$$WINHOST:11434/v1; \
	else \
	  echo "No reachable Ollama at localhost or WSL gateway." >&2; exit 1; \
	fi; \
	[ -f .env ] || cp .env.example .env; \
	sed -i "s|^BASE_URL=.*|BASE_URL=$$URL|" .env; \
	if [ "$(DEBUG)" = "1" ]; then echo "Set BASE_URL=$$URL"; fi

# Usage:
#   make summarize Q="What's new in Python 3.13?" URLS="https://docs.python.org/3.13/whatsnew/3.13.html"
#   make summarize Q="..." URLS="url1 url2" OUT=out/file.md
#   make summarize DEBUG=1 Q="..." URLS="..."          # shows extra logs
summarize: detect-host
	@set -e; \
	[ -n "$(URLS)" ] || { echo "ERROR: set URLS=\"<url1> [url2 ...]\"" >&2; exit 2; }; \
	FLAGS=""; \
	[ "$(DEBUG)" = "1" ] && FLAGS="$$FLAGS --debug"; \
	[ -n "$(OUT)" ] && FLAGS="$$FLAGS -o $(OUT)"; \
	if [ "$(DEBUG)" = "1" ]; then \
	  echo "→ scripts/summarize_urls.sh $$FLAGS \"$(Q)\" $(URLS)"; \
	else \
	  printf "\n"; \
	fi; \
	scripts/summarize_urls.sh $$FLAGS "$(Q)" $(URLS)
