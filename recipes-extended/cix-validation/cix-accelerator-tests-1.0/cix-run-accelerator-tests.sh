#!/usr/bin/env bash
set -euo pipefail
BASE="${1:-$HOME/proof-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$BASE"
cix-gpu-vulkan-mlp-test "$BASE/gpu-vulkan-mlp"
cix-vpu-h264-inference-test "$BASE/vpu-inference"
cix-npu-vgg-inference-test "$BASE/npu-vgg"
find "$BASE" -maxdepth 3 -type f -print | sort | tee "$BASE/manifest.txt"
