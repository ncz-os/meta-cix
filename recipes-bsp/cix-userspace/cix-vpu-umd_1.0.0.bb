# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Cix Sky1 VPU user-mode driver / firmware.
# Provides codec firmware blobs (.fwb files) for hardware-accelerated
# H.264 / H.265 / AV1 / AVS2 / MPEG-4 / VP8 / VP9 / JPEG decode + encode,
# loaded by the in-kernel VPU module from /lib/firmware/. Consumed by
# cix-gstreamer plugins (cix-vaapi via libgstcixsr) in a later S6 slice.

require cix-userspace.inc

SUMMARY = "Cix Sky1 VPU user-mode driver and codec firmware"
DESCRIPTION = "Closed-source firmware blobs (.fwb) for the Cix Sky1 VPU hardware codec accelerator. Source from minisforum-cix-p1-repo/cix_proprietary__cix_proprietary cix_proprietary-debs/cix-vpu-umd subtree."

LICENSE_FLAGS = "commercial_cix-vpu-umd"
# No embedded copyright file in cix-vpu-umd; use the cix_proprietary
# umbrella copyright as the license-of-record.
LIC_FILES_CHKSUM = "file://../copyright/cix-gpu-umd/copyright;md5=401bdaa6e0af0aec53d7201e5d88f62f"

CIX_USERSPACE_COMPONENT = "cix-vpu-umd"

# .fwb codec firmware lands under /lib/firmware/ where the kernel VPU
# module loads it via request_firmware().
FILES:${PN} += " \
    ${nonarch_base_libdir}/firmware \
"
