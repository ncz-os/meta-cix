# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Shared scaffolding for the Cix Sky1 closed-source userspace BSP recipes.
# All five components ride the same cix_proprietary monorepo + manifest pin;
# each per-recipe .bb sets PN_COMPONENT (the cix_proprietary-debs/<name>
# subdirectory) and its own LIC_FILES_CHKSUM.
#
# These recipes deploy ARM-Mali / Cix proprietary userspace binaries that
# are distributed under EULA-style closed-source licenses. They are ONLY
# usable by integrators who accept the per-component LICENSE_FLAGS via
# local.conf:
#
#     LICENSE_FLAGS_ACCEPTED = "commercial_cix-gpu-umd commercial_cix-noe-umd \
#                               commercial_cix-vpu-umd commercial_cix-isp-umd \
#                               commercial_cix-audio-dsp"
#
# Without that opt-in, bitbake refuses to package these recipes. This is
# the standard Yocto pattern for proprietary blob deploys (mirrors
# meta-arm-bsp's libmali handling).

LICENSE = "CLOSED"

# Inherit bin_package: copy S/* to ${D} verbatim, no compile, no strip.
# These are pre-built aarch64-linux-gnu binaries.
inherit bin_package

# Cix proprietary monorepo; per-recipe SRCREV pin in shared variable so
# all five components stay manifest-consistent. Bump CIX_PROPRIETARY_SRCREV
# when re-syncing from a newer Minisforum manifest.
CIX_PROPRIETARY_SRCREV = "f5ee18c3809dec30f12e9f253e8681e5d5ed6a52"
CIX_PROPRIETARY_BRANCH = "a0fb5/5cf6e/cix_p1_mg_dev"

SRC_URI = " \
    git://github.com/minisforum-cix-p1-repo/cix_proprietary__cix_proprietary.git;protocol=https;branch=${CIX_PROPRIETARY_BRANCH};name=cixprop \
"
SRCREV_cixprop = "${CIX_PROPRIETARY_SRCREV}"
SRCREV_FORMAT = "cixprop"

# Each per-recipe .bb sets CIX_USERSPACE_COMPONENT = cix-audio-dsp /
# cix-gpu-umd / cix-isp-umd / cix-noe-umd / cix-vpu-umd. We point S
# at that subdir so bin_package copies only that component's tree.
CIX_USERSPACE_COMPONENT ?= ""
S = "${WORKDIR}/git/cix_proprietary-debs/${CIX_USERSPACE_COMPONENT}"

# Proprietary aarch64 binaries trip several Yocto QA checks: they're
# pre-stripped, may have rpaths from upstream Cix's build, may link
# against libraries Yocto can't track. INSANE_SKIP these for the
# proprietary set — same posture meta-arm-bsp uses for libmali.
INSANE_SKIP:${PN} += "already-stripped ldflags rpaths file-rdeps dev-so"

# Disable do_package's split-debug step. Pre-built proprietary .so
# files (especially DSP-arm-compiled ones like libcix_dsp_*) and
# firmware blobs (dsp_fw.bin) can't be processed by aarch64-nclawzero-
# linux-objcopy --only-keep-debug — fails the package step. We don't
# need debug symbols extracted for closed-source binaries anyway.
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
INHIBIT_PACKAGE_STRIP = "1"

# Proprietary blobs are aarch64-only and built specifically for the
# Cix Sky1 / CP8180 SoC. Restrict to the cixmini machine.
COMPATIBLE_MACHINE = "(cixmini)"

# do_install for bin_package is `cp -R S/* D/` — no override needed
# unless a component requires post-install fixups (per-recipe).

# Sanity guard: make sure the per-recipe component variable is set.
python __anonymous() {
    if not d.getVar('CIX_USERSPACE_COMPONENT'):
        bb.fatal('CIX_USERSPACE_COMPONENT must be set in %s' % d.getVar('PN'))
}
