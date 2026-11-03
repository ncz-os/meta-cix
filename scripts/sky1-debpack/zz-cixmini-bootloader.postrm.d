#!/bin/sh
# /etc/kernel/postrm.d/zz-cixmini-bootloader (cixmini-boot >= 1.7).
# The 1.6 hook regenerated the whole ESP here. Removing a kernel no longer
# touches the ESP or refind.conf; the operator removes a staged entry by hand.
echo "zz-cixmini-bootloader: kernel ${1:-?} removed; ESP and refind.conf left unchanged (add-only policy)"
exit 0
