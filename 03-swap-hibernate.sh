#!/usr/bin/env bash
# [SSH->system] Swap (swapfile na @swap) + konfiguracja hibernacji.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

[[ $EUID -eq 0 ]] || { echo "Uruchom przez sudo: sudo bash 03-swap-hibernate.sh"; exit 1; }

ROOTDEV="$(findmnt -no SOURCE / | sed 's/\[.*//')"
BTRFS_UUID="$(findmnt -no UUID /)"
echo ">> root dev: ${ROOTDEV}   Btrfs UUID: ${BTRFS_UUID}   swap: ${SWAP_SIZE}"

# Subwolumen @swap (niezagnieżdżony, przeżywa rollbacki)
mount -o subvolid=5 "${ROOTDEV}" /mnt
btrfs subvolume show /mnt/@swap >/dev/null 2>&1 || btrfs subvolume create /mnt/@swap
umount /mnt

grep -q 'subvol=@swap' /etc/fstab || \
  echo "UUID=${BTRFS_UUID} /swap btrfs subvol=@swap,nodatacow,noatime 0 0" >> /etc/fstab
mkdir -p /swap
mountpoint -q /swap || mount /swap

# Swapfile = rozmiar RAM
if [[ ! -f /swap/swapfile ]]; then
  btrfs filesystem mkswapfile --size "${SWAP_SIZE}" /swap/swapfile
fi
swapon --show | grep -q '/swap/swapfile' || swapon /swap/swapfile
grep -q '/swap/swapfile' /etc/fstab || echo "/swap/swapfile none swap defaults 0 0" >> /etc/fstab

# resume + resume_offset do parametrów jądra
OFFSET="$(btrfs inspect-internal map-swapfile -r /swap/swapfile)"
echo ">> resume_offset: ${OFFSET}"
cp -a /etc/default/grub "/etc/default/grub.bkp.$(date +%s)"
if ! grep -q 'resume_offset=' /etc/default/grub; then
  sed -i "s#^GRUB_CMDLINE_LINUX_DEFAULT=\"#&resume=UUID=${BTRFS_UUID} resume_offset=${OFFSET} #" /etc/default/grub
fi
grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub
update-grub
dracut -f

# Odblokowanie hibernacji w Plasma (polkit)
cat > /etc/polkit-1/rules.d/10-enable-hibernate.rules <<'EOF'
polkit.addRule(function(action, subject) {
  if (action.id.indexOf("org.freedesktop.login1.hibernate") === 0 ||
      action.id == "org.freedesktop.upower.hibernate") {
    return polkit.Result.YES;
  }
});
EOF

echo ">> Swap + hibernacja skonfigurowane."
echo ">> Po restarcie i konfiguracji NVIDII przetestuj:  systemctl hibernate"
echo ">> Jeśli zamiast wyłączenia następuje restart: ustaw HibernateMode=shutdown w /etc/systemd/sleep.conf"
