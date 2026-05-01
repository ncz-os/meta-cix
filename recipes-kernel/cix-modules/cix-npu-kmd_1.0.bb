# SPDX-FileCopyrightText: Copyright (c) 2026 Jason Perlow
# SPDX-License-Identifier: Apache-2.0
#
# Cix Sky1 NPU (NoE — Neural Optimization Engine) kernel module.
# Source: minisforum-cix-p1-repo/cix_opensource__npu_driver
# Provides 45 TOPS NPU acceleration consumed by cix-noe-umd / cix-llama-cpp
# / cix-whisper-cpp / cix-mnn / cix-npu-onnxruntime in a future S5 slice.

require cix-modules.inc

SUMMARY = "Cix Sky1 NPU (NoE) kernel module"
DESCRIPTION = "Out-of-tree kernel module for the Cix Sky1 NoE NPU (45 TOPS). Source from Minisforum's downstream tree."

PV = "1.0+cix"
SRCREV = "608f8178858ef7749364f1a7ad4872e04615ceea"

SRC_URI = " \
    git://github.com/minisforum-cix-p1-repo/cix_opensource__npu_driver.git;protocol=https;branch=${KBRANCH};name=npukmd \
"
SRCREV_FORMAT = "npukmd"

LIC_FILES_CHKSUM = "file://driver/LICENSE.TXT;md5=ea9445d9cc03d508cf6bb769d15a54ef"

CIX_DRIVER_MAKEFILE = "npu.mk"
