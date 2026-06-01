#!/usr/bin/env bash
# [PC] Uruchom w środowisku LIVE na komputerze docelowym.
# Włącza serwer SSH, ustawia hasło użytkownika live i pokazuje adres IP,
# żeby dalszą pracę prowadzić z laptopa przez SSH.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Uruchom przez sudo: sudo bash 00-live-ssh.sh"
  exit 1
fi

apt-get update
apt-get install -y openssh-server
systemctl enable --now ssh

# Użytkownik live (ten, który wywołał sudo)
LIVE_USER="${SUDO_USER:-$(logname 2>/dev/null || echo kubuntu)}"

echo
echo ">> Ustaw hasło użytkownika live '${LIVE_USER}' (potrzebne do logowania SSH):"
passwd "${LIVE_USER}"

echo
echo ">> Użytkownik do SSH: ${LIVE_USER}"
echo ">> Adresy IP tej maszyny:"
ip -4 -br address
echo
echo ">> Z laptopa połącz się:  ssh ${LIVE_USER}@<IP_POWYZEJ>"
