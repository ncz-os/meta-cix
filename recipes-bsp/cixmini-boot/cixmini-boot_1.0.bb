# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# cixmini-boot -- the Sky1 boot policy package for cixmini (O6N).
#
# WHAT IT OWNS
#   /usr/local/sbin/ncz-refind-refresh   the ONLY thing that writes rEFInd
#                                        entries; add-only by default, with a
#                                        separate --promote command
#   /usr/local/sbin/cixmini-boot-refresh the postinst/trigger entry point
#
# WHAT IT NO LONGER DOES (operator decision 2026-11-01)
#   The postinst used to wipe the ESP kernels and refind.conf, repoint EVERY
#   entry (Default, Rescue, Rescue Partition) at the newest kernel and recreate
#   the firmware boot entry with efibootmgr -B/-c. On O6N -- the Sky1 kernel
#   TEST host -- that deleted the known-good kernel on every upgrade, and it
#   re-ran on every later apt run. The postinst now calls the add-only
#   refresh: it stages the newly installed kernel as ONE extra entry and
#   touches nothing else. It is idempotent, so a later apt run is a no-op.
#
#   The firmware boot entry is created once, by the installer, and is never
#   touched again from userland. Promotion to default is an explicit operator
#   action: /usr/local/sbin/ncz-refind-refresh --promote <KVER>.
#
# The script itself lives in this layer's scripts/ directory (one copy, no
# vendored duplicate) and is installed with FILESEXTRAPATHS.

SUMMARY = "Sky1/cixmini boot policy: add-only rEFInd kernel staging"
DESCRIPTION = "Installs ncz-refind-refresh. Installing a kernel adds one rEFInd menuentry for it and never removes or repoints an existing kernel; promoting a kernel to the default is the separate 'ncz-refind-refresh --promote KVER' command. Replaces the old postinst that wiped the ESP kernels and recreated the firmware boot entry on every apt run."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

# arch-agnostic shell + policy metadata; no compiled artifacts.
inherit allarch

FILESEXTRAPATHS:prepend := "${THISDIR}/../../scripts:"

SRC_URI = " \
    file://ncz-refind-refresh \
    file://cixmini-boot-refresh \
"

S = "${UNPACKDIR}"

# rEFInd itself is provided by the installer image; this package only edits
# the ESP it creates. bash + coreutils are the script's real dependencies
# (mkdir/cp/sync/mv/cut/stat/sort come from coreutils).
RDEPENDS:${PN} = "bash coreutils"

# Installed under /usr/local/sbin (not ${sbindir} == /usr/sbin): the wrapper
# and the postinst invoke /usr/local/sbin/ncz-refind-refresh by absolute path,
# and so does the operator documentation. Keeping one canonical location
# avoids a postinst that silently finds nothing to run.
CIXMINI_BOOT_SBINDIR = "/usr/local/sbin"

do_install() {
    install -d -m 0755 ${D}${CIXMINI_BOOT_SBINDIR}
    install -d -m 0755 ${D}${localstatedir}/log
    install -m 0755 ${UNPACKDIR}/ncz-refind-refresh ${D}${CIXMINI_BOOT_SBINDIR}/ncz-refind-refresh
    install -m 0755 ${UNPACKDIR}/cixmini-boot-refresh ${D}${CIXMINI_BOOT_SBINDIR}/cixmini-boot-refresh
}

# postinst: add-only refresh. Failure is reported but never fails the install
# -- a kernel package must still install if the ESP is temporarily unmounted
# (the operator can re-run 'ncz-refind-refresh' later; the strict refusal is
# the script's job, not dpkg's).
pkg_postinst:${PN}() {
    # $D is set on first-time install into a rootfs, unset on a live system.
    if [ -n "$D" ]; then
        # Image-build time: no ESP to touch, nothing to stage.
        exit 0
    fi
    if [ -x /usr/local/sbin/cixmini-boot-refresh ]; then
        /usr/local/sbin/cixmini-boot-refresh || \
            echo "cixmini-boot: refresh skipped/failed (see /var/log/ncz-refind-refresh.log)" >&2
    fi
}

FILES:${PN} = " \
    ${CIXMINI_BOOT_SBINDIR}/ncz-refind-refresh \
    ${CIXMINI_BOOT_SBINDIR}/cixmini-boot-refresh \
"

# The script is not a device node or an ELF; skip the arch QA scan.
INSANE_SKIP:${PN} += "arch"
