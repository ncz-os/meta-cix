#!/usr/bin/env bash
set -euo pipefail
OUTDIR="${1:-$HOME/proof-$(date +%Y%m%d)/npu-vgg}"
MODEL_DIR="${CIX_NPU_MODEL_DIR:-/opt/ncz/models/cix-compute}"
LIBNOE_WHL="${CIX_LIBNOE_WHL:-/usr/share/cix/pypi/libnoe-2.0.0-py3-none-manylinux2014_aarch64.whl}"
mkdir -p "$OUTDIR"
cd "$MODEL_DIR"
uv run --python 3.11 --with numpy --with "$LIBNOE_WHL" python run_vgg_direct_once.py 2>&1 | tee "$OUTDIR/npu-vgg-inference.log"
cp "$MODEL_DIR/output-direct-lts-20260606.bin" "$OUTDIR/output-vgg.bin"
cd "$OUTDIR"
python3 - <<'PY2' 2>&1 | tee npu-vgg-classifier.log
from pathlib import Path
import hashlib
buf=Path("output-vgg.bin").read_bytes()
vals=list(buf[:1000])
top=sorted(range(len(vals)), key=lambda i: vals[i], reverse=True)[:5]
print(f"NPU_OUTPUT_BYTES={len(buf)}")
print("NPU_OUTPUT_SHA256="+hashlib.sha256(buf).hexdigest())
print(f"NPU_INFERENCE_TOP1={top[0]} SCORE={vals[top[0]]}")
print("NPU_INFERENCE_TOP5="+",".join(f"{i}:{vals[i]}" for i in top))
PY2
sha256sum output-vgg.bin *.log | tee npu-proof-sha256.txt
