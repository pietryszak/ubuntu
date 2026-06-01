#!/usr/bin/env bash
# [SSH->system] TPM2 auto-unlock roota (start bez hasła).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

[[ $EUID -eq 0 ]] || { echo "Uruchom przez sudo: sudo bash 02-tpm2.sh"; exit 1; }

LUKS="$(blkid -t TYPE=crypto_LUKS -o device | head -1)"
[[ -n "${LUKS}" ]] || { echo "Nie znaleziono partycji LUKS."; exit 1; }
echo ">> Partycja LUKS: ${LUKS}"

# Moduł TPM2 w dracut
echo 'add_dracutmodules+=" tpm2-tss "' > /etc/dracut.conf.d/tpm2.conf

echo ">> Dostępne urządzenia TPM2:"
systemd-cryptenroll --tpm2-device=list || true

echo ">> Zapisuję klucz TPM2 (podaj obecne hasło LUKS):"
# Dla wymuszenia PIN dodaj: --tpm2-with-pin=yes
systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs="${TPM2_PCRS}" "${LUKS}"

cp -a /etc/crypttab "/etc/crypttab.bkp.$(date +%s)"
if ! grep -q 'tpm2-device=auto' /etc/crypttab; then
  sed -i '/luks/ s/$/,tpm2-device=auto/' /etc/crypttab
fi
echo ">> /etc/crypttab:"
cat /etc/crypttab

dracut -f
echo ">> TPM2 skonfigurowane. Po restarcie root powinien odblokować się bez hasła."
echo ">> (Hasło LUKS pozostaje jako awaryjne — zachowaj je.)"
