#!/bin/bash
# Read-only kernel/device investigation. Writes only a temporary capture directory.
# Run with sudo; emits a gzip tar archive on stdout. No mount, reprobe or reload.
set -eu
export PATH=/usr/sbin:/sbin:$PATH
[ "$(id -u)" = 0 ] || { echo 'Run this collector through sudo.' >&2; exit 1; }
command -v python3 >/dev/null
capture_dir=$(mktemp -d /tmp/sky1-audio-capture.XXXXXX)
trap 'rm -rf -- "$capture_dir"' EXIT
mkdir -p "$capture_dir/acpi-tables" "$capture_dir/module-files" "$capture_dir/loaded-module-notes"
{
    date -u
    uname -a
    cat /proc/version /proc/cmdline
    cat /proc/sys/kernel/random/boot_id
    uptime
    command -v git || true
    command -v dkms >/dev/null && dkms status || true
    command -v dpkg-query >/dev/null && dpkg-query -W 'linux-image*' 'linux-headers*' '*dkms*' 2>/dev/null || true
} > "$capture_dir/identity.txt" 2>&1
dmesg > "$capture_dir/dmesg.txt" 2>&1 || true
journalctl -b -k -o short-monotonic --no-pager > "$capture_dir/kernel-journal.txt" 2>&1 || true
cat /sys/kernel/debug/devices_deferred > "$capture_dir/devices_deferred.txt" 2>&1 || true
{
    cat /proc/asound/cards /proc/asound/pcm 2>/dev/null || true
    command -v aplay >/dev/null && aplay -l || true
    for f in /sys/kernel/debug/asoc/{cards,components,dais}; do
        echo "FILE $f"; cat "$f" 2>/dev/null || true
    done
} > "$capture_dir/asoc.txt" 2>&1
cat /proc/modules > "$capture_dir/loaded-modules.txt"
ps -eLo pid,tid,stat,wchan:40,comm > "$capture_dir/tasks.txt"
while read -r tid; do
    { echo "TID $tid"; cat "/proc/$tid/comm" "/proc/$tid/stack"; } >> "$capture_dir/blocked-stacks.txt" 2>&1 || true
done < <(ps -eLo tid=,stat= | awk '$2 ~ /^D/ {print $1}')
for module in trilin_dpsub linlon_dp snd_soc_sky1_sound_card snd_soc_cdns_i2s_mc snd_soc_hdmi_codec; do
    { echo "MODULE $module"; modinfo "$module"; } >> "$capture_dir/modules.txt" 2>&1 || true
    module_file=$(modinfo -n "$module" 2>/dev/null || true)
    if [ -f "$module_file" ]; then
        cp "$module_file" "$capture_dir/module-files/"
        sha256sum "$module_file" >> "$capture_dir/module-checksums.txt"
    fi
    module_note=/sys/module/$module/notes/.note.gnu.build-id
    [ ! -r "$module_note" ] || cat "$module_note" > "$capture_dir/loaded-module-notes/$module.build-id"
done
for f in /boot/config-"$(uname -r)" /proc/config.gz; do
    [ ! -r "$f" ] || cp "$f" "$capture_dir/"
done
python3 - "$capture_dir" <<'PY'
from pathlib import Path
import json, shutil, sys
out = Path(sys.argv[1])
def read(p):
    try: return p.read_text().strip()
    except OSError as e: return 'UNAVAILABLE: ' + str(e)
def describe(p):
    result = {'sysfs':str(p.resolve())}
    for key in ('path','hid','uid','status','modalias','waiting_for_supplier','power/runtime_status'):
        if (p/key).exists(): result[key] = read(p/key)
    result['driver'] = str((p/'driver').resolve()) if (p/'driver').is_symlink() else None
    result['links'] = {x.name:str(x.resolve()) for x in p.iterdir() if x.is_symlink() and (x.name.startswith(('physical_node','supplier:','consumer:')) or x.name=='firmware_node')}
    return result
acpi = []
for p in sorted(Path('/sys/bus/acpi/devices').iterdir()):
    entry = describe(p)
    entry['name'] = p.name
    entry['physical_nodes'] = [describe(x) for x in sorted(p.glob('physical_node*')) if x.is_dir()]
    acpi.append(entry)
(out/'acpi-devices.json').write_text(json.dumps(acpi,indent=2)+'\n')
platform = []
for p in sorted(Path('/sys/bus/platform/devices').iterdir()):
    if not p.name.startswith(('CIXH','hdmi-audio-codec','linlondp','trilin','sound')): continue
    entry = describe(p); entry['name'] = p.name
    entry['children'] = [describe(x) | {'name':x.name} for x in sorted(p.iterdir()) if x.is_dir() and not x.is_symlink() and x.name.startswith(('hdmi-audio-codec','i2c-'))]
    platform.append(entry)
(out/'platform-devices.json').write_text(json.dumps(platform,indent=2)+'\n')
for p in Path('/sys/firmware/acpi/tables').rglob('*'):
    if p.is_file():
        rel=p.relative_to('/sys/firmware/acpi/tables'); dest=out/'acpi-tables'/rel
        dest.parent.mkdir(parents=True,exist_ok=True)
        try: dest.write_bytes(p.read_bytes())
        except OSError as e: (out/'acpi-read-errors.txt').open('a').write(str(e)+'\n')
PY
tar -C "$capture_dir" -czf - .
