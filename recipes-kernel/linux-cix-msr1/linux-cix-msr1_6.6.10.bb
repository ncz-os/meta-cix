# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Linux kernel for Cix Sky1 / CP8180 on the Minisforum MS-R1 (cixmini machine).
#
# Pulls Minisforum's published downstream kernel source — same source tree the
# shipping firmware/Debian image runs (verified via `uname -r ==
# 6.6.10-cix-build-generic` on a live MS-R1). This supersedes the earlier
# linux-cix-ncz_7.0.bb recipe, which tracked the cixtech upstream-mainlining
# effort (kernel 7.0-rc) — that path is blocked on cixtech completing
# patches-7.0 and would not boot on real MS-R1 hardware until the proprietary
# driver pack is upstreamed. We're now building from Minisforum's downstream
# tree, which has the full driver pack already integrated and is what actually
# runs on shipping units.
#
# Manifest pin — see https://github.com/minisforum-cix-p1-repo/cix_manifest
# default.xml on branch a0fb5/5cf6e/cix_p1_mg_dev: cix_opensource__linux is
# pinned to the same a0fb5/5cf6e/cix_p1_mg_dev branch. SRCREV below pins the
# exact commit on that branch as of 2026-05-01 source sync to ARGOS.

SUMMARY = "Linux kernel for Cix Sky1 / CP8180 (Minisforum MS-R1)"
DESCRIPTION = "Linux 6.6.10 with the Cix Sky1 downstream patch stack and proprietary driver-pack hooks, built from minisforum-cix-p1-repo/cix_opensource__linux."
SECTION = "kernel"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

inherit kernel

LINUX_VERSION = "6.6.10"
# Match the shipping kernel uname -r suffix so /lib/modules/${KERNEL_VERSION}
# aligns with Minisforum's module ABI and our paired out-of-tree module
# recipes (cix-gpu-kmd / cix-npu-kmd / cix-vpu-kmd) install to the same
# kernel-version path the device's running kernel expects. KERNEL_LOCALVERSION
# is the plain-kernel.bbclass-supported variable on Scarthgap; the older
# LINUX_VERSION_EXTENSION belongs to kernel-yocto.bbclass.
KERNEL_LOCALVERSION = "-cix-build-generic"
PV = "${LINUX_VERSION}+cix"
KBRANCH = "a0fb5/5cf6e/cix_p1_mg_dev"

# Pinned to the HEAD of cix_p1_mg_dev as of the 2026-05-01 source-tree sync on
# ARGOS. Bump this with a fresh `repo sync` + the new HEAD SHA when adopting a
# newer Minisforum kernel rev.
SRCREV = "cc636a675f7926846f04d31524c17b591955acca"

SRC_URI = " \
    git://github.com/minisforum-cix-p1-repo/cix_opensource__linux.git;protocol=https;branch=${KBRANCH};name=kernel \
    file://usb-rootfs.cfg \
    file://console-fb.cfg \
"

# We deliberately do NOT carry SRC_URI patches that diverge from Minisforum's
# tree on the kernel side. Anything we want changed (Landlock, fbcon-on-HDMI)
# belongs upstream-bound at cixtech, not local-patched.

S = "${WORKDIR}/git"

COMPATIBLE_MACHINE = "(cixmini)"

# Sky1 build target per build-kernel.sh: `dtbs Image`. The MS-R1 specifically
# uses ACPI tables loaded by UEFI (not DT) for boot-time hardware discovery,
# but the kernel still ships DTBs for diagnostic / fallback use, and the
# build target requires them. KERNEL_DEVICETREE selection is informational
# only on cixmini (machine.conf doesn't APPEND a dtb=... cmdline).
KERNEL_IMAGETYPE = "Image"
KERNEL_DEVICETREE = " \
    cix/sky1-evb.dtb \
"

# Cix's build-kernel.sh runs `make defconfig cix.config` for the "cix" platform.
# defconfig is the standard arm64 defconfig; cix.config layers Sky1-specific
# enables (DRM/Mali/NPU/VPU/audio/etc) on top.
# We mirror that here under plain kernel.bbclass — kernel-yocto's
# KERNEL_CONFIG_FRAGMENTS / do_kernel_metadata flow is not available with
# plain `inherit kernel`, so we explicitly run the three make commands in
# do_configure:prepend before kernel.bbclass's olddefconfig step.
do_configure:prepend() {
    cd ${S}
    oe_runmake ARCH=arm64 O=${B} defconfig
    cat ${S}/arch/arm64/configs/cix.config >> ${B}/.config
    # Local override fragment: forces USB host + storage + UAS into the
    # kernel image so a USB-attached rootfs boots without initramfs
    # modules. See files/usb-rootfs.cfg for the full rationale.
    cat ${WORKDIR}/usb-rootfs.cfg >> ${B}/.config
    cat ${WORKDIR}/console-fb.cfg >> ${B}/.config
    oe_runmake ARCH=arm64 O=${B} olddefconfig
}

# QA: the kernel recipe is the build-host class kernel; symlinks etc. are
# already-stripped by the kernel-class do_strip step. No extra INSANE_SKIP.

# Maintainer expectation: this recipe is paired with a future
# meta-cix/recipes-kernel/cix-modules/{gpu,npu,vpu,csidma,isp}-kmd_*.bb set
# of out-of-tree kernel-module recipes that pull from each of:
#   minisforum-cix-p1-repo/cix_opensource__gpu_kernel
#   minisforum-cix-p1-repo/cix_opensource__npu_driver
#   minisforum-cix-p1-repo/cix_opensource__vpu_driver
# These build module .ko's against this kernel via KERNEL_SRC.
