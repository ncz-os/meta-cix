# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Ships /etc/sudoers.d/nclawzero. Trivial drop-in to give the `ncz`
# operator passwordless sudo on cixmini — the stock image recipe adds ncz
# to the `sudo` group but Yocto's default /etc/sudoers doesn't grant
# `%sudo` rights, so without this drop-in `sudo` always fails with
# "ncz is not in the sudoers file."

SUMMARY = "nclawzero sudoers drop-in for cixmini"
DESCRIPTION = "Grants the ncz operator NOPASSWD sudo. Installed under /etc/sudoers.d/nclawzero so it composes with whatever the base sudo recipe ships."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = "file://nclawzero"

S = "${WORKDIR}"

RDEPENDS:${PN} = "sudo"

# /etc/sudoers.d files MUST be mode 0440 (visudo / sudo enforces this).
do_install() {
    install -d -m 0750 ${D}${sysconfdir}/sudoers.d
    install -m 0440 ${WORKDIR}/nclawzero ${D}${sysconfdir}/sudoers.d/nclawzero
}

FILES:${PN} = "${sysconfdir}/sudoers.d/nclawzero"
CONFFILES:${PN} = "${sysconfdir}/sudoers.d/nclawzero"
