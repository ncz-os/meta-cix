# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0

require cix-multimedia.inc

SUMMARY = "CIX Sky1 VA-API driver"
DESCRIPTION = "Closed-source CIX VA-API driver for Sky1 VPU hardware acceleration. Source package: cix-vaapi_1.0.0_arm64.deb."

CIX_MM_DEB_GLOB = "cix-vaapi_1.0.0_arm64.deb"
RDEPENDS:${PN} += "cix-libva2 cix-libva-drm2 cix-vpu-umd"
