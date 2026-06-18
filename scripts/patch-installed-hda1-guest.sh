#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  cat >&2 <<'USAGE'
Usage:
  sudo ./scripts/patch-installed-hda1-guest.sh /path/to/slackware-installed-hda1-flat.vmdk

Environment variables:
  DISK_OFFSET_BYTES     default: 32256
  ROOT_PASSWORD_HASH    default: roK20XGbWEsSM  # DES crypt for password "root"

This script expects a flat/raw disk image with /dev/hda1 starting at byte 32256.
It installs static eth0 networking, DNS, telnetd enablement, securetty ttyp
entries, and a lab root password hash into the guest filesystem.
USAGE
  exit 2
fi

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run as root because this script uses losetup and mount." >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
DISK_IMAGE="$1"
DISK_OFFSET_BYTES="${DISK_OFFSET_BYTES:-32256}"
ROOT_PASSWORD_HASH="${ROOT_PASSWORD_HASH:-roK20XGbWEsSM}"

if [[ ! -f "${DISK_IMAGE}" ]]; then
  echo "Disk image not found: ${DISK_IMAGE}" >&2
  exit 1
fi

MNT="$(mktemp -d /tmp/slackware-hda1.XXXXXX)"
LOOP=""

cleanup() {
  set +e
  if mountpoint -q "${MNT}"; then
    umount "${MNT}"
  fi
  if [[ -n "${LOOP}" ]]; then
    losetup -d "${LOOP}"
  fi
  rmdir "${MNT}" 2>/dev/null
}
trap cleanup EXIT

LOOP="$(losetup --find --show -o "${DISK_OFFSET_BYTES}" "${DISK_IMAGE}")"
e2fsck -fy "${LOOP}" >/tmp/slackware-hda1-fsck.log 2>&1 || true
mount -t ext2 "${LOOP}" "${MNT}"

backup_once() {
  local path="$1"
  if [[ -e "${path}" && ! -e "${path}.before-qemu-telnet-lab" ]]; then
    cp -a "${path}" "${path}.before-qemu-telnet-lab"
  fi
}

backup_once "${MNT}/etc/rc.d/rc.inet1"
install -m 0755 "${REPO_DIR}/guest/etc/rc.d/rc.inet1" "${MNT}/etc/rc.d/rc.inet1"

backup_once "${MNT}/etc/resolv.conf"
install -m 0644 "${REPO_DIR}/guest/etc/resolv.conf" "${MNT}/etc/resolv.conf"

backup_once "${MNT}/etc/passwd"
perl -0pi -e "s/^root:[^:]*:/root:${ROOT_PASSWORD_HASH//\$/\\\$}:/m" "${MNT}/etc/passwd"

backup_once "${MNT}/etc/securetty"
touch "${MNT}/etc/securetty"
for tty in ttyp0 ttyp1 ttyp2 ttyp3 ttyp4 ttyp5 ttyp6 ttyp7 ttyp8 ttyp9; do
  grep -qx "${tty}" "${MNT}/etc/securetty" || echo "${tty}" >> "${MNT}/etc/securetty"
done

backup_once "${MNT}/etc/services"
touch "${MNT}/etc/services"
grep -qE '^telnet[[:space:]]+23/tcp' "${MNT}/etc/services" || \
  printf 'telnet\t\t23/tcp\n' >> "${MNT}/etc/services"

backup_once "${MNT}/etc/inetd.conf"
touch "${MNT}/etc/inetd.conf"
if grep -q 'in.telnetd' "${MNT}/etc/inetd.conf"; then
  perl -0pi -e 's/^[#[:space:]]*(telnet[[:space:]]+stream[[:space:]]+tcp[[:space:]]+nowait[[:space:]]+root[[:space:]]+\/usr\/sbin\/in\.telnetd[[:space:]]+in\.telnetd)/$1/m' "${MNT}/etc/inetd.conf"
else
  echo 'telnet stream tcp nowait root /usr/sbin/in.telnetd in.telnetd' >> "${MNT}/etc/inetd.conf"
fi

backup_once "${MNT}/etc/inittab"
if [[ -f "${MNT}/etc/inittab" ]]; then
  if grep -qE '^c1:12345:respawn:' "${MNT}/etc/inittab"; then
    perl -0pi -e 's#^c1:12345:respawn:.*$#c1:12345:respawn:/sbin/agetty 38400 tty1#m' "${MNT}/etc/inittab"
  else
    echo 'c1:12345:respawn:/sbin/agetty 38400 tty1' >> "${MNT}/etc/inittab"
  fi
fi

sync

cat <<EOF
Guest disk patched.

Installed:
  /etc/rc.d/rc.inet1     static eth0 192.168.1.100/24
  /etc/resolv.conf       nameserver 8.8.8.8
  /etc/passwd            root password hash configured
  /etc/securetty         ttyp0-ttyp9 allowed for root telnet login
  /etc/services          telnet 23/tcp
  /etc/inetd.conf        in.telnetd enabled
  /etc/inittab           tty1 uses agetty login prompt

Backups are saved as *.before-qemu-telnet-lab inside the guest filesystem.
EOF
