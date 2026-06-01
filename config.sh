#!/usr/bin/env bash
# Wspólna konfiguracja dla skryptów instalacyjnych.
# Edytuj wartości PRZED uruchomieniem. Sprawdź nazwy urządzeń:
#   lsblk -p -o NAME,SIZE,FSTYPE,MOUNTPOINTS

# --- Dysk docelowy i partycje (używane w Etapie 2, w środowisku live) ---
# Dla NVMe partycje to ...p1/p2/p3; dla SATA (sdX) to ...1/2/3.
DISK="/dev/nvme0n1"          # cały dysk
EFIPART="/dev/nvme0n1p1"     # 1 GiB FAT32  -> /boot/efi
BOOTPART="/dev/nvme0n1p2"    # 2 GiB ext4   -> /boot
LUKSPART="/dev/nvme0n1p3"    # reszta LUKS2 -> Btrfs

# --- Rozmiar swap dla hibernacji: best practice RAM + bufor, NIE równo RAM ---
# Obraz hibernacji może sięgnąć ~pełnego RAM, a swap pełni też zwykłą rolę,
# więc potrzebny zapas. Wybrany wariant RHEL (bezpieczniejszy): 1.5 x RAM.
#   64 GiB RAM -> 96 GiB  (oszczędny wariant Ubuntu RAM+round(sqrt(RAM)) = 72 GiB)
SWAP_SIZE="96g"

# --- TPM2: rejestry PCR (7 = stan Secure Boot). Można dodać PIN w 02-tpm2.sh ---
TPM2_PCRS="7"

# --- Twój login w docelowym systemie (utworzony w Calamares) ---
# Używany w: regule polkit hibernacji (03), strojeniu Snappera (05), hardeningu (07).
USERNAME="pietryszak"

# --- IP, z którego dopuszczamy SSH (hardening w 07-hardening.sh) ---
# Ustaw na adres laptopa w LAN. Wpisz "any" aby NIE ograniczać po adresie.
SSH_FROM="192.168.1.10"

# --- Dodatkowe subwolumeny: "nazwa=ścieżka_względem_@". Zakomentuj zbędne. ---
EXTRA_SUBVOLS=(
  "@root=root"
  "@opt=opt"
  "@srv=srv"
  "@usr_local=usr/local"
  "@var_log=var/log"
  "@var_cache=var/cache"
  "@var_tmp=var/tmp"
  "@var_spool=var/spool"
  "@var_lib_snapd=var/lib/snapd"        # Snap (domyślny w Kubuntu); usuń jeśli nie używasz
  # "@var_lib_flatpak=var/lib/flatpak"  # Flatpak / KDE Discover
  # "@var_lib_docker=var/lib/docker"    # Docker
  # "@var_lib_libvirt=var/lib/libvirt"  # KVM/QEMU
)
