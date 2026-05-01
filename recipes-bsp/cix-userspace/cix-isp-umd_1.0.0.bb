# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Cix Sky1 ISP user-mode tools.
# Camera / Image Signal Processor userspace utilities and configuration
# files (cal/tun/sh test scripts, NV12 pipeline configs, AI-demo Python).
# Most of this is operator-/integrator-side tooling for camera bring-up
# rather than rootfs-required runtime.

require cix-userspace.inc

SUMMARY = "Cix Sky1 ISP user-mode tools and configs"
DESCRIPTION = "Closed-source ISP utilities, calibration files, and demo scripts for the Cix Sky1 camera pipeline. Source from minisforum-cix-p1-repo/cix_proprietary__cix_proprietary cix_proprietary-debs/cix-isp-umd subtree."

LICENSE_FLAGS = "commercial_cix-isp-umd"
LIC_FILES_CHKSUM = "file://../copyright/cix-gpu-umd/copyright;md5=401bdaa6e0af0aec53d7201e5d88f62f"

CIX_USERSPACE_COMPONENT = "cix-isp-umd"

FILES:${PN} += " \
    ${datadir}/cix \
"

# ISP demo includes Python scripts; recommend (not require) python3.
RRECOMMENDS:${PN} += "python3-core bash"
