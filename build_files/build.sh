#!/usr/bin/env bash
set -euo pipefail

# Bazzite Deck with upstream-style storage, performance defaults and native apps.

[[ $(uname -m) == x86_64 ]] || { echo 'Minzite Deck targets x86_64.' >&2; exit 1; }

# Keep Bazaar/Flatpak for user-selected apps; inherit upstream browser/store choices.
unwanted=(bees snapper btrfs-assistant compsize btrfsmaintenance)
remove=()
for package in "${unwanted[@]}"; do
    if rpm -q "$package" >/dev/null 2>&1; then remove+=("$package"); fi
done
if ((${#remove[@]})); then
    dnf5 -y --setopt=clean_requirements_on_remove=False remove "${remove[@]}"
fi

# Native apps, Fedora Node.js 24 with matching npm, and build dependencies.
dnf5 -y --setopt=install_weak_deps=False install \
    obs-studio postgresql postgresql-server nodejs24 nodejs24-npm-bin \
    python3-pyyaml curl jq

# Vendor RPM repositories: Microsoft VS Code and Docker CE.
cat >/etc/yum.repos.d/vscode.repo <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
dnf5 config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
dnf5 -y --setopt=install_weak_deps=False install \
    code docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

# Latest stable mongosh, with its release digest and vendor RPM signature.
read -r url digest < <(curl -fLsS --retry 3 https://api.github.com/repos/mongodb-js/mongosh/releases/latest |
    jq -er '.tag_name as $tag | .assets[] |
        select(.name == ("mongodb-mongosh-shared-openssl3-" + ($tag | ltrimstr("v")) + ".x86_64.rpm")) |
        [.browser_download_url, .digest] | @tsv')
[[ "$digest" =~ ^sha256:[a-f0-9]{64}$ ]]
curl -fLsS --retry 3 -o /tmp/mongosh.rpm "$url"
echo "${digest#sha256:}  /tmp/mongosh.rpm" | sha256sum --check --status
rpm --import https://pgp.mongodb.com/mongosh.asc
dnf5 -y --setopt=localpkg_gpgcheck=True --setopt=install_weak_deps=False install /tmp/mongosh.rpm

# Official stable Discord RPM, including its native per-user updater.
curl -fLsS --retry 3 -o /tmp/discord.rpm 'https://discord.com/api/download?platform=linux&format=rpm'
dnf5 -y --setopt=install_weak_deps=False install /tmp/discord.rpm

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

node --version
npm --version

rm -f /tmp/discord.rpm /tmp/heroic.rpm /tmp/mongosh.rpm

# Install configuration after RPM transactions so package defaults cannot win.
cp -a /ctx/system_files/. /

# Keep Deck's zram memory policy when switching to the Performance power profile.
sed -i '/^\[profiles\]/,/^\[battery\]/s/^performance=throughput-performance-bazzite$/performance=performance-minzite/' /etc/tuned/ppd.conf

# If started manually or by Gaming Mode, use bpfland with upstream's mode flags.
sed -i 's/^default_sched = .*/default_sched = "scx_bpfland"/' /etc/scx_loader/config.toml

# Keep upstream Topgrade defaults except for our OS/firmware-only update policy.
sed -i 's/^only = .*/only = ["system", "firmware"]/' /usr/share/ublue-os/topgrade.toml

# Edit upstream Portal data rather than maintaining a full copy of it.
python3 - <<'PY'
from pathlib import Path
import yaml

path = Path('/usr/share/yafti/yafti.yml')
config = yaml.safe_load(path.read_text())
for screen in config['screens']:
    screen['actions'] = [action for action in screen.get('actions', [])
                         if action['id'] not in {'snapper', 'configure-beesd'}]
path.write_text(yaml.safe_dump(config, sort_keys=False, allow_unicode=True))
PY

# This image disables SELinux; runcon would prevent Gaming Mode OS updates.
sed -i '/^[[:space:]]*runcon system_u:unconfined_r:unconfined_t:s0 \\$/d' /usr/libexec/ogc/os-update
bash -n /usr/libexec/ogc/os-update

# Block automatic Flatpak/Homebrew setup and maintenance for removed Btrfs tools.
# Other services retain upstream defaults.
systemctl mask \
    bazzite-flatpak-manager.service ublue-flatpak-manager.service \
    flatpak-add-fedora-repos.service brew-setup.service \
    beesd@.service beesd@.timer snapperd.service \
    snapper-boot.timer snapper-cleanup.timer snapper-timeline.timer
# Docker starts on demand; PostgreSQL and sched-ext stay off at boot.
systemctl disable docker.service containerd.service postgresql.service scx_loader.service
systemctl enable docker.socket

# Fail rather than accidentally shipping a broken Gaming Mode or desktop.
rpm -q steam gamescope-session-ogui-steam steamos-manager-powerstation \
    jupiter-hw-support-btrfs bazzite-portal bazaar flatpak btrfs-progs e2fsprogs \
    sddm kwin plasma-desktop xdg-desktop-portal-kde \
    mesa-vulkan-drivers pipewire tuned-ppd \
    code discord heroic zoom obs-studio docker-ce docker-ce-cli \
    docker-buildx-plugin docker-compose-plugin postgresql postgresql-server \
    mongodb-mongosh-shared-openssl3 nodejs24 nodejs24-npm-bin
for package in "${unwanted[@]}"; do
    if rpm -q "$package" >/dev/null 2>&1; then
        echo "An unwanted package was reintroduced: $package" >&2
        exit 1
    fi
done

# A fresh install starts with no Flatpak apps; Bazaar itself is an inherited RPM.
flatpak_apps=$(flatpak list --system --app --columns=application)
if [[ -n "$flatpak_apps" ]]; then
    echo "Unexpected preinstalled Flatpak apps: $flatpak_apps" >&2
    exit 1
fi

dnf5 clean all
