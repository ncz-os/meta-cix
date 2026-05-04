# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Linux kernel for Cix Sky1 / CP8180 — Sky1-Linux 'next' track
# (mainline 7.0.x development).
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
# - 7.0 is the long-term direction; SCMI/BIOS will land eventually
#
# Differences from 6.18.26 LTS:
# - patches-next/ track (43 mainline-targeted patches)
# - SRCREV = v7.0.3 stable tag (gregkh/linux mirror, bumped from 7.0.1 — 46 generic security/stability commits, 0 Sky1 touches)
# - Patch 0014-sound-Add-CIX-Sky1-audio-drivers.patch is OMITTED for now —
#   needs alc269.c hand-merge for 7.0 base. Audio non-functional in BETA.
# - PR #18 0140-arm64-cix-fix-kconfig-deps applies cleanly here too
# - 2026-05-04 kernel triage cross-checked 3 candidate upstream backports (
#   IRQF_NO_SUSPEND on cix-mailbox 80784b427970; PCI sky1 ECAM cleanup
#   72e76b63d6ff; is_rc bool 99d986686331). All three were ALREADY effectively
#   present via Sky1-Linux community patches 0005 (mailbox ACPI) and 0008
#   (PCI cadence ACPI) — Sky1-Linux/linux-sky1 is ahead of mainline here.
# - LOCALVERSION = '-cix-sky1-next' (vs LTS's '-cix-sky1-lts')
# - PREFERRED_PROVIDER_virtual/kernel does NOT name this recipe — it's
#   sibling-installed alongside the LTS kernel for boot-menu user choice

SUMMARY = "Linux kernel for Cix Sky1 / CP8180 (Sky1-Linux 7.0 next BETA)"
DESCRIPTION = "Mainline Linux v7.0.3 + Sky1-Linux/linux-sky1 patches-next/ track \
(42 of 43 patches; audio patch omitted pending alc269 hand-merge). BETA installed \
alongside 6.18.26 LTS for runtime A/B comparison via systemd-boot menu. Same SoC \
target as the LTS kernel (Cix CP8180, Minisforum MS-R1)."
SECTION = "kernel"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

inherit kernel

LINUX_VERSION = "7.0.3"
KERNEL_LOCALVERSION = "-cix-sky1-next"
PV = "${LINUX_VERSION}+sky1-next"
KBRANCH = "linux-7.0.y"

# Sibling-installable alongside linux-cix-sky1 LTS — distinct work-shared
# dir prevents do_patch collision (Codex HIGH finding 2026-05-03).
KERNEL_PACKAGE_NAME = "kernel-${PN}"

# 7.0.3 stable tag from gregkh/linux mirror (point releases live on stable, not torvalds)
SRCREV_kernel = "03e81f004d7e665e7c0e203c2f240abefbb79056"

SRC_URI = " \
    git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git;protocol=https;branch=${KBRANCH};name=kernel \
    file://config.sky1-next \
    file://next-patches/0001-arm64-dts-cix-Add-Sky1-SoC-and-board-device-trees.patch \
    file://next-patches/0002-arm64-cix-Add-Sky1-SoC-infrastructure-drivers.patch \
    file://next-patches/0003-clk-cix-Add-ACPI-clock-infrastructure-for-CIX-Sky1.patch \
    file://next-patches/0004-reset-Add-Sky1-reset-controllers-and-lookup-table-AP.patch \
    file://next-patches/0005-mailbox-cix-Add-ACPI-support-and-channel-lookup.patch \
    file://next-patches/0006-firmware-arm_scmi-Add-ACPI-boot-support-for-CIX-Sky1.patch \
    file://next-patches/0007-pinctrl-cix-Update-Sky1-pin-controller.patch \
    file://next-patches/0008-PCI-cadence-sky1-Add-ACPI-support-and-fixes.patch \
    file://next-patches/0009-phy-cix-Add-Sky1-USB-and-PCIe-PHY-drivers.patch \
    file://next-patches/0010-usb-Add-CIX-Sky1-USB-support.patch \
    file://next-patches/0011-drm-panthor-Add-Sky1-GPU-support-and-ACPI.patch \
    file://next-patches/0012-drm-cix-Add-Sky1-display-drivers.patch \
    file://next-patches/0013-net-Add-CIX-Sky1-networking-drivers.patch \
    file://next-patches/0015-media-cix-Add-Sky1-video-codec-VPU-driver.patch \
    file://next-patches/0016-misc-armchina-npu-Add-Zhouyi-NPU-driver-for-CIX-Sky1.patch \
    file://next-patches/0017-thermal-cix-Add-Sky1-thermal-power-domain-and-cpufre.patch \
    file://next-patches/0018-arm64-cix-Add-Sky1-miscellaneous-peripheral-drivers.patch \
    file://next-patches/0019-remoteproc-cix-Add-DSP-remoteproc-and-rpmsg-support.patch \
    file://next-patches/0020-docs-Add-Sky1-platform-porting-status-and-build-guid.patch \
    file://next-patches/0021-arm64-cix-Add-missing-Sky1-firmware-and-pinctrl-ACPI.patch \
    file://next-patches/0022-iommu-arm-smmu-v3-Add-ACPI-boot-active-bypass-STEs-f.patch \
    file://next-patches/0023-drm-add-sky1-drm-render-node-bridge-for-CIX-Sky1-SoC.patch \
    file://next-patches/0024-drm-sky1-switch-from-faux_device-to-platform_device.patch \
    file://next-patches/0025-mm-add-Mali-GPU-movable_ops-page-type-support.patch \
    file://next-patches/0026-pmdomain-arm-scmi_perf_domain-export-helpers-for-EM-.patch \
    file://next-patches/0027-drm-linlon-dp-add-diagnostic-knobs-for-AFBC-and-10bp.patch \
    file://next-patches/0028-phy-cix-usbdp-Default-to-DP-mode-for-static-outputs-.patch \
    file://next-patches/0029-drm-trilin-dptx-tear-down-DP-core-on-HPD-disconnect-.patch \
    file://next-patches/0030-drm-trilin-dptx-reset-active_stream_cnt-on-HPD-disco.patch \
    file://next-patches/0031-media-linlon-add-missing-VIDEOBUF2_DMA_SG-and-VIDEOB.patch \
    file://next-patches/0032-drm-trilin-dptx-add-CEC-over-DP-AUX-support.patch \
    file://next-patches/0033-drm-trilin-dptx-recover-link-on-HPD-bounce-with-degr.patch \
    file://next-patches/0034-Kconfig-fix-missing-dependencies-for-sky1-socinfo-an.patch \
    file://next-patches/0035-pwm-sky1-fix-NULL-dereference-in-suspend.patch \
    file://next-patches/0036-fix-allmodconfig-build-warnings-across-CIX-drivers.patch \
    file://next-patches/0037-drm-trilin-dptx-retry-AUX-on-cold-plug-timeout.patch \
    file://next-patches/0043-cix-remove-pre-silicon-EMU-FPGA-dead-code-from-vendo.patch \
    file://next-patches/0140-arm64-cix-fix-kconfig-deps-and-reachability.patch \
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
