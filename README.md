# Minzite Deck

A PC gaming and development image based on `ghcr.io/ublue-os/bazzite-deck:stable`,
with Steam Gaming Mode on first boot and KDE Wayland in Desktop Mode.

- **Development:** Microsoft VS Code, Docker CE (Compose/Buildx, socket activated),
  Fedora-packaged Node.js 24 with its matching npm, native PostgreSQL server/client and mongosh.
- **Native apps:** Zoom, Heroic Games Launcher, OBS Studio and Discord. Minzite
  does not add Brave, Postman, Compass or an extra desktop/terminal package bundle;
  packages already supplied by Bazzite Deck remain.
- **App store:** Native Bazaar and Flatpak remain; Discover and bundled browsers
  are excluded. Fresh installs have no Flatpak apps. Connect to the internet, open
  Bazaar, enable Flathub if prompted, and choose a browser or other apps yourself.
- **Performance defaults:** `mitigations=off selinux=0 audit=0 zswap.enabled=0`,
  `kernel.split_lock_mitigate=0` via sysctl, Baloo indexing off and the root boot
  argument `rootflags=noatime`. Other services and sysctl settings
  follow upstream. Upstream kernel, Mesa, zram, controllers and SteamOS helpers stay.
- **Memory under load:** Performance mode extends Bazzite's profile while keeping
  Deck's swappiness 180 and dirty-write limits (256 MiB / 128 MiB background).
  Balanced remains the default; upstream CPU settings and scheduler hooks stay.
- **Optional CPU scheduler:** `scx_loader` is disabled at boot, with `scx_bpfland`
  in Auto mode if started manually or through Gaming Mode. Existing user-edited
  scheduler configuration may override this default.
- **Minimal background work:** Flatpak CLI remains for manual use; automatic
  Flatpak/Homebrew setup and updates are off. Topgrade updates only OS/firmware.
  Portal retains upstream screens but omits actions for removed Btrfs tools. Bees,
  Snapper, Btrfs Assistant, compsize and Btrfs maintenance are removed, with
  snapshot/deduplication timers masked; basic Btrfs support remains.

## Installation and updates

Pushes to `deck` and daily builds publish signed images using `SIGNING_SECRET`
(empty passphrase), matching `cosign.pub`. Renovate tracks Heroic's tag/checksum;
Bazzite Deck follows `stable`. ISO builds verify and pin the source container
digest, then sign and verify `SHA256SUMS` and check the ISO against it before upload.

After the container build succeeds, run **Build installer ISO** on `deck`. Extract
`minzite-deck-iso-amd64` for the ISO, signature bundle, SHA256 checksum and public key.
Boot in **UEFI mode** and select only the intended installation disk. Automatic
partitioning uses the upstream-style layout: EFI, a separate `/boot`, and Btrfs
root/home subvolumes. Disk selection and space reclamation remain interactive;
Minzite does not preselect disks or request unconditional wiping. No disk swap is
requested; zram remains. Review the selected disks and storage changes before
starting installation.

Custom partitioning remains available. Minzite retains ext4 tools and the upstream
kernel, and adds no Btrfs-only root mount options. For an experimental ext4 root
installation, retain a separate ext4 `/boot` and EFI partition; do not reuse
Btrfs-specific mount options such as `subvol=` or `compress=`. **Manual ext4
installation and boot have not been validated**; changing the default does not
establish that every custom layout works.

The user has confirmed a successful installation and boot on the automatic Btrfs
layout, including booting a Minzite update. Mode switching, rollback and Secure
Boot still need verification. OS rollback uses retained deployments, independently
of Snapper/Btrfs; it does not restore personal files or shared `/var` data.
Rebase existing Bazzite-Deck installs with
`sudo bootc switch ghcr.io/swapnanil1/minzite:latest`; this preserves their partitions.
Existing user-installed Flatpak apps are preserved when updating or rebasing;
the empty Flatpak app selection applies to fresh installs.

## Local databases

PostgreSQL is installed but stays off at boot. Initialize it once after installation,
then start it when needed:

```bash
sudo postgresql-setup --initdb
sudo systemctl start postgresql
sudo -u postgres psql
```

Data persists in `/var/lib/pgsql`; PostgreSQL major upgrades require a database
migration, independently of OS rollback. Mongosh is a client for your MongoDB
deployment; no MongoDB server is included. Its latest stable x86_64 RPM is refreshed
on image builds, with SHA-256 and MongoDB's RPM signature checked before install.

Discord uses the official stable RPM. Its launcher downloads the client into your
user configuration directory on first launch and updates it independently of the OS.

## Verify the downloaded ISO

Use a trusted copy of `cosign.pub` from this repository:

```bash
cosign verify-blob --key cosign.pub --bundle SHA256SUMS.sigstore.json SHA256SUMS
sha256sum --check SHA256SUMS
```

Only amd64 container and KDE installer ISO builds are supported. The container
workflow uses Ubuntu 26.04 x86; the ISO workflow retains Ubuntu 24.04 x86 from
the earlier runner compatibility fix. No ARM, QCOW2, RAW, VM or S3 builds are provided.
