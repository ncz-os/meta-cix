# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0

SUMMARY = "nclawzero Linux kernel for Cix Sky1 / Minisforum MS-R1"
DESCRIPTION = "Linux v7.0-rc4 with Cix Sky1 mainline patch stack, matching the ULTRA deb-package survey build."
SECTION = "kernel"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

inherit kernel

LINUX_VERSION = "7.0.0-rc4"
LINUX_VERSION_EXTENSION ?= "-cix-ncz"
PV = "${LINUX_VERSION}+cix"

SRCREV_kernel = "f338e77383789c0cae23ca3d48adcc5e9e137e3c"
SRCREV_cixmain = "0aebbccfd5694e7f0ba6aaae8be7e74b86bc3fa6"
SRCREV_FORMAT = "kernel_cixmain"

SRC_URI = " \
    file://gpu-opp-nonfatal.patch \
    git://github.com/torvalds/linux.git;protocol=https;branch=master;name=kernel;destsuffix=git \
    git://github.com/cixtech/cix-linux-main.git;protocol=https;branch=main;name=cixmain;destsuffix=cix-linux-main \
"

S = "${WORKDIR}/git"

COMPATIBLE_MACHINE = "(cixmini)"
KERNEL_VERSION_SANITY_SKIP = "1"
KCONFIG_MODE = "alldefconfig"

addtask apply_cix_patches after do_patch before do_configure

do_apply_cix_patches() {
    for patchfile in ${WORKDIR}/cix-linux-main/patches-7.0/*.patch; do
        bbnote "Applying Cix Sky1 kernel patch ${patchfile}"
        patch -d ${S} -p1 --forward < "${patchfile}"
    done
}

do_configure:prepend() {
    install -m 0644 ${WORKDIR}/cix-linux-main/config/config-7.0.defconfig ${S}/.config
}
