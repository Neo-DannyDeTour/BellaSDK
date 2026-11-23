# Source before running GEM-X or the v2m runner:  source backends/gemx/env.sh
export PATH="$HOME/.local/bin:$PATH"
export PYOPENGL_PLATFORM=osmesa
export LD_LIBRARY_PATH="$HOME/v2m/syslibs/root/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"
export GEMX_DIR="${GEMX_DIR:-$HOME/v2m/GEM-X}"
