#!/usr/bin/env bash
# [SSH->system] Szybka weryfikacja konfiguracji.
set -uo pipefail

# Raportuje parametr jądra: najpierw z aktywnego /proc/cmdline, a jeśli go tam
# nie ma — z grub.cfg (czyli "zadziała po reboocie"). Dzięki temu uruchomienie
# PRZED restartem nie pokazuje mylącego "BRAK", gdy konfiguracja w GRUB jest OK.
report_param() {  # $1 = regex parametru (np. 'resume_offset=[0-9]*')
  local v
  if v=$(grep -o "$1" /proc/cmdline 2>/dev/null) && [[ -n "$v" ]]; then
    echo "${v}   [aktywne w tym boocie]"
  elif v=$(sudo grep -ho "$1" /boot/grub/grub.cfg 2>/dev/null | sort -u | head -1) && [[ -n "$v" ]]; then
    echo "${v}   [w GRUB — zadziała po reboocie]"
  else
    echo "BRAK   [nie ma ani w /proc/cmdline, ani w grub.cfg]"
  fi
}

echo "== Subwolumeny Btrfs =="
sudo btrfs subvolume list / 2>/dev/null || true

echo
echo "== fstab (btrfs/swap) =="
grep -E 'btrfs|swap' /etc/fstab || true

echo
echo "== Swap / resume =="
swapon --show || true
echo -n "resume:        "; report_param 'resume=UUID=[^ ]*'

echo
echo "== crypttab (TPM2?) =="
cat /etc/crypttab 2>/dev/null || true

echo
echo "== Snapper =="
sudo snapper -c root list 2>/dev/null || echo "snapper root: brak/niedostępny"

echo
echo "== NVIDIA (PreserveVideoMemoryAllocations) =="
grep -i preserve /proc/driver/nvidia/params 2>/dev/null || echo "sterownik NVIDIA niezaładowany lub n/d"

echo
echo "== Usługi NVIDIA suspend/hibernate/resume =="
systemctl is-enabled nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service 2>/dev/null || true

echo
echo "== Hibernacja: resume w initramfs/cmdline =="
echo -n "resume_offset: "; report_param 'resume_offset=[0-9]*'
echo -n "polkit hibernacji: "; ([[ -f /etc/polkit-1/rules.d/10-enable-hibernate.rules ]] && echo "jest" || echo "BRAK")

echo
echo "== Zapora UFW =="
sudo ufw status verbose 2>/dev/null || echo "ufw niezainstalowany lub niedostępny"

echo
echo "== SSH (drop-in hardening) =="
grep -E '^(AllowUsers|PasswordAuthentication|PermitRootLogin)' \
  /etc/ssh/sshd_config.d/99-hardening.conf 2>/dev/null || echo "brak 99-hardening.conf"
