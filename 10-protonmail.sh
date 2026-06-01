#!/usr/bin/env bash
# [SSH->system] Proton Mail — aplikacja desktopowa (oficjalny .deb).
# UWAGA: desktopowy Proton Mail na Linux jest oficjalnie w wersji BETA.
# URL jest stały i zawsze wskazuje najnowszego .deb (bez zaszywania wersji).
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Uruchom przez sudo: sudo bash 10-protonmail.sh"; exit 1; }

DEB_URL="https://proton.me/download/mail/linux/ProtonMail-desktop-beta.deb"
DEB="/tmp/protonmail-desktop.deb"

apt-get update
apt-get install -y curl ca-certificates

echo ">> Pobieram Proton Mail (.deb, beta) z wznawianiem..."
# curl -C - dociąga po ewentualnym ucięciu połączenia (można wywołać wielokrotnie).
for i in 1 2 3 4 5; do
  curl -fL -C - -o "${DEB}" "${DEB_URL}" && break
  echo "!! Pobieranie urwane (próba ${i}/5), wznawiam..." >&2; sleep 3
done

# Instalacja wraz z zależnościami (apt sam dociągnie biblioteki).
apt-get install -y "${DEB}"
rm -f "${DEB}"

echo ">> Proton Mail (desktop) zainstalowany. Szukaj 'Proton Mail' w menu KDE."
echo ">> To wersja BETA — aktualizacje przez ponowne uruchomienie tego skryptu lub z apki."
