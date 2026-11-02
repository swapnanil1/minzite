#!/usr/bin/env bash
set -euo pipefail

# Minzite for PCs: Steam Gaming Mode, KDE, Medium performance tweaks and
# native desktop/development packages. Retain shared SteamOS hardware helpers.

[[ $(uname -m) == x86_64 ]] || { echo 'Minzite Deck targets x86_64.' >&2; exit 1; }

# Keep Flatpak CLI for manual installs; ext4 needs no Btrfs maintenance stack.
unwanted=(bazaar krunner-bazaar krunner-yafti flatpak-kcm
    bees snapper btrfs-assistant compsize btrfsmaintenance)
remove=()
for package in "${unwanted[@]}"; do
    if rpm -q "$package" >/dev/null 2>&1; then remove+=("$package"); fi
done
if ((${#remove[@]})); then
    dnf5 -y --setopt=clean_requirements_on_remove=False remove "${remove[@]}"
fi

# Native desktop and development tools.
dnf5 -y --setopt=install_weak_deps=False install \
    firefox gwenview okular kcalc haruna filelight kde-partitionmanager \
    plasma-systemmonitor protontricks obs-studio \
    postgresql postgresql-server \
    git git-lfs gh openssh-clients gcc gcc-c++ make cmake pkgconf-pkg-config python3 python3-pyyaml \
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

# Latest stable MongoDB clients, with release digests and vendor RPM signatures.
for tool in mongosh compass; do
    prefix="mongodb-${tool}"
    [[ "$tool" != mongosh ]] || prefix+="-shared-openssl3"
    read -r url digest < <(curl -fLsS --retry 3 "https://api.github.com/repos/mongodb-js/${tool}/releases/latest" |
        jq -er --arg prefix "$prefix" '.tag_name as $tag | .assets[] |
            select(.name == ($prefix + "-" + ($tag | ltrimstr("v")) + ".x86_64.rpm")) |
            [.browser_download_url, .digest] | @tsv')
    [[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]]
    curl -fLsS --retry 3 -o "/tmp/${tool}.rpm" "$url"
    echo "${digest#sha256:}  /tmp/${tool}.rpm" | sha256sum --check --status
    rpm --import "https://pgp.mongodb.com/${tool}.asc"
    dnf5 -y --setopt=localpkg_gpgcheck=True --setopt=install_weak_deps=False install "/tmp/${tool}.rpm"
    rm -f "/tmp/${tool}.rpm"
done

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
ln -sf /usr/bin/plasma-systemmonitor /usr/bin/missioncenter-helper

# Edit upstream Portal data rather than maintaining a full copy of it.
python3 - <<'PY'
from pathlib import Path
import yaml

path = Path('/usr/share/yafti/yafti.yml')
config = yaml.safe_load(path.read_text())
config['screens'] = [screen for screen in config['screens']
                     if screen['title'] != 'Install Applications']
for screen in config['screens']:
    screen['actions'] = [action for action in screen.get('actions', [])
                         if action['id'] not in {'bazaar', 'snapper', 'configure-beesd'}]
path.write_text(yaml.safe_dump(config, sort_keys=False, allow_unicode=True))
PY

# This image disables SELinux; runcon would prevent Gaming Mode OS updates.
sed -i '/^[[:space:]]*runcon system_u:unconfined_r:unconfined_t:s0 \\$/d' /usr/libexec/ogc/os-update
bash -n /usr/libexec/ogc/os-update

# Keep the OS updater and controller/session services; disable optional setup
# and maintenance, including any leftover units from removed packages.
systemctl mask \
    bazzite-flatpak-manager.service ublue-flatpak-manager.service \
    flatpak-add-fedora-repos.service brew-setup.service \
    beesd@.service beesd@.timer snapperd.service \
    snapper-boot.timer snapper-cleanup.timer snapper-timeline.timer \
    cockpit.socket cockpit.service cups.service cups.socket cups.path \
    cups-browsed.service ModemManager.service auditd.service \
    tailscaled.service waydroid-container.service podman.socket
# Container engines need not listen at every login. CLI Podman remains usable.
systemctl --global mask podman.socket
# Start Docker on demand and PostgreSQL manually.
systemctl disable docker.service containerd.service postgresql.service
systemctl enable docker.socket

# Fail rather than accidentally shipping a broken Gaming Mode or desktop.
rpm -q steam gamescope-session-ogui-steam steamos-manager-powerstation \
    jupiter-hw-support-btrfs bazzite-portal flatpak btrfs-progs \
    sddm kwin plasma-desktop xdg-desktop-portal-kde \
    mesa-vulkan-drivers pipewire tuned-ppd protontricks \
    code brave-browser zoom obs-studio docker-ce docker-ce-cli \
    docker-buildx-plugin docker-compose-plugin postgresql postgresql-server \
    mongodb-mongosh-shared-openssl3 mongodb-compass
for package in "${unwanted[@]}"; do
    if rpm -q "$package" >/dev/null 2>&1; then
        echo "An unwanted package was reintroduced: $package" >&2
        exit 1
    fi
done

dnf5 clean all
