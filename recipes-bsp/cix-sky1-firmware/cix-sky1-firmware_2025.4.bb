# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0

SUMMARY = "Cix Sky1 platform firmware blobs"
DESCRIPTION = "Firmware payloads needed by selected Cix Sky1 drivers. This first-pass recipe installs the documented DSP remoteproc firmware."
LICENSE = "CLOSED"

inherit allarch

SRC_URI = "https://github.com/cixtech/cix_proprietary__cix_proprietary/raw/refs/heads/cix_p1_k6.6_master/cix_proprietary-debs/cix-audio-dsp/usr/lib/firmware/dsp_fw.bin;downloadfilename=dsp_fw.bin;name=dsp"
SRC_URI[dsp.sha256sum] = "150e01047a842a9aa541b7fce76a9655abe80161de5416a2c9075a04d2e51408"

S = "${UNPACKDIR}"

do_install() {
    install -d ${D}${nonarch_base_libdir}/firmware/cix
    install -m 0644 ${UNPACKDIR}/dsp_fw.bin ${D}${nonarch_base_libdir}/firmware/cix/dsp_fw.bin
    ln -rs ${D}${nonarch_base_libdir}/firmware/cix/dsp_fw.bin ${D}${nonarch_base_libdir}/firmware/dsp_fw.bin
}

FILES:${PN} = " \
    ${nonarch_base_libdir}/firmware/cix/dsp_fw.bin \
    ${nonarch_base_libdir}/firmware/dsp_fw.bin \
"

# DSP firmware blob is for the Sky1 audio DSP coprocessor, not the main aarch64
# CPU. allarch is correct for deployment (the file is arch-agnostic from the
# rootfs side) but QA objdump-scans the ELF and complains. Skip arch + strip.
INSANE_SKIP:${PN} += "arch already-stripped"
