#!/usr/bin/env bash
# [SSH->system] Brave (oficjalne repo APT) + opcjonalnie Flatpak/Flathub.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Uruchom przez sudo: sudo bash 08-brave.sh"; exit 1; }

# Zainstaluj Flatpak + Flathub? (przydatne dla KDE Discover)
INSTALL_FLATPAK="${INSTALL_FLATPAK:-yes}"

apt-get update
apt-get install -y curl

# --- Brave z oficjalnego repozytorium (https://brave.com/linux/) ---
curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
  https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources \
  https://brave-browser-apt-release.s3.brave.com/brave-browser.sources
apt-get update

# Standardowy Brave Browser. Jeśli korzystasz z osobnego produktu "Brave Origin",
# sprawdź dostępne pakiety: apt-cache search brave  (i podmień nazwę poniżej).
apt-get install -y brave-browser

echo ">> Brave zainstalowany. Profil trafi do ~/.config/BraveSoftware (objęty @home),"
echo "   a cache do ~/.cache (wykluczony przez 06-user-subvolumes.sh)."

# --- Flatpak + Flathub (opcjonalnie) ---
if [[ "${INSTALL_FLATPAK}" == "yes" ]]; then
  apt-get install -y flatpak
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  echo ">> Flatpak + Flathub gotowe."
  echo ">> Jeśli chcesz dane Flatpak na osobnym subwolumenie: odkomentuj"
  echo "   @var_lib_flatpak w config.sh PRZED instalacją systemowych Flatpaków."
fi
