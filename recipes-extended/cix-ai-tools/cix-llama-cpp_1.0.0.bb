# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Cix Sky1 NPU-accelerated llama.cpp suite.
#
# Ships 8 binaries under /usr/share/cix/bin/:
#   - llama-server      (HTTP API server — the headline; what
#                        zeroclaw / openclaw / hermes call into)
#   - llama-cli         (interactive CLI)
#   - llama-bench       (perf benchmarking)
#   - llama-perplexity  (eval)
#   - llama-quantize    (model quantization)
#   - llama-llava-cli   (LLaVA multimodal)
#   - llama-minicpmv-cli (MiniCPM-V multimodal)
#   - llama-qwen2vl-cli (Qwen2-VL multimodal)
#
# Underlying llama.cpp is upstream OSS (MIT). Cix's distribution
# wraps it with NPU acceleration via the NoE runtime; the binary
# is closed-source and licensed under Cix's EULA — operators
# accept commercial_cix-llama-cpp via LICENSE_FLAGS_ACCEPTED.

require cix-ai-tools.inc

SUMMARY = "Cix Sky1 NPU-accelerated llama.cpp suite (llama-server, llama-cli, etc.)"
DESCRIPTION = "Closed-source pre-built llama.cpp suite with NPU acceleration via Cix's NoE runtime. Source from minisforum-cix-p1-repo/ext_debs cix-llama-cpp_1.0.0_arm64 subtree. Headline differentiator for cixmini fleet — zeroclaw/openclaw/hermes call llama-server for local NPU-accelerated inference (~45 TOPS on Sky1)."

LICENSE_FLAGS = "commercial_cix-llama-cpp"

CIX_AI_COMPONENT = "cix-llama-cpp_1.0.0_arm64"

FILES:${PN} += " \
    ${datadir}/cix \
"

# llama-server uses the Cix NoE runtime via dlopen at runtime (not
# linked at build time per readelf inspection on the synced binary).
# RDEPENDS on cix-noe-umd ensures /usr/share/cix/lib/libnoe.so is
# present when llama-server starts. Without it, llama-server falls
# back to CPU-only mode (loses the NPU acceleration that's the
# whole point of using cix-llama-cpp instead of upstream llama.cpp).
RDEPENDS:${PN} += "cix-noe-umd"
