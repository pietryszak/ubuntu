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

# --- Wykrycie typu modułu jądra: OPEN vs PROPRIETARY -------------------------
# Sterownik 595 obsługuje suspend/resume inaczej dla każdego z modułów:
#   OPEN        -> nvidia.ko sama zachowuje VRAM, gdy NVreg_UseKernelSuspendNotifiers=1,
#                  a stare usługi nvidia-suspend/resume/hibernate MUSZĄ być wyłączone
#                  (inaczej kolizja => "Pageflip timed out" / czarny ekran po S3).
#   PROPRIETARY -> zachowanie VRAM przez /proc/driver/nvidia/suspend => usługi nvidia-* WŁ.
# Detekcja działa też przed reboot (gdy moduł nie jest jeszcze załadowany):
#   1) /proc (gdy załadowany) -> 2) licencja modułu -> 3) nazwa pakietu.
is_open_module() {
  if [[ -r /proc/driver/nvidia/version ]] && grep -qi 'open' /proc/driver/nvidia/version; then
    return 0
  fi
  if modinfo nvidia 2>/dev/null | grep -qi 'license:.*Dual MIT/GPL'; then
    return 0
  fi
  if dpkg -l 2>/dev/null | grep -qE '^ii\s+nvidia-(driver|kernel)(-open|.*-open)'; then
    return 0
  fi
  return 1
}

# Zachowanie pamięci VRAM przy suspend/hibernate.
# /var/tmp musi być na dysku i mieć miejsce na zrzut VRAM (4070 Ti = 12 GB).
#
# nvidia_drm:
#   modeset=1 - wymagane pod Wayland/KMS
#   fbdev=1   - NVIDIA przejmuje framebuffer; bez tego KWin po wybudzeniu z S3
#               traci dostęp do DRM ("atomic commit failed: Permission denied",
#               "Failed to open /dev/dri/renderD128") => czarny ekran po sleep.
if is_open_module; then
  echo ">> Wykryto OPEN kernel module -> NVreg_UseKernelSuspendNotifiers=1, usługi nvidia-* WYŁĄCZONE."
  cat > /etc/modprobe.d/nvidia-power.conf <<'EOF'
options nvidia_drm modeset=1 fbdev=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1 NVreg_TemporaryFilePath=/var/tmp NVreg_UseKernelSuspendNotifiers=1
EOF
  # Przy open module nvidia.ko obsługuje suspend sama => stare usługi tylko przeszkadzają.
  systemctl disable nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service || true
else
  echo ">> Wykryto PROPRIETARY kernel module -> zachowanie VRAM przez usługi nvidia-* (WŁĄCZONE)."
  cat > /etc/modprobe.d/nvidia-power.conf <<'EOF'
options nvidia_drm modeset=1 fbdev=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1 NVreg_TemporaryFilePath=/var/tmp
EOF
  systemctl enable nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service || true
fi

rebuild_initramfs

echo ">> NVIDIA gotowe. Zalecany restart."
echo ">> Po restarcie zweryfikuj:"
echo "     cat /sys/module/nvidia_drm/parameters/fbdev      # ma być Y"
echo "     cat /proc/driver/nvidia/params | grep -i preserve"
echo ">> Test: 'systemctl suspend' oraz 'systemctl hibernate' — ekran ma wrócić."
