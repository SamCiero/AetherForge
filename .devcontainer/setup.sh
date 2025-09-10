# file: .devcontainer/setup.sh
#!/usr/bin/env bash
set -euo pipefail
cd /workspaces/AetherForge
python -m venv .venv
. .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt -r requirements-dev.txt
echo "[setup] venv ready at $(which python)"