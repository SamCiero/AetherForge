# file: scripts/run_agent.sh
#!/usr/bin/env bash
set -euo pipefail
if [ -d ".venv" ]; then
  . .venv/bin/activate
fi
export PYTHONPATH=src
python -m aetherforge.main