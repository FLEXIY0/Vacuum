#!/bin/sh
# Vacuum — mklive postsetup hook.
#
# mklive.sh runs this with the path to the assembled rootfs, after every
# package is installed and after rootfs/ has been copied over the top, but
# before the initramfs is generated. Anything that has to see the finished
# filesystem belongs here.
#
#   usage: postsetup.sh <rootfs>

set -eu

ROOTFS="${1:?usage: postsetup.sh <rootfs>}"
VERSION="${VACUUM_VERSION:-0.1}"
BUILD_DATE="${VACUUM_BUILD_DATE:-$(date -u +%Y-%m-%d)}"

msg() { printf '\033[1;36m[vacuum]\033[0m %s\n' "$*"; }

# --- identity --------------------------------------------------------------
msg "stamping release identity ($VERSION, $BUILD_DATE)"
sed -i \
    -e "s|^VERSION=.*|VERSION=\"$VERSION\"|" \
    -e "s|^BUILD_DATE=.*|BUILD_DATE=\"$BUILD_DATE\"|" \
    "$ROOTFS/etc/vacuum-release"

# os-release is owned by base-files, so it is rewritten here rather than
# shipped in rootfs/ where xbps-reconfigure could put Void's version back.
cat > "$ROOTFS/etc/os-release" <<EOF
NAME="Vacuum"
ID=vacuum
ID_LIKE=void
PRETTY_NAME="Vacuum $VERSION"
VERSION="$VERSION"
VERSION_ID="$VERSION"
BUILD_ID="$BUILD_DATE"
HOME_URL="https://github.com/FLEXIY0/Vacuum"
LOGO=vacuum
EOF

# --- PipeWire --------------------------------------------------------------
# PipeWire ships its optional pieces as examples; they only take effect once
# linked into the drop-in directory. Same wiring void-mklive uses.
if [ -d "$ROOTFS/usr/share/examples/pipewire" ]; then
    msg "wiring PipeWire drop-ins"
    mkdir -p "$ROOTFS/etc/pipewire/pipewire.conf.d"
    ln -sf /usr/share/examples/wireplumber/10-wireplumber.conf \
        "$ROOTFS/etc/pipewire/pipewire.conf.d/"
    ln -sf /usr/share/examples/pipewire/20-pipewire-pulse.conf \
        "$ROOTFS/etc/pipewire/pipewire.conf.d/"
    mkdir -p "$ROOTFS/etc/alsa/conf.d"
    ln -sf /usr/share/alsa/alsa.conf.d/50-pipewire.conf "$ROOTFS/etc/alsa/conf.d/"
    ln -sf /usr/share/alsa/alsa.conf.d/99-pipewire-default.conf "$ROOTFS/etc/alsa/conf.d/"
fi

# --- permissions -----------------------------------------------------------
msg "fixing modes on shipped files"
for f in vacuum-term vacuum-run vacuum-ram vacuum-install vacuum-battery-warn vacuum-wifi vacuum-update; do
    [ -f "$ROOTFS/usr/bin/$f" ] && chmod 755 "$ROOTFS/usr/bin/$f"
done
chmod 755 "$ROOTFS/etc/skel/.xinitrc" "$ROOTFS/etc/skel/.config/openbox/autostart"
# The live user is created by the initramfs with useradd -m, which copies
# /etc/skel verbatim; the modes it copies are the ones set here.
find "$ROOTFS/etc/skel" -type d -exec chmod 755 {} +

# --- default theme for the root account ------------------------------------
# root does not get /etc/skel, and a root X session is a real possibility on
# a live image, so give it the same configuration.
msg "seeding root's configuration"
for item in .bashrc .bash_profile .xinitrc .Xresources .gtkrc-2.0 .config; do
    [ -e "$ROOTFS/etc/skel/$item" ] || continue
    cp -a "$ROOTFS/etc/skel/$item" "$ROOTFS/root/"
done

# --- slimming --------------------------------------------------------------
# Documentation and translated manpages are the two big wins that cost
# nothing at runtime. Kernel firmware and locales are deliberately kept:
# dropping them breaks Wi-Fi and UI translations on real hardware.
msg "trimming documentation"
rm -rf "$ROOTFS/usr/share/doc" "$ROOTFS/usr/share/info"
find "$ROOTFS/usr/share/man" -mindepth 1 -maxdepth 1 -type d \
    ! -name 'man*' -exec rm -rf {} + 2>/dev/null || true

msg "clearing package cache"
rm -rf "$ROOTFS/var/cache/xbps"/*

msg "postsetup done"
