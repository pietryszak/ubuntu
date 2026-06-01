# Kubuntu 26.04 LTS — szyfrowany Btrfs + snapshoty + hibernacja (NVIDIA), sterowane przez SSH

Kompletny zestaw instrukcji i skryptów do postawienia **Kubuntu 26.04 LTS** z:

- pełnym szyfrowaniem roota (**LUKS2 / Btrfs**), `/boot` na osobnej partycji ext4,
- **automatycznym odblokowaniem przez TPM2** (start bez hasła),
- **hibernacją** (swapfile = RAM + bufor) działającą z kartą **NVIDIA (RTX 4070 Ti)**,
- **snapshotami i rollbackiem** (Snapper + grub-btrfs + Btrfs Assistant + hook `apt`),
- układem subwolumenów wg dobrych praktyk (wzorzec openSUSE),
- całością wykonywaną **przez SSH** z drugiego komputera w tej samej sieci.

To jest adaptacja przewodnika SysGuides dla Fedory 44 na realia Ubuntu/Kubuntu.

---

## Dlaczego taki wariant (a nie szyfrowany `/boot` jak w Fedorze)

Na Ubuntu **GRUB nie potrafi używać TPM2**, a podpisany GRUB nie zawiera modułów `luks2`/`cryptodisk`. Gdyby `/boot` był szyfrowany, hasło LUKS trzeba by podawać przy każdym starcie (TPM2 by nie pomógł na etapie GRUB). Dlatego:

- `/boot` jest **nieszyfrowany (ext4)** — dzięki temu szyfrowany root odblokowuje **TPM2 w initramfs** → start i wybudzenie z hibernacji **bez hasła**;
- **Secure Boot wyłączony** — upraszcza sterowniki NVIDIA (brak fizycznego MOK enrollment, więc instalacja NVIDII też idzie zdalnie);
- Kubuntu 26.04 używa **dracut** (jak Fedora), więc TPM2/initramfs konfiguruje się niemal identycznie.

Kompromis: jądro i initramfs w `/boot` nie są szyfrowane ani objęte rollbackiem snapshotów.

---

## Układ dysku

| Partycja | Rozmiar | FS | Montowanie | Szyfrowanie |
|---|---|---|---|---|
| p1 | 1 GiB | FAT32 (flaga `esp`) | `/boot/efi` | nie |
| p2 | 2 GiB | ext4 | `/boot` | nie |
| p3 | reszta | **Btrfs** | `/` | **LUKS2** |

## Subwolumeny Btrfs (wewnątrz LUKS2)

| Subwolumen | Montowanie | Rola |
|---|---|---|
| `@` | `/` | system (snapshotowany i cofany) |
| `@home` | `/home` | dane użytkownika |
| `@root` | `/root` | katalog domowy root |
| `@opt` | `/opt` | software spoza repo |
| `@srv` | `/srv` | dane serwisów |
| `@usr_local` | `/usr/local` | ręcznie instalowane programy |
| `@var_log` | `/var/log` | logi (zostają po rollbacku) |
| `@var_cache` | `/var/cache` | cache (wykluczone) |
| `@var_tmp` | `/var/tmp` | tymczasowe (tu NVIDIA zrzuca VRAM) |
| `@var_spool` | `/var/spool` | kolejki cron/mail |
| `@var_lib_snapd` | `/var/lib/snapd` | Snap (opcjonalnie) |
| `@swap` | `/swap` | swapfile do hibernacji, RAM + bufor (NOCOW, bez kompresji) |
| `@snapshots` | `/.snapshots` | tworzony przez Snapper |

Zasada: w `@` zostaje to, co ma się cofać razem z systemem (m.in. baza pakietów `/var/lib/dpkg`), a dane zmienne/duże/diagnostyczne są poza snapshotami.

---

## Wymagania

- Komputer docelowy + pendrive z **Kubuntu 26.04 LTS** (tryb UEFI).
- Drugi komputer (laptop) w tej samej sieci LAN — z niego sterujesz przez SSH.
- Dostęp do BIOS/UEFI (Secure Boot, kolejność bootowania).
- 64 GiB RAM → `SWAP_SIZE=96g` (best practice dla hibernacji: RHEL 1.5×RAM; dostosuj w `config.sh`).

> ⚠️ Cały dysk docelowy zostanie wymazany. Trzymaj hasło LUKS w bezpiecznym miejscu — TPM2 to wygoda, a nie jedyny klucz.

---

## Legenda kroków

- **[PC]** — fizycznie na komputerze docelowym.
- **[SSH→live]** — z laptopa przez SSH do środowiska live.
- **[SSH→system]** — z laptopa przez SSH do zainstalowanego systemu.

---

## Przebieg

### Etap 0 — [PC] Boot live + SSH

1. W BIOS: **wyłącz Secure Boot**, ustaw boot z USB (UEFI). Uruchom live Kubuntu.
2. Upewnij się, że jest sieć (Ethernet sam; Wi-Fi połącz w GUI).
3. Skopiuj ten katalog na maszynę albo uruchom `00-live-ssh.sh` (włącza SSH, ustawia hasło live, pokazuje IP).

```bash
# w live, na PC:
sudo bash 00-live-ssh.sh
```

Z laptopa połącz się: `ssh <user_live>@<ip_live>`.

### Etap 1 — [PC] Instalacja bazy (Calamares)

Tej części nie da się zeskryptować (GUI). W instalatorze wybierz **ręczne partycjonowanie** i utwórz układ z tabeli „Układ dysku" (EFI, ext4 `/boot`, oraz partycję `/` jako **btrfs z zaznaczonym szyfrowaniem LUKS**). Utwórz użytkownika i **hasło** (do SSH po restarcie).

