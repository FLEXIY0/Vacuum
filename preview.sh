#!/usr/bin/env bash
# Vacuum — screenshot the desktop without building an ISO.
#
# Renders the working tree's configs under Xvfb in a container that stays
# warm between runs. The first call installs the environment (a minute or
# so); every call after that is a few seconds, which makes this the right
# loop for anything under rootfs/: themes, panel, notifications, keybinds,
# the vacuum-* tools.
#
#   ./preview.sh                 the desktop with two terminals and a toast
#   ./preview.sh menu            the Openbox root menu, opened with Super+space
#   ./preview.sh dmenu           the launcher bar
#   ./preview.sh files           pcmanfm, to check the GTK dark theme
#   ./preview.sh term            one terminal, filling the screen
#   ./preview.sh clean           wallpaper and panel only
#   ./preview.sh hud             the side HUD with load and keybindings
#
#   ./preview.sh --size 1920x1080 menu
#   ./preview.sh --out shot.png
#   ./preview.sh --stop          drop the warm container
#
# What it does NOT cover: Xorg on real hardware, runit services, and
# anything that happens before the session starts. Those still need an ISO.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${VACUUM_BUILD_IMAGE:-ghcr.io/void-linux/void-glibc-full:latest}"
NAME="${VACUUM_PREVIEW_CONTAINER:-vacuum-preview}"
OUTDIR="$REPO_ROOT/preview"
SIZE="1366x768"
SCENE="desktop"
OUTNAME=""

msg() { printf '\033[1;36m[preview]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[preview]\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --stop)
            docker rm -f "$NAME" >/dev/null 2>&1 && msg "container removed" ||
                msg "no container running"
            exit 0
            ;;
        --size)  SIZE="${2:?--size needs WxH}"; shift 2 ;;
        --out)   OUTNAME="${2:?--out needs a path}"; shift 2 ;;
        -h|--help) sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
        -*)      die "unknown option: $1" ;;
        *)       SCENE="$1"; shift ;;
    esac
done

command -v docker >/dev/null 2>&1 || die "docker not found"
docker info >/dev/null 2>&1 || die "cannot reach the Docker daemon"

mkdir -p "$OUTDIR"
: "${OUTNAME:=$OUTDIR/$SCENE.png}"
mkdir -p "$(dirname "$OUTNAME")"

# --- the warm container -----------------------------------------------------
PROXY="${HTTPS_PROXY:-${https_proxy:-}}"

# A container outlives the shell that made it, and a proxy address can move
# between sessions. Keeping a container that points at a proxy which is no
# longer there produces "connection refused" from xbps and nothing else, so
# check for it rather than leaving someone to debug it.
stale_proxy() {
    [ -n "$PROXY" ] || return 1
    was=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$NAME" 2>/dev/null |
        sed -n 's/^https_proxy=//p' | head -1)
    [ -n "$was" ] && [ "$was" != "$PROXY" ]
}

if stale_proxy; then
    msg "proxy moved since this container was made; recreating it"
    docker rm -f "$NAME" >/dev/null 2>&1 || true
fi

if ! docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null | grep -q true; then
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    msg "starting the preview container"

    ARGS=(-d --name "$NAME" -v "$REPO_ROOT:/vacuum:ro" -v "$OUTDIR:/out")

    if [ -n "$PROXY" ]; then
        ARGS+=(--network host -e https_proxy="$PROXY" -e http_proxy="$PROXY")
    fi
    CA="${VACUUM_CA_BUNDLE:-${CURL_CA_BUNDLE:-${SSL_CERT_FILE:-}}}"
    if [ -n "$CA" ] && [ -r "$CA" ]; then
        ARGS+=(-v "$CA:/vacuum-ca.pem:ro" -e VACUUM_CA_BUNDLE=/vacuum-ca.pem)
    fi

    docker run "${ARGS[@]}" "$IMAGE" sleep infinity >/dev/null
fi

# --- render -----------------------------------------------------------------
start=$(date +%s)
docker exec "$NAME" sh /vacuum/mk/preview-session.sh \
    "$SCENE" "$SIZE" "/out/$(basename "$OUTNAME")"

# The container writes into $OUTDIR; move it if the caller asked elsewhere.
if [ "$(dirname "$OUTNAME")" != "$OUTDIR" ]; then
    mv "$OUTDIR/$(basename "$OUTNAME")" "$OUTNAME"
fi

msg "$OUTNAME  ($(( $(date +%s) - start ))s)"
