#!/usr/bin/env bash
# [SSH->system] Hardening: SSH (drop-in) + zapora UFW.
# Domyślnie ogranicza SSH do adresu SSH_FROM z config.sh.
# UWAGA: uruchamiasz to przez SSH — skrypt NAJPIERW dodaje regułę zezwalającą,
# dopiero potem włącza UFW, żeby nie odciąć Ci dostępu.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

require_root

# Login docelowy + IP, z którego dopuszczamy SSH (wykryte z sesji SSH)
USERNAME="${USERNAME:-$(detect_target_user)}"
ask USERNAME "Login użytkownika (AllowUsers w SSH)"
SSH_FROM="${SSH_FROM:-$(detect_ssh_from)}"
ask SSH_FROM "IP laptopa do SSH (lub 'any' = bez ograniczeń)" "any"

apt-get update
apt-get install -y openssh-server ufw

# --- SSH: utwardzony drop-in (nie rusza głównego sshd_config) ---
# PasswordAuthentication zostaje YES, żeby nie odciąć Cię przed ssh-copy-id.
# Wyłącz je dopiero po wgraniu klucza (instrukcja na końcu).
if [[ "${SSH_FROM}" == "any" ]]; then
  ALLOW_LINE="AllowUsers ${USERNAME}"
else
  ALLOW_LINE="AllowUsers ${USERNAME}@${SSH_FROM}"
fi

cat > /etc/ssh/sshd_config.d/99-hardening.conf <<EOF
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
KbdInteractiveAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
${ALLOW_LINE}
EOF

sshd -t && systemctl restart ssh
echo ">> SSH: zastosowano 99-hardening.conf (${ALLOW_LINE})."

# --- UFW: domyślnie blokuj wejścia, przepuść SSH z wybranego adresu ---
ufw default deny incoming
ufw default allow outgoing
if [[ "${SSH_FROM}" == "any" ]]; then
  ufw allow 22/tcp comment 'SSH'
else
  ufw allow from "${SSH_FROM}" to any port 22 proto tcp comment 'SSH only from installer IP'
fi
ufw --force enable
systemctl enable ufw
ufw status verbose

echo
echo ">> Hardening gotowy."
echo ">> Aby wyłączyć logowanie hasłem (po wgraniu klucza z laptopa):"
echo "     ssh-copy-id ${USERNAME}@<IP_TEGO_PC>      # z laptopa"
echo "     sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' \\"
echo "        /etc/ssh/sshd_config.d/99-hardening.conf && sudo systemctl restart ssh"
