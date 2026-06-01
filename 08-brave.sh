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
#
# Pakiet .deb Brave (~134 MB) bywa ucinany przez CDN ("OpenSSL ... unexpected eof").
# Dlatego: kilka prób z Acquire::Retries + --fix-missing, a gdy APT dalej zawodzi —
# pobranie .deb bezpośrednio z WZNAWIANIEM (curl -C -) i instalacja lokalna.
install_brave() {
  local i
  for i in 1 2 3; do
    if apt-get -o Acquire::Retries=3 install -y --fix-missing brave-browser; then
      return 0
    fi
    echo "!! Próba ${i}/3 nie powiodła się (CDN uciął pobieranie), ponawiam..." >&2
    sleep 3
  done

  echo ">> APT wciąż zawodzi — pobieram .deb bezpośrednio z wznawianiem..." >&2
  local url deb="/tmp/brave-browser.deb"
  url="$(apt-get install --reinstall --print-uris -y brave-browser 2>/dev/null \
         | awk '/brave-browser_.*\.deb/ {gsub(/'\''/,"",$1); print $1; exit}')"
  [[ -n "${url}" ]] || { echo "!! Nie udało się ustalić URL pakietu brave-browser." >&2; exit 1; }
  # curl -C - dociąga od miejsca przerwania (można wywołać wielokrotnie).
  for i in 1 2 3 4 5; do
    curl -fL -C - -o "${deb}" "${url}" && break
    echo "!! Pobieranie urwane (próba ${i}), wznawiam..." >&2; sleep 3
  done
  apt-get install -y "${deb}"
}
install_brave

echo ">> Brave zainstalowany. Profil trafi do ~/.config/BraveSoftware (objęty @home),"
echo "   a cache do ~/.cache (wykluczony przez 06-user-subvolumes.sh)."

# --- Flatpak + Flathub (opcjonalnie) ---
if [[ "${INSTALL_FLATPAK}" == "yes" ]]; then
  apt-get install -y flatpak
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  echo ">> Flatpak + Flathub gotowe."
  echo ">> Dane Flatpak (/var/lib/flatpak) są na osobnym subwolumenie @var_lib_flatpak"
  echo "   (tworzony w 01, domyślnie włączony w config.sh) -> poza snapshotami roota."
fi
