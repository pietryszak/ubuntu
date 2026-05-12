# Ubuntu Server 26.04 LTS (Resolute Raccoon) — pełna instalacja krok po kroku

**Sprzęt:** Dell Latitude 5421 (Intel 11. gen Tiger Lake)  
**Konfiguracja:** KDE Plasma 6 (minimal, Wayland) · BTRFS · LUKS2 (pełne szyfrowanie) · Snapper + grub-btrfs · hibernacja · SSH ograniczony do `192.168.1.10`

Założenia: 32 GB RAM, dysk NVMe, instalację robisz przez SSH z komputera `192.168.1.10` do laptopa zbootowanego z **Ubuntu Server 26.04 LTS Live USB** (na konsoli live tylko krótko: hasło, `openssh-server`, adres IP; `debootstrap` i narzędzia dysku instalujesz już po SSH).

Release notes: [Ubuntu 26.04 LTS](https://documentation.ubuntu.com/release-notes/26.04/).

> **ZANIM ZACZNIESZ:**
>
> - Dysk laptopa zostanie **całkowicie wyczyszczony** — zrób backup.
> - W BIOS-ie Dell-a (F2 przy logo) wyłącz **Secure Boot** (`Boot Configuration → Secure Boot = Disabled`). Hibernacja nie działa z włączonym Secure Boot.
> - Podłącz kabel Ethernet i ładowarkę.

---

## SEKCJA 0 — Live USB + dostęp SSH

Zbootuj laptop z **Ubuntu Server 26.04 LTS** ISO. Wejdź do powłoki z `apt` (np. drugi TTY `Ctrl+Alt+F2`, menu **Help** / **Enter shell**, albo środowisko po wyborze „Try/Install” — zależnie od wariantu ISO). Typowo dostępny jest użytkownik `**ubuntu-server`** (pierwsze logowanie często bez hasła; ustaw hasło).

```bash
sudo passwd ubuntu-server

sudo apt update
sudo apt install -y openssh-server
sudo systemctl start ssh

ip -4 addr show | grep inet
```

Z komputera `192.168.1.10`:

```bash
ssh ubuntu-server@<IP_LAPTOPA>
sudo -i
```

**Od tego momentu wszystkie komendy w sesji SSH na roota.** Na laptopie wpisałeś minimum — resztę pakietów do instalacji zrób już zdalnie:

```bash
apt update
apt install -y debootstrap gdisk btrfs-progs cryptsetup
```

---

## SEKCJA 1 — Zmienne i identyfikacja dysku

```bash
lsblk -po name,size,model,fstype,label,uuid
```

Ustaw zmienne — **edytuj wartości pod siebie**:

```bash
# === DOSTOSUJ ===
export DISK=/dev/nvme0n1
export DISK_P=p                     # 'p' dla NVMe, '' dla SATA
export HOSTNAME=latitude
export USERNAME=pietryszak
export TIMEZONE=Europe/Warsaw
export SSH_FROM=192.168.1.10
export SWAP_GB=34                   # RAM (32) + 2 GB zapasu na hibernację
# ================

export PART_EFI=${DISK}${DISK_P}1
export PART_LUKS=${DISK}${DISK_P}2

echo "EFI:  $PART_EFI"
echo "LUKS: $PART_LUKS"
```

---

## SEKCJA 2 — Partycjonowanie + LUKS2 + BTRFS

```bash
apt update
apt install -y gdisk btrfs-progs cryptsetup debootstrap

# Wymaż i utwórz GPT
sgdisk -Z $DISK
sgdisk -og $DISK

# EFI (1 GiB) + LUKS (reszta)
sgdisk -n 1::+1G -t 1:ef00 -c 1:'ESP' $DISK
sgdisk -n 2:: -t 2:8309 -c 2:'cryptsystem' $DISK

partprobe $DISK
sleep 2

mkfs.fat -F32 -n EFI $PART_EFI
lsblk -po name,size,fstype,label $DISK
```

### LUKS2 z `argon2id`

GRUB 2.14 w Ubuntu 26.04 (`grub-efi-amd64` 2.14-2ubuntu1) odblokowuje LUKS2 z `**argon2id**` — w `grub-install` doda się moduł `**argon2**` (już ujęty w SEKCJI 11). **Hasło LUKS musi być ASCII** — GRUB ma US keyboard layout.

```bash
cryptsetup luksFormat \
    --type luks2 \
    --cipher aes-xts-plain64 \
    --key-size 512 \
    --hash sha512 \
    --pbkdf argon2id \
    --pbkdf-memory 524288 \
    --pbkdf-parallel 4 \
    --iter-time 2000 \
    --use-random \
    --label cryptsystem \
    --verify-passphrase \
    $PART_LUKS

cryptsetup open $PART_LUKS cryptroot

mkfs.btrfs -L UBUNTU /dev/mapper/cryptroot
```

`--pbkdf-memory 524288` (512 MiB) i `--iter-time 2000` — wygodne dla GRUB w pre-boot (na 32 GB RAM laptopa bez problemu) i przy okazji szybkie do odblokowania w initramfs.

---

## SEKCJA 3 — Subwoluminy BTRFS i montowanie

Snapshoty Snappera będą w zagnieżdżonym `/.snapshots` — **nie** tworzymy osobnego top-level `@snapshots`.

```bash
mount /dev/mapper/cryptroot /mnt

cd /mnt
btrfs subvolume create @
btrfs subvolume create @home
btrfs subvolume create @opt
btrfs subvolume create @cache
btrfs subvolume create @log
btrfs subvolume create @tmp
btrfs subvolume create @spool
btrfs subvolume create @sddm
btrfs subvolume create @swap

btrfs subvolume create @docker
btrfs subvolume create @containers
btrfs subvolume create @flatpak
btrfs subvolume create @libvirt
btrfs subvolume create @games
cd /

btrfs subvolume list /mnt
umount /mnt
```

```bash
export BTRFS_OPTS="defaults,noatime,compress=zstd:1"

mount -o $BTRFS_OPTS,subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{home,opt,boot/efi,swap,games,var/{cache,log,tmp,spool,lib/{sddm,docker,containers,flatpak,libvirt}}}

mount -o $BTRFS_OPTS,subvol=@home       /dev/mapper/cryptroot /mnt/home
mount -o $BTRFS_OPTS,subvol=@opt        /dev/mapper/cryptroot /mnt/opt
mount -o $BTRFS_OPTS,subvol=@cache      /dev/mapper/cryptroot /mnt/var/cache
mount -o $BTRFS_OPTS,subvol=@log        /dev/mapper/cryptroot /mnt/var/log
mount -o $BTRFS_OPTS,subvol=@tmp        /dev/mapper/cryptroot /mnt/var/tmp
mount -o $BTRFS_OPTS,subvol=@spool      /dev/mapper/cryptroot /mnt/var/spool
mount -o $BTRFS_OPTS,subvol=@sddm       /dev/mapper/cryptroot /mnt/var/lib/sddm

mount -o $BTRFS_OPTS,subvol=@docker     /dev/mapper/cryptroot /mnt/var/lib/docker
mount -o $BTRFS_OPTS,subvol=@containers /dev/mapper/cryptroot /mnt/var/lib/containers
mount -o $BTRFS_OPTS,subvol=@flatpak    /dev/mapper/cryptroot /mnt/var/lib/flatpak
mount -o $BTRFS_OPTS,subvol=@libvirt    /dev/mapper/cryptroot /mnt/var/lib/libvirt
mount -o $BTRFS_OPTS,subvol=@games      /dev/mapper/cryptroot /mnt/games

mount -o defaults,noatime,subvol=@swap  /dev/mapper/cryptroot /mnt/swap

mount $PART_EFI /mnt/boot/efi

findmnt /mnt
```

### Rollback `/` a historia, maile, Flatpak użytkownika

- `**snapper -c root rollback**` nie cofa `@home` — profil przeglądarki, poczta, `~/.var` (Flatpak per-user) zostają bieżące.
- **grub-btrfs** bootuje starszy `/`, ale `**fstab` montuje ten sam `@home`** — zamierzone.
- **Flatpak systemowy** (`/var/lib/flatpak` na `@flatpak`) może się zmienić przy rollbacku roota; dane użytkownika w `~/.var` na `@home`.

### 3.1 Co po co — subwoluminy


| Subwolumin    | Mount                 | Po co                                |
| ------------- | --------------------- | ------------------------------------ |
| `@`           | `/`                   | system + snapshoty `snapper -c root` |
| `@home`       | `/home`               | dane użytkownika                     |
| `@opt`        | `/opt`                | oprogramowanie spoza APT             |
| `@cache`      | `/var/cache`          | cache APT — poza snapshotami `/`     |
| `@log`        | `/var/log`            | logi przeżywają rollback `/`         |
| `@tmp`        | `/var/tmp`            | tymczasowe                           |
| `@spool`      | `/var/spool`          | kolejki                              |
| `@sddm`       | `/var/lib/sddm`       | SDDM po rollbacku                    |
| `@swap`       | `/swap`               | swapfile — bez kompresji i CoW       |
| `@docker`     | `/var/lib/docker`     | Docker                               |
| `@containers` | `/var/lib/containers` | Podman rootful                       |
| `@flatpak`    | `/var/lib/flatpak`    | Flatpak systemowy                    |
| `@libvirt`    | `/var/lib/libvirt`    | QEMU/KVM                             |
| `@games`      | `/games`              | Steam/gry (opcjonalnie)              |


---

## SEKCJA 4 — debootstrap (Ubuntu `resolute`)

```bash
debootstrap --arch=amd64 \
    --components=main,restricted,universe,multiverse \
    resolute /mnt http://archive.ubuntu.com/ubuntu
```

(EU: `http://pl.archive.ubuntu.com/ubuntu` itd.)

---

## SEKCJA 5 — fstab + crypttab + keyfile

### 5.1 UUID-y

```bash
export BTRFS_UUID=$(blkid -s UUID -o value /dev/mapper/cryptroot)
export EFI_UUID=$(blkid -s UUID -o value $PART_EFI)
export LUKS_UUID=$(blkid -s UUID -o value $PART_LUKS)

echo "BTRFS: $BTRFS_UUID"
echo "EFI:   $EFI_UUID"
echo "LUKS:  $LUKS_UUID"
```

### 5.2 /etc/fstab

```bash
cat > /mnt/etc/fstab <<EOF
# <device>                <mount>             <fs>    <options>                                          <d> <p>
UUID=$BTRFS_UUID          /                   btrfs   defaults,noatime,compress=zstd:1,subvol=@          0   0
UUID=$BTRFS_UUID          /home               btrfs   defaults,noatime,compress=zstd:1,subvol=@home      0   0
UUID=$BTRFS_UUID          /opt                btrfs   defaults,noatime,compress=zstd:1,subvol=@opt       0   0
UUID=$BTRFS_UUID          /var/cache          btrfs   defaults,noatime,compress=zstd:1,subvol=@cache     0   0
UUID=$BTRFS_UUID          /var/log            btrfs   defaults,noatime,compress=zstd:1,subvol=@log       0   0
UUID=$BTRFS_UUID          /var/tmp            btrfs   defaults,noatime,compress=zstd:1,subvol=@tmp       0   0
UUID=$BTRFS_UUID          /var/spool          btrfs   defaults,noatime,compress=zstd:1,subvol=@spool     0   0
UUID=$BTRFS_UUID          /var/lib/sddm       btrfs   defaults,noatime,compress=zstd:1,subvol=@sddm      0   0
UUID=$BTRFS_UUID          /var/lib/docker     btrfs   defaults,noatime,compress=zstd:1,subvol=@docker    0   0
UUID=$BTRFS_UUID          /var/lib/containers btrfs   defaults,noatime,compress=zstd:1,subvol=@containers 0   0
UUID=$BTRFS_UUID          /var/lib/flatpak    btrfs   defaults,noatime,compress=zstd:1,subvol=@flatpak   0   0
UUID=$BTRFS_UUID          /var/lib/libvirt    btrfs   defaults,noatime,compress=zstd:1,subvol=@libvirt   0   0
UUID=$BTRFS_UUID          /games              btrfs   defaults,noatime,compress=zstd:1,subvol=@games     0   0
UUID=$BTRFS_UUID          /swap               btrfs   defaults,noatime,subvol=@swap                      0   0
UUID=$EFI_UUID            /boot/efi           vfat    defaults,noatime,umask=0077                        0   2
/swap/swapfile            none                swap    defaults                                           0   0
EOF
```

### 5.3 Keyfile

```bash
mkdir -p /mnt/etc/cryptsetup-keys.d
dd if=/dev/urandom of=/mnt/etc/cryptsetup-keys.d/cryptroot.key bs=512 count=8
chmod 600 /mnt/etc/cryptsetup-keys.d/cryptroot.key
chmod 700 /mnt/etc/cryptsetup-keys.d

cryptsetup luksAddKey $PART_LUKS /mnt/etc/cryptsetup-keys.d/cryptroot.key

cryptsetup luksDump $PART_LUKS | grep -E "Keyslots:|^  [0-9]:"
```

### 5.4 /etc/crypttab

```bash
cat > /mnt/etc/crypttab <<EOF
# <target>   <source>              <keyfile>                              <options>
cryptroot    UUID=$LUKS_UUID       /etc/cryptsetup-keys.d/cryptroot.key   luks,discard,key-slot=1,no-read-workqueue,no-write-workqueue
EOF
```

---

## SEKCJA 6 — Wejście do chroot

```bash
for d in dev dev/pts proc sys run sys/firmware/efi/efivars; do
    mount --rbind /$d /mnt/$d
    mount --make-rslave /mnt/$d
done

chroot /mnt /bin/bash
```

> DNS w chroocie działa „samo": `/etc/resolv.conf` z debootstrapa to symlink na `../run/systemd/resolve/stub-resolv.conf`, a `/run` przed chwilą zbindowaliśmy z live ISO.

Załaduj zmienne w chroocie:

```bash
export DISK=/dev/nvme0n1
export DISK_P=p
export HOSTNAME=latitude
export USERNAME=pietryszak
export TIMEZONE=Europe/Warsaw
export SSH_FROM=192.168.1.10
export SWAP_GB=34
export PART_EFI=${DISK}${DISK_P}1
export PART_LUKS=${DISK}${DISK_P}2
export BTRFS_UUID=$(blkid -s UUID -o value /dev/mapper/cryptroot)
export LUKS_UUID=$(blkid -s UUID -o value $PART_LUKS)
```

---

## SEKCJA 7 — Konfiguracja podstawowa

### 7.1 Repozytoria (deb822)

Ubuntu nie używa `non-free` jak Debian — komponenty to `main restricted universe multiverse`.

`rm -f /etc/apt/sources.list` kasuje **legacy** jednolinijkowy plik po debootstrapie. Tworzymy **deb822** w `sources.list.d/ubuntu.sources` (format domyślny od 24.04). Dwa bloki — `archive` na zwykłe paczki, `security.ubuntu.com` na `-security`, dokładnie jak na stocku.

```bash
rm -f /etc/apt/sources.list
mkdir -p /etc/apt/sources.list.d

cat > /etc/apt/sources.list.d/ubuntu.sources <<'EOF'
Types: deb
URIs: http://archive.ubuntu.com/ubuntu/
Suites: resolute resolute-updates resolute-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://security.ubuntu.com/ubuntu/
Suites: resolute-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF

apt update
```

### 7.2 Bez snapd (trwałe)

```bash
apt purge -y snapd 2>/dev/null || true
apt-mark hold snapd 2>/dev/null || true

mkdir -p /etc/apt/preferences.d
cat > /etc/apt/preferences.d/99-no-snap.pref <<'EOF'
Package: snapd
Pin: release a=*
Pin-Priority: -1
EOF

apt autoremove --purge -y
```

### 7.3 Locale, czas, klawiatura, hostname

```bash
apt install -y locales console-setup tzdata keyboard-configuration

sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^# *pl_PL.UTF-8 UTF-8/pl_PL.UTF-8 UTF-8/' /etc/locale.gen
locale-gen

cat > /etc/default/locale <<'EOF'
LANG=en_US.UTF-8
LC_TIME=pl_PL.UTF-8
LC_PAPER=pl_PL.UTF-8
LC_MEASUREMENT=pl_PL.UTF-8
LC_MONETARY=pl_PL.UTF-8
LC_NUMERIC=pl_PL.UTF-8
LC_ADDRESS=pl_PL.UTF-8
LC_TELEPHONE=pl_PL.UTF-8
LC_NAME=pl_PL.UTF-8
EOF

ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
dpkg-reconfigure -f noninteractive tzdata

cat > /etc/default/keyboard <<'EOF'
XKBMODEL="pc105"
XKBLAYOUT="pl"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF
dpkg-reconfigure -f noninteractive keyboard-configuration

echo $HOSTNAME > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF
```

### 7.4 Użytkownik + sudo

Grupa `**sudo**` (nie `wheel`).

```bash
apt install -y sudo

passwd

# 'netdev' tworzy dopiero network-manager (sec 10); 'input' bywa też dosypywany
# przez X11 — załóżmy je defensywnie, żeby useradd przeszedł od ręki
for g in netdev input; do getent group "$g" >/dev/null || groupadd -r "$g"; done

useradd -m -G sudo,audio,video,plugdev,netdev,input -s /bin/bash $USERNAME
passwd $USERNAME
```

---

## SEKCJA 8 — Jądro, firmware, sterowniki Dell Latitude 5421

Jeden meta-pakiet `**linux-firmware**` zamiast rozbitnych pakietów Debiana.

```bash
apt install -y \
    linux-generic linux-headers-generic \
    linux-firmware \
    intel-microcode \
    thermald fwupd \
    mesa-vulkan-drivers mesa-va-drivers \
    intel-media-va-driver vainfo \
    btrfs-progs cryptsetup cryptsetup-initramfs \
    dosfstools \
    grub-efi-amd64 efibootmgr os-prober \
    bash-completion lsb-release ca-certificates
```

---

## SEKCJA 9 — Initramfs (keyfile) + GRUB (LUKS)

### 9.1 Initramfs — osadzenie keyfile

```bash
echo 'KEYFILE_PATTERN="/etc/cryptsetup-keys.d/*.key"' >> /etc/cryptsetup-initramfs/conf-hook
echo 'UMASK=0077' >> /etc/initramfs-tools/initramfs.conf
```

### 9.2 GRUB z cryptodisk

`GRUB_DISABLE_OS_PROBER=true` — w chroocie z Live USB `os-prober` potrafi skanować pendrive i sypać błędami.

`quiet loglevel=3` — mniej szumu na konsoli (ACPI Della, watchdog przy reboot).

`i915.enable_psr=0 i915.enable_fbc=0 i915.enable_dc=0` — **krytyczne dla Tiger Lake na Latitude 5421**: domyślny PSR/FBC/DC w sterowniku `i915` powoduje **martwy ekran + brak reakcji klawiatury** w okolicach przełączania trybu wyświetlania (typowo: koniec boota, przejście z konsoli na SDDM/KMS). Bez tych trzech parametrów boot wisi tuż przed loginem.

```bash
cat > /etc/default/grub <<'EOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT=3
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Ubuntu`
GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 i915.enable_psr=0 i915.enable_fbc=0 i915.enable_dc=0"
GRUB_CMDLINE_LINUX=""
GRUB_ENABLE_CRYPTODISK=y
GRUB_DISABLE_OS_PROBER=true
GRUB_GFXMODE=auto
GRUB_GFXPAYLOAD_LINUX=keep
GRUB_TERMINAL_OUTPUT=console
EOF

grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck \
    --no-uefi-secure-boot \
    --modules="part_gpt cryptodisk luks2 argon2 pbkdf2 gcry_rijndael gcry_sha512 btrfs"

# Weryfikacja — argon2 MUSI być w embedded binarce, inaczej LUKS-2 z argon2id nie odblokuje
grep -aoE 'argon2|luks2|cryptodisk|pbkdf2|btrfs' /boot/efi/EFI/ubuntu/grubx64.efi | sort -u
```

> `resume=` / `resume_offset=` dodamy w sekcji 13.

> **Krytyczne — `--no-uefi-secure-boot`.** Bez tego flag-a `grub-install` na Ubuntu cichcem podstawi **podpisany przez Canonical `grubx64.efi`** (z `grub-efi-amd64-signed`), który **nie ma w środku modułu `argon2`** (Canonical go nie podpisuje, zob. [LP #2141233](https://bugs.launchpad.net/ubuntu/+source/grub2-signed/+bug/2141233)). Skutek: GRUB ładuje banner, próbuje `cryptomount` przeciwko slotowi argon2id z naszej SEKCJI 2 — i wiesza się bez prompta, bo nie umie wyliczyć KDF. Weryfikacja z `grep -aoE` musi pokazać **pięć** linii (`argon2 btrfs cryptodisk luks2 pbkdf2`); jeśli `argon2` brak — usuń `grub-efi-amd64-signed`+`shim-signed` i powtórz `grub-install`. Plik `grubx64.efi` zbudowany lokalnie ma ~300–500 KB; signed Canonical ~2.7 MB.

### 9.3 Pierwsze wygenerowanie

```bash
update-initramfs -u -k all
update-grub
```

> **Krytyczna asercja — nie pomijaj.** `update-initramfs` musi pobiec **po** instalacji `cryptsetup-initramfs` (sec 8) i **po** wpisaniu `KEYFILE_PATTERN` (9.1). Bez tego `/boot/initrd.img-*` nie zawiera ani binarki `cryptsetup`, ani `crypttab`, ani `cryptroot.key` → GRUB pokaże menu, ale kernel po starcie nie odblokuje rootfs i wejdziesz w kernel panic / czarny ekran. Weryfikacja:
>
> ```bash
> lsinitramfs /boot/initrd.img-$(uname -r 2>/dev/null || ls /boot | grep ^vmlinuz | head -1 | sed 's/vmlinuz-//') \
>   | grep -E 'sbin/cryptsetup$|cryptroot\.key|conf/conf\.d/cryptroot'
> ```
>
> Powinieneś zobaczyć **trzy trafienia**. Pustka = wracaj do `apt install -y cryptsetup-initramfs && update-initramfs -u -k all && update-grub`.

---

## SEKCJA 10 — Sieć (NetworkManager + netplan) + SSH + UFW

### 10.1 NetworkManager przez netplan

```bash
apt install -y network-manager netplan.io

mkdir -p /etc/netplan
cat > /etc/netplan/01-networkmanager.yaml <<'EOF'
network:
  version: 2
  renderer: NetworkManager
EOF
chmod 600 /etc/netplan/01-networkmanager.yaml

# Jeśli debootstrap dorzucił domyślny netplan (np. cloud-init), niech wygrywa NM:
rm -f /etc/netplan/50-cloud-init.yaml 2>/dev/null

systemctl disable systemd-networkd.service systemd-networkd.socket 2>/dev/null || true
systemctl enable NetworkManager
```

### 10.2 SSH + UFW

```bash
apt install -y openssh-server ufw

cat > /etc/ssh/sshd_config.d/99-hardening.conf <<EOF
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
KbdInteractiveAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
AllowUsers $USERNAME@$SSH_FROM
EOF

ufw default deny incoming
ufw default allow outgoing
ufw allow from $SSH_FROM to any port 22 proto tcp comment 'SSH only from installer IP'
sed -i 's/^ENABLED=.*/ENABLED=yes/' /etc/ufw/ufw.conf

systemctl enable ssh
systemctl enable ufw
```

> **Po pierwszym boocie** uruchom `sudo ufw enable` **lokalnie** (sekcja 17.0).

---

## SEKCJA 11 — KDE Plasma 6 minimalny (Wayland)

```bash
apt install -y --no-install-recommends \
    sddm sddm-theme-breeze \
    plasma-desktop \
    plasma-workspace \
    kwin-wayland \
    konsole \
    systemsettings \
    kinfocenter \
    plasma-nm \
    plasma-pa \
    powerdevil power-profiles-daemon \
    bluedevil bluez \
    kscreen kde-config-screenlocker \
    kde-cli-tools \
    polkit-kde-agent-1 \
    libpam-kwallet5 \
    dolphin \
    kde-spectacle \
    breeze breeze-icon-theme \
    qt6-wayland \
    xdg-desktop-portal-kde xdg-user-dirs \
    pipewire pipewire-pulse pipewire-audio wireplumber libspa-0.2-bluetooth \
    fonts-noto

systemctl enable sddm
systemctl enable bluetooth
systemctl enable power-profiles-daemon
systemctl enable thermald

# KRYTYCZNE — debootstrap zostawia default.target wskazujący na multi-user.target
# (lub w ogóle bez wpisu). Bez tego SDDM jest enabled, ale 'graphical.target'
# nigdy nie zostaje osiągnięty → ekran logowania KDE się nie pokazuje.
systemctl set-default graphical.target
```

### 11.1 Wymuś Wayland w SDDM

```bash
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/10-wayland.conf <<'EOF'
[General]
DisplayServer=wayland

[Wayland]
SessionDir=/usr/share/wayland-sessions
EOF
```

---

## SEKCJA 12 — Narzędzia: neovim, btop, fastfetch, curl, wget, git

```bash
apt install -y neovim btop fastfetch curl wget git

apt purge -y 'vim*' 2>/dev/null
apt autoremove --purge -y

update-alternatives --install /usr/bin/editor editor /usr/bin/nvim 100
update-alternatives --set editor /usr/bin/nvim

cat >> /home/$USERNAME/.bashrc <<'EOF'

# === Custom ===
export EDITOR=nvim
export VISUAL=nvim
alias vi='nvim'
alias vim='nvim'
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias ..='cd ..'
alias ...='cd ../..'

command -v fastfetch >/dev/null && fastfetch
EOF
chown $USERNAME:$USERNAME /home/$USERNAME/.bashrc

cat >> /root/.bashrc <<'EOF'
export EDITOR=nvim
alias vi='nvim'
alias vim='nvim'
alias ll='ls -lah --color=auto'
EOF
```

---

## SEKCJA 13 — Hibernacja (swapfile BTRFS + resume_offset)

### 13.1 Swapfile

```bash
btrfs filesystem mkswapfile --size ${SWAP_GB}g --uuid clear /swap/swapfile
chmod 600 /swap/swapfile

swapon /swap/swapfile
swapon --show
free -h
```

### 13.2 resume_offset

```bash
export RESUME_OFFSET=$(btrfs inspect-internal map-swapfile -r /swap/swapfile)
export RESUME_UUID=$(findmnt -no UUID -T /swap/swapfile)

echo "resume        = UUID=$RESUME_UUID"
echo "resume_offset = $RESUME_OFFSET"
```

### 13.3 GRUB + initramfs

```bash
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"resume=UUID=$RESUME_UUID resume_offset=$RESUME_OFFSET hibernate.compressor=lz4\"|" /etc/default/grub

grep GRUB_CMDLINE_LINUX /etc/default/grub

echo "RESUME=UUID=$RESUME_UUID" > /etc/initramfs-tools/conf.d/resume

update-initramfs -u -k all
update-grub
```

### 13.4 Polkit — hibernacja bez hasła roota

> Sprawdź po utworzeniu: `grep subject.user /etc/polkit-1/rules.d/10-hibernate.rules` — ma być Twój login.

```bash
mkdir -p /etc/polkit-1/rules.d
cat > /etc/polkit-1/rules.d/10-hibernate.rules <<EOF
polkit.addRule(function(action, subject) {
    if ((action.id == "org.freedesktop.login1.hibernate" ||
         action.id == "org.freedesktop.login1.hibernate-multiple-sessions" ||
         action.id == "org.freedesktop.login1.handle-hibernate-key" ||
         action.id == "org.freedesktop.upower.hibernate") &&
        subject.user == "$USERNAME") {
        return polkit.Result.YES;
    }
});
EOF
```

---

## SEKCJA 14 — Snapper

```bash
apt install -y snapper inotify-tools make git
```

> W chroocie: `**snapper --no-dbus**` (brak `snapperd`/D-Bus).

### 14.2–14.4 Konfiguracja

```bash
snapper --no-dbus -c root create-config /
chmod 750 /.snapshots

snapper --no-dbus -c root set-config ALLOW_USERS="$USERNAME"
snapper --no-dbus -c root set-config SYNC_ACL=yes
snapper --no-dbus -c root set-config "TIMELINE_CREATE=yes"
snapper --no-dbus -c root set-config "TIMELINE_CLEANUP=yes"
snapper --no-dbus -c root set-config "TIMELINE_LIMIT_HOURLY=5"
snapper --no-dbus -c root set-config "TIMELINE_LIMIT_DAILY=7"
snapper --no-dbus -c root set-config "TIMELINE_LIMIT_WEEKLY=4"
snapper --no-dbus -c root set-config "TIMELINE_LIMIT_MONTHLY=2"
snapper --no-dbus -c root set-config "TIMELINE_LIMIT_YEARLY=0"
snapper --no-dbus -c root set-config "NUMBER_LIMIT=20"

snapper --no-dbus -c home create-config /home
snapper --no-dbus -c home set-config ALLOW_USERS="$USERNAME"
snapper --no-dbus -c home set-config SYNC_ACL=yes
snapper --no-dbus -c home set-config "TIMELINE_LIMIT_HOURLY=2"
snapper --no-dbus -c home set-config "TIMELINE_LIMIT_DAILY=7"
snapper --no-dbus -c home set-config "TIMELINE_LIMIT_WEEKLY=2"
snapper --no-dbus -c home set-config "TIMELINE_LIMIT_MONTHLY=0"
snapper --no-dbus -c home set-config "NUMBER_LIMIT=15"

snapper --no-dbus list-configs
```

### 14.5 Snapshoty pre/post przy `apt`

```bash
cat > /etc/apt/apt.conf.d/80snapper <<'EOF'
DPkg::Pre-Invoke {"if [ -x /usr/bin/snapper ] && [ -d /.snapshots ]; then /usr/bin/snapper --no-dbus create -d 'apt pre' -t pre -p > /tmp/snapper_pre_apt 2>/dev/null || true; fi";};
DPkg::Post-Invoke {"if [ -x /usr/bin/snapper ] && [ -d /.snapshots ] && [ -f /tmp/snapper_pre_apt ]; then PRE_NUM=$(cat /tmp/snapper_pre_apt); /usr/bin/snapper --no-dbus create -d 'apt post' -t post --pre-number $PRE_NUM > /dev/null 2>&1 || true; rm -f /tmp/snapper_pre_apt; fi";};
EOF

systemctl enable snapper-timeline.timer
systemctl enable snapper-cleanup.timer
```

---

## SEKCJA 15 — grub-btrfs

**Ubuntu nie pakuje `grub-btrfs` w żadnej suicie** (sprawdzone na [packages.ubuntu.com](https://packages.ubuntu.com/search?keywords=grub-btrfs&searchon=names&suite=all&section=all)) — `apt search grub-btrfs` zwraca pustkę. Instalujemy z [Antynea/grub-btrfs](https://github.com/Antynea/grub-btrfs) (git + make były już doinstalowane w SEKCJI 14).

```bash
cd /tmp
git clone https://github.com/Antynea/grub-btrfs.git
cd grub-btrfs

cat > config <<'EOF'
GRUB_BTRFS_GRUB_DIRNAME="/boot/grub"
GRUB_BTRFS_MKCONFIG=/usr/sbin/update-grub
GRUB_BTRFS_MKCONFIG_LIB=/usr/lib/grub/grub-mkconfig_lib
GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS="systemd.volatile=state"
EOF

make install
systemctl enable grub-btrfsd.service
update-grub
```

`make install` kopiuje skrypt `41_snapshots-btrfs` do `/etc/grub.d/`, `config` do `/etc/default/grub-btrfs/`, binarkę `grub-btrfsd` i unit systemd. Na koniec sam zawoła `grub-mkconfig` — `update-grub` powyżej jest dla pewności, że wpisy snapshotów Snappera trafiają do menu.

---

## SEKCJA 16 — Wyjście z chroot, restart

```bash
swapoff /swap/swapfile
exit
```

**Na hoście Live:**

```bash
sync
reboot
```

Wyjmij pendrive przy POST.

> Opcjonalnie ręcznie: `umount -R /mnt/dev ...`, `btrfs device scan --forget`, `cryptsetup close cryptroot` — często `Device busy`; `sync && reboot` jest niezawodniejsze.

---

## SEKCJA 17 — Pierwszy boot i weryfikacja

### 17.0 UFW — włącz lokalnie

**Lokalnie** na laptopie (nie przez SSH zanim UFW nie jest pewny):

```bash
sudo ufw enable
sudo ufw status verbose
```

### 17.1 Oczekiwany przebieg

1. GRUB + hasło LUKS
2. Initramfs + keyfile
3. NetworkManager (Ethernet)
4. SDDM → **Plasma (Wayland)**
5. PipeWire (17.2) jeśli brak dźwięku

### 17.2 PipeWire (jako użytkownik)

```bash
systemctl --user enable --now pipewire pipewire-pulse wireplumber
systemctl --user status pipewire wireplumber
```

### 17.3 SSH

Z `192.168.1.10`: `ssh $USERNAME@<IP>` — powinno wejść. Z innego IP — blokada.

### 17.4 Hibernacja

```bash
swapon --show
cat /sys/kernel/security/lockdown 2>/dev/null || true
mokutil --sb-state
systemctl hibernate
```

### 17.5 Weryfikacja resume / keyfile

```bash
sudo lsinitramfs /boot/initrd.img-$(uname -r) | grep cryptroot.key
sudo btrfs inspect-internal map-swapfile -r /swap/swapfile
cat /proc/cmdline | tr ' ' '\n' | grep resume
```

### 17.6 Snapper

```bash
sudo snapper -c root create -d "after install"
sudo snapper -c root list
```

### 17.7 Nested subwoluminy w `@home` (OPCJONALNE)

> Pomiń, jeśli nie planujesz `snapper -c home rollback` całego `/home`.

```bash
btrfs subvolume create ~/.mozilla
btrfs subvolume create ~/.thunderbird
btrfs subvolume create ~/.ssh
btrfs subvolume create ~/.var

sudo btrfs subvolume list / | grep "$USER"
```

#### `File exists` przy `btrfs subvolume create`

```bash
sudo btrfs subvolume show ~/.mozilla
```

- Już subwolumin → nic nie rób.  
- Zwykły katalog z danymi → migracja: `mv` → `btrfs subvolume create` → `cp -a` → `rm` backup.

### 17.8 Pokrywa → hibernacja (KDE)

**System Settings → Power Management → Energy Saving** — **When laptop lid closed** = **Hibernate**.

Lub:

```bash
kwriteconfig6 --file powermanagementprofilesrc --group AC --group HandleButtonEvents --key lidAction 4
kwriteconfig6 --file powermanagementprofilesrc --group Battery --group HandleButtonEvents --key lidAction 4
```

### 17.9 ssh-copy-id + wyłączenie hasła

Z `192.168.1.10`:

```bash
ssh-copy-id $USERNAME@<IP_LAPTOPA>
```

Na laptopie:

```bash
sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config.d/99-hardening.conf
sudo systemctl restart ssh
```

---

## Załącznik A — BIOS + przydatne komendy

**BIOS (F2):**

- Secure Boot: **Disabled** (hibernacja).  
- SATA/NVMe: **AHCI**, nie RAID Intel RST (dla instalacji na jednym dysku z LUKS).  
- Boot: UEFI, pendrive pierwszy tylko na czas instalacji.

**Po instalacji:**

```bash
sudo snapper -c root list
sudo btrfs filesystem usage /
sudo fwupdmgr refresh && sudo fwupdmgr get-updates
sudo ufw status verbose
```

---

## Załącznik B — Gdy coś pójdzie nie tak

### Boot nie wstaje

W GRUB: **Advanced options for Ubuntu** → **snapshots** / wpisy **grub-btrfs** → ostatni działający snapshot. Potem:

```bash
sudo snapper -c root list
sudo snapper -c root rollback <numer>
sudo reboot
```

### GRUB: `Invalid passphrase` / `Argon2 not supported`

1. Hasło nie-ASCII / zły layout w GRUB — zmień hasło (Live): `cryptsetup luksChangeKey /dev/nvme0n1p2`.
2. Brakuje modułu `argon2` w `grubx64.efi` — patrz **SEKCJA 11** (`--modules="... argon2 ..."` + `update-grub` + `grub-install`).
3. Recovery: konwersja slotu na argon2id albo z powrotem na pbkdf2 — patrz **Załącznik B** → „Migracja istniejącego slotu na Argon2id”.

### LUKS pyta dwa razy

```bash
sudo lsinitramfs /boot/initrd.img-$(uname -r) | grep cryptroot.key
sudo update-initramfs -u -k all
```

### Hibernacja: „Cannot find swap device”

```bash
cat /etc/initramfs-tools/conf.d/resume
sudo update-initramfs -u -k all
sudo btrfs inspect-internal map-swapfile -r /swap/swapfile
```

### Wi-Fi

```bash
sudo apt install --reinstall linux-firmware
sudo modprobe -r iwlwifi && sudo modprobe iwlwifi
journalctl -k | grep iwlwifi
```

### SDDM

```bash
sudo journalctl -u sddm -b
sudo chown -R sddm:sddm /var/lib/sddm
```

### Touchpad „nie działa” (KDE)

Zobacz [sysguides — BTRFS na Debianie](https://sysguides.com/install-debian-13-with-btrfs) jako ogólny wzorzec; na Ubuntu ten sam stack Plasma.

```bash
grep -i enabled ~/.config/kcminputrc
```

Dwa bloki `[Libinput][...]` (legacy) vs `[Libinput/.../...]` — legacy z `Enabled=false` wygrywa:

```bash
mv ~/.config/kcminputrc ~/.config/kcminputrc.bak
# wyloguj / zaloguj
```

### ACPI `\_TZ.ETMD` / watchdog przy reboot / `finalize remaining DM devices`

Szum na konsoli — już częściowo tłumiony przez `loglevel=3` w sekcji 9. Nieszkodliwe na Latitude.

### Nowszy kernel (HWE / OEM)

```bash
apt-cache policy linux-generic-hwe-26.04 linux-oem-26.04
sudo apt install linux-generic-hwe-26.04 linux-headers-generic-hwe-26.04
# lub Dell-focused:
# sudo apt install linux-oem-26.04 linux-headers-oem-26.04
sudo reboot
```

Backport z tego samego archiwum:

```bash
sudo apt install -t resolute-backports linux-generic linux-headers-generic
```

### Migracja istniejącego slotu na Argon2id

Jeśli LUKS2 został kiedyś sformatowany z PBKDF2 (stary przewodnik), slot można przekonwertować bez reinstalacji:

```bash
sudo cryptsetup luksConvertKey \
    --pbkdf argon2id --pbkdf-memory 524288 --pbkdf-parallel 4 --iter-time 2000 \
    /dev/nvme0n1p2

sudo cryptsetup luksConvertKey \
    --pbkdf argon2id --pbkdf-memory 524288 --pbkdf-parallel 4 --iter-time 800 \
    --key-file /etc/cryptsetup-keys.d/cryptroot.key \
    /dev/nvme0n1p2
```

Po tym **musisz mieć w GRUB moduł `argon2`** (SEKCJA 11). Sprawdź: `sudo cryptsetup luksDump /dev/nvme0n1p2 | grep PBKDF`.

---

## Załącznik C — Brave + Flatpak

```bash
# https://brave.com/linux/
sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
sudo curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources \
    https://brave-browser-apt-release.s3.brave.com/brave-browser.sources
sudo apt update
sudo apt install -y brave-browser

sudo apt install -y flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
```

---

**Koniec.** System: Ubuntu 26.04 LTS, LUKS2 + BTRFS + Snapper + grub-btrfs, hibernacja, SSH z jednego IP, KDE Plasma 6 (Wayland), bez snapd.