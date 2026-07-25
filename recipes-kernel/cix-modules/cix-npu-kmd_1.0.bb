# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Cix Sky1 NPU (Zhouyi v3) OOT kernel module
#
# Builds aipu.ko from the Minisforum Sky1 cix_opensource__npu_driver
# repo against linux-cix-sky1-next kernel headers.

SUMMARY = "Cix Sky1 NPU (Zhouyi v3) OOT kernel module"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://driver/LICENSE.TXT;md5=ea9445d9cc03d508cf6bb769d15a54ef"

inherit module

PV = "1.0+cix-r57"
SRCREV = "608f8178858ef7749364f1a7ad4872e04615ceea"
SRC_URI = "git://github.com/minisforum-cix-p1-repo/cix_opensource__npu_driver.git;protocol=https;branch=a0fb5/5cf6e/cix_p1_mg_dev;name=npukmd \
           file://0001-armchina-npu-scmi-removal.patch \
           file://0002-armchina-npu-Makefile-ccflags-y.patch \
           file://0003-armchina-npu-MODULE_IMPORT_NS-quoted.patch \
           file://0004-armchina-npu-remove-void.patch \
           file://0005-armchina-npu-pm-runtime-put-void.patch \
           file://0006-armchina-npu-module-metadata-v3_1.patch \
           file://0007-armchina-npu-drop-IRQF_ONESHOT.patch \
           file://0008-armchina-npu-pm-runtime-enable-redundant.patch"

# Patches apply at S=${WORKDIR}/git
FILESEXTRAPATHS:prepend := "${THISDIR}/cix-npu-kmd-1.0:"

B = "${S}/driver"
COMPATIBLE_MACHINE = "(cixmini)"

DEPENDS += "virtual/kernel"

do_configure() {
    # Fresh git checkout each bake — skip module.bbclass default
    # make-clean against host kernel that doesn't exist in container.
    :
}

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
        BUILD_NPU_DEVFREQ=n \
        KCFLAGS="-Wno-error=missing-prototypes -Wno-error" \
        modules
}

do_install() {
    install -d ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/extra/cix
    install -m 0644 ${B}/aipu.ko ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/extra/cix/aipu.ko
}

FILES:${PN} = "${nonarch_base_libdir}/modules/${KERNEL_VERSION}/extra/cix/aipu.ko"
