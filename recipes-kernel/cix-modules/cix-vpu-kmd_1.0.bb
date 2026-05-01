# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Cix Sky1 VPU (Video Processing Unit) kernel module.
# Source: minisforum-cix-p1-repo/cix_opensource__vpu_driver
# Provides hardware-accelerated H.264 / H.265 / AV1 decode, H.265 / H.264
# encode for Cix Sky1. Consumed by cix-gstreamer (S6) and cix-vaapi.

require cix-modules.inc

SUMMARY = "Cix Sky1 VPU kernel module"
DESCRIPTION = "Out-of-tree kernel module for the Cix Sky1 VPU (video codec accelerator). Source from Minisforum's downstream tree."

PV = "1.0+cix"
SRCREV = "66180b68ba259c230613bb7dd1634ce4b5ad3716"

SRC_URI = " \
    git://github.com/minisforum-cix-p1-repo/cix_opensource__vpu_driver.git;protocol=https;branch=${KBRANCH};name=vpukmd \
"
SRCREV_FORMAT = "vpukmd"

MAKE_TARGETS = "-f vpu.mk"

# vpu_driver also ships an SCons-based build (sconstruct + site_scons/) but
# the .mk path is what Minisforum's build-scripts/build-vpu_driver.sh uses
# for the kernel-module half. The SCons surface is for the userspace side
# packaged separately under cix-vpu-umd in a later slice.
