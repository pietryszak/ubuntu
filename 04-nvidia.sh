#!/usr/bin/env bash
# [SSH->system] Sterownik NVIDIA + obsługa hibernacji (zachowanie VRAM).
# Secure Boot wyłączony => brak MOK => można zdalnie.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

require_root

apt-get update

echo ">> Wykryte/zalecane sterowniki:"
ubuntu-drivers list || true

# Instalacja zalecanego sterownika własnościowego
if ! ubuntu-drivers install; then
  echo ">> 'ubuntu-drivers install' nie powiodło się, próbuję autoinstall..."
  ubuntu-drivers autoinstall
fi

# Zachowanie pamięci VRAM przy suspend/hibernate.
# /var/tmp musi być na dysku i mieć miejsce na zrzut VRAM (4070 Ti = 12 GB).
cat > /etc/modprobe.d/nvidia-power.conf <<'EOF'
options nvidia NVreg_PreserveVideoMemoryAllocations=1 NVreg_TemporaryFilePath=/var/tmp
EOF

# Usługi NVIDIA dla stanów uśpienia
systemctl enable nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service || true

rebuild_initramfs

echo ">> NVIDIA gotowe. Zalecany restart."
echo ">> Jeśli hibernacja zwróci błąd -5/pci_pm_freeze, sprawdź:"
echo "     cat /proc/driver/nvidia/params | grep -i preserve"
echo "   oraz istnienie /proc/driver/nvidia/suspend (wymaga załadowanego sterownika po restarcie)."
