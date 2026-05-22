require cix-modules.inc
SUMMARY = "Cix Sky1 NPU (NoE) kernel module"
PV = "1.0+cix"
SRCREV = "608f8178858ef7749364f1a7ad4872e04615ceea"
SRC_URI = "git://github.com/minisforum-cix-p1-repo/cix_opensource__npu_driver.git;protocol=https;branch=a0fb5/5cf6e/cix_p1_mg_dev;name=npukmd"
LIC_FILES_CHKSUM = "file://driver/LICENSE.TXT;md5=ea9445d9cc03d508cf6bb769d15a54ef"
CIX_DRIVER_MAKEFILE = "npu.mk"
