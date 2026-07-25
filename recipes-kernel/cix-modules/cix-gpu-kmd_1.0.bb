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
"
SRCREV_FORMAT = "gpukmd"

LIC_FILES_CHKSUM = "file://license.txt;md5=13e14ae1bd7ad5bff731bba4a31bb510"

# The Cix gpu_kernel tree uses gpu.mk (driven by Minisforum's
# build-scripts/build-gpu-driver.sh in their downstream pipeline). The shared
# cix-modules.inc do_compile / do_install invokes this makefile.
CIX_DRIVER_MAKEFILE = "gpu.mk"

# Mali kbase produces a single mali_kbase.ko (matches Sky1-Linux/cix-gpu-kmd
# DKMS packaging).

# gpu.mk is an Android-product makefile: map its TARGET_* / CIX_* vars onto Yocto
# paths, force the writable output dir, the cross prefix, and the "gpu" target.
do_compile() {
    oe_runmake -f gpu.mk gpu \
        CIX_GPU_PATH=${S} \
        CIX_KERNEL_PATH=${STAGING_KERNEL_DIR} \
        KERNEL_OUT=${STAGING_KERNEL_DIR} \
        TARGET_OUT_INTERMEDIATES=${B} \
        TARGET_KERNEL_ARCH=arm64 ARCH=arm64 \
        GPU_CROSS_COMPILE=${TARGET_PREFIX} CROSS_COMPILE=${TARGET_PREFIX} \
        KDIR=${STAGING_KERNEL_DIR} KSRC=${STAGING_KERNEL_DIR} \
        hide= clean_build=0
}

do_install() {
    install_dir="${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/extra/cix"
    install -d "$install_dir"
    find "${B}" -name "*.ko" -exec install -m 0644 {} "$install_dir/" \;
}
