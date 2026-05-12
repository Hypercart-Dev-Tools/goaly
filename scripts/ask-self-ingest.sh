#!/bin/bash
set -euo pipefail

ASK_SELF_PATH="${ASK_SELF_PATH:-/Users/noelsaw/Documents/GH Repos/ask-self}"

if [ ! -d "$ASK_SELF_PATH" ]; then
  echo "Error: ask-self not found at $ASK_SELF_PATH. Set ASK_SELF_PATH."
  exit 1
fi

PYTHON_BIN="python3"
if [ -n "${ASK_SELF_PYTHON:-}" ]; then
    PYTHON_BIN="$ASK_SELF_PYTHON"
elif [ -f "$ASK_SELF_PATH/.venv/bin/python" ]; then
    PYTHON_BIN="$ASK_SELF_PATH/.venv/bin/python"
fi

exec "$PYTHON_BIN" "$ASK_SELF_PATH/ask_self_ingest.py" \
  --harness-config "ask_self/ask_self_harness.json" \
  "$@"
