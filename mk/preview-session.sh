#!/bin/sh
# Vacuum — render the desktop under Xvfb and screenshot it. Runs inside the
# preview container; mk/preview.sh is the entry point on the host.
#
#   preview-session.sh <scene> <WxH> <output.png>
#
# Everything under rootfs/ is copied in fresh on every run, so a screenshot
# always reflects the working tree rather than whatever the last run left
# behind. Openbox, the panel and the demo windows are restarted for the same
# reason.
#
# The X server is not restarted between renders. It does not need to be --
# every config Vacuum owns lives in the clients -- and reusing it keeps a
# render to about a second.
#
# Readiness is probed with `xset q` rather than xdpyinfo. That is not a
# style choice: xdpyinfo was missing from this environment, so the wait loop
# could never succeed and simply burned its whole timeout on every run,
# which is what made renders look ten seconds slower than they were.

set -eu

SCENE="${1:-desktop}"
SIZE="${2:-1366x768}"
OUT="${3:-/out/preview.png}"

# Bump the suffix when the package list below changes, so existing
# containers reinstall instead of silently missing a new tool.
READY=/var/lib/vacuum-preview-ready.3
SIZE_STAMP=/var/lib/vacuum-preview-size
DISP=:99
export DISPLAY="$DISP" HOME=/root

log() { printf '\033[1;36m[preview]\033[0m %s\n' "$*"; }

# --- one-time setup ---------------------------------------------------------
if [ ! -f "$READY" ]; then
    log "first run: installing the preview environment (once)"
    if [ -n "${VACUUM_CA_BUNDLE:-}" ] && [ -r "$VACUUM_CA_BUNDLE" ]; then
        cat "$VACUUM_CA_BUNDLE" >> /etc/ssl/certs/ca-certificates.crt
    fi
    xbps-install -Sy >/dev/null 2>&1
    xbps-install -y \
        xorg-server-xvfb xsetroot xprop xset xdpyinfo setxkbmap \
        openbox tint2 dunst dmenu st feh nitrogen pcmanfm conky \
        dbus dbus-x11 libnotify xdotool ImageMagick procps-ng \
        dejavu-fonts-ttf font-misc-misc terminus-font \
        hicolor-icon-theme adwaita-icon-theme xdg-user-dirs bash \
        >/dev/null 2>&1
    mkdir -p "$(dirname "$READY")" && touch "$READY"
    log "environment ready; later runs skip this"
fi

# --- install the working tree ----------------------------------------------
cp -a /vacuum/rootfs/usr/share/themes/Vacuum /usr/share/themes/ 2>/dev/null || true
mkdir -p /usr/share/vacuum /etc/vacuum
cp -a /vacuum/rootfs/usr/share/vacuum/. /usr/share/vacuum/
cp -a /vacuum/rootfs/usr/bin/vacuum-* /usr/bin/
chmod 755 /usr/bin/vacuum-*
cp -a /vacuum/rootfs/etc/vacuum/. /etc/vacuum/
cp -a /vacuum/rootfs/etc/vacuum-release /etc/
rm -rf /root/.config
cp -a /vacuum/rootfs/etc/skel/. /root/

# There is no sound card here, so the panel's volume item would honestly
# read "n/a" and the thing worth looking at -- that it renders, fits, and
# lines up with the clock -- would not be visible. Stand in for wpctl so the
# real parsing path in vacuum-vol still runs; only the readings are fake.
cat > /usr/bin/wpctl <<'STUB'
#!/bin/sh
[ "$1" = get-volume ] && echo "Volume: 0.45"
exit 0
STUB
chmod 755 /usr/bin/wpctl

# --- the X server, started once and kept ------------------------------------
want_restart=0
xset q >/dev/null 2>&1 || want_restart=1
[ -f "$SIZE_STAMP" ] && [ "$(cat "$SIZE_STAMP")" = "$SIZE" ] || want_restart=1

