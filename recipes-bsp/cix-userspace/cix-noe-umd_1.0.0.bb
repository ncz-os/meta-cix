# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Cix Sky1 NPU NoE user-mode driver — the headline NPU userspace.
# 45 TOPS NPU acceleration consumed by cix-llama-cpp, cix-whisper-cpp,
# cix-mnn, cix-npu-onnxruntime in subsequent S5 recipes.
#
# Ships libnoe.so + Python 3.11/3.12 bindings (libnoe.cpython-3{11,12}-
# aarch64-linux-gnu.so) + the cix_noe_standard_api.h header + a pkg-config
# .pc file. Tiny package (8 files) but load-bearing for the entire
# AI-acceleration stack on cixmini.

require cix-userspace.inc
inherit python3-dir

SUMMARY = "Cix Sky1 NPU NoE user-mode driver"
DESCRIPTION = "Closed-source NPU User-Mode Driver for the Cix Sky1 NoE (Neural Optimization Engine) — 45 TOPS NPU acceleration. Source from minisforum-cix-p1-repo/cix_proprietary__cix_proprietary cix_proprietary-debs/cix-noe-umd subtree."

LICENSE_FLAGS = "commercial_cix-noe-umd"
# cix-noe-umd has no embedded copyright file; use the cix_proprietary
# umbrella copyright (cix-gpu-umd's, broadest in the tree) as the
# license-of-record for the LIC_FILES_CHKSUM gate.
LIC_FILES_CHKSUM = "file://../copyright/cix-gpu-umd/copyright;md5=401bdaa6e0af0aec53d7201e5d88f62f"

CIX_USERSPACE_COMPONENT = "cix-noe-umd"

do_install:append() {
    install -d ${D}${PYTHON_SITEPACKAGES_DIR}
    for binding in ${D}${libdir}/python3/dist-packages/libnoe.cpython-3*-aarch64-linux-gnu.so; do
        [ -e "$binding" ] || continue
        mv "$binding" ${D}${PYTHON_SITEPACKAGES_DIR}/
    done
    rmdir ${D}${libdir}/python3/dist-packages 2>/dev/null || true
    rmdir ${D}${libdir}/python3 2>/dev/null || true

    install -d ${D}${libdir}/pkgconfig
    if [ -f ${D}${libdir}/aarch64-linux-gnu/pkgconfig/cix-noe-umd.pc ]; then
        mv ${D}${libdir}/aarch64-linux-gnu/pkgconfig/cix-noe-umd.pc ${D}${libdir}/pkgconfig/
    fi
    rmdir ${D}${libdir}/aarch64-linux-gnu/pkgconfig 2>/dev/null || true
    rmdir ${D}${libdir}/aarch64-linux-gnu 2>/dev/null || true
}

# Python bindings are relocated from Debian's /usr/lib/python3/dist-packages/
# into Yocto's Python site-packages path. Both 3.11 and 3.12 upstream bindings
# are preserved; only the matching CPython ABI will load. Keep them in ${PN}
# since they're tightly coupled to libnoe.so; split ${PN}-python in a later
# packaging cleanup if image composition needs it.
FILES:${PN} += " \
    ${PYTHON_SITEPACKAGES_DIR} \
    ${libdir}/pkgconfig \
"
FILES:${PN}-dev:remove = "${libdir}/pkgconfig ${libdir}/pkgconfig/*"

# libnoe.so ships under /usr/share/cix/lib — the linker-path drop-in
# for that location lives in cix-libdrm (S5). RDEPENDS on cix-libdrm
# guarantees the drop-in is present in the rootfs before our postinst
# runs ldconfig (otherwise the cache rebuild scans without seeing
# /usr/share/cix/lib at all).
RDEPENDS:${PN} += "ldconfig cix-libdrm"

pkg_postinst:${PN}() {
    if [ -n "$D" ]; then
        if ! command -v ldconfig >/dev/null 2>&1; then
            echo "${PN}: ldconfig missing from rootfs at \$D=$D — libnoe.so under /usr/share/cix/lib will not resolve" >&2
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

# libnoe.so consumers will need python3 at runtime if they import the
# Python bindings. Hard RDEPENDS would force python3 into all images
# that include the C library; instead, RRECOMMENDS it so an image-author
# choosing only the C path doesn't drag python3 along.
RRECOMMENDS:${PN} += "python3-core"
