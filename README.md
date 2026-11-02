# Minzite Deck

A PC gaming and development image based on `ghcr.io/ublue-os/bazzite-deck:stable`,
with Steam Gaming Mode on first boot and KDE Wayland in Desktop Mode.

- **Development:** Microsoft VS Code, Docker CE (Compose/Buildx, socket activated),
  latest stable Node.js with latest npm, Git/Git LFS/GitHub CLI, GCC/G++, Make,
  CMake, Python, native PostgreSQL server/client, mongosh and MongoDB Compass.
- **Desktop apps:** Brave, Firefox, Postman, Zoom, Heroic, OBS Studio,
  Protontricks, Gwenview, Okular, Haruna, Filelight, KCalc, KDE Partition Manager
  and native Plasma System Monitor.
- **Medium preset:** `mitigations=off selinux=0 audit=0 zswap.enabled=0`, Baloo
  indexing off, `vm.page-cluster=0`, ext4 with `noatime`, and optional services
  masked. Upstream kernel, Mesa, zram, controllers and shared SteamOS helpers stay.
- **Minimal background work:** Flatpak CLI remains for manual use; automatic
  Flatpak/Homebrew setup and updates are off. Topgrade updates only OS/firmware.
  Portal omits app-installation prompts and actions for removed tools. Bees,
  Snapper, Btrfs Assistant, compsize and Btrfs maintenance are removed, with
  snapshot/deduplication timers masked; basic Btrfs support remains.

## Installation and updates

Pushes to `deck` and daily builds publish signed images using `SIGNING_SECRET`
(empty passphrase), matching `cosign.pub`. Renovate tracks Heroic's tag/checksum;
Bazzite Deck follows `stable`. ISO builds verify and pin the source container
digest, then sign and verify the ISO itself before upload.

After the container build succeeds, run **Build installer ISO** on `deck`. Extract
`minzite-deck-iso-amd64` for the ISO, signature bundle, SHA256 checksum and public key.
Boot in **UEFI mode**, select only the target SSD, and reclaim its old partitions
interactively for a two-partition install: **1 GiB EFI/FAT32 at `/boot/efi` +
remaining space as ext4 `/` (minimum 20 GiB)**. No separate `/boot`, `/home` or disk
swap is requested; zram remains. Encryption needs a different layout.

[OSTree supports `/boot` on root](https://ostreedev.github.io/ostree/atomic-upgrades/#the-bootostree-directory).
OS rollback uses retained deployments, independently of Snapper/Btrfs; it does
not restore personal files or shared `/var` data. **The custom ISO layout has not
been installation-tested**; verify boot, mode switching, updates and rollback.
Rebase existing Bazzite-Deck installs with
`sudo bootc switch ghcr.io/swapnanil1/minzite:latest`; this preserves their partitions.

## Local databases

PostgreSQL is installed but stays off at boot. Initialize it once after installation,
then start it when needed:

```bash
sudo postgresql-setup --initdb
sudo systemctl start postgresql
sudo -u postgres psql
```

Data persists in `/var/lib/pgsql`; PostgreSQL major upgrades require a database
migration, independently of OS rollback. Mongosh and Compass are clients for your
MongoDB deployment. Their latest stable x86_64 RPMs are refreshed on image builds,
with SHA-256 and MongoDB's product-specific RPM signatures checked before install.

## Verify the downloaded ISO

Use a trusted copy of `cosign.pub` from this repository:

```bash
cosign verify-blob --key cosign.pub --bundle minzite-deck-amd64.iso.sigstore.json minzite-deck-amd64.iso
sha256sum --check SHA256SUMS
```

Only amd64 container and KDE installer ISO builds are supported. The container
workflow uses Ubuntu 26.04 x86; the ISO workflow retains Ubuntu 24.04 x86 from
the earlier runner compatibility fix. No ARM, QCOW2, RAW, VM or S3 builds are provided.
