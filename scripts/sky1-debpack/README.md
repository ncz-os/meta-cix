# sky1-debpack: side-by-side Sky1 kernel packages for Debian hosts (O6N)

Packages one bitbake-built Sky1 kernel so it installs NEXT TO the running
kernel on an NCZ Debian forky host, without removing or rewriting anything.

    build-sky1-sidebyside-debs.sh --kver 7.3.1-sky1-ncz --rev r297 \
        --yocto-debs <out>/kernel-debs --headers-tar <out>/headers-cixmini.tar.zst \
        --gpu-ko <out>/dkms-ko/cix-gpu-kmd --out <dir>
    test-o6n-sidebyside-install.sh <dir> <baseline-dir> <evidence-dir>

Output (nothing is compiled; all inputs come from one bitbake build and the
script refuses a mixed set: Image release string, headers `.config` and
`Module.symvers` equal to the image build's, module vermagic):

| package | content | maintainer scripts |
|---|---|---|
| `linux-image-<KVER>` | `/boot/vmlinuz-<KVER>` (the Image), config, System.map, all modules, prebuilt GPU modules in `updates/` | postinst: depmod; forced DKMS build+install of every registered module for `<KVER>` only; `dracut --kver <KVER>` (refuses if `<KVER>` is the running kernel); `ncz-refind-refresh --kver <KVER>` (add-only). Does NOT run `/etc/kernel/postinst.d`. prerm refuses to remove the running kernel. |
| `linux-headers-<KVER>` | full DKMS build tree `/usr/lib/modules/<KVER>/build` | postinst rebuilds fixdep/modpost natively (`modules_prepare`), checks `kernel.release` |
| `cixmini-boot` 1.7+rNNN | add-only `ncz-refind-refresh`, add-only `cixmini-update-bootloader`, add-only `zz-cixmini-bootloader` hooks | postinst copies the add-only tool and wrapper over the 1.6 copies in `/usr/local/sbin`, including `.ncz-cixmini-update-bootloader`, which the installer's apt hook `91-ncz-fix-cixmini-boot` restores after every dpkg run. Runs no refresh itself. |

Per-release names, no Provides/Conflicts/Replaces on `linux-image-cixmini` /
`linux-headers-cixmini`, so apt neither upgrades nor removes the installed
7.3.0 packages. `cixmini-boot` 1.7 is an upgrade over the installed 1.6+r293.

Not shipped on purpose:
- DKMS source debs: O6N already has the same versions; reinstalling them runs
  their postinst, which rebuilds the initramfs of `uname -r` (the default
  entry's kernel). The installed ones are rebuilt for `<KVER>` by the image
  postinst.
- `cix-npu-kmd-dkms`: O6N has `cix-npu-driver-dkms` (module `aipu` 6.2.0); both
  provide `aipu`. The installed one is built for `<KVER>`.
- the Yocto `linux-image-cixmini`/`linux-headers-cixmini` metas and the Yocto
  `cixmini-boot` 1.0-r0 (downgrade).

Promotion to default stays a separate operator step:
`ncz-refind-refresh --promote <KVER>`. Removing `linux-image-<KVER>` leaves its
ESP files and rEFInd entry in place (add-only policy).
