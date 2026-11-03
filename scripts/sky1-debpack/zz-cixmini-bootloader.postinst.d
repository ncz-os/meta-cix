#!/bin/sh
# /etc/kernel/postinst.d/zz-cixmini-bootloader (cixmini-boot >= 1.7).
# Called by Debian-style kernel packages as: <hook> KVER [IMAGE]. Stages that
# one kernel add-only; never fails the kernel install.
/usr/lib/cixmini/cixmini-update-bootloader "${1:-}" || true
exit 0
