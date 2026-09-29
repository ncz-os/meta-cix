# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Linux kernel for Cix Sky1 / CP8180 -- NCZ 7.3 track (NEXT/test, not yet
# the shipping/stable release -- that is 7.2.x, see linux-cix-sky1-ncz_7.2.bb).
#
# Base: torvalds mainline v7.3-rc5, peeled commit 72d3fcf802c45d00b300f25b848a93c3a2bd7c7e.
# (v7.3-rc5 is NOT in linux-stable -- rc tags live in Linus's tree. Stable's
# refs/tags/v7.3-rc5^{} is absent; torvalds's refs/tags/v7.3-rc5^{} resolves
# to 72d3fcf802c4.)
#
# The recipe pins the peeled upstream v7.3-rc5 commit in SRCREV_kernel and
# applies the complete, rebased CIX port as sky1-ncz-v7.3-rc5-port.patch.
# The equivalent 207-commit review branch is kernel-73rc5-port.
#
# Patch decisions vs. the dry-run 205-patch replay (operator accepted the
# orchestrator advisory 2026-09-29; each item re-verified against source, see
# cix-installer docs/reports/2026-09-29-sky1-rc5-advisory-implementation.md).
# None of the raw 7.2 patches below is in SRC_URI: this recipe applies ONE
# consolidated diff of the kernel-73rc5-port branch, so "drop" means "the raw
# patch is not re-applied", NOT "its content is absent from the tree".
#   0027 (Cadence Sky1 vendor PCIe) and 0029 (Cadence ACPI clock release):
#        mainline b5672f9463f2 / ea34744eb094 / d70e964dc099 add the HPA flag
#        and LTSSM debugfs only; they do NOT cover 0027. The port carried
#        cdns_pcie_hpa_host_restore() (65108d59b2be), register_syscore() and
#        the LMR base block (23d4657ab234). The rest (HPA ECAM region,
#        sky1_cdns_pcie_find_capability(), HPA root-port base, the
#        "sky1-pcie-cix" rename, ACPI vendor-id/device-id/no-inbound-bar)
#        and 0029's CLKT-keyed clocks are re-ported for native mode in
#        0002-PCI-cadence-sky1-cix-restore-ACPI-native-mode-on-v7.3.patch
#        (operator decision 2026-09-29: native PCIe wanted on 7.3). Default
#        cmdline sky1_pcie_native=off is unchanged.
#   0058 (fwnode_drm_find_panel export): dropped. Its forward-port
#        3d3bd1842516 is reverted and the only caller (0008 trilin_dp_probe)
#        is re-aimed at the counted of_drm_find_panel() by
#        0001-drm-cix-trilin-dp-drop-fwnode_drm_find_panel-use-cou.patch below;
#        drm_panel.[ch] are byte-identical to v7.3-rc5 again.
#   0074 (6.6->7.2 API drift): not re-applied. H1-H14 are present in the port
#        tree; H15-H17 are superseded by the 0172-shaped cix_scmi_em.[ch] from
#        9fa83019a3ea (not by 0066/0068/0069, whose 0069 copy still called
#        perf_ops->device_domain_id()).
#   0004/0005/0065/0105: not re-applied (there is no per-patch SRC_URI to
#        delete them from). 0105 is covered (no .prepare op, no put_noidle).
#        0004/0005/0065 are only PARTLY covered by mainline 3730fe6032d9 /
#        7cd3ca90d921 / b5fa9d3beec4 (DT AUDSS clock + reset). Their ACPI
#        halves are load-bearing and stay: CIXHA010 provider a4de88c36585,
#        reset ACPI lookup db1fd834dae3 + cad63faa518b, AUDSS CIXH6061 match
#        77b1624778cc.
#   NPU in-tree chain 0119 0120 0121 0123 0125 0159 0220: DROPPED BY POLICY.
#        The NPU ships as the DKMS cix-npu-driver (aipu), never in-tree
#        (port commit 3da51e546c4b records the verdict).
#   CLKT chain 0096 0138 0147 0148 0157 0168: drivers/clk/cix is identical
#        to the r277 (v7.2.8) tree except clk-sky1-audss.c (mainline driver
#        + port fixes), so the chain is at r277 parity; nothing to port.
#   0172: carried by 9fa83019a3ea. cix_scmi_register_em() is called by the
#        out-of-tree mali_kbase DKMS (mali_kbase_devfreq.c), not in-tree.
#   0089: acpi_clk.c half present; the runtime-PM early-boot gate is
#        re-ported in 0003-PM-runtime-restore-the-CIX-Sky1-early-boot-runtime-P.patch.
#   0001 and 0091: already carried (0001: 3d7823f9c2b2 + 535db5995054;
#        0091: 6d3cab5b0154 + 9291c638f97a).
#   0212 (cacheinfo PPTT global IDs): NOT ported; no 7.3 failure has been
#        observed; the r279 boot sheet compares cache topology with 7.2.8.
#   0216 (resctrl MB_PROP): NOT ported; inert (CONFIG_ARM64_MPAM is off).
#   r279 config: CONFIG_MODULE_COMPRESS off (fleet rule: never xz a .ko).
#
# Expected replay result: ~178 applied of 205, matching rc3/rc4 exactly.
# rc4 and rc5 have an identical failure set, so a result close to that is
# CORRECT, not a regression. rc3 and rc4 both already shipped as Sky1 test
# kernels on this same footing.
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
FILESEXTRAPATHS:prepend := "${THISDIR}/linux-cix-sky1-ncz-7.3-rc5:"

