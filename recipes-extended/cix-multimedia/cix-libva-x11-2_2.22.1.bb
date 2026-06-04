# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0

require cix-multimedia.inc

SUMMARY = "CIX-optimized VA-API X11 backend"
DESCRIPTION = "Closed-source CIX Multimedia SDK VA-API X11 backend. Source package: cix-libva-x11-2_2.22.1-1_arm64.deb."

CIX_MM_DEB_GLOB = "cix-libva-x11-2_2.22.1-1_arm64.deb"
RDEPENDS:${PN} += "cix-libva2"
