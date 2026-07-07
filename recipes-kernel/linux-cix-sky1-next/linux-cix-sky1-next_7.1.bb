# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Linux kernel for Cix Sky1 / CP8180 — Sky1-Linux 'next' track
# (mainline 7.1 development).
#
# **BETA TRACK** — sibling recipe to linux-cix-sky1 (which provides
# virtual/kernel = 6.18.26 LTS, the production default).
#
# Built explicitly with: bitbake linux-cix-sky1-next
#
# Sky1-Linux community status (issue #12, MartJohnson 2026-04-30):
# - Confirmed boots on Minisforum MS-R1 with cmdline:
#     efi=noruntime acpi=force arm-smmu-v3.disable_bypass=0 \
#     audit_backlog_limit=8192 clk_ignore_unused keep_bootcon panic=30
# - Has known SCMI transition errors (BIOS missing required updates)
# - Has occasional boot freezes / shutdown crashes
# - These issues are absent on 6.18.26 LTS (with same cmdline)
# - 7.1 is the mainline-forward target; SCMI/BIOS will land eventually
#
# Differences from 6.18.26 LTS:
# - patches-next/ track plus validated cixmini 7.1 rebase fixes
# - SRCREV = v7.1 mainline tag (torvalds/linux), plus validated MS-R1 fixes for SCMI/GPU/VPU/NPU/display
# - Patch 0014-sound-Add-CIX-Sky1-audio-drivers.patch is OMITTED for now —
#   needs alc269.c hand-merge for 7.1 base. Audio non-functional in BETA.
# - PR #18 0140-arm64-cix-fix-kconfig-deps applies cleanly here too
# - 2026-05-04 kernel triage cross-checked 3 candidate upstream backports (
#   IRQF_NO_SUSPEND on cix-mailbox 80784b427970; PCI sky1 ECAM cleanup
#   72e76b63d6ff; is_rc bool 99d986686331). All three were ALREADY effectively
#   present via Sky1-Linux community patches 0005 (mailbox ACPI) and 0008
#   (PCI cadence ACPI) — Sky1-Linux/linux-sky1 is ahead of mainline here.
# - LOCALVERSION = '-cix-sky1-next' (vs LTS's '-cix-sky1-lts')
# - PREFERRED_PROVIDER_virtual/kernel does NOT name this recipe — it's
#   sibling-installed alongside the LTS kernel for boot-menu user choice

SUMMARY = "Linux kernel for Cix Sky1 / CP8180 (Sky1-Linux 7.1 next BETA)"
DESCRIPTION = "Mainline Linux v7.1 + Sky1-Linux/linux-sky1 patches-next/ track \
(base next patch track plus validated cixmini 7.1 rebase fixes; audio patch omitted pending alc269 hand-merge). BETA installed \
alongside 6.18.26 LTS for runtime A/B comparison via systemd-boot menu. Same SoC \
target as the LTS kernel (Cix CP8180, Minisforum MS-R1)."
SECTION = "kernel"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

inherit kernel

LINUX_VERSION = "7.1.0"
KERNEL_LOCALVERSION = "-cix-sky1-next"
PATCHTOOL = "git"
PV = "${LINUX_VERSION}+sky1-next"
KBRANCH = "master"

# Sibling-installable alongside linux-cix-sky1 LTS — distinct work-shared
# dir prevents do_patch collision (Codex HIGH finding 2026-05-03).
KERNEL_PACKAGE_NAME = "kernel-${PN}"

# 7.1 stable tag from gregkh/linux mirror (point releases live on stable, not torvalds)
SRCREV_kernel = "8cd9520d35a6c38db6567e97dd93b1f11f185dc6"

SRC_URI = " \
    git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git;protocol=https;branch=${KBRANCH};name=kernel \
    file://config.sky1-next \
    file://next-patches-v7.1/0001-cix-sky1-next-v7.1-squashed.patch \
    file://next-patches-v7.1/0002-clk-sky1-audss-port-divider-ops-to-v7.1.patch \
    file://next-patches-v7.1/0003-mailbox-cix-restore-legacy-macro-aliases-for-v7.1-rebase.patch \
    file://next-patches-v7.1/0004-mailbox-cix-fix-v7.1-message-length-and-val32.patch \
    file://next-patches-v7.1/0005-drm-cix-virtual-update-color-formats-for-v7.1.patch \
    file://next-patches-v7.1/0006-drm-cix-update-remaining-color-formats-for-v7.1.patch \
    file://next-patches-v7.1/0007-drm-cix-linlon-dp-update-color-format-for-v7.1.patch \
    file://next-patches-v7.1/0008-drm-cix-update-drm_atomic_private_obj_init-for-v7.1.patch \
    file://next-patches-v7.1/0009-drm-cix-update-color-formats-in-dp_component-for-v7.1.patch \
    file://next-patches-v7.1/0010-soc-cix-acpi-resource-lookup-resolve-dev_id-by-acpi.patch \
"

S = "${WORKDIR}/git"

COMPATIBLE_MACHINE = "(cixmini)"

# This recipe does NOT provide virtual/kernel — that role belongs to
# linux-cix-sky1 (LTS, 6.18.26). This is the BETA sibling, installed
# alongside via explicit-build.
PROVIDES = "${PN}"

do_configure:prepend() {
    cd ${S}
    cp ${WORKDIR}/config.sky1-next ${B}/.config
    sed -i "s|^CONFIG_EXTRA_FIRMWARE=.*|# CONFIG_EXTRA_FIRMWARE is not set|" ${B}/.config
    sed -i "/^CONFIG_EXTRA_FIRMWARE_DIR=/d" ${B}/.config
    oe_runmake ARCH=arm64 O=${B} olddefconfig
}

KERNEL_IMAGETYPE = "Image"
KERNEL_DEVICETREE = " \
    cix/sky1-orion-o6.dtb \
"
