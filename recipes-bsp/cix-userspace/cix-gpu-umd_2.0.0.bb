# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Cix Sky1 Mali-G720-Immortalis GPU userspace driver (libmali, OpenCL,
# EGL/GLES, gbm). Pulls from cix_proprietary__cix_proprietary at the
# manifest-pinned commit and deploys the pre-built aarch64 binaries.
# Headline payload: libmali.so.0.53.0 (the actual Mali userspace driver),
# libOpenCL.so.1.0.0 (OpenCL runtime), libEGL_cix.so.1.4.0 (Cix EGL impl),
# libgbm.so.1.0.0 (GBM for Wayland), plus glvnd egl_vendor.d JSON shim
# and llvm-spirv for OpenCL kernel compilation.

require cix-userspace.inc

SUMMARY = "Cix Sky1 Mali-G720 GPU userspace driver (libmali, OpenCL, EGL)"
DESCRIPTION = "Closed-source ARM Mali userspace driver and OpenCL/EGL runtime as packaged by Cix for the CP8180 Sky1 platform. Source from minisforum-cix-p1-repo/cix_proprietary__cix_proprietary cix_proprietary-debs/cix-gpu-umd subtree."

LICENSE_FLAGS = "commercial_cix-gpu-umd"
LIC_FILES_CHKSUM = "file://usr/share/doc/cix-gpu-umd/copyright;md5=401bdaa6e0af0aec53d7201e5d88f62f"

CIX_USERSPACE_COMPONENT = "cix-gpu-umd"

# Files install under /opt/cixgpu-pro/ and /opt/cixgpu-compat/ rather
# than the standard /usr/lib/aarch64-linux-gnu/ layout, matching the
# Cix Debian image's ld.so.conf.d/00-cixgpu-pro.conf + 01-cixgpu-compat.conf
# search paths. Operators picking up Mali-accelerated apps need those
# ld.so config drop-ins, so ship them here with the binaries.
do_install:append() {
    install -d ${D}${sysconfdir}/ld.so.conf.d
    echo "/opt/cixgpu-pro/lib/aarch64-linux-gnu" > ${D}${sysconfdir}/ld.so.conf.d/00-cixgpu-pro.conf
    echo "/opt/cixgpu-compat/lib/aarch64-linux-gnu" > ${D}${sysconfdir}/ld.so.conf.d/01-cixgpu-compat.conf
}

FILES:${PN} += " \
    /opt/cixgpu-pro \
    /opt/cixgpu-compat \
    /lib/udev/rules.d \
    ${sysconfdir}/ld.so.conf.d/* \
"

RDEPENDS:${PN} += "ldconfig"

pkg_postinst:${PN}() {
    # When $D is set we are running at rootfs-construction time; ldconfig -r
    # rebuilds the TARGET rootfs's ld.so.cache. ldconfig is mandatory in this
    # branch — RDEPENDS lists it, image construction must include it. If
    # missing, fail loud rather than silently succeed and ship an image
    # whose linker can't find /opt/cixgpu-* libraries.
    # No host-fallback (would mutate build-host state).
    # When $D is empty we run on first boot against the live target;
    # ldconfig should always be present at runtime since RDEPENDS pulled it.
    if [ -n "$D" ]; then
        if ! command -v ldconfig >/dev/null 2>&1; then
            echo "${PN}: ldconfig missing from rootfs at \$D=$D — image will not resolve /opt/cixgpu-* libs" >&2
            exit 1
        fi
        ldconfig -r "$D"
    else
        if ! command -v ldconfig >/dev/null 2>&1; then
            echo "${PN}: ldconfig missing on target — first-boot linker cache rebuild skipped" >&2
            exit 1
        fi
        ldconfig
    fi
}
