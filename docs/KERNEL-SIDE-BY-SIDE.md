# Sky1 kernels side by side on O6N (install, promote, roll back)

O6N is the CIX Sky1 kernel TEST host. It must be able to install a new kernel
**without losing the known-good one**, and getting back to the known-good
kernel must be a decision an operator makes deliberately, never a side effect
of `apt`.

This document describes the two mechanisms that make that true:

1. **Per-version kernel packages** (`recipes-kernel/linux-cix-sky1-ncz/`), so
   installing a new kernel does not remove the old one's files.
2. **`ncz-refind-refresh` add-only mode**, so staging a new kernel on the
   ESP does not remove, repoint or reorder any existing rEFInd entry.

Nothing here reboots the machine, clears the firmware boot entry, or touches a
host by itself. Promotion to default is the one deliberate operator step.

---

## What changed, and why the old flow was unsafe

Previously `linux-image-cixmini` and `linux-headers-cixmini` were **single-name**
packages: a 7.3.1 build shipped under the same package names as 7.3.0. dpkg
handles that as an *upgrade*, so it removed the 7.3.0 files in the same
transaction that installed 7.3.1:

- `/boot/vmlinuz-7.3.0*` (and `/boot/Image-7.3.0-sky1-ncz`)
- `/usr/lib/modules/7.3.0-sky1-ncz/`
- the 7.3.0 headers tree

At the same time the `cixmini-boot` postinst ran `ncz-refind-refresh`, which
wiped the ESP kernels and `refind.conf`, pointed **every** entry (Default,
Rescue, Rescue Partition) at the newest kernel and recreated the firmware boot
entry with `efibootmgr -B/-c`. It also re-ran on every later `apt` run.

Net effect: one install erased both the files and the boot path back to the
kernel that was known to work.

### Now

Every kernel release gets its own package names:

| Package                                   | Contents / role                                  |
|-------------------------------------------|--------------------------------------------------|
| `linux-image-7.3.1-sky1-ncz`              | the kernel image package (files)                 |
| `linux-headers-7.3.1-sky1-ncz`            | the headers package (files)                      |
| `linux-image-cixmini`                     | thin meta; `Depends: linux-image-<KVER>`         |
| `linux-headers-cixmini`                   | thin meta; `Depends: linux-headers-<KVER>`       |

The meta packages are **empty** (`ALLOW_EMPTY`) and depend on the *exact*
current release. They carry no files, so upgrading or removing them cannot
evict an older kernel. They exist so anything that still asks for the
historical `linux-image-cixmini` / `linux-headers-cixmini` keeps working.

Installing 7.3.1 therefore leaves `linux-image-7.3.0-sky1-ncz` installed, its
`/boot/vmlinuz-7.3.0-sky1-ncz` and `/usr/lib/modules/7.3.0-sky1-ncz` intact,
and the 7.3.0 rEFInd entry exactly where it was.

---

## `ncz-refind-refresh` modes

The **mode is the default**, not a flag. There is no option that selects
destructive behaviour.

### add-only (default)

```
ncz-refind-refresh [--kver <KVER>]
```

Stages the kernel named by `--kver` — or, with no argument, the newest kernel
in `/boot` that is not staged yet — as **one extra** `menuentry` whose
`options` are copied **verbatim** from the Default entry. Then it stops.

What add-only guarantees, and what the shell tests assert byte for byte:

- `default_selection` is unchanged.
- The `Rescue`, `Rescue Partition` and `NCZRESCUE` entries are unchanged.
- Every existing kernel file on the ESP is unchanged.
- `refind.conf` is only **appended to** (the previous bytes are a strict
  prefix of the new file); no existing entry is edited or reordered.
- The firmware boot entry is not touched (no `efibootmgr` call exists).
- Re-running it is a **no-op** once the kernel is staged, so a later `apt`
  run writes nothing.

Each release is staged into its own directory, `EFI/ncz/ncz-<KVER>/`, so no
version can overwrite another's `vmlinuz` / `initrd.img` / DTB.

### `--promote <KVER>` — the separate, explicit command

```
ncz-refind-refresh --promote 7.3.1-sky1-ncz
```

Makes an **already-staged** kernel the default by rewriting the numeric
`default_selection` line and nothing else. It does not edit any `menuentry`,
re-stage any file, or touch the firmware boot entry. It refuses (non-zero, no
ESP writes) if the kernel is not staged.

### Refusals (non-zero exit, no ESP writes)

| Exit | Meaning |
|------|---------|
| 2    | usage error |
| 3    | ESP is not mounted at `/boot/efi` |
| 4    | preflight refusal: `refind.conf` missing/malformed, no `menuentry`, the new kernel's image or initramfs is missing from `/boot`, **or the known-good kernel is missing** from `/boot` / from the ESP |
| 5    | a write failed |

Every decision is logged to stdout and to `/var/log/ncz-refind-refresh.log`.

---

## O6N: install a new kernel side by side

