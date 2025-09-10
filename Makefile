# file: Makefile
VENV ?= $(HOME)/.venvs/aetherforge
PY   = $(VENV)/bin/python
PIP  = $(PY) -m pip

bootstrap:
	python -m venv $(VENV)
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
	sed -i "s|^BASE_URL=.*|BASE_URL=$$URL|" .env; \
	echo "Set BASE_URL=$$URL"
