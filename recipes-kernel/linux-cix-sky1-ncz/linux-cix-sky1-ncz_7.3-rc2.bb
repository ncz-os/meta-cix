# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Linux kernel for Cix Sky1 / CP8180 -- NCZ 7.3 track (NEXT/test, not yet
# the shipping/stable release -- that is 7.2.x, see linux-cix-sky1-ncz_7.2.bb).
#
# Base: torvalds mainline v7.3-rc2.
#
# Unlike the 7.2 recipe (which applies ~205 file://patches-7.2/*.patch at
# build time against pristine upstream), this recipe points SRC_URI directly
# at a working branch, kernel-73rc2-port, on the canonical ARGONAS mirror
# of linux-cix.git, in which all of those patches have ALREADY been
# forward-ported and committed. That branch is also pushed to gitlab.com/
# ncz-os/linux-cix.git and github.com/ncz-os/linux-sky1.git (same 3-remote
# pattern as every other canonical repo on this fleet).
#
# Provenance (2026-09-09): dry-run replay of the full 205-patch series
# (build/port-series.sh v7.3-rc2, from the linux-port-v7.3-rc2 working tree)
# applied 168/203 cleanly; the 35 failures (mailbox/clk-cix ACPI+SCMI bridge
# cluster, armchina/Zhouyi NPU driver cluster, usb-cdns3 Sky1 wrapper,
# cacheinfo, resctrl-mpam) were then individually re-derived against the
# real v7.3-rc2 diff and landed as 11 real forward-port commits on top of
# the dry-run base, ending at kernel-73rc2-port HEAD 03ba72644afe.
#
# NOT YET DONE as of this recipe's authoring: a real bitbake compile of this
# tree. Patches applying/replaying cleanly is not proof the kernel builds or
# boots (see ~/.claude/rules/kernel-build-checklist.md) -- that is exactly
# what pulling this recipe into a real Yocto build is for. Full
# kernel-build-checklist.md gates (dkms-abi-gate, kvm-kernel-gate,
# CONFIG_MODVERSIONS=y, boot on O6N only/human-supervised) all still apply
# before this track is ever considered for shipping.

LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

inherit kernel
FILESEXTRAPATHS:prepend := "${THISDIR}/linux-cix-sky1-ncz-7.3-rc2:"

LINUX_VERSION = "7.3-rc2"
KERNEL_LOCALVERSION = "-sky1-ncz"
PV = "7.3-rc2+ncz"
PR = "r1"
KBRANCH = "kernel-73rc2-port"
KERNEL_PACKAGE_NAME = "kernel-${PN}"

do_shared_workdir:append() {
    shared_kernel_dir="${TMPDIR}/work-shared/${MACHINE}"
    install -d "$shared_kernel_dir"
    ln -sfn "${S}" "$shared_kernel_dir/kernel-source"
    ln -sfn "${WORKDIR}/kernel-build-artifacts" "$shared_kernel_dir/kernel-build-artifacts"
    ln -sfn "${KERNEL_PACKAGE_NAME}-abiversion" "${WORKDIR}/kernel-build-artifacts/kernel-abiversion"
    ln -sfn "${KERNEL_PACKAGE_NAME}-localversion" "${WORKDIR}/kernel-build-artifacts/kernel-localversion"
}

# kernel-73rc2-port HEAD, verified identical across local working tree,
# gitlab.com/ncz-os/linux-cix.git and the ARGONAS bare mirror on 2026-09-09.
SRCREV_kernel = "3c0c23241c8da45f9d12035205e4acae737100ff"

# NOTE: fetches from a LOCAL bare mirror under this build container's workdir mount
# (the ncz-yocto-y6 podman sandbox has no SSH keys, so it cannot reach the
# ARGONAS ssh:// remote directly). The canonical, pushed copy of this exact
# commit is gitlab.com/ncz-os/linux-cix.git + the ARGONAS bare mirror at
# /mnt/datapool/git/ncz-os/linux-cix.git, branch kernel-73rc2-port,
# verified identical 2026-09-09. Re-clone the local mirror
# (~/yocto-work/kernel-mirrors/linux-cix-kernel-73rc2-port.git) from one
# of those canonical remotes if it goes stale.
SRC_URI = " \
    git:///workdir/kernel-mirrors/linux-cix-kernel-73rc2-port.git;protocol=file;branch=${KBRANCH};name=kernel \
    file://config-7.3-rc2.defconfig \
"

COMPATIBLE_MACHINE = "(cixmini)"
S = "${UNPACKDIR}/${BB_GIT_DEFAULT_DESTSUFFIX}"

PROVIDES = "${PN} virtual/kernel"

do_configure:prepend() {
    cd ${S}
    cp ${UNPACKDIR}/config-7.3-rc2.defconfig ${B}/.config
    oe_runmake ARCH=arm64 O=${B} olddefconfig
}

KERNEL_IMAGETYPE = "Image"
KERNEL_DEVICETREE = " \
    cix/sky1-orion-o6.dtb \
"
