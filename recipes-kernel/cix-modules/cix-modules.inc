# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Shared include for the Cix Sky1 out-of-tree kernel-module recipes.
# Each driver gets its own .bb that requires this file and overrides the
# few per-driver knobs (SRC_URI repo, source subdir, module name).
#
# All Cix Sky1 out-of-tree driver-pack modules (gpu/npu/vpu) build against
# the kernel built by linux-cix-msr1 and install into
# /lib/modules/${KERNEL_VERSION}/extra/cix/. csidma and isp drivers are
# in-tree under linux/drivers/media/platform/cix/ and build via cix.config —
# no separate recipe needed.

LICENSE = "GPL-2.0-only"

inherit module

CIX_DRIVER_MAKEFILE ?= ""

# All the Sky1 driver-pack modules track Minisforum's mass-production branch.
KBRANCH = "a0fb5/5cf6e/cix_p1_mg_dev"

# Cix's .mk-driven build expects the kernel source tree at $(KDIR)/$(KSRC).
# module-base points STAGING_KERNEL_DIR at the staged kernel headers + build
# tree, which is what these out-of-tree module Makefiles want.
do_compile() {
    if [ -z "${CIX_DRIVER_MAKEFILE}" ]; then
        bbfatal "CIX_DRIVER_MAKEFILE must be set by ${PN}"
    fi

    oe_runmake -f ${CIX_DRIVER_MAKEFILE} \
        KDIR=${STAGING_KERNEL_DIR} \
        KSRC=${STAGING_KERNEL_DIR}
}

do_install() {
    if [ -z "${CIX_DRIVER_MAKEFILE}" ]; then
        bbfatal "CIX_DRIVER_MAKEFILE must be set by ${PN}"
    fi

    oe_runmake -f ${CIX_DRIVER_MAKEFILE} \
        KDIR=${STAGING_KERNEL_DIR} \
        KSRC=${STAGING_KERNEL_DIR} \
        INSTALL_MOD_PATH=${D}

    install -d ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/extra/cix
    find ${B} -name "*.ko" -exec install -m 0644 {} ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/extra/cix/ \;
}

S = "${WORKDIR}/git"

DEPENDS += "virtual/kernel"
RDEPENDS:${PN} += "kernel-${KERNEL_VERSION}"

COMPATIBLE_MACHINE = "(cixmini)"

# Per-recipe overrides: PV, SRCREV, SRC_URI (the matching cix_opensource__*
# repo on minisforum-cix-p1-repo), CIX_DRIVER_MAKEFILE (the matching
# gpu.mk / npu.mk / vpu.mk entrypoint), and LIC_FILES_CHKSUM (each driver's
# license.txt has its own md5).