LINUX_VERSION = "7.3-rc5"
KERNEL_LOCALVERSION = "-sky1-ncz"
PV = "7.3-rc5+ncz"
PR = "r3"
KBRANCH = "kernel-73rc5-port"
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
# 2026-09-11 (4th bitbake attempt): compile failed on a missing header
# linux/cix/cix_scmi_em.h. The cix_scmi_em.c file in the port was the
# pre-0074 single-arg cix_scmi_register_em(struct device *dev) version
# from patch 0069 (last commit touching it: 63f4b57c286f), and the header
# file itself was never carried into this tree at all -- both 0074
# (which CREATED include/linux/cix/cix_scmi_em.h) and 0172 (which evolved
# both to the 2-arg cix_scmi_register_em(dev, perf_dev) signature using
# scmi_perf_domain_power_scale()/est_power()) never landed on this
# forward-port. This is the same missing-patch-never-carried-into-7.3
# sub-pattern the loop instructions explicitly call out for missing-header
# failures (see ef818e8dc33d commit message). Copied both files
# byte-for-byte from the 7.2.5 reference tree (.../7.2.5+ncz/kernel-
# source/) -- the post-copy diff against the reference is zero. No API
# drift detected: include/linux/scmi_perf_domain.h exists in 7.3-rc2
# with the required helper signatures, and CONFIG_CIX_SCMI_ENERGY_MODEL
# is defined in drivers/thermal/cix/Kconfig.
# SRCREV_kernel is now the tip of kernel-73rc2-port (ebb3f4e1874e) so
# the build picks up all seven forward-port fixes together.
# 2026-09-11 (5th bitbake attempt): compile passed do_compile but FAILED
# at the final vmlinux link stage -- cdns_pcie_host_restore undefined.
# Root cause: pci-sky1-cix.c's sky1_pcie_resume_noirq() calls
# cdns_pcie_host_restore(rc) (extern + 2 call sites), but no such
# function exists anywhere in this tree (grep confirms: zero
# definitions, only the extern decl + the call sites in pci-sky1-cix.c).
# The 7.2.5 reference uses cdns_pcie_hpa_host_restore() (note the _hpa
# infix), defined in pcie-cadence-host-hpa.c:471 and prototyped in
# pcie-cadence.h:486. The 7.3-rc2 port renamed it to the wrong shorter
# name during the forward-port without adding a corresponding
# definition -- same missing-patch-carried-forward sub-pattern as the
# cix_scmi_em fix (ebb3f4e1874e) and the cix-plat SMMU guards
# (ef818e8dc33d). 7.2 series patch
# 0027-pci-cadence-sky1-cix-fix-sky1-cix-vendor-pcie-driver.patch
# contains the cdns_pcie_hpa_host_restore() definition but the
# corresponding hunk was never ported.
# Fix: restored the _hpa infix at the 2 call sites in pci-sky1-cix.c,
# added the missing function definition to pcie-cadence-host-hpa.c
# (copied from 7.2.5 line 471, with one trivial substitution:
# cdns_pcie_link_up -> cdns_pcie_hpa_link_up to match the HPA link-up
# callback name in this tree), added the prototype + static inline
# fallback to pcie-cadence.h (mirroring 7.2.5 lines 486 and 507-510),
# removed the now-redundant local extern decl from pci-sky1-cix.c.
# See commit 78a45c61229d for the full commit message.
# SRCREV_kernel is now the tip of kernel-73rc2-port (78a45c61229d) so
# the build picks up all eight forward-port fixes together.
# 2026-09-11 (6th bitbake attempt): vmlinux compiled clean (no more
# cdns_pcie_hpa_host_restore link error), do_compile_kernelmodules
# then failed on a single cix_edp_panel.c call to
# of_drm_get_panel_orientation() -- the symbol was renamed upstream
# to drm_of_get_panel_orientation() in 7.3 (declaration moved from
# include/drm/drm_panel.h to include/drm/drm_of.h:52, signature
# unchanged). Both 7.2.5 reference and 7.3-rc2 cix_edp_panel.c still
# use the old name, but only the 7.3-rc2 build fails because the old
# symbol no longer exists in this tree. Grep of all 7.2 patches shows
# no patch touches the symbol name -- this is a NEW upstream API
# rename the 7.3-rc2 forward-port didn't pick up, not a dropped hunk
# of an existing patch. Renamed the call site + added <drm/drm_of.h>
# include. vmlinux now builds clean and modules have begun compiling.
# See commit aec39fe3c662.
# SRCREV_kernel is now the tip of kernel-73rc2-port (aec39fe3c662) so
# the build picks up all nine forward-port fixes together.
# 2026-09-12 (7th bitbake attempt): real-metal boot-test on O6N
# (192.168.207.3) of the aec39fe3c662 kernel exposed a 10th bug this
# session, in a new sub-class: a forward-port that re-ported ONE
# hunk of a multi-hunk 7.2 patch but forgot its sibling. SCMI
# channel setup failed at protocol 0x10 BASE with
# "arm-scmi arm-scmi.1.auto: failed to setup channel for
# protocol:0x10", cascading into NPU devfreq init failure
# (aipu), linlondp-cluster DPU probe failure (no /dev/dri), and
# no mali_kbase probe for CIXH5000 GPU -- ALL three regress at
# once because every firmware-driven subsystem on this SoC goes
# through SCMI, and SCMI's mailbox transport can't talk to the
# SCP without a working cix-mailbox controller registered under
# ACPI. Root cause: the v7.3-rc2 forward-port of patches-7.2/0001
# (commit a0ea259f3d27) re-ported the ACPI branch in
# cix_mbox_probe() correctly but forgot to add the matching
# struct acpi_device_id cix_mbox_acpi_match[] = { { "CIXHA001",
# 0 }, ... } table + MODULE_DEVICE_TABLE(acpi, ...) +
# .acpi_match_table = ACPI_PTR(...) on the platform_driver.
# Without those, the driver never binds to CIXHA001 ACPI devices
# (the CIX sky1 mailbox controllers), and SCMI's
# mbox_request_channel(cl, 0) during scmi_chan_setup() loops on
# -EPROBE_DEFER until it gives up. Fix: ported the missing hunks
# verbatim from patches-7.2/0001.
# See commit 32e112b6d7aa for the full commit message.
# SRCREV_kernel is now the tip of kernel-73rc2-port (32e112b6d7aa) so
# the build picks up all ten forward-port fixes together.
# Bumped to a49de0beac8c: 11th (final) forward-port fix, the CIX clock
# driver rewrite that adds the CIXHA010 ACPI clock provider driver
# (clk-sky1-acpi.c, acpi_clk.c, acpi_scmi_clk.c, cix-clk-debug.c,
# clk.c, acpi_clk.h, clk.h, sky1-clk.h, acpi_clk-scmi.h -- the
# post-0065 state of patches-7.2/0065). Without this, CIXHA010 stays
# unbound and every device with _DEP on it (CIXH5010 DPU, CIXH502F,
# CIXH2030..9, CIXH1002, CIXH1003, CIXH200B, CIXH2011, CIXH3010,
# CIXH6070) stays in permanent -EPROBE_DEFER. linlondp-cluster
# (CIXH50C0) finds no slave mdev, "ACPI cluster: no DPUs", no /dev/dri.
# See commit a49de0beac8c for the full commit message.
SRCREV_kernel = "72d3fcf802c45d00b300f25b848a93c3a2bd7c7e"

