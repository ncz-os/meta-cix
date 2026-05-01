# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Cix Sky1 Audio DSP coprocessor — firmware + userspace codec libs.
# Ships dsp_fw.bin (DSP firmware loaded by the audio subsystem at boot)
# plus a set of cix-DSP-accelerated audio codec libraries for HE-AAC,
# MP3, Opus, FLAC, Vorbis, and xHE-AAC encode/decode. Consumed by the
# Cix GStreamer plugins (cix-gstreamer / libgstcixdspif).
#
# Note: meta-cix's existing cix-sky1-firmware_2025.4.bb recipe also
# ships dsp_fw.bin (downloaded as a single file in that recipe). This
# recipe is now the canonical source for DSP firmware plus audio codec
# libs; cix-sky1-firmware_2025.4.bb is legacy and should be removed in
# a follow-up cleanup slice once images stabilize around cix-audio-dsp.

require cix-userspace.inc

SUMMARY = "Cix Sky1 audio DSP firmware + userspace codec libs"
DESCRIPTION = "Closed-source DSP firmware (dsp_fw.bin) and Cix-DSP-accelerated audio codec libraries (HE-AAC, MP3, Opus, FLAC, Vorbis, xHE-AAC) for the Cix Sky1 audio subsystem. Source from minisforum-cix-p1-repo/cix_proprietary__cix_proprietary cix_proprietary-debs/cix-audio-dsp subtree."

LICENSE_FLAGS = "commercial_cix-audio-dsp"
LIC_FILES_CHKSUM = "file://../copyright/cix-gpu-umd/copyright;md5=401bdaa6e0af0aec53d7201e5d88f62f"

CIX_USERSPACE_COMPONENT = "cix-audio-dsp"

FILES:${PN} += " \
    ${nonarch_base_libdir}/firmware \
    ${datadir}/cix \
"

RPROVIDES:${PN} += "cix-sky1-firmware"
RREPLACES:${PN} += "cix-sky1-firmware"
RCONFLICTS:${PN} += "cix-sky1-firmware"
