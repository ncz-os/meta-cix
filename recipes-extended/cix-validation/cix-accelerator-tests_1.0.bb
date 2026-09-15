# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0

SUMMARY = "CIX Sky1 accelerator validation tests"
DESCRIPTION = "Operator-run proof scripts for CIX Sky1 GPU, VPU, and NPU inference paths on Minisforum MS-R1/cixmini."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = " \
    file://cix-gpu-vulkan-mlp-test.sh \
    file://cix-vpu-h264-inference-test.sh \
    file://cix-npu-vgg-inference-test.sh \
    file://cix-npu-sustained-benchmark.sh \
    file://cix-run-accelerator-tests.sh \
"

S = "${UNPACKDIR}"

RDEPENDS:${PN} = "bash coreutils python3-core"

do_install() {
    install -d ${D}${libexecdir}/cix-accelerator-tests
    install -m 0755 ${UNPACKDIR}/cix-gpu-vulkan-mlp-test.sh ${D}${libexecdir}/cix-accelerator-tests/
    install -m 0755 ${UNPACKDIR}/cix-vpu-h264-inference-test.sh ${D}${libexecdir}/cix-accelerator-tests/
    install -m 0755 ${UNPACKDIR}/cix-npu-vgg-inference-test.sh ${D}${libexecdir}/cix-accelerator-tests/
    install -m 0755 ${UNPACKDIR}/cix-npu-sustained-benchmark.sh ${D}${libexecdir}/cix-accelerator-tests/
    install -m 0755 ${UNPACKDIR}/cix-run-accelerator-tests.sh ${D}${libexecdir}/cix-accelerator-tests/

    install -d ${D}${bindir}
    ln -sf ${libexecdir}/cix-accelerator-tests/cix-gpu-vulkan-mlp-test.sh ${D}${bindir}/cix-gpu-vulkan-mlp-test
    ln -sf ${libexecdir}/cix-accelerator-tests/cix-vpu-h264-inference-test.sh ${D}${bindir}/cix-vpu-h264-inference-test
    ln -sf ${libexecdir}/cix-accelerator-tests/cix-npu-vgg-inference-test.sh ${D}${bindir}/cix-npu-vgg-inference-test
    ln -sf ${libexecdir}/cix-accelerator-tests/cix-npu-sustained-benchmark.sh ${D}${bindir}/cix-npu-sustained-benchmark
    ln -sf ${libexecdir}/cix-accelerator-tests/cix-run-accelerator-tests.sh ${D}${bindir}/cix-run-accelerator-tests
}
