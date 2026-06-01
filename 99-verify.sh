#!/usr/bin/env bash
# [SSH->system] Szybka weryfikacja konfiguracji.
set -uo pipefail

echo "== Subwolumeny Btrfs =="
sudo btrfs subvolume list / 2>/dev/null || true

echo
echo "== fstab (btrfs/swap) =="
grep -E 'btrfs|swap' /etc/fstab || true

echo
echo "== Swap / resume =="
swapon --show || true
echo -n "cmdline resume: "; (grep -o 'resume[^ ]*' /proc/cmdline || echo "BRAK")

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
