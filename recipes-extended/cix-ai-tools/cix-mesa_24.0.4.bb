# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Cix Sky1 Mesa runtime.
#
# Ships the Mesa OpenGL/Vulkan userspace runtime from Minisforum's
# ext_debs payload. cix-mnn uses this at runtime for OpenCL/Vulkan
# backend initialization alongside cix-gpu-umd's Mali userspace driver.

require cix-ai-tools.inc

SUMMARY = "Cix Sky1 Mesa OpenGL/Vulkan userspace runtime"
DESCRIPTION = "Closed-source pre-built Mesa 24.0.4 runtime for Cix Sky1. Source from minisforum-cix-p1-repo/ext_debs cix-mesa_24.0.4_arm64 subtree. Provides OpenGL/Vulkan userspace pieces needed by accelerated consumers such as cix-mnn."

LICENSE_FLAGS = "commercial_cix-mesa"
LIC_FILES_CHKSUM = "file://${WORKDIR}/cixprop/cix_proprietary-debs/copyright/cix-gpu-umd/copyright;md5=401bdaa6e0af0aec53d7201e5d88f62f"

CIX_AI_COMPONENT = "cix-mesa_24.0.4_arm64"

# Cix's Mesa libs ship under /usr/lib/aarch64-linux-gnu (Debian
# multi-arch path), which Yocto's runtime linker doesn't search by
# default. Without an ld.so.conf.d entry, RDEPENDS pulls cix-mesa
# in but Vulkan/OpenGL consumers (cix-mnn libMNN_Vulkan.so etc.)
# fail to resolve at dlopen time and fall back to CPU. Mirror the
# cix-gpu-umd pattern: ship an ld.so.conf.d drop-in + run ldconfig
# in postinst with proper $D handling.
do_install:append() {
    install -d ${D}${sysconfdir}/ld.so.conf.d
    echo "/usr/lib/aarch64-linux-gnu" > ${D}${sysconfdir}/ld.so.conf.d/02-cix-mesa.conf
}

FILES:${PN} += " \
    ${libdir}/aarch64-linux-gnu \
    ${datadir}/drirc.d \
    ${datadir}/glvnd \
    ${datadir}/vulkan \
    ${sysconfdir}/ld.so.conf.d/* \
"

RDEPENDS:${PN} += "ldconfig cix-libdrm cix-libglvnd"

pkg_postinst:${PN}() {
    # Same fail-loud-on-missing-ldconfig pattern as cix-gpu-umd
    # (S4 review-mome9398-rfyl3r convergence).
    if [ -n "$D" ]; then
        if ! command -v ldconfig >/dev/null 2>&1; then
            echo "${PN}: ldconfig missing from rootfs at \$D=$D — image will not resolve /usr/lib/aarch64-linux-gnu libs" >&2
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
