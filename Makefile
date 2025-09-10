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
