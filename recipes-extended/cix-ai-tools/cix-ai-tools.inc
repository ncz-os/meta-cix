# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Shared scaffolding for the Cix Sky1 AI-tool recipes.
#
# These recipes deploy pre-built aarch64 binaries from Minisforum's
# ext_debs repo (which mirrors the .deb packages Cix ships on the
# desktop image). License-of-record is the cix_proprietary umbrella
# copyright (closed, EULA-style) — pulled as a second SRC_URI entry
# so LIC_FILES_CHKSUM can reference it.
#
# Operators must opt into the per-recipe LICENSE_FLAGS via local.conf:
#
#     LICENSE_FLAGS_ACCEPTED += "commercial_cix-llama-cpp \
#                                commercial_cix-mnn \
#                                commercial_cix-mesa \
#                                commercial_cix-libdrm \
#                                commercial_cix-libglvnd"
#
# Mirrors the S4 cix-userspace.inc opt-in pattern.
#
# COVERAGE GAP: cix-whisper-cpp and cix-npu-onnxruntime are NOT
# present in the published Minisforum source tree (ext_debs has
# only cix-llama-cpp and cix-mnn; cix_unit_test has an
# onnxruntime_py_test test fixture but not the runtime itself).
# To package those, we'd need either (a) Cix to publish the
# corresponding ext_debs entries, or (b) a separate fetch of the
# pre-built .debs from a Cix apt mirror. Neither exists yet — these
# remain as documented follow-ups for S5b once Cix publishes them.

LICENSE = "CLOSED"

inherit bin_package

# ext_debs repo for the binary payload + cix_proprietary repo for the
# license-of-record file. Pin both to the manifest commits as of the
# 2026-05-01 source-tree sync on ARGOS.
EXT_DEBS_SRCREV = "78d7ce8e12ad455f020956fbac02690ed5f3fd5e"
CIX_PROPRIETARY_SRCREV = "f5ee18c3809dec30f12e9f253e8681e5d5ed6a52"
CIX_BRANCH = "a0fb5/5cf6e/cix_p1_mg_dev"

SRC_URI = " \
    git://github.com/minisforum-cix-p1-repo/ext_debs.git;protocol=https;branch=${CIX_BRANCH};name=extdebs;destsuffix=ext_debs \
    git://github.com/minisforum-cix-p1-repo/cix_proprietary__cix_proprietary.git;protocol=https;branch=${CIX_BRANCH};name=cixprop;destsuffix=cixprop \
"
SRCREV_extdebs = "${EXT_DEBS_SRCREV}"
SRCREV_cixprop = "${CIX_PROPRIETARY_SRCREV}"
SRCREV_FORMAT = "extdebs_cixprop"

# Per-recipe sets CIX_AI_COMPONENT to the ext_debs subdir name (e.g.
# "cix-llama-cpp_1.0.0_arm64"). S points at the deb-extracted file
# tree; bin_package's do_install copies S/ to D/ verbatim.
CIX_AI_COMPONENT ?= ""
S = "${WORKDIR}/ext_debs/${CIX_AI_COMPONENT}"

# License lives in cix_proprietary umbrella. Same md5 we use across
# the S4 closed-source recipes.
LIC_FILES_CHKSUM = "file://${WORKDIR}/cixprop/cix_proprietary-debs/copyright/cix-gpu-umd/copyright;md5=401bdaa6e0af0aec53d7201e5d88f62f"

# Pre-built proprietary aarch64 binaries — same QA-skip posture as
# the S4 cix-userspace.inc.
INSANE_SKIP:${PN} += "already-stripped ldflags rpaths file-rdeps dev-so"

# Disable do_package's split-debug + strip steps. Pre-built closed-
# source .so files can't be processed by aarch64-nclawzero-linux-
# objcopy / strip — fails the package step. Same fix as
# cix-userspace.inc S4.
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
INHIBIT_PACKAGE_STRIP = "1"

COMPATIBLE_MACHINE = "(cixmini)"

# Don't ship the DEBIAN/ control metadata (Debian-pkg internal) or
# the Debian changelog (we'll have our own changelog via Yocto's
# package-changelog mechanism).
do_install:append() {
    rm -rf ${D}/DEBIAN
    rm -rf ${D}${datadir}/doc/*/changelog.Debian.gz
}

# Sanity guard.
python __anonymous() {
    if not d.getVar('CIX_AI_COMPONENT'):
        bb.fatal('CIX_AI_COMPONENT must be set in %s' % d.getVar('PN'))
}