# NOTE: fetches from a LOCAL bare mirror under this build container's workdir mount
# (the ncz-yocto-y6 podman sandbox has no SSH keys, so it cannot reach the
# ARGONAS ssh:// remote directly). The canonical pushed copies are
# gitlab.com/ncz-os/linux-cix.git + the ARGONAS bare mirror at
# /mnt/datapool/git/ncz-os/linux-cix.git, branch kernel-73rc5-port.
# Local mirror at ~/yocto-work/kernel-mirrors/linux-cix-kernel-73rc5-port.git
# was created from ~/linux-port-v7.3-rc5 on 2026-09-27 by cherry-picking all
# 207 kernel-73rc4-port commits onto peeled v7.3-rc5^{} = 72d3fcf802c4.
# Rebuild with `git clone --bare ~/linux-port-v7.3-rc5` if it goes stale again.
SRC_URI = " \
    git:///workdir/kernel-mirrors/linux-cix-kernel-73rc5-port.git;protocol=file;branch=${KBRANCH};name=kernel \
    file://config-7.3-rc5.defconfig \
    file://sky1-ncz-v7.3-rc5-port.patch \
    file://0001-drm-cix-trilin-dp-drop-fwnode_drm_find_panel-use-cou.patch \
    file://0002-PCI-cadence-sky1-cix-restore-ACPI-native-mode-on-v7.3.patch \
    file://0003-PM-runtime-restore-the-CIX-Sky1-early-boot-runtime-P.patch \
"

