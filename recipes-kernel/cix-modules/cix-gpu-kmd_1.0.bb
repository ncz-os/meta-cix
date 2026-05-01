# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Cix Sky1 Mali-G720-Immortalis GPU kernel module (out-of-tree).
# Source: minisforum-cix-p1-repo/cix_opensource__gpu_kernel
# (the same blob that ships as the cix-gpu-driver .deb on the Cix Debian
# image; we build it from source here against our linux-cix-msr1 kernel).

require cix-modules.inc

SUMMARY = "Cix Sky1 Mali-G720 GPU kernel module"
DESCRIPTION = "Out-of-tree kernel module for the ARM Mali-G720-Immortalis GPU as integrated into Cix Sky1 / CP8180. Source from Minisforum's published downstream tree."

PV = "1.0+cix"
SRCREV = "a752e916d18484dd4f67bb6b351543447c978135"

SRC_URI = " \
    git://github.com/minisforum-cix-p1-repo/cix_opensource__gpu_kernel.git;protocol=https;branch=${KBRANCH};name=gpukmd \
"
SRCREV_FORMAT = "gpukmd"

# The Cix gpu_kernel tree uses gpu.mk (driven by Minisforum's
# build-scripts/build-gpu-driver.sh in their downstream pipeline). For Yocto
# we invoke the make target directly. The module class's do_compile passes
# the standard out-of-tree-module variables (KERNEL_SRC, KBUILD_EXTRA_SYMBOLS,
# CC, etc); the gpu.mk needs to honor them.
MAKE_TARGETS = "-f gpu.mk"

# Mali kbase produces a single mali_kbase.ko (matches Sky1-Linux/cix-gpu-kmd
# DKMS packaging). License file is at license.txt in the source tree; the
# parent .inc references it via LIC_FILES_CHKSUM.
