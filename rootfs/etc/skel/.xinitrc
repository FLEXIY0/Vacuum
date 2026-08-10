#!/bin/sh
# Vacuum — X session startup. Run by startx (see ~/.bash_profile).

[ -f "$HOME/.Xresources" ] && command -v xrdb >/dev/null 2>&1 &&
    xrdb -merge "$HOME/.Xresources"

# Keyboard layouts. Override per user by exporting these before startx,
# or system-wide in /etc/vacuum/xkb.conf.
[ -f /etc/vacuum/xkb.conf ] && . /etc/vacuum/xkb.conf
command -v setxkbmap >/dev/null 2>&1 && setxkbmap \
    -layout "${VACUUM_XKB_LAYOUT:-us,ru}" \
    -option "${VACUUM_XKB_OPTIONS:-grp:alt_shift_toggle}"

# openbox-session sources ~/.config/openbox/autostart. The session bus is
# started here so PipeWire, dunst and pcmanfm all share one.
if command -v dbus-run-session >/dev/null 2>&1; then
    exec dbus-run-session openbox-session
else
    exec openbox-session
fi
