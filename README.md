# Vacuum

A small desktop on top of Void Linux: runit, Xorg, Openbox, and nothing that
is not earning its place. Dark, flat, keyboard-first.

Vacuum is not a fork of Void — it is a build recipe. Everything here is a
package list, a set of configs, and a script that hands them to
[`void-mklive`](https://github.com/void-linux/void-mklive). The result is a
bootable live ISO that installs to disk with the stock Void installer, and
an installed system that is a normal Void system: `xbps-install` works, the
Void repositories work, Void's documentation applies.

- **Base:** Void Linux, glibc, x86_64
- **Init:** runit
- **Session:** Xorg + Openbox + tint2 + dunst + dmenu
- **Audio:** PipeWire
- **Memory:** zram (zstd, 60% of RAM) with matching `vm.*` tuning
- **Power:** TLP

---

## Build it

The build must run on Void, because it uses `xbps` to populate a chroot. On
anything else, `build.sh` wraps it in a Void container for you.

```sh
git clone https://github.com/FLEXIY0/Vacuum
cd Vacuum
./build.sh                    # needs docker; ~20 min, ~8 GB of scratch disk
./build.sh --version 0.2      # stamp a version into the image
./build.sh --native           # on Void itself, as root, no container
./build.sh --shell            # drop into the build container to poke around
```

The ISO and its checksum land in `out/`.

The container runs `--privileged`: `mklive` bind-mounts `/dev`, `/proc` and
`/sys` into the rootfs it is assembling and then chroots into it, and none
of that works under Docker's default capability set.

`.github/workflows/build-iso.yml` does the same thing on GitHub Actions —
run it by hand from the Actions tab, or push a `v*` tag to get an ISO
attached to a release.

## Run it

Write the ISO to a USB stick and boot it — it is a hybrid image, so both
UEFI and BIOS machines will take it.

```sh
sha256sum -c out/vacuum-live-x86_64-*.iso.sha256
sudo dd if=out/vacuum-live-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

The live session logs in automatically as `anon` (password `voidlinux`,
root the same) and starts the desktop on tty1.

## Install it

```sh
sudo vacuum-install
```

That wraps `void-installer`. One thing matters there: leave **Source** on
`Local`. Local copies the running Vacuum system to disk — desktop, theme,
tools and all. `Network` would fetch a stock Void `base-system` instead and
none of Vacuum would come along. The installer then removes the live-only
pieces (the `anon` user, its passwordless sudo rule, the tty1 autologin) and
rebuilds the initramfs for real hardware.

Vacuum has no automatic partitioner. The installer offers `cfdisk`.

---

## Keys

| Key | Action |
| --- | --- |
| `Super`+`Return` | Terminal |
| `Super`+`d` | Run a program (dmenu) |
| `Super`+`e` | File manager |
| `Super`+`space` | Root menu |
| `Super`+`q` | Close window |
| `Super`+`f` / `m` / `n` | Fullscreen / maximize / minimize |
| `Super`+`←` / `→` | Snap to left or right half |
| `Super`+`1`…`4` | Switch desktop |
| `Super`+`Shift`+`1`…`4` | Send window to desktop |
| `Alt`+`Tab` | Cycle windows |
| `Super`+`Shift`+`e` | Log out |

Right-click the desktop for the root menu. `Alt` + drag moves a window from
anywhere in it; `Alt` + right-drag resizes.

Keyboard layouts default to `us,ru` with `Alt`+`Shift` to switch — change
that in `/etc/vacuum/xkb.conf`.

## What is running, and what it costs

Run `vacuum-ram` (or `sudo vacuum-ram` for exact numbers — reading another
user's proportional memory needs root, and Xorg is not your user).

It reports PSS, not RSS: shared libraries are split across the processes
that map them instead of being counted once per process. RSS totals for a
desktop like this typically read 40-60% high.

| Component | What it does | Roughly |
| --- | --- | --- |
| Void base + runit | kernel, init, base services | 35–45 MB |
| Xorg (`xorg-minimal`) | display server | 30–50 MB |
| Openbox | window manager | ~2 MB |
| tint2 | panel | ~8 MB |
| dunst | notifications | ~4 MB |
| dmenu | launcher (spawned on a key, then gone) | ~0 MB |
| nitrogen / feh | wallpaper (sets it and exits) | ~1 MB |
| pcmanfm | file manager (on demand) | ~0 MB |
| D-Bus | session and system bus | ~3 MB |
| PipeWire + WirePlumber | audio | ~15 MB |
| zram + TLP | compressed swap, power management | ~5 MB |
| **Total** | **desktop, idle, no browser** | **~105–135 MB** |

The last three rows are the honest addition to the original sketch: audio
and a session bus are what make a desktop usable rather than a demo, and
they cost about 18 MB between them. Drop `pipewire`, `wireplumber` and
`alsa-pipewire` from `packages/desktop.pkgs` if you would rather have the
memory than the sound.

Figures are for an idle session on 4 GB of RAM. Xorg's number in particular
depends on the driver and the resolution, so treat the range as a range.

## zram

`zramen` creates a zstd-compressed swap device sized at 60% of RAM, and
`/etc/sysctl.d/99-vacuum.conf` sets `vm.swappiness=100` and
`vm.page-cluster=0` so the kernel actually uses it and reads it a page at a
time. zstd gets roughly 3–4× on desktop working sets against lz4's 2–2.5×,
which is the trade worth making when RAM is the scarce resource and the CPU
is idle anyway.

On a machine with plenty of RAM this costs nothing: zram allocates physical
pages lazily, so an untouched device is nearly free. Tune it in
`/etc/sv/zramen/conf`.

---

## Layout

```
build.sh                  host entry point: wraps the build in a container
mk/
  build-in-container.sh   the actual build; POSIX sh, runs on Void
  postsetup.sh            runs against the finished rootfs before initramfs
  gen-wallpaper.py        regenerates the wallpaper, no dependencies
  palette.sh              the palette, in one place
packages/
  desktop.pkgs            what gets installed on top of base-system
  services.list           what runit enables
rootfs/                   copied verbatim over the image's filesystem
  etc/skel/               the user's default configs
  etc/vacuum/             system-wide knobs for the vacuum-* tools
  usr/bin/vacuum-*        the tools below
  usr/share/themes/Vacuum openbox theme
```

`rootfs/` is the whole of Vacuum's userland customisation. Add a file there
and it appears in the image; there is no other mechanism.

## Tools

| Command | What it does |
| --- | --- |
| `vacuum-term` | st, with a font it can actually be given |
| `vacuum-run` | dmenu, in the Vacuum palette |
| `vacuum-ram` | the memory report above |
| `vacuum-install` | install to disk (wraps `void-installer`) |

The first two exist because Void builds `st` and `dmenu` from vanilla
sources: neither reads a config file or the X resource database, so the
only way to theme them is on the command line. The wrappers are that command
line, and they read their defaults from `/etc/vacuum/`.

## Palette

| | |
| --- | --- |
| background | `#0b0c0e` |
| raised surface | `#131519` |
| hover / selected | `#1a1d22` |
| border | `#262a31` |
| text | `#d2d6dc` |
| dim text | `#6b7280` |
| accent | `#5fb8c7` |
| urgent | `#d4796a` |

One accent, used sparingly: the focused window's border, the active task
underline, the dmenu selection. Everything else is greyscale.

## Licence

Vacuum's own configs and scripts are MIT (see `LICENSE`). The image is built
from Void Linux packages and `void-mklive`, which carry their own licences —
`void-mklive` is 2-clause BSD, and everything in the image is whatever its
upstream says it is.
