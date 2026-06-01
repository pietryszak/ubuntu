#!/usr/bin/env bash
# config.sh — OPCJONALNE nadpisania.
#
# Domyślnie możesz NIC tu nie zmieniać: skrypty same wykryją sprzęt
# (dysk, partycje, LUKS, RAM), a o resztę (login, IP laptopa) zapytają
# interaktywnie. Wypełniaj poniższe TYLKO jeśli chcesz wymusić konkretną
# wartość albo masz nietypowy układ (np. kilka dysków).

# --- Dysk i partycje (puste = auto-detekcja po partycji LUKS) ---
DISK=""        # np. /dev/nvme0n1
EFIPART=""     # np. /dev/nvme0n1p1  (FAT32 -> /boot/efi)
BOOTPART=""    # np. /dev/nvme0n1p2  (ext4  -> /boot)
LUKSPART=""    # np. /dev/nvme0n1p3  (LUKS2 -> Btrfs)

# --- Swap dla hibernacji (puste = 1.5×RAM i pyta; ustawione = bez pytania) ---
# 96g: 64 GB RAM + zapas, z naddatkiem starcza na hibernację.
SWAP_SIZE="96g"

# --- TPM2: rejestry PCR ---
# PUSTE = brak PCR (clevis: '{}') => TPM wydaje klucz niezależnie od stanu firmware.
#   + plus: aktualizacja BIOS/UEFI NIE psuje auto-unlock (nie pyta o hasło).
#   - minus: brak wiązania z pomiarem bootu; przy wyłączonym Secure Boot i tak
#            ochrona z PCR jest minimalna, więc dla desktopa to rozsądny wybór.
# "7" = wiązanie ze stanem Secure Boot (po każdym flashu BIOS trzeba przepiąć).
TPM2_PCRS=""

# --- Login docelowy (puste = $SUDO_USER i pyta; ustawione = bez pytania) ---
USERNAME="johndoe"

# --- IP laptopa do SSH w hardeningu 07 (puste = wykryte z sesji SSH; "any" = bez ograniczeń) ---
# Pojedynczy host (bez /24). Ustaw rezerwację DHCP/statyk na routerze dla tego IP.
SSH_FROM="192.168.1.249"

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
  "@var_lib_flatpak=var/lib/flatpak"    # Flatpak / KDE Discover (08 instaluje Flatpak -> trzymamy poza snapshotami)
  # "@var_lib_docker=var/lib/docker"    # Docker
  # "@var_lib_libvirt=var/lib/libvirt"  # KVM/QEMU
)
