# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Cix Sky1 Mesa runtime.
#
# Ships the Mesa OpenGL/Vulkan userspace runtime from Minisforum's
# ext_debs payload. cix-mnn uses this at runtime for OpenCL/Vulkan
# backend initialization alongside cix-gpu-umd's Mali userspace driver.

require cix-ai-tools.inc

SUMMARY = "Cix Sky1 Mesa OpenGL/Vulkan userspace runtime"
DESCRIPTION = "Closed-source pre-built Mesa 24.0.4 runtime for Cix Sky1. Source from minisforum-cix-p1-repo/ext_debs cix-mesa_24.0.4_arm64 subtree. Provides OpenGL/Vulkan userspace pieces needed by accelerated consumers such as cix-mnn."

LICENSE_FLAGS = "commercial_cix-mesa"
LIC_FILES_CHKSUM = "file://${WORKDIR}/cixprop/cix_proprietary-debs/copyright/cix-gpu-umd/copyright;md5=401bdaa6e0af0aec53d7201e5d88f62f"

CIX_AI_COMPONENT = "cix-mesa_24.0.4_arm64"

FILES:${PN} += " \
    ${libdir}/aarch64-linux-gnu \
    ${datadir}/drirc.d \
    ${datadir}/glvnd \
    ${datadir}/vulkan \
"
