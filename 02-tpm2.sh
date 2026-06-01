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
  # UWAGA: pin 'tpm2' jest w osobnej paczce clevis-tpm2 (bez niej: "not a valid pin").
  apt-get install -y clevis clevis-tpm2 clevis-luks clevis-initramfs cryptsetup-initramfs tpm2-tools
  echo ">> Zapisuję klucz TPM2 w slocie LUKS przez clevis (podaj obecne hasło LUKS):"
  # PCR 7 = stan Secure Boot. Bank sha256 jawnie — clevis domyślnie próbuje sha1,
  # którego nowoczesne TPM-y nie mają aktywnego ("Unable to validate ... PCR bank 'sha1'").
  # Dla maks. niezawodności można użyć '{}' (bez PCR).
  PCR_BANK="${TPM2_PCR_BANK:-sha256}"
  clevis luks bind -d "${LUKS}" tpm2 "{\"pcr_bank\":\"${PCR_BANK}\",\"pcr_ids\":\"${TPM2_PCRS}\"}"
  echo ">> Zapisane tokeny LUKS:"; clevis luks list -d "${LUKS}" || true

  # --- Drobne usprawnienia bootu (opcjonalne, nieszkodliwe) ---
  # UWAGA: w praktyce widoczny monit o hasło na kilka sekund wynika z czasu
  # initramfs (udev/enumeracja urządzeń, init fTPM) oraz POST firmware, a NIE
  # z entropii. Sam clevis+TPM to ~1.4 s. Poniższe to dobre domyślne, ale nie
  # gwarantują zniknięcia monitu — na wolnym fTPM AMD kilka sekund jest normą.
  # 1) Wczesne wczytanie sterownika TPM w initramfs.
  for m in tpm_tis tpm_crb; do
    grep -qxF "$m" /etc/initramfs-tools/modules 2>/dev/null || echo "$m" >> /etc/initramfs-tools/modules
  done
  # 2) Entropia z CPU (RDRAND) — rozsądne domyślne na wczesny boot.
  #    Wpisujemy do GRUB_CMDLINE_LINUX (działa niezależnie od ' lub " w pliku).
  if ! grep -q 'random.trust_cpu=on' /etc/default/grub; then
    cp -a /etc/default/grub "/etc/default/grub.bkp.$(date +%s)"
    if grep -q '^GRUB_CMDLINE_LINUX=' /etc/default/grub; then
      sed -i -E "s/^(GRUB_CMDLINE_LINUX=)([\"'])(.*)\2/\1\2\3 random.trust_cpu=on\2/" /etc/default/grub
    else
      echo 'GRUB_CMDLINE_LINUX="random.trust_cpu=on"' >> /etc/default/grub
    fi
    update-grub
  fi

  update-initramfs -u -k all
fi

echo ">> TPM2 skonfigurowane. Po restarcie root powinien odblokować się bez hasła."
echo ">> (Hasło LUKS pozostaje jako awaryjne — zachowaj je.)"
echo ">> Jeśli mimo to pyta o hasło: sprawdź TPM (ls /dev/tpmrm0) i logi initramfs."
