# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0

require cix-multimedia.inc

SUMMARY = "CIX-optimized FFmpeg libavcodec 5.1.7"
DESCRIPTION = "Closed-source CIX Multimedia SDK build of FFmpeg libavcodec with hardware multimedia integration. Source package: cix-libavcodec59_5.1.7-0+deb12u1+b1_arm64.deb."

CIX_MM_DEB_GLOB = "cix-libavcodec59_5.1.7-0+deb12u1+b1_arm64.deb"
RDEPENDS:${PN} += "cix-libavutil57"
