#!/usr/bin/env bash
# [SSH->system] Cursor (edytor AI) — najnowszy .deb z oficjalnego API.
# API zwraca JSON z 'debUrl' aktualnej wersji stabilnej, więc nie zaszywamy wersji.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Uruchom przez sudo: sudo bash 09-cursor.sh"; exit 1; }

API="https://www.cursor.com/api/download?platform=linux-x64&releaseTrack=stable"
DEB="/tmp/cursor-latest.deb"

apt-get update
apt-get install -y curl ca-certificates

echo ">> Pobieram URL najnowszego .deb Cursora z API..."
DEB_URL="$(curl -fsSL "${API}" | grep -oP '"debUrl"\s*:\s*"\K[^"]+')"
[[ -n "${DEB_URL}" ]] || { echo "!! Nie udało się odczytać debUrl z API Cursora." >&2; exit 1; }
echo ">> ${DEB_URL}"

# Pobranie z WZNAWIANIEM (curl -C - dociąga po ewentualnym ucięciu połączenia).
for i in 1 2 3 4 5; do
  curl -fL -C - -o "${DEB}" "${DEB_URL}" && break
  echo "!! Pobieranie urwane (próba ${i}/5), wznawiam..." >&2; sleep 3
done

# Instalacja wraz z zależnościami (apt sam dociągnie biblioteki).
apt-get install -y "${DEB}"
rm -f "${DEB}"

echo ">> Cursor zainstalowany ($(command -v cursor || echo '/usr/bin/cursor'))."
echo ">> Aktualizacje: Cursor aktualizuje się sam z poziomu aplikacji."
