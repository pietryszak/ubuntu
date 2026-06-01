#!/usr/bin/env bash
# [SSH->system] Snapper + grub-btrfs + Btrfs Assistant + automatyczne snapshoty apt.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

[[ $EUID -eq 0 ]] || { echo "Uruchom przez sudo: sudo bash 05-snapper-grub-btrfs.sh"; exit 1; }

apt-get update
apt-get install -y snapper btrfs-assistant inotify-tools git make

# Konfiguracje Snappera (tworzą /.snapshots i /home/.snapshots)
snapper get-config root >/dev/null 2>&1 || snapper -c root create-config /
snapper get-config home >/dev/null 2>&1 || snapper -c home create-config /home

# Strojenie: zarządzanie bez sudo (ALLOW_USERS+SYNC_ACL) i rozsądne limity retencji
snapper -c root set-config ALLOW_USERS="${USERNAME}" SYNC_ACL=yes \
  TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes \
  TIMELINE_LIMIT_HOURLY=5 TIMELINE_LIMIT_DAILY=7 TIMELINE_LIMIT_WEEKLY=4 \
  TIMELINE_LIMIT_MONTHLY=2 TIMELINE_LIMIT_YEARLY=0 NUMBER_LIMIT=20
chmod 750 /.snapshots 2>/dev/null || true

snapper -c home set-config ALLOW_USERS="${USERNAME}" SYNC_ACL=yes \
  TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes \
  TIMELINE_LIMIT_HOURLY=2 TIMELINE_LIMIT_DAILY=7 TIMELINE_LIMIT_WEEKLY=2 \
  TIMELINE_LIMIT_MONTHLY=0 TIMELINE_LIMIT_YEARLY=0 NUMBER_LIMIT=15
chmod 750 /home/.snapshots 2>/dev/null || true

systemctl enable --now snapper-timeline.timer snapper-cleanup.timer

# Automatyczne snapshoty pre/post przy operacjach apt
cat > /etc/apt/apt.conf.d/80snapper <<'EOF'
DPkg::Pre-Invoke  { "if command -v snapper >/dev/null; then snapper -c root create -t pre  -c number -p -d 'apt' >/var/lib/snapper/apt-pre 2>/dev/null || true; fi"; };
DPkg::Post-Invoke { "if command -v snapper >/dev/null; then snapper -c root create -t post -c number --pre-number \"$(cat /var/lib/snapper/apt-pre 2>/dev/null)\" -d 'apt' 2>/dev/null || true; fi"; };
EOF

# grub-btrfs: bootowanie snapshotów z menu GRUB
if [[ ! -d /tmp/grub-btrfs ]]; then
  git clone https://github.com/Antynea/grub-btrfs /tmp/grub-btrfs
fi
make -C /tmp/grub-btrfs install
systemctl enable --now grub-btrfsd
update-grub

echo ">> Snapper + grub-btrfs + Btrfs Assistant gotowe."
echo ">> Test: 'sudo apt install htop' -> powinny powstać snapshoty pre/post (snapper -c root list)."
echo ">> GUI: uruchom 'btrfs-assistant' jako root, by zarządzać snapshotami."
