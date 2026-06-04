# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Shared scaffolding for CIX Multimedia SDK runtime recipes.
#
# The SDK is distributed as a local vendor tarball (`cix-mm-1.0.0.tar.gz`)
# containing Debian arm64 packages for VAAPI, FFmpeg, GStreamer, NNStreamer,
# libcme and VPU tests.  The tarball is intentionally NOT committed into this
# public layer; provide it to bitbake with CIX_MM_ARCHIVE, e.g.:
#
#     CIX_MM_ARCHIVE = "/mnt/argonas/datapool/projects/nclawzero-yocto/sdk/cix-mm-1.0.0.tar.gz"
#     LICENSE_FLAGS_ACCEPTED += "commercial_cix-mm"
#
# Each per-recipe .bb sets CIX_MM_DEB_GLOB to the package's .deb filename glob.

LICENSE = "CLOSED"
LICENSE_FLAGS = "commercial_cix-mm"

inherit bin_package

CIX_MM_VERSION ?= "1.0.0"
CIX_MM_ARCHIVE ?= "/mnt/argonas/datapool/projects/nclawzero-yocto/sdk/cix-mm-${CIX_MM_VERSION}.tar.gz"
CIX_MM_DEB_GLOB ?= ""

SRC_URI = "file://${CIX_MM_ARCHIVE}"
SRC_URI[sha256sum] = "7189294e165eb30be9f2c3bb3789ab29c56da13bdbc0e17d6bfd87488bffbaf3"

# The archive release notes are the only license-of-record material shipped in
# this SDK bundle.  The packages themselves are closed-source vendor binaries.
LIC_FILES_CHKSUM = "file://${WORKDIR}/cix-mm/releasenotes.md;md5=22ae15d73c88f10688b9e22fc810fd7b"

S = "${WORKDIR}/${PN}-root"

do_extract_cix_mm_deb[depends] += "dpkg-native:do_populate_sysroot"
do_extract_cix_mm_deb() {
    rm -rf ${S}
    install -d ${S}

    deb="$(find ${WORKDIR}/cix-mm -name '${CIX_MM_DEB_GLOB}' -type f | sort | head -n 1)"
    if [ -z "$deb" ]; then
        bbfatal "CIX multimedia .deb not found for ${PN}: ${CIX_MM_DEB_GLOB}"
    fi

    ${STAGING_BINDIR_NATIVE}/dpkg-deb -x "$deb" ${S}
}
addtask extract_cix_mm_deb after do_unpack before do_patch

# Pre-built proprietary aarch64 binaries may be stripped, may carry Debian
# rpaths/file dependencies, and may install into vendor layouts.  Keep the same
# QA posture as the existing CIX closed-source userspace recipes.
INSANE_SKIP:${PN} += "already-stripped ldflags rpaths file-rdeps dev-so libdir"
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
INHIBIT_PACKAGE_STRIP = "1"

COMPATIBLE_MACHINE = "(cixmini)"

FILES:${PN} += " \
    /etc \
    /lib \
    /usr \
    /opt \
"

python __anonymous() {
    if not d.getVar('CIX_MM_DEB_GLOB'):
        bb.fatal('CIX_MM_DEB_GLOB must be set in %s' % d.getVar('PN'))
}
