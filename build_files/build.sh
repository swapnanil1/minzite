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
    plasma-systemmonitor protontricks obs-studio \
    git git-lfs gh openssh-clients gcc gcc-c++ make cmake pkgconf-pkg-config python3 \
    curl wget jq ripgrep fd-find unzip zip tar xz rsync lsof bind-utils openssl

# Vendor RPM repositories: Microsoft VS Code, Docker CE and Brave stable.
cat >/etc/yum.repos.d/vscode.repo <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
dnf5 config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
dnf5 config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
dnf5 -y --setopt=install_weak_deps=False install \
    code brave-browser docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

# Latest native Zoom Meetings/Workplace RPM, verified against Zoom's signing key.
rpm --import https://zoom.us/linux/download/pubkey
dnf5 -y --setopt=localpkg_gpgcheck=True --setopt=install_weak_deps=False install \
    https://zoom.us/client/latest/zoom_x86_64.rpm

# Renovate updates the release tag and matching RPM digest together.
heroic_version=v2.22.4
heroic_sha256=c346ce64b5f29a53367c8fd701d061b9a3a83a7b5d53135a31a81147a36951e4
curl -fLsS --retry 3 -o /tmp/heroic.rpm \
    "https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/releases/download/${heroic_version}/Heroic-${heroic_version#v}-linux-x86_64.rpm"
echo "${heroic_sha256}  /tmp/heroic.rpm" | sha256sum --check --status
dnf5 -y --setopt=install_weak_deps=False install /tmp/heroic.rpm

# Latest stable Node release, regardless of LTS status. Never select an alpha/RC.
node_version=$(curl -fLsS --retry 3 https://nodejs.org/dist/index.json |
    jq -er '[.[] | select(.version | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))] |
        max_by(.version | ltrimstr("v") | split(".") | map(tonumber)) | .version')
node_archive="node-${node_version}-linux-x64.tar.xz"
curl -fLsS --retry 3 -o "/tmp/${node_archive}" "https://nodejs.org/dist/${node_version}/${node_archive}"
curl -fLsS --retry 3 "https://nodejs.org/dist/${node_version}/SHASUMS256.txt" |
    awk -v archive="$node_archive" '$2 == archive {print $1 "  /tmp/" $2}' |
    sha256sum --check --status
mkdir -p /usr/lib/nodejs-current
tar -xJf "/tmp/${node_archive}" --strip-components=1 -C /usr/lib/nodejs-current
for command in node npm npx; do
    ln -sf "/usr/lib/nodejs-current/bin/${command}" "/usr/bin/${command}"
done
NPM_CONFIG_CACHE=/tmp/npm-cache npm install --global --prefix /usr/lib/nodejs-current \
    --engine-strict --no-audit --no-fund npm@latest
node --version
npm --version

# Official native Postman bundle. /usr/lib is updated with the OS image.
curl -fLsS --retry 3 -o /tmp/postman.tar.gz https://dl.pstmn.io/download/latest/linux_64
mkdir -p /usr/lib/postman
tar -xzf /tmp/postman.tar.gz --strip-components=1 -C /usr/lib/postman
test -x /usr/lib/postman/app/Postman
ln -sf /usr/lib/postman/app/Postman /usr/bin/postman
rm -f /tmp/heroic.rpm "/tmp/${node_archive}" /tmp/postman.tar.gz
rm -rf /tmp/npm-cache

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
# Start Docker on demand; do not start containers at every boot.
systemctl disable docker.service containerd.service
systemctl enable docker.socket

# Fail rather than accidentally shipping a damaged desktop after package removal.
rpm -q steam kwin plasma-desktop xdg-desktop-portal-kde \
    mesa-vulkan-drivers pipewire tuned-ppd protontricks \
    code brave-browser zoom obs-studio docker-ce docker-ce-cli \
    docker-buildx-plugin docker-compose-plugin

dnf5 clean all
