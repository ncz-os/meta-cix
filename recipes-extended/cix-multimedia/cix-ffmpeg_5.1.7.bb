# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0

require cix-multimedia.inc

SUMMARY = "CIX-optimized FFmpeg tools"
DESCRIPTION = "Closed-source CIX Multimedia SDK FFmpeg command-line tools optimized for Sky1 multimedia acceleration. Source package: cix-ffmpeg_5.1.7-0+deb12u1+b1_arm64.deb."

CIX_MM_DEB_GLOB = "cix-ffmpeg_5.1.7-0+deb12u1+b1_arm64.deb"
RDEPENDS:${PN} += "cix-libavutil57 cix-libavcodec59 cix-libavformat59 cix-vaapi"
