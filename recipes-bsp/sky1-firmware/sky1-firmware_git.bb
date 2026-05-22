# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Sky1 SoC firmware blobs — required runtime support for the in-tree
# drivers introduced by linux-cix-sky1 (mainline 6.18 + Sky1-Linux
# patches). Without these, panthor (GPU) / cix_dsp_rproc (HiFi5 audio
# DSP) / linlon (VPU) all probe but fail to bring hardware online.
#
# Source: github.com/Sky1-Linux/sky1-firmware
# Contents land at /lib/firmware/{mali/,cix/,rtw89/,*.fwb,*.bin}.

SUMMARY = "Cix Sky1 SoC firmware blobs (Mali GPU / HiFi5 DSP / VPU codecs)"
DESCRIPTION = "Firmware files for CIX Sky1 SoC — mali_csffw.bin (Mali-G720 \
CSF for panthor), dsp_fw.bin (Tensilica HiFi5 audio DSP), 13 video codec \
*.fwb files (linlon VPU), arm/mali/ extras, rtw89/* WiFi. Sourced from \
Sky1-Linux/sky1-firmware. Required for in-tree drivers to init hardware."
SECTION = "kernel"

# License: redistributable firmware blobs. The repo's debian/copyright
# is the truth here; using LICENSE = "Proprietary" + a license-flag
# acceptance to mirror linux-firmware's pattern.
LICENSE = "Firmware-Redistributable"
LIC_FILES_CHKSUM = "file://README.md;md5=ce7859016b011a3165e63503b87c4eac"
LICENSE_FLAGS = "commercial"

SRC_URI = "git://github.com/Sky1-Linux/sky1-firmware.git;protocol=https;branch=main;name=fw"
SRCREV = "dd81690747ddb092bcc2a221daa0f8f679ee4bc4"
PV = "0+git${SRCPV}"

S = "${WORKDIR}/git"

# No build, just install.
do_compile[noexec] = "1"
do_configure[noexec] = "1"

do_install() {
    install -d ${D}${nonarch_base_libdir}/firmware
    cp -r ${S}/firmware/* ${D}${nonarch_base_libdir}/firmware/
}

# Files land under /lib/firmware (or /usr/lib/firmware on usrmerge).
FILES:${PN} = "${nonarch_base_libdir}/firmware"

# Tolerate the redistributable-firmware QA flags.
INSANE_SKIP:${PN} = "license-checksum"
