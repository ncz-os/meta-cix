# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Cix Sky1 VPU (Video Processing Unit) kernel module -- amvx.
# Provides hardware H.264 / H.265 / AV1 decode and H.264 / H.265 encode.
# Consumed by cix-gstreamer (S6) and cix-vaapi.
#
# Source: cixtech/cix_opensource__vpu_driver, branch cix_mainline_dev.
# This is the vendor's own mainline-tracking branch (v1.0.2). It already
# carries the forward-ports that the older minisforum fork
# (a0fb5/5cf6e/cix_p1_mg_dev, SRCREV 66180b68) lacks and which are required
# on kernels >= 6.8: the dentry d_subdirs/d_child -> d_children/d_sib
# conversion, and the MODULE_IMPORT_NS() string-literal form. Both are
# version-gated upstream, so this still builds against the 7.0.12 LTS tier.
# Do not repoint this at the minisforum fork -- it does not compile on 7.2.

SUMMARY = "Cix Sky1 VPU (Linlon) kernel module"
DESCRIPTION = "Out-of-tree kernel module for the Cix Sky1 VPU video codec accelerator, from the vendor's mainline-tracking branch."
LICENSE = "GPL-2.0-only"

inherit module

PV = "1.0.2+cix"
SRCREV = "51d1ec01c0952d1d3a8b6ef2fc34a0ca84fe9436"

SRC_URI = " \
    git://github.com/cixtech/cix_opensource__vpu_driver.git;protocol=https;branch=cix_mainline_dev;name=vpukmd \
    file://0001-amvx-use-strscpy-for-vdev-name.patch \
"
SRCREV_FORMAT = "vpukmd"

FILESEXTRAPATHS:prepend := "${THISDIR}/cix-vpu-kmd-1.0.2:"

# vpu_driver ships no standalone LICENSE/COPYING. Source headers carry the GNU
# GPL v2 boilerplate plus an SPDX-License-Identifier: GPL-2.0-only tag. Point
# at the header block of one representative .c file.
LIC_FILES_CHKSUM = "file://driver/mvx_pm_runtime.c;beginline=1;endline=30;md5=0ce8466561de54500d9758d6ad225176"

COMPATIBLE_MACHINE = "(cixmini)"
DEPENDS += "virtual/kernel"

do_configure() {
    # Fresh git checkout each bake -- skip module.bbclass's default make-clean
    # against a host kernel that does not exist in the build container.
    :
}

do_compile() {
    # KDIR/-C must be STAGING_KERNEL_BUILDDIR (the configured, built tree with
    # correct Module.symvers + utsrelease.h), not STAGING_KERNEL_DIR (raw
    # unconfigured source). module.bbclass injects KERNEL_SRC=${STAGING_KERNEL_DIR}
    # via EXTRA_OEMAKE; pairing -C with O= here is what keeps vermagic correct.
    # See cix-gpu-kmd_1.0.bb for the full root cause of the vermagic trap.
    unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS
    oe_runmake -C ${STAGING_KERNEL_DIR} M=${S} \
        CC="${KERNEL_CC}" LD="${KERNEL_LD}" AR="${KERNEL_AR}" \
        O=${STAGING_KERNEL_BUILDDIR} \
        KBUILD_EXTMOD=${S} \
        CONFIG_VIDEO_LINLON=m \
        KCFLAGS="-Wno-error" \
        modules
}

do_install() {
    install_dir="${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/extra/cix"
    install -d "$install_dir"
    install -m 0644 ${S}/amvx.ko "$install_dir/amvx.ko"
}

FILES:${PN} = "${nonarch_base_libdir}/modules/${KERNEL_VERSION}/extra/cix/amvx.ko"
