# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0

require cix-multimedia.inc

SUMMARY = "CIX Sky1 GStreamer multimedia plugins"
DESCRIPTION = "Closed-source CIX Multimedia SDK GStreamer plugin package for Sky1 multimedia acceleration. Source package: cix-gstreamer_1.22.1_arm64.deb."

CIX_MM_DEB_GLOB = "cix-gstreamer_1.22.1_arm64.deb"
RDEPENDS:${PN} += "gstreamer1.0-plugins-good gstreamer1.0-plugins-bad cix-vaapi cix-vpu-umd"
