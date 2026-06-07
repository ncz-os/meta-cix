#!/usr/bin/env bash
set -euo pipefail
OUTDIR="/home/jasonperlow/proof-20260607/npu-benchmark"
ITERS="1000"
WARMUP="50"
MODEL_DIR="/opt/ncz/models/cix-compute"
LIBNOE_WHL="/usr/share/cix/pypi/libnoe-2.0.0-py3-none-manylinux2014_aarch64.whl"
mkdir -p ""
cd ""
cat > npu_sustained_bench.py <<PY
import sys, time, json, statistics, hashlib
from pathlib import Path
MODEL_DIR=Path(__import__(os).environ.get(MODEL_DIR,/opt/ncz/models/cix-compute))
sys.path.insert(0, str(MODEL_DIR))
from libnoe import *
MODEL=str(MODEL_DIR/vgg.cix); INPUT=str(MODEL_DIR/datasets/input.bin); GRAPH=str(MODEL_DIR/graph.json)
ITERS=int(sys.argv[1]) if len(sys.argv)>1 else 1000; WARMUP=int(sys.argv[2]) if len(sys.argv)>2 else 50
def data(x): return x[1] if isinstance(x, tuple) and len(x)>1 else None
def ok(x): return x == 0 or str(x) in (0,noe_status_t.NOE_STATUS_SUCCESS)
def graph_ops():
    obj=json.load(open(GRAPH)); vals=[]
    def walk(x):
        if isinstance(x,dict):
            ops=x.get(ops_count); name=x.get(layer node name)
            if isinstance(ops,(int,float)) and ops and name: vals.append((name,int(ops)))
            for v in x.values(): walk(v)
        elif isinstance(x,list):
            for v in x: walk(v)
    walk(obj); uniq={}
    for n,o in vals: uniq.setdefault(n,o)
    return sum(uniq.values()), sum(o for _,o in vals), len(uniq), len(vals)
ops_unique, ops_all, uniq_n, entry_n = graph_ops()
n=NPU(); t0=time.perf_counter(); r=n.noe_init_context(); assert ok(r), r; t_init=time.perf_counter()-t0
t0=time.perf_counter(); lg=n.noe_load_graph(MODEL); assert ok(lg[0]), lg; gid=data(lg); t_load=time.perf_counter()-t0
cfg=noe_create_job_cfg_t(); cfg.partition_id=0; cfg.dbg_dispatch=0; cfg.dbg_core_id=0; cfg.qos_level=0; cfg.fm_idxes=[]
t0=time.perf_counter(); cj=n.noe_create_job(gid,cfg); assert ok(cj[0]), cj; jid=data(cj); t_job=time.perf_counter()-t0
t0=time.perf_counter(); r=n.noe_load_tensor_from_file(jid,0,INPUT); assert ok(r), r; t_tensor=time.perf_counter()-t0
for i in range(WARMUP):
    r=n.noe_job_infer_sync(jid,5000)
    if not ok(r): raise RuntimeError((warmup,i,r))
times=[]; t_start=time.perf_counter()
for i in range(ITERS):
    a=time.perf_counter(); r=n.noe_job_infer_sync(jid,5000); b=time.perf_counter()
    if not ok(r): raise RuntimeError((iter,i,r))
    times.append(b-a)
t_total=time.perf_counter()-t_start; p95=sorted(times)[int(0.95*len(times))-1]
gt=n.noe_get_tensor(jid,NOE_TENSOR_TYPE_OUTPUT,0); out=data(gt) if isinstance(gt, tuple) else None
out_bytes=bytes(out) if out is not None and not isinstance(out, bytes) else (out or b)
print(NPU_GRAPH_OPS_UNIQUE, ops_unique, OPS_ALL, ops_all, UNIQUE_NAMES, uniq_n, ENTRIES, entry_n)
print(NPU_SETUP_SECONDS init={:.6f} load_graph={:.6f} create_job={:.6f} load_tensor={:.6f}.format(t_init,t_load,t_job,t_tensor))
print(NPU_BENCH_ITERS, ITERS, WARMUP, WARMUP)
print(NPU_LATENCY_MS min={:.6f} p50={:.6f} mean={:.6f} p95={:.6f} max={:.6f}.format(min(times)*1000, statistics.median(times)*1000, statistics.mean(times)*1000, p95*1000, max(times)*1000))
print(NPU_TOTAL_SECONDS, {:.6f}.format(t_total), FPS, {:.3f}.format(ITERS/t_total))
print(NPU_EFFECTIVE_TOPS_UNIQUE mean={:.3f} p50={:.3f} throughput={:.3f}.format(ops_unique/statistics.mean(times)/1e12, ops_unique/statistics.median(times)/1e12, ops_unique*ITERS/t_total/1e12))
print(NPU_EFFECTIVE_TOPS_ALL mean={:.3f} p50={:.3f} throughput={:.3f}.format(ops_all/statistics.mean(times)/1e12, ops_all/statistics.median(times)/1e12, ops_all*ITERS/t_total/1e12))
print(NPU_OUTPUT_SHA256, hashlib.sha256(out_bytes).hexdigest() if out_bytes else NO_OUTPUT_BYTES, BYTES, len(out_bytes))
print(NPU_CLEAN, n.noe_clean_job(jid), n.noe_unload_graph(gid), n.noe_deinit_context())
PY
MODEL_DIR="" uv run --python 3.11 --with numpy --with "" python npu_sustained_bench.py "" "" 2>&1 | tee npu-sustained-.log
sha256sum npu_sustained_bench.py npu-sustained-.log | tee npu-benchmark-sha256.txt
