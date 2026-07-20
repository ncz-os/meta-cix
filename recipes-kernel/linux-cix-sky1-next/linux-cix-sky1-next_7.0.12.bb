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
# - patches-next/ track plus validated cixmini 7.0.12 fixes
# - SRCREV = v7.0.12 stable tag (gregkh/linux mirror), plus validated MS-R1 fixes for SCMI/GPU/VPU/NPU/display
# - CIX Sky1 audio stack PORTED to the 7.0 base (patches 2014-2016):
#   2014 adds sound/soc/cix/ (sky1-card ASoC machine CIXH6070 + Cadence I2S
#   CIXH6011) lifted from the 6.18 LTS tree (builds unmodified on 7.0 ASoC);
#   2015 adds the ACPI binding (CIXH6020 + dma_range_map + CIXA1019 RSVL
#   reserved memory) to the mainline cix-ipbloq HDA controller; 2016 is the
#   hand-merged alc269.c Phecda fixup; 2017 fixes the cix-ipbloq ACPI
#   reset/clock resource names (reset con_id "hda", clocks sysclk/clk48m,
#   matching the Sky1 AUDSS reset lookup + ACPI clock infra) so the
#   controller actually binds on MS-R1 and the ALC269VC analog card
#   registers alongside HDMI/DP. The kernel/dma/coherent.c bits the
#   audio DMA needs (WC->WB memremap fallback + dma_declare_coherent_memory
#   export) are already carried by patch 0018.
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
DESCRIPTION = "Mainline Linux v7.0.12 + Sky1-Linux/linux-sky1 patches-next/ track \
(base next patch track plus validated cixmini 7.0.12 fixes; CIX Sky1 audio stack ported via patches 2014-2016). BETA installed \
alongside 6.18.26 LTS for runtime A/B comparison via systemd-boot menu. Same SoC \
target as the LTS kernel (Cix CP8180, Minisforum MS-R1)."
SECTION = "kernel"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

inherit kernel

LINUX_VERSION = "7.0.12"
KERNEL_LOCALVERSION = "-cix-sky1-next"
PATCHTOOL = "git"
PV = "${LINUX_VERSION}+sky1-next"
KBRANCH = "linux-7.0.y"

# Package name is versioned per Debian/Ubuntu convention (linux-image-<kver>)
# so a kernel bump produces a NEW package name instead of replacing the same
# fixed-name apt package in place -- old and new kernels coexist on disk and
# the bootloader falls back to the old one if the new kernel is bad. Also
# gives the BETA sibling a unique package namespace vs the LTS kernel so the
# two can be installed side by side without collision.
# Dots in the version segment are replaced with dashes (dpkg package names
# permit only [a-z0-9.+-]).
KERNEL_PACKAGE_NAME = "linux-image-${@ (d.getVar('LINUX_VERSION') + d.getVar('KERNEL_LOCALVERSION')).replace('.', '-').lower() }"

# 7.0.12 stable tag from gregkh/linux mirror (point releases live on stable, not torvalds)
SRCREV_kernel = "f53879e2e1e2fa053040e734c1ef8f386109a61b"

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
    file://next-patches/0009-fix-pcie-cadence-missing-enum-for-7.0.9.patch \
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
    file://next-patches/0140-arm64-cix-fix-kconfig-deps-and-reachability.patch \
    file://next-patches/2001-gpio-gpio-cadence-fix-crashing-pcie-on-cix-p1-acpi-s.patch \
    file://next-patches/2002-drm-linlon-dp-remove-existing-drivers-that-may-own-t.patch \
    file://next-patches/2004-acpi-sta-quirk-for-7.0.9.patch \
    file://next-patches/2005-armchina-npu-fix-pm-runtime-put-void-7.0.9.patch \
    file://next-patches/2006-armchina-npu-sky1-null-pd-core-guard.patch \
    file://next-patches/2007-acpi-sta-quirk-add-cixh4010-npu-cores.patch \
    file://next-patches/2008-armchina-npu-force-D0-before-probe.patch \
    file://next-patches/2009-armchina-npu-msr1-smmu-32bit-dma-constraint.patch \
    file://next-patches/0039-pmdomain-scmi_pm_domain-add-fwnode-provider-for-ACPI.patch \
    file://next-patches/2011-fix-acpi-force-enable-hidden-Sky1-SCMI-NPU-child-dev.patch \
    file://next-patches/2012-fix-panthor-gate-Sky1-gpu_core-clock-fallback.patch \
    file://next-patches/2013-fix-display-harden-Sky1-DPTX-audio-and-fbdev-restore.patch \
    file://next-patches/2014-ASoC-cix-Add-CIX-Sky1-ASoC-machine-and-Cadence-I2S-d.patch \
    file://next-patches/2015-ALSA-hda-cix-ipbloq-Add-ACPI-binding-DMA-range-map-a.patch \
    file://next-patches/2016-ALSA-hda-realtek-Add-CIX-Sky1-Phecda-board-fixup.patch \
    file://next-patches/2017-ALSA-hda-cix-ipbloq-Fix-ACPI-reset-clock-resource-na.patch \
    file://next-patches/2018-armchina-npu-drop-irqf-oneshot.patch \
    file://next-patches/2019-hwmon-scmi-dont-skip-thermal-zone-on-config-set-fail.patch \
    file://next-patches/2020-drm-cix-edp-panel-acpi-desc-properties.patch \
    file://next-patches/2021-drm-cix-linlondp-defer-on-missing-aclk-instead-of-failing.patch \
    file://next-patches/2022-phy-cix-usb3-defer-on-missing-clocks-fix-ref-clk-check.patch \
    file://next-patches/2023-usb-cdns3-cdnsp-sky1-defer-on-missing-clocks.patch \
    file://next-patches/2024-i2c-cadence-defer-on-missing-clock.patch \
    file://next-patches/2025-clocksource-sky1-defer-on-missing-timer-clocks.patch \
    file://next-patches/2026-soc-cix-acpi-resource-lookup-tighten-badly-specified-guard.patch \
"


COMPATIBLE_MACHINE = "(cixmini)"

# This recipe does NOT provide virtual/kernel — that role belongs to
# linux-cix-sky1 (LTS, 6.18.26). This is the BETA sibling, installed
# alongside via explicit-build.
S = "${UNPACKDIR}/${BB_GIT_DEFAULT_DESTSUFFIX}"

PROVIDES = "${PN}"

do_configure:prepend() {
    cd ${S}
    cp ${UNPACKDIR}/config.sky1-next ${B}/.config
    sed -i "s|^CONFIG_EXTRA_FIRMWARE=.*|# CONFIG_EXTRA_FIRMWARE is not set|" ${B}/.config
    sed -i "/^CONFIG_EXTRA_FIRMWARE_DIR=/d" ${B}/.config
    oe_runmake ARCH=arm64 O=${B} olddefconfig
}

KERNEL_IMAGETYPE = "Image"
KERNEL_DEVICETREE = " \
    cix/sky1-orion-o6.dtb \
"
