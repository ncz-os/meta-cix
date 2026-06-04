# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0

require cix-multimedia.inc

SUMMARY = "CIX Sky1 VPU unit-test utilities"
DESCRIPTION = "Closed-source CIX Multimedia SDK VPU test utilities for validating the Sky1 VPU driver stack. Source package: cix-vpu-test_1.0.0_arm64.deb."

CIX_MM_DEB_GLOB = "cix-vpu-test_1.0.0_arm64.deb"
RDEPENDS:${PN} += "cix-vpu-umd cix-vpu-kmd"
