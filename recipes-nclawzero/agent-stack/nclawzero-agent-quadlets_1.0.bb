# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Ships the three Podman quadlet (.container) systemd unit definitions
# for the nclawzero agent stack on cixmini, plus the /etc/nclawzero/
# agent-env sample env file and basic permissions. Mirrors the bigpi
# (Pi 5 16GB) reference deployment — see
# ~/.claude/rules/handoff-3-agent-rootfs-2026-04-29.md for the full
# topology rationale.
#
# Quadlets are root-owned, mode 0644, in /etc/containers/systemd/.
# At boot, podman-system-generator converts them into systemd .service
# units in /run/systemd/generator/. Each agent runs as its own Podman
# container with the shared /etc/nclawzero/agent-env supplying API keys.
#
# This recipe ships only the unit/config files. It does NOT pre-pull
# the OCI images — that's done at first-boot by the (separate, future)
# nclawzero-load-agent-images.service which expects OCI tarballs at
# /var/lib/nclawzero/agent-images/{zeroclaw,openclaw,hermes}.oci.tar.
# The quadlets here have After=nclawzero-load-agent-images.service so
# they wait until images are loaded before podman tries to start.

SUMMARY = "Podman quadlet units for nclawzero agent stack on cixmini"
DESCRIPTION = "Systemd quadlet (.container) unit files for the nclawzero three-agent stack — zeroclaw (custom claw runtime), openclaw (NemoClaw OSS upstream), hermes (NousResearch Hermes) — plus the shared /etc/nclawzero/agent-env environment file. Pulls into images that include podman + systemd."

LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

inherit allarch systemd

SRC_URI = " \
    file://zeroclaw.container \
    file://openclaw.container \
    file://hermes.container \
    file://hermes-isolated.network \
    file://agent-env.sample \
"

S = "${WORKDIR}"

# Quadlets land in /etc/containers/systemd/. agent-env.sample lands at
# /etc/nclawzero/agent-env.sample (operators copy and populate).
do_install() {
    install -d ${D}${sysconfdir}/containers/systemd
    install -m 0644 ${WORKDIR}/zeroclaw.container        ${D}${sysconfdir}/containers/systemd/zeroclaw.container
    install -m 0644 ${WORKDIR}/openclaw.container        ${D}${sysconfdir}/containers/systemd/openclaw.container
    install -m 0644 ${WORKDIR}/hermes.container          ${D}${sysconfdir}/containers/systemd/hermes.container
    install -m 0644 ${WORKDIR}/hermes-isolated.network   ${D}${sysconfdir}/containers/systemd/hermes-isolated.network

    install -d ${D}${sysconfdir}/nclawzero
    install -m 0640 ${WORKDIR}/agent-env.sample ${D}${sysconfdir}/nclawzero/agent-env.sample
    # Empty agent-env created at correct mode/ownership; operators
    # populate post-deploy via fleet-secrets workflow.
    install -m 0640 /dev/null ${D}${sysconfdir}/nclawzero/agent-env

    # Standard data dirs the quadlets bind-mount into containers.
    install -d ${D}${localstatedir}/lib/nclawzero/openclaw-home
}

FILES:${PN} += " \
    ${sysconfdir}/containers/systemd \
    ${sysconfdir}/nclawzero \
    ${localstatedir}/lib/nclawzero \
"

# Hard-depend on podman + systemd for the quadlet generator.
RDEPENDS:${PN} += "podman systemd"

# nclawzero group ownership is set up by the cix-mini firstboot deb (or
# manually by the operator). We do not create the group in this recipe
# because Yocto's useradd-staticids workflow needs explicit group
# definitions in conf/distro/include — out of scope here. Document in
# README that operators must `groupadd nclawzero && chgrp nclawzero
# /etc/nclawzero/agent-env*` before agent containers can read the
# env file.

COMPATIBLE_MACHINE = "(cixmini)"
