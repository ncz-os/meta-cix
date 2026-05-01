# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Cix Sky1 MNN (Mobile Neural Network) framework.
#
# Ships:
#   /usr/share/cix/bin/mnn/llm_demo       — LLM inference demo
#   /usr/share/cix/bin/mnn/diffusion_demo — image-diffusion demo
#   /usr/share/cix/lib/libMNN.so          — core MNN runtime
#   /usr/share/cix/lib/libMNN_CL.so       — OpenCL backend
#   /usr/share/cix/lib/libMNN_Vulkan.so   — Vulkan backend
#   /usr/share/cix/lib/libMNN_Express.so  — graph-mode high-level API
#   /usr/share/cix/lib/libMNNOpenCV.so    — OpenCV-MNN bridge
#   /usr/share/cix/lib/libllm.so          — MNN-LLM glue
#   /usr/share/cix/lib/libdiffusion.so    — diffusion glue
#
# Underlying MNN is upstream OSS (Apache 2.0, Alibaba). Cix's
# distribution adds OpenCL + Vulkan backends for Sky1 + EULA wrapper.

require cix-ai-tools.inc

SUMMARY = "Cix Sky1 MNN (Mobile Neural Network) framework with OpenCL+Vulkan backends"
DESCRIPTION = "Closed-source pre-built MNN runtime + LLM/diffusion demos for Cix Sky1. Source from minisforum-cix-p1-repo/ext_debs cix-mnn_1.0.0_arm64 subtree. Provides an alternative inference path to llama.cpp — useful for vision/diffusion workloads cix-llama-cpp doesn't cover."

LICENSE_FLAGS = "commercial_cix-mnn"

CIX_AI_COMPONENT = "cix-mnn_1.0.0_arm64"

FILES:${PN} += " \
    ${datadir}/cix \
"

# MNN with the Vulkan and OpenCL backends needs cix-mesa's
# OpenGL/Vulkan runtime plus cix-gpu-umd's userspace driver to
# talk to the Mali GPU. Without those, libMNN_CL.so and
# libMNN_Vulkan.so load but their backends fail at init and MNN
# falls back to CPU.
RDEPENDS:${PN} += "cix-gpu-umd"
RDEPENDS:${PN} += "cix-mesa"

# Demos under bin/mnn/ are operator-side example apps; not auto-run
# at boot. Mark as RRECOMMENDS for the framework so an image author
# choosing MNN gets the demos for testing without forcing them on
# minimal images.