if [ "$want_restart" -eq 1 ]; then
    log "starting X at $SIZE"
    pkill -f "Xvfb $DISP" 2>/dev/null || true
    rm -f "/tmp/.X${DISP#:}-lock" "/tmp/.X11-unix/X${DISP#:}"
    sleep 0.3
    Xvfb "$DISP" -screen 0 "${SIZE}x24" -nolisten tcp >/tmp/xvfb.log 2>&1 &
    i=0
    while [ "$i" -lt 200 ]; do
        xset q >/dev/null 2>&1 && break
        sleep 0.05
        i=$((i + 1))
    done
    xset q >/dev/null 2>&1 || {
        echo "X server failed to start; see /tmp/xvfb.log in the container" >&2
        exit 1
    }
    echo "$SIZE" > "$SIZE_STAMP"
fi

# --- restart the session on the existing server -----------------------------
for p in openbox tint2 dunst st dmenu pcmanfm conky dbus-daemon; do
    pkill -x "$p" 2>/dev/null || true
done
# Blank the root window: the server persists between runs, so last run's
# wallpaper would otherwise survive a change to the wallpaper itself.
xsetroot -solid '#000000' 2>/dev/null || true

eval "$(dbus-launch --sh-syntax)"

openbox > /tmp/openbox.log 2>&1 &
i=0
while [ "$i" -lt 100 ]; do
    xprop -root _NET_SUPPORTING_WM_CHECK >/dev/null 2>&1 && break
    sleep 0.05
    i=$((i + 1))
done

# The real autostart, so wallpaper, panel and notifications are exercised.
sh /root/.config/openbox/autostart > /tmp/autostart.log 2>&1 || true

# --- helpers ----------------------------------------------------------------
# Wait for windows rather than sleeping a fixed amount: correct on a slow
# run, and instant on a fast one.
wait_win() {
    pat="$1"; want="${2:-1}"; limit="${3:-120}"; i=0
    while [ "$i" -lt "$limit" ]; do
        n=$(xdotool search --onlyvisible --class "$pat" 2>/dev/null | wc -l)
        [ "$n" -ge "$want" ] && return 0
        sleep 0.05
        i=$((i + 1))
    done
    return 1
}

term() { st -f "DejaVu Sans Mono:pixelsize=14" -e bash -c "$1; sleep 3600" & }

# --- scenes -----------------------------------------------------------------
case "$SCENE" in
    clean)
        wait_win tint2 1 60 || true
        sleep 0.3
        ;;
    desktop)
        term 'cat /usr/share/vacuum/logo.txt'
        wait_win st 1 || true
        term 'vacuum-ram'
        wait_win st 2 || true
        sleep 0.6
        notify-send -u normal "Vacuum" "Notifications look like this." || true
        sleep 0.6
        ;;
    menu)
        term 'cat /usr/share/vacuum/logo.txt'
        wait_win st 1 || true
        sleep 0.4
        xdotool key --clearmodifiers super+space
        # Openbox draws its menu in an override-redirect window, which does
        # not show up in a window-manager search -- so this one is a sleep.
        sleep 0.6
        ;;
    dmenu)
        term 'cat /usr/share/vacuum/logo.txt'
        wait_win st 1 || true
        vacuum-run &
        sleep 0.8
        ;;
    files)
        pcmanfm >/tmp/pcmanfm.log 2>&1 &
        wait_win Pcmanfm 1 200 || true
        sleep 1
        ;;
    term)
        term 'cat /usr/share/vacuum/logo.txt; echo; vacuum-ram'
        wait_win st 1 || true
        sleep 0.8
        ;;
    hud)
        # conky needs a couple of update cycles before its readings settle.
        term 'cat /usr/share/vacuum/logo.txt'
        wait_win st 1 || true
        sleep 4
        ;;
    *)
        echo "unknown scene: $SCENE" >&2
        echo "scenes: desktop menu dmenu files term hud clean" >&2
        exit 1
        ;;
esac

import -window root "$OUT"
log "$SCENE @ $SIZE"

# Surface config errors: a screenshot that looks right can still hide a
# parse failure that silently fell back to a default.
for f in /tmp/openbox.log /tmp/autostart.log; do
    [ -s "$f" ] || continue
    grep -viE "glib slice|xRandr|Loading config|systray|panel items|nb monitors|transparency|uses scale|uevent|pixmap background|XSETTINGS|dpms|FcInit|AdwaitaLegacy|Creating executor" "$f" |
        grep -vE "^[[:space:]]*$" | sed "s|^|[$(basename "$f" .log)] |" || true
done
