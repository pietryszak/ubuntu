#!/usr/bin/env bash
# [SSH->live] Uruchom w środowisku LIVE PO instalacji bazowej Calamares
# (po "Wyjdź do live", PRZED restartem).
#
# Co robi:
#   - dokłada subwolumeny wg dobrych praktyk i przenosi do nich dane,
#   - włącza kompresję zstd dla @ i @home,
#   - przez chroot instaluje openssh-server + avahi do docelowego systemu,
#     żeby po restarcie wejść od razu przez SSH.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

require_root

# Auto-detekcja partycji (nadpisania z config.sh mają pierwszeństwo)
LUKSPART="${LUKSPART:-$(detect_luks)}"
[[ -n "${LUKSPART}" ]] || die "Nie znaleziono partycji LUKS (crypto_LUKS). Czy instalacja bazy się zakończyła?"
DISK="${DISK:-$(parent_disk "${LUKSPART}")}"
EFIPART="${EFIPART:-$(part_by_fstype "${DISK}" vfat)}"
BOOTPART="${BOOTPART:-$(part_by_fstype "${DISK}" ext4)}"
[[ -n "${DISK}" && -n "${EFIPART}" && -n "${BOOTPART}" ]] || \
  die "Nie udało się wykryć wszystkich partycji. Ustaw je ręcznie w config.sh."

echo ">> Wykryto:"
echo "   Dysk:   ${DISK}"
echo "   EFI:    ${EFIPART}"
echo "   /boot:  ${BOOTPART}"
echo "   LUKS:   ${LUKSPART}"
confirm "Czy te urządzenia są poprawne? (dane na nich będą modyfikowane)" || die "Przerwano."

swapoff -a 2>/dev/null || true
umount -R /mnt 2>/dev/null || true
umount -R /mnt2 2>/dev/null || true

if ! cryptsetup status cryptroot >/dev/null 2>&1; then
  echo ">> Otwieram LUKS (podaj hasło):"
  cryptsetup open "${LUKSPART}" cryptroot
fi
ROOTDEV="/dev/mapper/cryptroot"
BTRFS_UUID="$(blkid -s UUID -o value "${ROOTDEV}")"
echo ">> Btrfs UUID: ${BTRFS_UUID}"

mount -o subvolid=5 "${ROOTDEV}" /mnt
[[ -d /mnt/@ ]] || { echo "Brak subwolumenu @ w /mnt — czy Calamares zakończył instalację?"; exit 1; }

FSTAB="/mnt/@/etc/fstab"
cp -a "${FSTAB}" "${FSTAB}.bkp.$(date +%s)"

# Kompresja dla istniejących wpisów (@ i @home) — tylko jeśli brak compress
if ! grep -q 'compress=zstd' "${FSTAB}"; then
  sed -i '/[[:space:]]btrfs[[:space:]]/ s/\(subvol=[^ ,]*\)/\1,compress=zstd:1,noatime/' "${FSTAB}"
fi

# Tworzenie subwolumenów + przeniesienie danych + wpisy fstab
for item in "${EXTRA_SUBVOLS[@]}"; do
  sv="${item%%=*}"
  p="${item#*=}"
  if ! btrfs subvolume show "/mnt/${sv}" >/dev/null 2>&1; then
    btrfs subvolume create "/mnt/${sv}"
  fi
  if [[ -d "/mnt/@/${p}" && ! -L "/mnt/@/${p}" ]]; then
    cp -a --reflink=auto "/mnt/@/${p}/." "/mnt/${sv}/" 2>/dev/null || true
    rm -rf "/mnt/@/${p}"
  fi
  mkdir -p "/mnt/@/${p}"
  if ! grep -q "subvol=${sv}[ ,]" "${FSTAB}"; then
    echo "UUID=${BTRFS_UUID} /${p} btrfs subvol=${sv},compress=zstd:1,noatime,x-systemd.device-timeout=0 0 0" >> "${FSTAB}"
  fi
done

# Uprawnienia specjalne
[[ -d /mnt/@var_tmp ]] && chmod 1777 /mnt/@var_tmp
[[ -d /mnt/@root ]] && chmod 700 /mnt/@root

echo ">> Docelowy /etc/fstab:"
cat "${FSTAB}"

# --- chroot: doinstaluj SSH do docelowego systemu ---
echo ">> Instaluję openssh-server + avahi w docelowym systemie (chroot)..."
mkdir -p /mnt2
mount -o subvol=@,compress=zstd:1,noatime "${ROOTDEV}" /mnt2
mount "${BOOTPART}" /mnt2/boot
mount "${EFIPART}" /mnt2/boot/efi
# --make-rslave: bez tego (przy współdzielonej propagacji) późniejszy 'umount -lR /mnt2'
# przenosi się na ŻYWY /dev/pts i ubija pty sesji live ("sudo: unable to open pty").
for d in dev dev/pts proc sys run; do
  mount --rbind "/${d}" "/mnt2/${d}"
  mount --make-rslave "/mnt2/${d}"
done

# DNS w chroot działa przez podmontowane /run (systemd-resolved z live).
# Jeśli apt nie rozwiązuje nazw, odkomentuj poniższą linię:
# echo 'nameserver 1.1.1.1' > /mnt2/etc/resolv.conf

chroot /mnt2 apt-get update
chroot /mnt2 apt-get install -y openssh-server avahi-daemon
chroot /mnt2 systemctl enable ssh

# Sprzątanie odporne na zajęte /run/user/* (lazy umount w razie potrzeby)
sync
umount -R /mnt2 2>/dev/null || umount -lR /mnt2 2>/dev/null || true
umount -R /mnt  2>/dev/null || umount -lR /mnt  2>/dev/null || true
cryptsetup close cryptroot 2>/dev/null || true
sync

echo
echo ">> GOTOWE. Wyjmij USB i zrestartuj:  sudo systemctl reboot"
echo ">> Po restarcie wejdziesz przez SSH do zainstalowanego systemu i uruchomisz 02..08."
