#!/usr/bin/env bash
# Called from Windows by `v2m run` (wsl --exec): run_wsl.sh <video> <out_dir> [runner args...]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/env.sh"
cd "$GEMX_DIR"
exec .venv/bin/python "$HERE/v2m_gemx_runner.py" --video "$1" --out "$2" "${@:3}"
