# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Cix Sky1 NPU (Zhouyi v3) OOT kernel module
#
# Builds armchina_npu.ko from the Minisforum Sky1 cix_opensource__npu_driver
# repo against linux-cix-sky1-next kernel headers.

SUMMARY = "Cix Sky1 NPU (Zhouyi v3) OOT kernel module"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://driver/LICENSE.TXT;md5=ea9445d9cc03d508cf6bb769d15a54ef"

inherit module

PV = "1.0+cix-r57"
SRCREV = "608f8178858ef7749364f1a7ad4872e04615ceea"
SRC_URI = "git://github.com/minisforum-cix-p1-repo/cix_opensource__npu_driver.git;protocol=https;branch=a0fb5/5cf6e/cix_p1_mg_dev;name=npukmd"

S = "${WORKDIR}/git"
B = "${S}/driver"
COMPATIBLE_MACHINE = "(cixmini)"

DEPENDS += "virtual/kernel"

do_compile() {
    unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS
    oe_runmake -C ${STAGING_KERNEL_DIR} M=${B} \
        CC="${KERNEL_CC}" LD="${KERNEL_LD}" AR="${KERNEL_AR}" \
        KERNEL_PATH=${STAGING_KERNEL_DIR} \
        KERNEL_VERSION=${KERNEL_VERSION} \
        O=${STAGING_KERNEL_BUILDDIR} \
        KBUILD_EXTMOD=${B} \
        COMPASS_DRV_BTENVAR_KMD_VERSION=5.11.0 \
        BUILD_AIPU_VERSION_KMD=BUILD_ZHOUYI_V3 \
        BUILD_TARGET_PLATFORM_KMD=BUILD_PLATFORM_SKY1 \
        BUILD_NPU_DEVFREQ=y \
        modules
}

do_install() {
    install -d ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/extra/cix
    install -m 0644 ${B}/armchina_npu.ko ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/extra/cix/armchina_npu.ko
}

FILES:${PN} = "${nonarch_base_libdir}/modules/${KERNEL_VERSION}/extra/cix/armchina_npu.ko"
