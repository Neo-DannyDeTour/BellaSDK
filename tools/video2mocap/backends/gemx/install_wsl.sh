#!/usr/bin/env bash
# Installs the NVIDIA GEM-X backend inside WSL2/Linux, user-space only (no sudo, no compiler).
# GEM-X: Apache-2.0 code, NVIDIA Open Model License weights (commercial use allowed).
# We use GEM-X's ONNX pipeline (demo_soma_onnx.py), which does not need detectron2,
# so no C++/CUDA toolchain is required.
#
# Usage:  bash backends/gemx/install_wsl.sh [install_dir]   (default: ~/v2m/GEM-X)
set -euo pipefail

INSTALL_DIR="${1:-$HOME/v2m/GEM-X}"
GEMX_REF="${GEMX_REF:-main}"
BIN="$HOME/.local/bin"
mkdir -p "$BIN"
export PATH="$BIN:$PATH"

need() { command -v "$1" >/dev/null 2>&1; }

# GEM-X declares one submodule with an SSH url; force HTTPS for this process only (no global config
# change) and never block on an interactive prompt.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.https://github.com/.insteadOf" GIT_CONFIG_VALUE_0="git@github.com:"
export GIT_TERMINAL_PROMPT=0

if ! need uv; then
  echo "[v2m] installing uv"
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi

if ! need git-lfs; then
  echo "[v2m] installing git-lfs (static binary)"
  tmp="$(mktemp -d)"
  ver="3.5.1"
  curl -LsSf "https://github.com/git-lfs/git-lfs/releases/download/v${ver}/git-lfs-linux-amd64-v${ver}.tar.gz" -o "$tmp/lfs.tgz"
  tar -xzf "$tmp/lfs.tgz" -C "$tmp"
  cp "$tmp"/git-lfs-*/git-lfs "$BIN/"
  git lfs install --skip-repo
fi

if ! need ffmpeg; then
  echo "[v2m] installing ffmpeg (static build)"
  tmp="$(mktemp -d)"
  curl -LsSf "https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz" -o "$tmp/ff.tar.xz"
  tar -xJf "$tmp/ff.tar.xz" -C "$tmp"
  cp "$tmp"/ffmpeg-*-static/ffmpeg "$tmp"/ffmpeg-*-static/ffprobe "$BIN/"
fi

mkdir -p "$(dirname "$INSTALL_DIR")"
if [ ! -d "$INSTALL_DIR/.git" ]; then
  git clone --recursive https://github.com/NVlabs/GEM-X.git "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"
git fetch --all -q && git checkout -q "$GEMX_REF"
# --force: an interrupted clone can leave a submodule folder with only its .git file
git submodule update --init --recursive --force
[ -d third_party/sam-3d-body/sam_3d_body ] || { echo "[v2m] ERROR: sam-3d-body submodule is empty"; exit 1; }
git rev-parse HEAD > .v2m_commit

echo "[v2m] user-space system libraries (libusb for open3d, OSMesa for offscreen rendering)"
SYSLIBS="$HOME/v2m/syslibs"
if [ ! -f "$SYSLIBS/root/usr/lib/x86_64-linux-gnu/libusb-1.0.so.0" ]; then
  mkdir -p "$SYSLIBS/debs" && (cd "$SYSLIBS/debs" && apt-get download libusb-1.0-0 libosmesa6 libllvm19 libglapi-mesa)
  for d in "$SYSLIBS"/debs/*.deb; do dpkg -x "$d" "$SYSLIBS/root"; done
fi

echo "[v2m] python env"
[ -d .venv ] || uv venv .venv --python 3.12
# shellcheck disable=SC1091
source .venv/bin/activate
uv pip install torch torchvision --index-url https://download.pytorch.org/whl/cu126
uv pip install -e third_party/soma
(cd third_party/soma && git lfs pull)
# Without inputs/soma_assets, SOMA downloads the LATEST assets from HuggingFace (nvidia/soma-x@main),
# whose format can be newer than the SOMA code pinned by GEM-X ("joint_parent_ids is not a file in the
# archive"). Use the assets that ship with the pinned submodule instead.
mkdir -p inputs && ln -sfn "$PWD/third_party/soma/assets" inputs/soma_assets
uv pip install -e .
uv pip install cloudpickle fvcore iopath pycocotools braceexpand roma 'setuptools<75'
# onnxruntime-gpu >= 1.24 targets CUDA 13; 1.23.x matches the cu126 torch wheels (cuBLAS 12, cuDNN 9)
uv pip install "onnxruntime-gpu==1.23.2"
# `pip install -e .` may pull a newer torch from PyPI that no longer matches torchvision
# ("operator torchvision::nms does not exist"): pin the pair GEM-X's requirements.txt was built with.
uv pip install --reinstall "torch==2.10.0" "torchvision==0.25.0" --index-url https://download.pytorch.org/whl/cu126

python - <<'EOF'
import torch, onnxruntime as ort
print("[v2m] torch", torch.__version__, "cuda", torch.cuda.is_available(),
      torch.cuda.get_device_name(0) if torch.cuda.is_available() else "")
print("[v2m] onnxruntime providers", ort.get_available_providers())
EOF
echo "[v2m] GEM-X installed at $INSTALL_DIR (commit $(cat .v2m_commit))"