Prerequisites: the ESP is mounted at `/boot/efi`, rEFInd is installed, and the
currently-default kernel (the known-good one) is still on the ESP. The
preflight refuses to run without the last two — that refusal is the point.

```bash
# 0. Recon: what is on the ESP now, and what is the default?
sudo ncz-refind-refresh --list
#    default_selection: 2

# 1. Install the new kernel. Per-version packages: 7.3.0 stays installed.
#    (Names illustrative; use the .deb set you built.)
sudo dpkg -i linux-image-7.3.0-sky1-ncz_*.deb     # already installed, kept
sudo dpkg -i linux-image-7.3.1-sky1-ncz_*.deb \
             linux-headers-7.3.1-sky1-ncz_*.deb

# 2. Stage it on the ESP as an ADDITIONAL entry. The cixmini-boot postinst
#    does this automatically; running it by hand is equivalent and is what
#    the log shows.
sudo ncz-refind-refresh --kver 7.3.1-sky1-ncz

# 3. Confirm the old kernel survived, as a file and as an entry.
ls -l /boot/vmlinuz-7.3.0-sky1-ncz /boot/vmlinuz-7.3.1-sky1-ncz
ls -ld /usr/lib/modules/7.3.0-sky1-ncz /usr/lib/modules/7.3.1-sky1-ncz
sudo ncz-refind-refresh --list
#    7.3.1-sky1-ncz  staged (entry 4)
#    7.3.0-sky1-ncz  staged (entry 2)

# 4. Here the default is STILL 7.3.0. Reboot and pick the 7.3.1 entry from
#    the rEFInd menu to test it. Do not promote yet.
sudo reboot
```

At this point 7.3.0 is the default and 7.3.1 is an extra menu entry you can
select once at the menu. Testing 7.3.1 does not require promoting it.

### Once 7.3.1 is proven good, promote it

Only after 7.3.1 has booted and passed the acceptance checks on O6N:

```bash
sudo ncz-refind-refresh --promote 7.3.1-sky1-ncz
sudo ncz-refind-refresh --list          # default_selection now points at 7.3.1
```

7.3.0 stays installed and stays a menu entry. It is now the *fallback* rather
than the default: roll back by selecting it in the menu, or by promoting it
back (below). You do **not** need the 7.3.1 packages to be removed for the
fallback to work.

---

## O6N: roll back to the known-good kernel

The rollback is a boot-menu selection, not a reinstall.

### Fast rollback (during a boot failure)

1. Reboot into the rEFInd menu.
2. Select the **`NCZ 7.3.0-sky1-ncz`** entry (the old default). It is still a
   full entry with its own file contents; it boots exactly as before.
3. Once booted, if you want that to be the default again, run:

```bash
sudo ncz-refind-refresh --promote 7.3.0-sky1-ncz
```

That changes `default_selection` back to the 7.3.0 entry and nothing else.

### If 7.3.1 never boots far enough to reach a shell

The ESP entry for 7.3.0 is untouched by the 7.3.1 install, so the menu
selection above is enough. If the menu itself is unreachable, `NCZRESCUE` is
still present and still points where it always did.

### Removing a bad kernel afterwards (optional, deliberate)

7.3.1 is a per-version package, so it can be removed on its own without
touching 7.3.0:

```bash
sudo dpkg -r linux-image-7.3.1-sky1-ncz linux-headers-7.3.1-sky1-ncz
```

The `linux-image-cixmini` / `linux-headers-cixmini` metapackages would then
have an unsatisfied dependency; if you also remove them, 7.3.0 stays
installed and stays the default. The 7.3.1 ESP directory
(`EFI/ncz/ncz-7.3.1-sky1-ncz/`) and its menu entry are **not** removed
automatically — `ncz-refind-refresh` never deletes an entry. Decide about them
by hand, deliberately, after the rollback has succeeded.

---

## What is deliberately NOT automated

- **No automatic promotion.** A newly installed kernel is never made the
  default. That is the whole safety property, and it is why the `cixmini-boot`
  postinst runs add-only only.
- **No automatic entry removal.** Stale `menuentry`s are left in place; they
  point at per-version directories, so a stale entry only fails if its own
  files were deleted, which nothing does automatically.
- **No `efibootmgr` calls.** The firmware boot entry is created once by the
  installer and left alone from then on.

## Tests

`scripts/test-ncz-refind-refresh.sh` runs the whole contract against a fake
ESP and a fake `/boot` (no real host, no `efibootmgr`, no reboot):

- add-only mode leaves every pre-existing entry and kernel file
  byte-identical (before/after diff), and appends exactly one entry whose
  options equal the Default's;
- the old version's files survive installing the new one, and a second run is
  a no-op;
- `--promote` changes only the `default_selection` line;
- the script refuses, non-zero, with no ESP write, when the ESP is not mounted
  or the known-good kernel is missing.

```bash
scripts/test-ncz-refind-refresh.sh -v
```
