#!/bin/sh
# Vacuum — ISO build, from inside a Void Linux container.
#
# This is the half of the build that has to run on Void: it needs xbps to
# install packages into a chroot and runit's service layout to enable
# services. build.sh puts a Void container around it; run it directly only
# if you are already on Void and are root.
#
# Written for POSIX sh on purpose — the Void base image ships dash as
# /bin/sh and no bash at all. bash arrives with the build dependencies
# below, which is soon enough for mklive.sh (which is a bash script).
#
# Environment:
#   VACUUM_VERSION      release string stamped into the image  (default 0.1)
#   VACUUM_OUT          output directory                       (default ./out)
#   VOID_MKLIVE_REF     void-mklive commit/tag to build with
#   VOID_MKLIVE_REPO    where to clone void-mklive from
#   XBPS_MIRROR         Void mirror to install packages from

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKDIR="${VACUUM_WORKDIR:-/tmp/vacuum-build}"
OUTDIR="${VACUUM_OUT:-$REPO_ROOT/out}"
VERSION="${VACUUM_VERSION:-0.1}"
BUILD_DATE="${VACUUM_BUILD_DATE:-$(date -u +%Y%m%d)}"

# Pinned so a rebuild months from now produces the same live scaffolding.
# Override to track upstream.
VOID_MKLIVE_REPO="${VOID_MKLIVE_REPO:-https://github.com/void-linux/void-mklive.git}"
VOID_MKLIVE_REF="${VOID_MKLIVE_REF:-81ad067c4fbc46f9706607b65ea6a34298e9d6b8}"

XBPS_MIRROR="${XBPS_MIRROR:-https://repo-default.voidlinux.org/current}"

msg() { printf '\033[1;36m[vacuum]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[vacuum]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "must run as root (mklive chroots into the rootfs)"
command -v xbps-install >/dev/null 2>&1 || die "not running on Void: xbps-install missing"

# --- read the package and service lists ------------------------------------
# Strip comments and blank lines, collapse to a single space-separated line,
# which is the form mklive.sh's -p and -S expect.
read_list() {
    sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^[[:space:]]*$/d' "$1" | tr '\n' ' '
}

PKGS="$(read_list "$REPO_ROOT/packages/desktop.pkgs")"
SERVICES="$(read_list "$REPO_ROOT/packages/services.list")"

msg "packages: $PKGS"
msg "services: $SERVICES"

# --- build host prerequisites ----------------------------------------------
msg "installing build dependencies"
xbps-install -Sy >/dev/null
xbps-install -uy xbps >/dev/null 2>&1 || true
xbps-install -y git make bash curl tar xz squashfs-tools xorriso dosfstools \
    mtools e2fsprogs util-linux which >/dev/null

# --- void-mklive -----------------------------------------------------------
mkdir -p "$WORKDIR"
MKLIVE="$WORKDIR/void-mklive"
if [ ! -d "$MKLIVE/.git" ]; then
    msg "cloning void-mklive"
    git clone "$VOID_MKLIVE_REPO" "$MKLIVE"
fi
git -C "$MKLIVE" fetch --all --tags --quiet || true
git -C "$MKLIVE" checkout --quiet "$VOID_MKLIVE_REF"
msg "void-mklive at $(git -C "$MKLIVE" rev-parse --short HEAD)"

# --- assemble the include tree ---------------------------------------------
# mklive copies this over the rootfs after packages are installed, so it is
# how every Vacuum config gets into the image.
INCLUDEDIR="$WORKDIR/includedir"
rm -rf "$INCLUDEDIR"
mkdir -p "$INCLUDEDIR"
cp -a "$REPO_ROOT/rootfs/." "$INCLUDEDIR/"

# void-installer is a script in the void-mklive tree, not a package; this is
# the same substitution mkiso.sh does before shipping it.
msg "adding void-installer"
MKLIVE_VERSION="$(cat "$MKLIVE/version" 2>/dev/null || echo unknown)"
mkdir -p "$INCLUDEDIR/usr/bin"
sed "s/@@MKLIVE_VERSION@@/${MKLIVE_VERSION}/" "$MKLIVE/installer.sh" \
    > "$INCLUDEDIR/usr/bin/void-installer"
chmod 755 "$INCLUDEDIR/usr/bin/void-installer"

# --- build -----------------------------------------------------------------
mkdir -p "$OUTDIR"
ISO="$OUTDIR/vacuum-live-x86_64-${VERSION}-${BUILD_DATE}.iso"

msg "building $(basename "$ISO")"
cd "$MKLIVE"
VACUUM_VERSION="$VERSION" VACUUM_BUILD_DATE="$BUILD_DATE" \
./mklive.sh \
    -a x86_64 \
    -r "$XBPS_MIRROR" \
    -T "Vacuum" \
    -p "$PKGS" \
    -S "$SERVICES" \
    -I "$INCLUDEDIR" \
    -x "$REPO_ROOT/mk/postsetup.sh" \
    -s xz \
    -o "$ISO"

msg "done: $ISO ($(du -h "$ISO" | cut -f1))"
sha256sum "$ISO" | tee "$ISO.sha256"
