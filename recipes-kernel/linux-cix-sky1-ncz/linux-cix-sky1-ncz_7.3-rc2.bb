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
# 2026-09-11: First real bitbake compile found additional forward-port
# gaps that were not reachable by dry-run patch replay:
# - PCI: cadence: add Sky1 IP Local Management Registers base block
#   (commit 4f84181bfab4) -- CIX-added offset macros used by Sky1 I_*
#   helpers in pci-sky1-cix.c, simply missing from this branch.
# Bumped SRCREV_kernel to current HEAD 4f84181bfab4.
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

# kernel-73rc2-port HEAD. Brief prior to this commit claimed the PCI commit
# had SHA 4f84181bfab456e9b8dbabb47fbb02f6c7f48d6c, but that hash does NOT
# exist in the repo -- the actual stored object has SHA
# 4f84181bfab41cd1253d09f444d0544f2eb5022f (verified via zlib decompress
# of the loose object on disk: real SHA1 of the stored commit content is
# the 1cd1253d... one, not 56e9b8...). Bitbake's git fetcher happily reports
# the bare 40-char string back on rev-parse even when the object is absent,
# so the bogus hash made the recipe LOOK valid while the actual fetch
# failed with 'Unable to find revision ... even from upstream'.
#
# After PCI was fixed, two more real bugs landed on top of it:
#   f924ac6d2942 cix: acpi: dsdt_override: switch asm/unaligned.h to
#                    linux/unaligned.h
#   0c37f837d3a7 cix: ddr-lp: fix platform_driver .remove signature
#                   (int -> void)
# 2026-09-11 (2nd bitbake attempt): compile failed on a 4th platform_driver
# .remove() int->void mismatch, cix_aec_remove() in cix-acpi-ec.c (same class
# as cix_ddrlp_remove -- see kernel-build-checklist.md). Audited all 5
# CIX .remove= assignments in the port tree against the 7.2.5 reference;
# only this one and cix_ddrlp_remove needed the fix. Fixed in commit
# 1aa3075a23ea.
#
# SRCREV_kernel is now the tip of kernel-73rc2-port (1aa3075a23ea) so the
# build picks up all four forward-port fixes together.
# 2026-09-11 (3rd bitbake attempt): compile failed on 2 more bugs:
# 1) cix_aec_gpio_set() in cix-acpi-ec-gpio.c was void, but this gpiolib
#    still has gpio_chip.set as int-returning (matches 7.2.5 reference,
#    which is int) -- reverted to int, return 0.
# 2) cix-plat.cs whole CONFIG_CIX_SMMU_ATTACH_NOTIFIER block was missing
#    its ifdef guards -- a dropped hunk of 7.2 series patch 0074 (the
#    same patch that supplied the cix_ddrlp_remove fix; only that sibling
#    hunk landed). Restored the guards verbatim from patch 0074; the
#    option is unset in the built .config so the block now compiles out,
#    matching 7.2.5s working behavior byte-for-byte.
#
# SRCREV_kernel is now the tip of kernel-73rc2-port (ef818e8dc33d) so
# the build picks up all six forward-port fixes together.
SRCREV_kernel = "a50d3f1838cacbf2859135c5432b7920b38c9470"

# NOTE: fetches from a LOCAL bare mirror under this build container's workdir mount
# (the ncz-yocto-y6 podman sandbox has no SSH keys, so it cannot reach the
# ARGONAS ssh:// remote directly). The canonical pushed copies are
# gitlab.com/ncz-os/linux-cix.git + the ARGONAS bare mirror at
# /mnt/datapool/git/ncz-os/linux-cix.git, branch kernel-73rc2-port.
# Local mirror at ~/yocto-work/kernel-mirrors/linux-cix-kernel-73rc2-port.git
# was rebuilt cleanly from ~/linux-72 on 2026-09-11 after the previous copy
# turned out to have a corrupt (non-existent) SHA for the PCI commit; rebuild
# with `git clone --bare ~/linux-72` if it goes stale again.
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
