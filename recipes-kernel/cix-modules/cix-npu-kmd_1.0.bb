# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Cix Sky1 NPU (Zhouyi v3) OOT kernel module
#
# Builds armchina_npu.ko from the Minisforum Sky1 cix_opensource__npu_driver
# repo using the clean driver/Makefile (NCX 26.5 r56 OOT Kbuild) — bypasses
# the upstream npu.mk which is Android-build-system-style and requires
# TARGET_OUT_INTERMEDIATES (AOSP env var; not present under Yocto).
#
# Target: linux-cix-sky1-next (7.0.9) — kernel-build-artifacts must be
# populated in /home/jasonperlow/yocto-tmp/build-cixmini-tmp/work-shared/
# cixmini/kernel-build-artifacts/.config. If empty, force run
# `bitbake linux-cix-sky1-next -c shared_workdir -f` or rsync from
# recipe-local kernel-build-artifacts.

SUMMARY = "Cix Sky1 NPU (Zhouyi v3) OOT kernel module"
DESCRIPTION = "armchina-npu KMD for the Sky1 SoC NPU, built OOT against \
linux-cix-sky1-next kernel headers. Source: Minisforum cix_opensource__npu_driver \
mass-production branch; driver/Makefile is the NCX 26.5 r56 OOT Kbuild port."

LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://driver/LICENSE.TXT;md5=ea9445d9cc03d508cf6bb769d15a54ef"

inherit module

PV = "1.0+cix-r56"
SRCREV = "608f8178858ef7749364f1a7ad4872e04615ceea"
SRC_URI = "git://github.com/minisforum-cix-p1-repo/cix_opensource__npu_driver.git;protocol=https;branch=a0fb5/5cf6e/cix_p1_mg_dev;name=npukmd"

S = "${WORKDIR}/git"
B = "${S}/driver"
COMPATIBLE_MACHINE = "(cixmini)"

DEPENDS += "virtual/kernel"

do_compile() {
    oe_runmake -C ${STAGING_KERNEL_DIR} M=${B} modules
}

do_install() {
    install -d ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/extra/cix
    install -m 0644 ${B}/armchina_npu.ko ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/extra/cix/armchina_npu.ko
}

FILES:${PN} = "${nonarch_base_libdir}/modules/${KERNEL_VERSION}/extra/cix/armchina_npu.ko"
