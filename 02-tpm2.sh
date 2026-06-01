#!/usr/bin/env bash
# [SSH->system] TPM2 auto-unlock roota (start bez hasła).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

require_root

LUKS="${LUKSPART:-$(detect_luks)}"
[[ -n "${LUKS}" ]] || die "Nie znaleziono partycji LUKS."
echo ">> Partycja LUKS: ${LUKS}"

KIND="$(initramfs_kind)"
say "Generator initramfs: ${KIND}"

if [[ "${KIND}" == dracut ]]; then
  # --- dracut + systemd-cryptenroll ---
  echo 'add_dracutmodules+=" tpm2-tss "' > /etc/dracut.conf.d/tpm2.conf
  echo ">> Dostępne urządzenia TPM2:"
  systemd-cryptenroll --tpm2-device=list || true
  echo ">> Zapisuję klucz TPM2 (podaj obecne hasło LUKS):"
  # Dla wymuszenia PIN dodaj: --tpm2-with-pin=yes
  systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs="${TPM2_PCRS}" "${LUKS}"
  cp -a /etc/crypttab "/etc/crypttab.bkp.$(date +%s)"
  grep -q 'tpm2-device=auto' /etc/crypttab || sed -i '/luks/ s/$/,tpm2-device=auto/' /etc/crypttab
  echo ">> /etc/crypttab:"; cat /etc/crypttab
  dracut -f
else
  # --- initramfs-tools + clevis (natywna droga TPM2 na Ubuntu) ---
  apt-get update
  apt-get install -y clevis clevis-luks clevis-initramfs cryptsetup-initramfs tpm2-tools
  echo ">> Zapisuję klucz TPM2 w slocie LUKS przez clevis (podaj obecne hasło LUKS):"
  # PCR 7 = stan Secure Boot. Dla maks. niezawodności można użyć '{}' (bez PCR).
  clevis luks bind -d "${LUKS}" tpm2 "{\"pcr_ids\":\"${TPM2_PCRS}\"}"
  echo ">> Zapisane tokeny LUKS:"; clevis luks list -d "${LUKS}" || true
  update-initramfs -u -k all
fi

echo ">> TPM2 skonfigurowane. Po restarcie root powinien odblokować się bez hasła."
echo ">> (Hasło LUKS pozostaje jako awaryjne — zachowaj je.)"
echo ">> Jeśli mimo to pyta o hasło: sprawdź TPM (ls /dev/tpmrm0) i logi initramfs."
