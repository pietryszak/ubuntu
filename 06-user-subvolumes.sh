#!/usr/bin/env bash
# [SSH->system] Wykluczenia per-user ze snapshotów @home.
# Uruchom JAKO ZWYKŁY UŻYTKOWNIK (bez sudo), po pierwszym zalogowaniu,
# z ZAMKNIĘTYMI przeglądarkami i aplikacjami.
set -euo pipefail

[[ $EUID -ne 0 ]] || { echo "NIE uruchamiaj przez sudo — odpal jako zwykły użytkownik."; exit 1; }

make_subvol() {
  local d="$1"
  if btrfs subvolume show "${d}" >/dev/null 2>&1; then
    echo ">> ${d}: już jest subwolumenem, pomijam."
    return 0
  fi
  [[ -e "${d}" ]] && mv "${d}" "${d}.bak"
  mkdir -p "$(dirname "${d}")"
  btrfs subvolume create "${d}"
  if [[ -e "${d}.bak" ]]; then
    cp -a "${d}.bak/." "${d}/" 2>/dev/null || true
    rm -rf "${d}.bak"
  fi
  echo ">> ${d}: utworzono subwolumen."
}

# Cache: subwolumen + NOCOW (cache jest odtwarzalny)
if ! btrfs subvolume show "${HOME}/.cache" >/dev/null 2>&1; then
  [[ -e "${HOME}/.cache" ]] && mv "${HOME}/.cache" "${HOME}/.cache.bak"
  btrfs subvolume create "${HOME}/.cache"
  chattr +C "${HOME}/.cache" || true
  if [[ -e "${HOME}/.cache.bak" ]]; then
    cp -a "${HOME}/.cache.bak/." "${HOME}/.cache/" 2>/dev/null || true
    rm -rf "${HOME}/.cache.bak"
  fi
  echo ">> ~/.cache: utworzono subwolumen (NOCOW)."
fi

# Dane per-app, które wykluczamy ze snapshotów @home
make_subvol "${HOME}/snap"
make_subvol "${HOME}/.var/app"
make_subvol "${HOME}/.local/share/Trash"

echo ">> Gotowe. Wykluczenia obejmują m.in. cache Brave / Brave Origin."
