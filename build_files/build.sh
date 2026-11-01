#!/usr/bin/env bash
set -euo pipefail

# Preset 2 targets CPU time and available RAM, not unused files on disk.
# Keep the upstream kernel, Mesa (including i686), PipeWire and KDE booster.
[[ $(uname -m) == x86_64 ]] || { echo 'Minzite targets x86_64 AMD desktops.' >&2; exit 1; }

# Remove the Flatpak storefront, not shared libraries needed by desktop portals.
# Do not autoremove unrelated dependencies or inactive optional applications.
remove=()
for package in bazaar krunner-bazaar krunner-yafti flatpak-kcm; do
    if rpm -q "$package" >/dev/null 2>&1; then remove+=("$package"); fi
done
if ((${#remove[@]})); then
    dnf5 -y --setopt=clean_requirements_on_remove=False remove "${remove[@]}"
fi

dnf5 -y --setopt=install_weak_deps=False install \
    firefox gwenview okular kcalc haruna filelight kde-partitionmanager \
    plasma-systemmonitor protontricks

# Install configuration after RPM transactions so package defaults cannot win.
cp -a /ctx/system_files/. /
# Replace the on-demand Flatpak monitor installer with the native KDE monitor.
ln -sf /usr/bin/plasma-systemmonitor /usr/bin/missioncenter-helper

# Start Steam on demand. Leave its launcher and shader settings unchanged.
rm -f /etc/skel/.config/autostart/steam.desktop

# Opt-in features stay installed but cannot start through socket/D-Bus activation.
# Bluetooth, networking, firmware updates, audio and hardware fixes stay available.
for unit in \
    bazzite-flatpak-manager.service ublue-flatpak-manager.service \
    flatpak-add-fedora-repos.service brew-setup.service \
    input-remapper.service waydroid-container.service tailscaled.service \
    cockpit.socket cockpit.service cups.service cups.socket cups.path \
    cups-browsed.service ModemManager.service \
    auditd.service scx_loader.service; do
    systemctl mask "$unit"
done
# Container engines need not listen at every login. CLI Podman remains usable.
systemctl mask podman.socket
systemctl --global mask podman.socket

# Fail rather than accidentally shipping a damaged desktop after package removal.
rpm -q steam kwin plasma-desktop xdg-desktop-portal-kde \
    mesa-vulkan-drivers pipewire tuned-ppd protontricks

dnf5 clean all
