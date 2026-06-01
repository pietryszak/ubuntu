#!/usr/bin/env bash
# [SSH->system] Narzędzia CLI: +btop +fastfetch +neovim +git +wget +curl, -vim.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Uruchom przez sudo: sudo bash 11-cli-tools.sh"; exit 1; }

export DEBIAN_FRONTEND=noninteractive

apt-get update

# Instalacja narzędzi (neovim zamiast vima).
apt-get install -y btop fastfetch neovim git wget curl

# Usunięcie vima (purge + sprzątanie osieroconych zależności, np. vim-runtime).
if dpkg -l vim 2>/dev/null | grep -q '^ii'; then
  apt-get purge -y vim
fi
apt-get autoremove --purge -y

echo ">> Gotowe: zainstalowano btop, fastfetch, neovim, git, wget, curl; usunięto vim."
echo ">> 'vi'/'vim' mogą jeszcze wskazywać na vim-tiny — ustaw neovim jako domyślny edytor:"
echo "     sudo update-alternatives --install /usr/bin/editor editor /usr/bin/nvim 100"
echo "     sudo update-alternatives --set editor /usr/bin/nvim"
