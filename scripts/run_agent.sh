# file: scripts/run_agent.sh
#!/usr/bin/env bash
set -euo pipefail
VENV_PATH="${AF_VENV:-$HOME/.venvs/aetherforge}"
if [ -d "$VENV_PATH" ]; then
  . "$VENV_PATH/bin/activate"
elif [ -d ".venv" ]; then
  . ".venv/bin/activate"
fi
export PYTHONPATH=src
python -m aetherforge.main
