#!/usr/bin/env bash
# Vacuum — build the live ISO.
#
# The build has to run on Void Linux (it uses xbps to populate a chroot), so
# on any other distro this wraps it in a Void container. On Void itself, run
# `./build.sh --native` as root and skip the container entirely.
#
#   ./build.sh                    build with Docker
#   ./build.sh --native           build here, no container (root, on Void)
#   ./build.sh --version 0.2      stamp a version into the image
#   ./build.sh --shell            drop into the build container instead
#
# Result lands in ./out as vacuum-live-x86_64-<version>-<date>.iso.
#
# The container runs --privileged: mklive bind-mounts /dev, /proc and /sys
# into the rootfs it is assembling and chroots into it, none of which works
# under the default seccomp and capability set.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${VACUUM_BUILD_IMAGE:-ghcr.io/void-linux/void-glibc-full:latest}"
VERSION="${VACUUM_VERSION:-0.1}"
OUTDIR="${VACUUM_OUT:-$REPO_ROOT/out}"

NATIVE=0
SHELL_ONLY=0

msg() { printf '\033[1;36m[vacuum]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[vacuum]\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --native)  NATIVE=1; shift ;;
        --shell)   SHELL_ONLY=1; shift ;;
        --version) VERSION="${2:?--version needs an argument}"; shift 2 ;;
        --image)   IMAGE="${2:?--image needs an argument}"; shift 2 ;;
        --out)     OUTDIR="${2:?--out needs an argument}"; shift 2 ;;
        -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
        *)         die "unknown argument: $1" ;;
    esac
done

mkdir -p "$OUTDIR"

if [ "$NATIVE" -eq 1 ]; then
    [ "$(id -u)" -eq 0 ] || die "--native needs root"
    exec env VACUUM_VERSION="$VERSION" VACUUM_OUT="$OUTDIR" \
        "$REPO_ROOT/mk/build-in-container.sh"
fi

command -v docker >/dev/null 2>&1 || die "docker not found (or use --native on Void)"
docker info >/dev/null 2>&1 || die "cannot reach the Docker daemon"

DOCKER_ARGS=(
    --rm
    --privileged
    -v "$REPO_ROOT:/vacuum"
    -v "$OUTDIR:/out"
    -e VACUUM_VERSION="$VERSION"
    -e VACUUM_OUT=/out
)

# Behind a proxy, the container needs both the proxy address and, if it is a
# TLS-intercepting one, its CA. A proxy on 127.0.0.1 is only reachable from
# the container with host networking.
PROXY="${HTTPS_PROXY:-${https_proxy:-}}"
if [ -n "$PROXY" ]; then
    msg "using proxy $PROXY"
    DOCKER_ARGS+=(--network host -e https_proxy="$PROXY" -e http_proxy="$PROXY")
fi

CA="${VACUUM_CA_BUNDLE:-${CURL_CA_BUNDLE:-${SSL_CERT_FILE:-}}}"
if [ -n "$CA" ] && [ -r "$CA" ]; then
    msg "trusting CA bundle $CA"
    DOCKER_ARGS+=(-v "$CA:/vacuum-ca.pem:ro" -e VACUUM_CA_BUNDLE=/vacuum-ca.pem)
fi

if [ "$SHELL_ONLY" -eq 1 ]; then
    msg "opening a shell in $IMAGE"
    # The Void base image has no bash, so the interactive shell is sh.
    exec docker run -it "${DOCKER_ARGS[@]}" "$IMAGE" sh -c '
        if [ -n "${VACUUM_CA_BUNDLE:-}" ] && [ -r "$VACUUM_CA_BUNDLE" ]; then
            cat "$VACUUM_CA_BUNDLE" >> /etc/ssl/certs/ca-certificates.crt
        fi
        exec sh'
fi

msg "building Vacuum $VERSION in $IMAGE"
docker run "${DOCKER_ARGS[@]}" "$IMAGE" sh -c '
    set -e
    if [ -n "${VACUUM_CA_BUNDLE:-}" ] && [ -r "$VACUUM_CA_BUNDLE" ]; then
        cat "$VACUUM_CA_BUNDLE" >> /etc/ssl/certs/ca-certificates.crt
    fi
    exec /vacuum/mk/build-in-container.sh
'

msg "artifacts in $OUTDIR:"
ls -lh "$OUTDIR"
