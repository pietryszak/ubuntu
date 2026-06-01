#!/usr/bin/env bash
# lib.sh — wspólne funkcje: auto-detekcja sprzętu i interaktywne pytania.
# Sourcowane przez pozostałe skrypty; nie uruchamiaj bezpośrednio.

say()  { printf '>> %s\n' "$*"; }
warn() { printf '!! %s\n' "$*" >&2; }
die()  { printf '!! %s\n' "$*" >&2; exit 1; }

require_root()    { [[ $EUID -eq 0 ]] || die "Uruchom przez sudo (jako root)."; }
require_nonroot() { [[ $EUID -ne 0 ]] || die "NIE uruchamiaj przez sudo — odpal jako zwykły użytkownik."; }

# ask VAR "Pytanie" ["domyślna"]
# Nie pyta, jeśli VAR już ma wartość (np. nadpisanie z config.sh).
ask() {
  local __var="$1" __prompt="$2" __default="${3:-}" __ans=""
  [[ -n "${!__var:-}" ]] && return 0
  if [[ ! -t 0 ]]; then
    [[ -n "$__default" ]] || die "Brak wartości dla ${__var} i brak terminala, by zapytać."
    printf -v "$__var" '%s' "$__default"; return 0
  fi
  if [[ -n "$__default" ]]; then
    read -rp "${__prompt} [${__default}]: " __ans
    __ans="${__ans:-$__default}"
  else
    while [[ -z "$__ans" ]]; do read -rp "${__prompt}: " __ans; done
  fi
  printf -v "$__var" '%s' "$__ans"
}

# confirm "Pytanie" -> 0 gdy tak
confirm() {
  local __ans=""
  read -rp "$1 [t/N]: " __ans
  [[ "$__ans" =~ ^([tT]([aA][kK])?|[yY]([eE][sS])?)$ ]]
}

# --- detekcje sprzętu ---

# Partycja LUKS (crypto_LUKS)
detect_luks() { blkid -t TYPE=crypto_LUKS -o device 2>/dev/null | head -1; }

# Dysk-rodzic danej partycji: /dev/nvme0n1p3 -> /dev/nvme0n1
parent_disk() {
  local pk; pk="$(lsblk -no PKNAME "$1" 2>/dev/null | head -1)"
  [[ -n "$pk" ]] && printf '/dev/%s' "$pk"
}

# Pierwsza PARTYCJA (TYPE=part) danego typu FS na danym dysku (np. vfat, ext4).
# Filtr TYPE=part pomija zmapowane urządzenia (np. otwarty cryptroot/btrfs).
part_by_fstype() {
  lsblk -lnpo NAME,TYPE,FSTYPE "$1" 2>/dev/null \
    | awk -v t="$2" '$2=="part" && $3==t {print $1; exit}'
}

# RAM w GiB (zaokrąglone w górę)
ram_gib() {
  local kb; kb="$(awk '/MemTotal/{print $2}' /proc/meminfo)"
  echo $(( (kb + 1048575) / 1048576 ))
}

# Sugerowany swap dla hibernacji: 1.5×RAM (GiB, zaokrąglone w górę)
suggested_swap_gib() { local r; r="$(ram_gib)"; echo $(( (r * 3 + 1) / 2 )); }

# Login docelowego użytkownika (ten, który wywołał sudo; awaryjnie pierwszy z /home)
detect_target_user() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    echo "${SUDO_USER}"
  else
    ls /home 2>/dev/null | head -1
  fi
}

# Generator initramfs: "initramfs-tools" (domyślny w Ubuntu/Kubuntu) lub "dracut"
initramfs_kind() {
  if command -v update-initramfs >/dev/null 2>&1 && [[ -d /etc/initramfs-tools ]]; then
    echo initramfs-tools
  elif command -v dracut >/dev/null 2>&1; then
    echo dracut
  else
    echo initramfs-tools
  fi
}

# Przebuduj initramfs właściwym narzędziem
rebuild_initramfs() {
  if [[ "$(initramfs_kind)" == dracut ]]; then
    dracut -f
  else
    update-initramfs -u -k all
  fi
}

# IP, z którego trwa połączenie SSH (SSH_CONNECTION gubi się pod sudo -> fallback who -m)
detect_ssh_from() {
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    awk '{print $1}' <<<"${SSH_CONNECTION}"; return 0
  fi
  who -m 2>/dev/null | grep -oE '\(([0-9.]+)\)' | tr -d '()' | head -1
}
