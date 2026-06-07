#!/usr/bin/env bash
set -euo pipefail
OUTDIR="${1:-$HOME/proof-$(date +%Y%m%d)/vpu-inference}"
mkdir -p "$OUTDIR"
cd "$OUTDIR"
ffmpeg -hide_banner -y -f lavfi -i testsrc2=size=224x224:rate=30 -frames:v 30 -pix_fmt nv12 -c:v h264_v4l2m2m -b:v 1M input-hw-encoded.mp4 2>&1 | tee vpu-h264-encode.log
ffmpeg -hide_banner -y -c:v h264_v4l2m2m -i input-hw-encoded.mp4 -frames:v 30 -pix_fmt gray -f rawvideo decoded-gray.raw 2>&1 | tee vpu-h264-decode.log
python3 - <<'PY2' 2>&1 | tee vpu-frame-classifier.log
from pathlib import Path
import hashlib
w=h=224
buf=Path("decoded-gray.raw").read_bytes()
frames=len(buf)//(w*h)
assert frames==30, frames
means=[]
for i in range(frames):
    fr=buf[i*w*h:(i+1)*w*h]
    means.append(sum(fr)/len(fr))
first,last=means[0],means[-1]
trend="brighter" if last>first else "darker_or_equal"
q=[0,0,0,0]
fr=buf[-w*h:]
for y in range(h):
    for x in range(w):
        idx=(0 if y<h//2 else 2)+(0 if x<w//2 else 1)
        q[idx]+=fr[y*w+x]
cls=max(range(4), key=lambda i:q[i])
print(f"VPU_DECODED_FRAMES={frames}")
print(f"VPU_INFERENCE_MEAN_FIRST={first:.6f} LAST={last:.6f} TREND={trend}")
print(f"VPU_INFERENCE_BRIGHTEST_QUADRANT={cls} QUADRANT_SUMS={q}")
print("RAW_SHA256="+hashlib.sha256(buf).hexdigest())
PY2
sha256sum input-hw-encoded.mp4 decoded-gray.raw *.log | tee vpu-proof-sha256.txt
