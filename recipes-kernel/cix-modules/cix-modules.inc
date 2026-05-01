# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Shared include for the Cix Sky1 out-of-tree kernel-module recipes.
# Each driver gets its own .bb that requires this file and overrides the
# few per-driver knobs (SRC_URI repo, source subdir, module name).
#
# All five Cix Sky1 driver-pack modules (gpu/npu/vpu/csidma/isp) build
# against the kernel built by linux-cix-msr1 and install into
# /lib/modules/${KERNEL_VERSION}/extra/cix/.

LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://license.txt;md5=89df4dc36c4c81e92ca2d8c39028e132"

inherit module

# All the Sky1 driver-pack modules track Minisforum's mass-production branch.
KBRANCH = "a0fb5/5cf6e/cix_p1_mg_dev"

# Cix's .mk-driven build expects the kernel source tree at $(KDIR). Yocto's
# module class points STAGING_KERNEL_DIR at the staged kernel headers + build
# tree, which is what these out-of-tree module Makefiles want.
EXTRA_OEMAKE += "KDIR=${STAGING_KERNEL_DIR}"

# Each driver Makefile/.mk produces one or more .ko files. The module class's
# default do_install copies *.ko under /lib/modules/${KERNEL_VERSION}/extra/.
# We narrow the install path to /lib/modules/${KERNEL_VERSION}/extra/cix/
# so the pack stays grouped.
module_install_dir = "/lib/modules/${KERNEL_VERSION}/extra/cix"

S = "${WORKDIR}/git"

DEPENDS += "virtual/kernel"
RDEPENDS:${PN} += "kernel-${KERNEL_VERSION}"

COMPATIBLE_MACHINE = "(cixmini)"

# Per-driver recipes set: PV, SRCREV, SRC_URI (the matching cix_opensource__*
# repo on minisforum-cix-p1-repo), MODULE_NAME (used in PROVIDES /
# install path).