Po instalacji wybierz **„Wyjdź do live"** — **nie restartuj**.

### Etap 2 — [SSH→live] Subwolumeny + SSH do docelowego systemu

Skopiuj skrypty do live i uruchom `01-subvolumes.sh` (reorganizuje subwolumeny offline i doinstalowuje `openssh-server` do docelowego systemu przez chroot):

```bash
# z laptopa:
scp -r ~/Code/Ubuntu <user_live>@<ip_live>:/tmp/ubuntu-setup
ssh <user_live>@<ip_live>
cd /tmp/ubuntu-setup
nano config.sh                 # ustaw DISK / partycje / SWAP_SIZE
sudo bash 01-subvolumes.sh
```

Po zakończeniu: **[PC]** wyjmij USB i `sudo systemctl reboot`. Przy starcie podaj raz hasło LUKS (TPM2 dodamy w Etapie 3).

### Etap 3 — [SSH→system] Konfiguracja docelowa

Skopiuj skrypty do zainstalowanego systemu i uruchom po kolei:

```bash
# z laptopa:
scp -r ~/Code/Ubuntu <twoj_user>@<ip>:~/ubuntu-setup      # lub ssh <twoj_user>@<host>.local
ssh <twoj_user>@<ip>
cd ~/ubuntu-setup
sudo bash 02-tpm2.sh             # TPM2 auto-unlock (poda hasło LUKS)
sudo bash 03-swap-hibernate.sh   # swap + hibernacja
sudo bash 04-nvidia.sh           # sterownik NVIDIA + hibernacja
sudo bash 05-snapper-grub-btrfs.sh
sudo bash 07-hardening.sh        # (opcjonalnie) SSH + UFW ograniczone do SSH_FROM
sudo bash 08-brave.sh            # (opcjonalnie) Brave + Flatpak/Flathub
sudo reboot
```

> `07-hardening.sh` ogranicza SSH do adresu `SSH_FROM` z `config.sh` (ustaw `any`, by nie ograniczać). Skrypt najpierw dodaje regułę UFW, dopiero potem włącza zaporę — nie odetnie Ci sesji.

Po restarcie (przez SSH) — jako Twój użytkownik, **bez sudo**, po pierwszym zalogowaniu do sesji graficznej i z zamkniętymi przeglądarkami:

```bash
bash 06-user-subvolumes.sh       # wyklucza ~/.cache, ~/snap, ~/.var/app, Trash ze snapshotów @home
```

Weryfikacja:

```bash
bash 99-verify.sh
```

---

## Kolejność skryptów (skrót)

| Skrypt | Gdzie | Jako | Po co |
|---|---|---|---|
| `00-live-ssh.sh` | [PC] live | sudo | włącz SSH w live |
| `01-subvolumes.sh` | [SSH→live] | sudo | subwolumeny + openssh do targetu |
| `02-tpm2.sh` | [SSH→system] | sudo | TPM2 auto-unlock |
| `03-swap-hibernate.sh` | [SSH→system] | sudo | swap + hibernacja |
| `04-nvidia.sh` | [SSH→system] | sudo | NVIDIA + hibernacja |
| `05-snapper-grub-btrfs.sh` | [SSH→system] | sudo | snapshoty + rollback + strojenie Snappera |
| `06-user-subvolumes.sh` | [SSH→system] | użytkownik | wykluczenia per-user |
| `07-hardening.sh` | [SSH→system] | sudo | SSH + UFW (opcjonalnie) |
| `08-brave.sh` | [SSH→system] | sudo | Brave + Flatpak (opcjonalnie) |
| `99-verify.sh` | [SSH→system] | sudo | szybka weryfikacja |

Wszystkie współdzielą `config.sh` (edytuj go raz): `DISK`/partycje, `SWAP_SIZE`, `USERNAME`, `SSH_FROM`.

---

## Rollback (cofanie zmian)

- Z menu **GRUB** → „Btrfs snapshots" wybierz snapshot, żeby go obejrzeć (tryko-do-odczytu; jądro bieżące z `/boot`).
- Graficznie: **Btrfs Assistant** (uruchom jako root) → przywróć snapshot.
- Z terminala: `sudo snapper -c root list`, a następnie przywrócenie wg dokumentacji Snappera.

Snapshoty pre/post tworzą się automatycznie przy `apt` (hook `80snapper`).

---

## Uwagi

- **Brave / Brave Origin**: instaluj z oficjalnego repo (`08-brave.sh`). Dane trafiają do `/home` (objęte `@home`); cache wykluczasz przez subwolumen `~/.cache` (`06-user-subvolumes.sh`). Profile (`~/.config/...`) zostają w snapshotach. Po instalacji zweryfikuj nazwy: `ls ~/.config`, `ls ~/.cache`. Dla osobnego produktu „Brave Origin" sprawdź pakiet: `apt-cache search brave`.
- **`USERNAME` w `config.sh`** musi odpowiadać loginowi utworzonemu w Calamares — używają go reguła hibernacji (polkit), strojenie Snappera (`ALLOW_USERS`) i hardening SSH.
- **TPM2 PCR 7** = stan Secure Boot. Po zmianie Secure Boot/firmware odblokowanie TPM2 wymaga ponownego zapisu klucza (podasz wtedy hasło LUKS i uruchomisz `02-tpm2.sh` ponownie).
- **Snapshot ≠ backup**: leżą na tym samym dysku. Awaria dysku = utrata wszystkiego. Backup `/home` poza dyskiem dorzuć osobno (opcjonalnie).
- Skrypty zakładają domyślny układ Calamares: subwolumeny `@` i `@home`. Zweryfikuj `ls /mnt` w Etapie 2.
