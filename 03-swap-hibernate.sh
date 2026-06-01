#!/usr/bin/env bash
# [SSH->system] Swap (swapfile na @swap) + konfiguracja hibernacji.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

require_root

# Login docelowy (do reguły hibernacji w polkit)
USERNAME="${USERNAME:-$(detect_target_user)}"
ask USERNAME "Login użytkownika (do reguły hibernacji)"

# Rozmiar swap: domyślnie 1.5×RAM (best practice dla hibernacji)
ask SWAP_SIZE "Rozmiar swapfile dla hibernacji (np. 96g)" "$(suggested_swap_gib)g"

ROOTDEV="$(findmnt -no SOURCE / | sed 's/\[.*//')"
BTRFS_UUID="$(findmnt -no UUID /)"
echo ">> root dev: ${ROOTDEV}   Btrfs UUID: ${BTRFS_UUID}   swap: ${SWAP_SIZE}   user: ${USERNAME}"

# Subwolumen @swap (niezagnieżdżony, przeżywa rollbacki)
mount -o subvolid=5 "${ROOTDEV}" /mnt
btrfs subvolume show /mnt/@swap >/dev/null 2>&1 || btrfs subvolume create /mnt/@swap
umount /mnt

# Wpis montowania @swap (Calamares mógł już go dodać jako subvol=/@swap — nie dubluj)
grep -qE 'subvol=/?@swap([,[:space:]]|$)' /etc/fstab || \
  echo "UUID=${BTRFS_UUID} /swap btrfs subvol=@swap,nodatacow,noatime 0 0" >> /etc/fstab
mkdir -p /swap
mountpoint -q /swap || mount /swap

# Swapfile o żądanym rozmiarze. Jeśli istnieje (np. z Calamares) i ma inny rozmiar
# — odtwórz na właściwy (= RAM + bufor, best practice dla hibernacji).
DESIRED_BYTES="$(numfmt --from=iec "${SWAP_SIZE^^}")"
RECREATE=1
if [[ -f /swap/swapfile ]]; then
  CUR_BYTES="$(stat -c%s /swap/swapfile 2>/dev/null || echo 0)"
  if [[ "${CUR_BYTES}" == "${DESIRED_BYTES}" ]]; then
    RECREATE=0
  else
    say "Istniejący swapfile ma $(numfmt --to=iec "${CUR_BYTES}"), żądany ${SWAP_SIZE} — odtwarzam."
  fi
fi
if [[ "${RECREATE}" -eq 1 ]]; then
  swapoff /swap/swapfile 2>/dev/null || true
  rm -f /swap/swapfile
  btrfs filesystem mkswapfile --size "${SWAP_SIZE}" /swap/swapfile
fi
swapon --show | grep -q '/swap/swapfile' || swapon /swap/swapfile
grep -q '/swap/swapfile' /etc/fstab || echo "/swap/swapfile none swap defaults 0 0" >> /etc/fstab

# resume + resume_offset do parametrów jądra
OFFSET="$(btrfs inspect-internal map-swapfile -r /swap/swapfile)"
echo ">> resume_offset: ${OFFSET}"
cp -a /etc/default/grub "/etc/default/grub.bkp.$(date +%s)"
# resume + szybsza kompresja obrazu hibernacji (lz4) — istotne przy dużym RAM
if ! grep -q 'resume_offset=' /etc/default/grub; then
  sed -i "s#^GRUB_CMDLINE_LINUX_DEFAULT=\"#&resume=UUID=${BTRFS_UUID} resume_offset=${OFFSET} hibernate.compressor=lz4 #" /etc/default/grub
fi
grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub
update-grub
dracut -f

# Odblokowanie hibernacji w Plasma (polkit) — zawężone do Twojego użytkownika
cat > /etc/polkit-1/rules.d/10-enable-hibernate.rules <<EOF
polkit.addRule(function(action, subject) {
  if ((action.id == "org.freedesktop.login1.hibernate" ||
       action.id == "org.freedesktop.login1.hibernate-multiple-sessions" ||
       action.id == "org.freedesktop.login1.handle-hibernate-key" ||
       action.id == "org.freedesktop.upower.hibernate") &&
      subject.user == "${USERNAME}") {
    return polkit.Result.YES;
  }
});
EOF

echo ">> Swap + hibernacja skonfigurowane."
echo ">> Po restarcie i konfiguracji NVIDII przetestuj:  systemctl hibernate"
echo ">> Jeśli zamiast wyłączenia następuje restart: ustaw HibernateMode=shutdown w /etc/systemd/sleep.conf"
