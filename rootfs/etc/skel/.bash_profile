# Vacuum — login shell profile.

[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"

# Start the desktop on the first virtual terminal only. Not exec'd on
# purpose: if X fails to come up you land back in a usable shell instead of
# being logged out, which matters on a live image meeting new hardware.
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    startx
fi
