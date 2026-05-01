# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Cix Sky1 libdrm userspace.
#
# Ships the Cix-flavored libdrm runtime + headers + diagnostic
# binaries. Distinct from upstream OE-core libdrm — Cix's fork has
# Sky1-specific extensions (cix_drm.h) that the rest of the
# proprietary userspace (cix-mesa, cix-gpu-umd) calls into.
#
# Also responsible for the /usr/share/cix/lib ld.so.conf.d drop-in:
# multiple Cix proprietary packages ship .so files there
# (cix-libdrm itself, cix-mnn, cix-audio-dsp, etc.) and the Yocto
# runtime linker doesn't search that path by default. Concentrating
# the drop-in here means consumers RDEPENDS on cix-libdrm and
# inherit the search path; avoids file-collision from multiple
# packages each shipping their own /etc/ld.so.conf.d/*-cix-shared
# entry.

require cix-ai-tools.inc

SUMMARY = "Cix Sky1 libdrm userspace runtime + headers + diag tools"
DESCRIPTION = "Closed-source pre-built Cix-flavored libdrm runtime, DRM headers (incl Sky1-specific cix_drm.h), and diagnostic binaries (modetest, cix_test). Source from minisforum-cix-p1-repo/ext_debs cix-libdrm_1.0.0_arm64 subtree."

LICENSE_FLAGS = "commercial_cix-libdrm"
LIC_FILES_CHKSUM = "file://${WORKDIR}/cixprop/cix_proprietary-debs/copyright/cix-gpu-umd/copyright;md5=401bdaa6e0af0aec53d7201e5d88f62f"

CIX_AI_COMPONENT = "cix-libdrm_1.0.0_arm64"

# Multiple Cix proprietary packages install .so files under
# /usr/share/cix/lib (this recipe, cix-mnn, cix-audio-dsp, etc.).
# Yocto's runtime linker doesn't search that path by default.
# Ship a single ld.so.conf.d drop-in here so all dependents resolve
# correctly via transitive RDEPENDS.
do_install:append() {
    install -d ${D}${sysconfdir}/ld.so.conf.d
    echo "/usr/share/cix/lib" > ${D}${sysconfdir}/ld.so.conf.d/04-cix-shared.conf
}

FILES:${PN} += " \
    ${datadir}/cix \
    ${sysconfdir}/ld.so.conf.d/* \
"

RDEPENDS:${PN} += "ldconfig"

pkg_postinst:${PN}() {
    if [ -n "$D" ]; then
        if ! command -v ldconfig >/dev/null 2>&1; then
            echo "${PN}: ldconfig missing from rootfs at \$D=$D — image will not resolve /usr/share/cix/lib" >&2
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
