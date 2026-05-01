# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Cix Sky1 NPU NoE user-mode driver — the headline NPU userspace.
# 45 TOPS NPU acceleration consumed by cix-llama-cpp, cix-whisper-cpp,
# cix-mnn, cix-npu-onnxruntime in subsequent S5 recipes.
#
# Ships libnoe.so + Python 3.11/3.12 bindings (libnoe.cpython-3{11,12}-
# aarch64-linux-gnu.so) + the cix_noe_standard_api.h header + a pkg-config
# .pc file. Tiny package (8 files) but load-bearing for the entire
# AI-acceleration stack on cixmini.

require cix-userspace.inc

SUMMARY = "Cix Sky1 NPU NoE user-mode driver"
DESCRIPTION = "Closed-source NPU User-Mode Driver for the Cix Sky1 NoE (Neural Optimization Engine) — 45 TOPS NPU acceleration. Source from minisforum-cix-p1-repo/cix_proprietary__cix_proprietary cix_proprietary-debs/cix-noe-umd subtree."

LICENSE_FLAGS = "commercial_cix-noe-umd"
# cix-noe-umd has no embedded copyright file; use the cix_proprietary
# umbrella copyright (cix-gpu-umd's, broadest in the tree) as the
# license-of-record for the LIC_FILES_CHKSUM gate.
LIC_FILES_CHKSUM = "file://../copyright/cix-gpu-umd/copyright;md5=401bdaa6e0af0aec53d7201e5d88f62f"

CIX_USERSPACE_COMPONENT = "cix-noe-umd"

# Python bindings ship under /usr/lib/python3/dist-packages/. Yocto's
# python3 packaging convention places these under PN-python3 or via the
# python3-* split; we keep them in ${PN} since they're tightly coupled
# to libnoe.so and not separately consumable.
FILES:${PN} += " \
    ${libdir}/python3/dist-packages \
    ${libdir}/aarch64-linux-gnu/pkgconfig \
"

# libnoe.so consumers will need python3 at runtime if they import the
# Python bindings. Hard RDEPENDS would force python3 into all images
# that include the C library; instead, RRECOMMENDS it so an image-author
# choosing only the C path doesn't drag python3 along.
RRECOMMENDS:${PN} += "python3-core"
