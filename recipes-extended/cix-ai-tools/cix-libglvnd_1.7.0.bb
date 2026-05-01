# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Cix Sky1 libglvnd userspace.
#
# Ships the GL Vendor Neutral Dispatch (libGL.so, libEGL.so,
# libGLESv2.so, libGLX.so, libOpenGL.so, libGLdispatch.so) plus
# pkg-config descriptors. All under /opt/cixgpu-compat/lib/aarch64-
# linux-gnu/ — already covered by cix-gpu-umd's
# /etc/ld.so.conf.d/01-cixgpu-compat.conf, so no new ld.so.conf.d
# drop-in needed here. Just RDEPENDS cix-gpu-umd.
#
# Required by cix-mesa for the GL dispatch chain — Cix Mesa libGL
# stubs are in /opt/cixgpu-compat tree, dispatched through libGL.so.1
# from this package.

require cix-ai-tools.inc

SUMMARY = "Cix Sky1 libglvnd OpenGL/EGL/GLES vendor-neutral dispatch"
DESCRIPTION = "Closed-source pre-built libglvnd runtime for Cix Sky1. Source from minisforum-cix-p1-repo/ext_debs cix-libglvnd_1.7.0_arm64 subtree. Required by cix-mesa for the GL/EGL dispatch chain."

LICENSE_FLAGS = "commercial_cix-libglvnd"
# Has its own embedded copyright file (one of only two ext_debs
# components with one — cix-mesa is the other).
LIC_FILES_CHKSUM = "file://usr/share/doc/cix-libglvnd/copyright;md5=96aa9f3a44040e7d50de816f57487503"

CIX_AI_COMPONENT = "cix-libglvnd_1.7.0_arm64"

# All libs land under /opt/cixgpu-compat/lib/aarch64-linux-gnu —
# the path that cix-gpu-umd's 01-cixgpu-compat.conf already adds
# to ld.so.conf.d. So ldconfig coverage transits through cix-gpu-umd.
RDEPENDS:${PN} += "cix-gpu-umd"

FILES:${PN} += " \
    /opt/cixgpu-compat \
"
