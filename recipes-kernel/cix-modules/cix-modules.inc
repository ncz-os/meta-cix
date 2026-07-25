LICENSE = "GPL-2.0-only"
inherit module
CIX_DRIVER_MAKEFILE ?= ""
DEPENDS += "virtual/kernel"

do_compile() {
    oe_runmake -f ${CIX_DRIVER_MAKEFILE} KDIR=${STAGING_KERNEL_DIR} KSRC=${STAGING_KERNEL_DIR}
}

do_install() {
    oe_runmake -f ${CIX_DRIVER_MAKEFILE} KDIR=${STAGING_KERNEL_DIR} KSRC=${STAGING_KERNEL_DIR} INSTALL_MOD_PATH=${D}
    modules=$(find "${B}" -name "*.ko" -print)
    install_dir="${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/extra/cix"
    install -d "$install_dir"
    printf '%s\n' "$modules" | while IFS= read -r ko; do install -m 0644 "$ko" "$install_dir/"; done
}

COMPATIBLE_MACHINE = "(cixmini)"
