# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Cix Sky1 Mali-G720-Immortalis GPU kernel module (out-of-tree).
# Source: minisforum-cix-p1-repo/cix_opensource__gpu_kernel
# (the same blob that ships as the cix-gpu-driver .deb on the Cix Debian
# image; we build it from source here against our linux-cix-msr1 kernel).

require cix-modules.inc

SUMMARY = "Cix Sky1 Mali-G720 GPU kernel module"
DESCRIPTION = "Out-of-tree kernel module for the ARM Mali-G720-Immortalis GPU as integrated into Cix Sky1 / CP8180. Source from Minisforum's published downstream tree."

PV = "1.0+cix"
SRCREV = "a752e916d18484dd4f67bb6b351543447c978135"

SRC_URI = " \
    git://github.com/minisforum-cix-p1-repo/cix_opensource__gpu_kernel.git;protocol=https;branch=a0fb5/5cf6e/cix_p1_mg_dev;name=gpukmd \
    file://0001-mali-kbase-wq-unbound-flags.patch \
    file://0002-drivers-base-arm-fix-external-module-include-path.patch \
    file://0003-mm-get-unmapped-area-5arg.patch \
    file://0004-midgard-kbuild-fix-src-normalization.patch \
    file://0005-mali-kbase-mem-migrate-page-movable-api-removed.patch \
    file://0006-mali-kbase-hrtimer-setup-api.patch \
    file://0007-mali-kbase-fence-ops-drop-fence-value-str.patch \
    file://0008-midgard-makefile-route-config-defines-via-kcflags.patch \
    file://0009-mali-kbase-hrtimer-setup-on-stack-api.patch \
    file://0010-mali-kbase-devfreq-cix-scmi-register-em-perf-dev.patch \
    file://0011-mali-kbase-timer-delete-rename.patch \
    file://0012-mali-kbase-dma-fence-signal-void-return.patch \
    file://0013-mali-kbase-shmem-file-setup-vma-flags-t.patch \
    file://0014-mali-kbase-mmap-non-ack-vma-search.patch \
    file://0015-mali-kbase-ipa-null-model-guard.patch \
"
SRCREV_FORMAT = "gpukmd"

LIC_FILES_CHKSUM = "file://license.txt;md5=13e14ae1bd7ad5bff731bba4a31bb510"

# The Cix gpu_kernel tree uses gpu.mk (driven by Minisforum's
# build-scripts/build-gpu-driver.sh in their downstream pipeline). The shared
# cix-modules.inc do_compile / do_install invokes this makefile.
CIX_DRIVER_MAKEFILE = "gpu.mk"

# Mali kbase produces a single mali_kbase.ko (matches Sky1-Linux/cix-gpu-kmd
# DKMS packaging).

# LOCALVERSION=-sky1-ncz below: STAGING_KERNEL_DIR/setlocalversion does not
# reliably thread linux-cix-sky1-ncz_7.2.bb KERNEL_LOCALVERSION into OOT module
# builds -- confirmed 2026-07-28 (utsrelease.h came out bare 7.2.0-rc5 without
# this override, causing a vermagic mismatch against the deployed kernel).
# gpu.mk is an Android-product makefile: map its TARGET_* / CIX_* vars onto Yocto
# paths, force the writable output dir, the cross prefix, and the "gpu" target.
# do_compile:prepend -- pin the correct kernel release string into
# STAGING_KERNEL_BUILDDIR before gpu.mk runs. Root cause (2026-07-28,
# confirmed via three separate build attempts + a live GNU make precedence
# test): STAGING_KERNEL_BUILDDIR resolves (via
# work-shared/${MACHINE}/kernel-build-artifacts, a symlink) to the SAME
# ${B}=build/ tree the kernel recipe's own do_compile uses. gpu.mk's inner
# `make -C $(KERNEL_SRC) M=... modules` sub-make does not reliably forward
# LOCALVERSION into that tree's own utsrelease.h/kernel.release regeneration,
# so it silently reverts to bare KERNELVERSION (e.g. "7.2.0-rc5" instead of
# "7.2.0-rc5-sky1-ncz") even when the outer oe_runmake call sets
# LOCALVERSION=-sky1-ncz correctly. modpost embeds vermagic straight from
# these two generated files, so patch them immediately before the build
# that actually reads them, rather than trust upstream regeneration.
do_compile:prepend() {
    _rel="7.2.0-rc5-sky1-ncz"
    if [ -f "${STAGING_KERNEL_BUILDDIR}/include/generated/utsrelease.h" ]; then
        printf '#define UTS_RELEASE "%s"\n' "$_rel" > "${STAGING_KERNEL_BUILDDIR}/include/generated/utsrelease.h"
    fi
    if [ -f "${STAGING_KERNEL_BUILDDIR}/include/config/kernel.release" ]; then
        printf '%s\n' "$_rel" > "${STAGING_KERNEL_BUILDDIR}/include/config/kernel.release"
    fi
    bbnote "cix-gpu-kmd: pinned STAGING_KERNEL_BUILDDIR release string to $_rel"
}

do_compile() {
    # KERNEL_SRC override: module.bbclass unconditionally injects
    # EXTRA_OEMAKE += "KERNEL_SRC=${STAGING_KERNEL_DIR}" (the raw, unconfigured
    # kernel source checkout) for every module-class recipe. Stock module.bbclass
    # do_compile pairs that with O=${STAGING_KERNEL_BUILDDIR} (the real, built
    # tree with correct Module.symvers/utsrelease.h) -- but our gpu.mk-based
    # do_compile never had an equivalent pairing, so gpu.mk (KERNEL_SRC :=
    # $(CIX_KERNEL_PATH)/kernel) silently got the wrong KERNEL_SRC from
    # EXTRA_OEMAKE instead, and its `make -C $(KERNEL_SRC) M=... modules`
    # sub-make ran against unconfigured source -- confirmed 2026-07-28 via
    # direct read of module.bbclass line 9 + module-base.bbclass line 20/22/23
    # (which shows STAGING_KERNEL_BUILDDIR/kernel-abiversion and
    # kernel-localversion are the canonical, correctly-suffixed source of
    # truth). oe_runmake appends EXTRA_OEMAKE before "$@" (see base.bbclass
    # oe_runmake_call: "${MAKE} ${EXTRA_OEMAKE} \"$@\""), so a later
    # KERNEL_SRC= here overrides the earlier EXTRA_OEMAKE one.
    oe_runmake -f gpu.mk gpu \
        CIX_GPU_PATH=${S} \
        CIX_KERNEL_PATH=${STAGING_KERNEL_DIR} \
        KERNEL_OUT=${STAGING_KERNEL_DIR} \
        TARGET_OUT_INTERMEDIATES=${B} \
        TARGET_KERNEL_ARCH=arm64 ARCH=arm64 \
        GPU_CROSS_COMPILE=${TARGET_PREFIX} CROSS_COMPILE=${TARGET_PREFIX} \
        KDIR=${STAGING_KERNEL_BUILDDIR} KSRC=${STAGING_KERNEL_DIR} \
        KERNEL_SRC=${STAGING_KERNEL_BUILDDIR} \
        LOCALVERSION=-sky1-ncz \
        hide= clean_build=0
}

do_install() {
    install_dir="${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/extra/cix"
    install -d "$install_dir"
    find "${B}" -name "*.ko" -exec install -m 0644 {} "$install_dir/" \;
}
