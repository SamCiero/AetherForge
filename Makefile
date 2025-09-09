# file: Makefile
VENV=.venv
PY=$(VENV)/bin/python
PIP=$(VENV)/bin/pip

bootstrap:
	python -m venv $(VENV)
	. $(VENV)/bin/activate; $(PIP) -U pip
	. $(VENV)/bin/activate; $(PIP) install -r requirements.txt -r requirements-dev.txt

dev:
	. $(VENV)/bin/activate; export PYTHONPATH=src; $(PY) -m aetherforge.main

lint:
	. $(VENV)/bin/activate; ruff check src

test:
	. $(VENV)/bin/activate; pytest -q