# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Linux kernel for Cix Sky1 / CP8180 -- NCZ 7.2 track.
#
# Base: torvalds mainline v7.2-rc1 (no linux-7.2.y stable branch yet, so
#       KBRANCH=master + SRCREV pinned to the v7.2-rc1 tag commit).
# Patches: patches-7.2 = cixtech 2026q2 vendor driver set
#   (github.com/cixtech/cix_opensource__linux @ cix_k6.6.89_2026q2)
#   forward-ported from k6.6.89 onto v7.2-rc1, PLUS the NCZ core ACPI
#   glue patches (from patches-7.1) that still apply.
#   Upstream v7.2-rc1 already carries: sky1-orion-o6 DTS, cix-mailbox,
#   pci-sky1 (Cadence HPA, OF), pinctrl-sky1, reset-sky1, HDA cix-ipbloq
#   -- those are used as-is with NCZ ACPI deltas on top.
#   NOT ported yet: panthor ACPI support (v7.2 split panthor_regs.h;
#   needs a fresh forward-port), vendor cdns3 core reset/u3-disable hook
#   invocation (stage-2; glue registers hooks, core does not call them).
# Config: config-7.2.defconfig = 7.1 NCZ config + olddefconfig on v7.2-rc1
#   + CIX 2026q2 symbols + CONFIG_BTRFS_FS=y (built-in; btrfs root without
#   initrd module).
# RTC (RA8900CE, ACPI HID RX008900): RESOLVED. cixtech vendor issue #39
#   (Orange Pi 6 Plus, 2026-07-03) = mainline rtc-ds1307 supports ra8900
#   only via i2c_device_id (no ACPI table), so ACPI-enumerated RTC never
#   binds -> rtc-efi fallback, clock resets. Vendor fix = patch
#   0049-add-hym8563-rx8900-rtc-driver. We carry it as patches-7.2/
#   0040-add-hym8563-rx8900-rtc-driver: rtc-rx8900.c has acpi_match
#   RX008900 (=y built-in, "Third Party RX8900 Driver"), rtc-hym8563.c
#   has acpi_match HYM8563. Full ACPI chain present: i2c-cadence
#   (CIXH200B, =y) -> RTC0 child (RX008900) -> rtc-rx8900. Battery-backed
#   hwclock works at boot without initrd. No further action needed.
# AUDSS clk+reset: kept as cixtech 2026q2 self-contained drivers
#   (clk-sky1-audss.c, reset-sky1-audss.c; compat "cix,sky1-audss-reset",
#   ACPI HID CIXH6062). The upstream "Add Cix Sky1 AUDSS clock and reset
#   support" series (Zabel reviewing ~2026-06-30) is NOT in v7.2-rc1 and
#   is DT-oriented; adopting an in-review series would be worse than the
#   vendor driver, and only the vendor form carries the ACPI HID cixmini
#   needs. The audss determine_rate migration (old hand-patch 9001) is
#   already in the vendor clk driver, so NO divergent hand-patch is
#   carried. RECONCILE-WHEN-LANDED: once the audss series merges in a
#   stable release, drop these two vendor files and adopt the mainline
#   form, forward-porting the ACPI HID if upstream stays DT-only.
# Required cmdline: clk_ignore_unused acpi_scmi_en=off; UEFI O/S HW
#   Description = ACPI. acpi_scmi_en=off keeps the 2026q2 deny-handler
#   from blocking CIXHA010 so the BIOS-1.0 CLKT clkdev bridge
#   (clk-sky1-acpi, patch 0096) can provide the 207 consumer clocks;
#   without it every apb/pclk consumer (PCIe/USB PHYs, pwm, uart) is
#   clockless and NVMe never appears (patches 0093-0098 chain).

SUMMARY = "NCZ Linux kernel for Cix Sky1 / CP8180 (v7.2-rc1 + CIX 2026q2 patch set)"
DESCRIPTION = "NCZ kernel: mainline Linux v7.2-rc1 plus the cixtech 2026q2 Sky1 driver set forward-ported by NCZ. Not a CIX/vendor release."
SECTION = "kernel"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