COMPATIBLE_MACHINE = "(cixmini)"
S = "${UNPACKDIR}/${BB_GIT_DEFAULT_DESTSUFFIX}"

PROVIDES = "${PN} virtual/kernel"

do_configure:prepend() {
    cd ${S}
    cp ${UNPACKDIR}/config-7.3-rc5.defconfig ${B}/.config
    oe_runmake ARCH=arm64 O=${B} olddefconfig
}

KERNEL_IMAGETYPE = "Image"
KERNEL_DEVICETREE = " \
    cix/sky1-orion-o6.dtb \
"
# SRCREV_kernel is now the tip of kernel-73rc2-port (b58f477c30f6) so the audss ACPI match-table fix (CIXH6061 audio bind) is included -- 12th forward-port bug.
# SRCREV_kernel is now the tip of kernel-73rc2-port (f1a2007e424f) -- the REAL audio fix (syscon regmap, not just ACPI match table), 13th forward-port bug. All diagnostic dev_err instrumentation reverted.
# 2026-09-13: rebased all 207 kernel-73rc2-port commits from v7.3-rc2
# onto v7.3-rc4 as kernel-73rc4-port. All commits applied cleanly; none
# needed conflict resolution or were dropped as already upstream.

# 2026-09-20: replayed all 207 kernel-73rc3-port commits onto peeled
# v7.3-rc4 commit 93f51579e7df248780214094418f205253383cc5. The replay
# completed without conflicts or dropped commits; range-diff reports all
# 207 commits patch-equivalent. Raw 205-patch audit: 178 applied, 27 failed;
# all 27 are represented by the corrected forward-port commits in the
# rebased series and consolidated recipe patch.

