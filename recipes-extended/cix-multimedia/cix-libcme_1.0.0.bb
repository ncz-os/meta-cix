# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0

require cix-multimedia.inc

SUMMARY = "CIX Media Engine runtime library"
DESCRIPTION = "Closed-source CIX Media Engine runtime for accelerated 2D image processing operations on CIX Sky1. Source package: cix-libcme_1.0.0_arm64.deb."

CIX_MM_DEB_GLOB = "cix-libcme_1.0.0_arm64.deb"
RDEPENDS:${PN} += "libyuv"