inherit kernel
FILESEXTRAPATHS:prepend := "${THISDIR}/linux-cix-sky1-ncz-7.2:"

LINUX_VERSION = "7.2-rc1"
KERNEL_LOCALVERSION = "-ncz"
PATCHTOOL = "git"
PV = "7.2+ncz"
KBRANCH = "master"
KERNEL_PACKAGE_NAME = "kernel-${PN}"

# v7.2-rc1 tag commit (torvalds mainline, on master)
SRCREV_kernel = "dc59e4fea9d83f03bad6bddf3fa2e52491777482"

SRC_URI = " \
    git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git;protocol=https;branch=${KBRANCH};name=kernel \
    file://config-7.2.defconfig \
    file://patches-7.2/0001-mailbox-add-acpi-support-to-cix-mailbox-driver.patch \
    file://patches-7.2/0002-acpi-Add-a-property-reference-count-interface.patch \
    file://patches-7.2/0003-clk-clk-scmi-register-clkdev-for-acpi.patch \
    file://patches-7.2/0004-clk-add-cix-clk-driver.patch \
    file://patches-7.2/0005-reset-add-cix-reset-driver.patch \
    file://patches-7.2/0006-soc-add-cix-acpi-resource-lookup-driver.patch \
    file://patches-7.2/0007-remoteproc-add-cix-dsp-remoteproc-driver.patch \
    file://patches-7.2/0008-drm-add-cix-linlon-dp-driver.patch \
    file://patches-7.2/0009-irqchip-add-cix-sky1-pdc-driver.patch \
    file://patches-7.2/0010-sound-hda-add-cix-ipbloq-hda-driver.patch \
    file://patches-7.2/0011-kernel-dma-Export-dma_declare_coherent_memory-for-mo.patch \
    file://patches-7.2/0012-mfd-syscon-add-acpi-support-for-cix-soc.patch \
    file://patches-7.2/0013-dma-arm-dma350-add-acpi-support-for-cix-soc.patch \
    file://patches-7.2/0014-gpio-add-acpi-support-to-cadence-driver.patch \
    file://patches-7.2/0015-clk-clkdev-increase-clkdev-MAX_CON_ID-from-16-to-32.patch \
    file://patches-7.2/0016-i2c-add-acpi-support-for-cadence-driver.patch \
    file://patches-7.2/0017-firmware-add-cix-dsp-ipc-driver.patch \
    file://patches-7.2/0018-sound-soc-add-cix-sof-driver.patch \
    file://patches-7.2/0019-sound-soc-add-cix-soc-support.patch \
    file://patches-7.2/0020-syscon-add-device_syscon_regmap_lookup_by_property.patch \
    file://patches-7.2/0021-phy-add-cix-phy-driver.patch \
    file://patches-7.2/0022-typec-add-rts5453-driver.patch \
    file://patches-7.2/0023-soc-add-cix-acpi-usb-scan-handler.patch \
    file://patches-7.2/0024-pwm-add-pwm-support-for-CIX-SoC.patch \
    file://patches-7.2/0025-disable-acpi-pcie-devices.patch \
    file://patches-7.2/0026-add-cix-vendor-pci-driver.patch \
    file://patches-7.2/0027-pci-cadence-sky1-cix-fix-sky1-cix-vendor-pcie-driver.patch \
    file://patches-7.2/0028-regulator-add-acpi-support.patch \
    file://patches-7.2/0029-pci-cadence-sky1-fix-clk-under-ACPI.patch \
    file://patches-7.2/0030-hda-cix-ipbloq-skip-init-of-verb-table-at-resume.patch \
    file://patches-7.2/0031-arm-smmu-v3-add-suspend-resume-support.patch \
    file://patches-7.2/0032-pci-cadence-add-PCI_SKY1_HOST_CIX-for-bsp-driver.patch \
    file://patches-7.2/0033-panthor-set-DPM_FLAG_NO_DIRECT_COMPLETE-for-STR-on-s.patch \
    file://patches-7.2/0034-thermal-set-thermal_zone-type-from-firmware-in-acpi_.patch \
    file://patches-7.2/0035-DPTSW-19618-linlon-dp-Set-AFBC-32x8-to-the-highest-p.patch \
    file://patches-7.2/0036-pwm-sky1-check-pwm-state-before-enable-disable-clk-i.patch \
    file://patches-7.2/0037-clocksource-add-sky1-gpt-timer-driver.patch \
    file://patches-7.2/0038-drm-cix-fix-hdmi-str.patch \
    file://patches-7.2/0039-pinctrl-sky1-add-acpi-support.patch \
    file://patches-7.2/0040-add-hym8563-rx8900-rtc-driver.patch \
    file://patches-7.2/0041-arm64-add-model-name-for-Cix-Sky1-Soc.patch \
    file://patches-7.2/0042-add-cix-thermal-ipa-driver.patch \
    file://patches-7.2/0043-add-thermal-IPA-support.patch \
    file://patches-7.2/0044-DPTSW-25537-drm-cix-dptx-HPD-fast-replug-link-train-.patch \
    file://patches-7.2/0045-watchdog-sbsa-Update-the-value-of-the-refresh-regist.patch \
    file://patches-7.2/0046-drm-cix-dptx-trigger-connector-hotplug-on-resume_ear.patch \
    file://patches-7.2/0047-dptx-check-null-pointer-in-trilin_dp_panel_hw_cfg.patch \
    file://patches-7.2/0048-firmware-arm_scmi-mailbox-set-max_rx_timeout_ms-to-3.patch \
    file://patches-7.2/0049-optee-check-system_state-when-probing-at-shutdown.patch \
    file://patches-7.2/0050-ACPI-thermal-bind-devfreq-cooling-devices-via-devfre.patch \
    file://patches-7.2/0051-thermal-ipa-enhance-ipa.patch \
    file://patches-7.2/0052-add-cix_dst-driver.patch \
    file://patches-7.2/0053-linlondp-fix-build-of-debugfs.patch \
    file://patches-7.2/0054-linlondp-add-missing-headers.patch \
    file://patches-7.2/0055-linlondp-add-api-fix-up-to-6.18.patch \
    file://patches-7.2/0056-linlondp-disable-enable_render-by-default.patch \
    file://patches-7.2/0057-linlondp-set-DRM_FBDEV_DMA_DRIVER_OPS-for-linlondp-k.patch \
    file://patches-7.2/0058-drm-panel-add-fwnode_drm_find_panel.patch \
    file://patches-7.2/0059-gpio-gpio-cadence-fix-crashing-pcie-on-cix-p1-acpi-s.patch \
    file://patches-7.2/0060-drm-linlon-dp-remove-existing-drivers-that-may-own-t.patch \
    file://patches-7.2/0061-acpi-add-backward-complibility-to-old-firmware-with-.patch \
    file://patches-7.2/0062-rtc-rx8900-drop-removed-of_gpio-header-include.patch \
    file://patches-7.2/0063-drm-cix-add-color-format-compat-macros-for-v7.1.patch \
    file://patches-7.2/0064-soc-cix-acpi-resource-lookup-resolve-dev_id-by-ACPI-.patch \
    file://patches-7.2/0065-clk-cix-replace-with-cixtech-2026q2-k6.6.89-driver-s.patch \
    file://patches-7.2/0066-soc-cix-replace-with-cixtech-2026q2-platform-ACPI-su.patch \
    file://patches-7.2/0067-drm-cix-replace-linlon-dp-dptx-with-cixtech-2026q2-o.patch \
    file://patches-7.2/0068-phy-cix-replace-with-cixtech-2026q2.patch \
    file://patches-7.2/0069-thermal-cix-replace-IPA-drivers-with-cixtech-2026q2.patch \
    file://patches-7.2/0070-ASoC-HDA-cix-replace-SOF-machine-ipbloq-with-cixtech.patch \
    file://patches-7.2/0071-firmware-cix-replace-dsp-ipc-with-cixtech-2026q2.patch \
    file://patches-7.2/0072-usb-cdns3-replace-sky1-platform-glue-with-cixtech-20.patch \
    file://patches-7.2/0073-HDA-drop-vendor-hda_cix_ipbloq-upstream-sound-hda-co.patch \
    file://patches-7.2/0074-cix-fix-6.6-7.2-API-drift-in-clk-soc-phy-thermal-fir.patch \
    file://patches-7.2/0075-firmware-arm_scmi-add-acpi-support-to-SCMI-NCZ-0003-.patch \
    file://patches-7.2/0076-firmware-arm_scmi-add-backward-complibility-to-old-f.patch \
    file://patches-7.2/0077-pmdomain-add-acpi-support-to-cix-soc-NCZ-0008-forwar.patch \
    file://patches-7.2/0078-pmdomain-fix-dev_pm_domain_attach_by_name-for-sky1-m.patch \
    file://patches-7.2/0079-usb-cdns3-wire-CIX-Sky1-USBSSP-glue-into-v7.2-unifie.patch \
    file://patches-7.2/0080-ASoC-cix-fix-6.6-7.2-API-drift-rtd-id-daifmt-parse-d.patch \
    file://patches-7.2/0081-drm-cix-fix-6.6-7.2-API-drift-in-linlon-dp-dptx.patch \
    file://patches-7.2/0082-pmdomain-scmi-export-perf-est-power-power-scale-by-d.patch \
    file://patches-7.2/0083-soc-cix-acpi-reserved-memory-without-fdt_reserved_me.patch \
    file://patches-7.2/0084-drm-panthor-fix-7.2-API-drift-add-cix-sky1-acpi-scmi.patch \
    file://patches-7.2/0085-firmware-arm_scmi-mailbox-fix-acpi-driver-data-type-confusion.patch \
    file://patches-7.2/0086-drm-panthor-try-named-gpu_core-acpi-clock-before-bare-null-lookup.patch \
    file://patches-7.2/0087-reset-sky1-restore-acpi-support.patch \
    file://patches-7.2/0088-pmdomain-scmi-perf-defer-fwnode-provider.patch \
    file://patches-7.2/0089-clk-cix-acpi-pm-runtime-acpi-power-mgmt-resume-gate.patch \
    file://patches-7.2/0090-acpi-pm-skip-notifier-removal-in-probe-failure-cleanup.patch \
    file://patches-7.2/0091-clk-reset-sky1-audss-dont-defer-on-missing-parents-regmap.patch \
    file://patches-7.2/0092-drm-panthor-explicitly-enable-core-clock-before-hw-init.patch \
    file://patches-7.2/0093-firmware-arm_scmi-activate-implemented-protocols-on-acpi.patch \
    file://patches-7.2/0094-drm-panthor-sky1-acpi-defer-probe-gpu-clock-not-ready.patch \
    file://patches-7.2/0095-phy-cix-defer-probe-acpi-clkdev-clocks-not-registered.patch \
    file://patches-7.2/0096-clk-cix-sky1-clkt-clkdev-bridge-bios10.patch \
    file://patches-7.2/0097-soc-cix-acpi-resource-lookup-v1-bios10.patch \
    file://patches-7.2/0098-soc-cix-v1-lookup-owns-cixa1019.patch \
    file://patches-7.2/0099-pci-sky1-acpi-standard-ecam-mode-knob.patch \
    file://patches-7.2/0100-iommu-smmu-v3-sky1-pcie-bypass-ste-ats-override.patch \
    file://patches-7.2/0101-pci-sky1-acpi-block-cixh2020-standard-mode.patch \
"

S = "${WORKDIR}/git"
COMPATIBLE_MACHINE = "(cixmini)"
PROVIDES = "${PN} virtual/kernel"

do_configure:prepend() {
    cd ${S}
    cp ${WORKDIR}/config-7.2.defconfig ${B}/.config
    oe_runmake ARCH=arm64 O=${B} olddefconfig
}

KERNEL_IMAGETYPE = "Image"
KERNEL_DEVICETREE = " \
    cix/sky1-orion-o6.dtb \
"
