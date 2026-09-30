# rocksmith-linux-asio

Get **Rocksmith 2014 Remastered (Steam)** working on Linux with a guitar input, using
PipeWire, [WineASIO](https://github.com/wineasio/wineasio) and [RS_ASIO](https://github.com/mdias/rs_asio).
Works with a Real Tone Cable or a normal audio interface (e.g. a Focusrite Scarlett).

```
guitar ─▶ PipeWire (pipewire-jack) ─▶ WineASIO (patched) ─▶ RS_ASIO ─▶ Rocksmith (Proton 10)
```

## Quick start

1. In Steam, install **Proton 10.0** (search your Library for it), then set Rocksmith →
   Properties → Compatibility → **Proton 10.0**. Launch the game once until the first
   screen appears, then quit.
2. Install the requirements (see below), log out and back in.
3. Run:
   ```sh
   git clone https://github.com/5TN1rcZRS79VAEFuUCRB/rocksmith-linux-asio
   cd rocksmith-linux-asio
   ./setup.sh            # add --tiling-wm if you use dwm/i3/sway-xwayland etc.
   ```
   It asks which input your guitar is plugged into and where to play the sound.
4. Set Rocksmith's Steam **Launch Options** to:
   ```
   ~/.local/bin/rocksmith-launch %command%
   ```
5. Start the game from Steam and pick **Real Tone Cable** as the connection.

Re-run `./setup.sh` whenever Steam updates Proton 10 (the update removes WineASIO from it).

## Requirements

| | Arch | Debian / Ubuntu | Fedora |
|---|---|---|---|
| PipeWire + JACK layer | `pipewire pipewire-jack lib32-pipewire-jack` | `pipewire pipewire-jack pipewire-jack:i386` | `pipewire-jack-audio-connection-kit pipewire-jack-audio-connection-kit-libs.i686` |
| Real-time audio (locked-memory limit) | `realtime-privileges`, user in `realtime` + `audio` | user in `audio` | user in `pipewire` |
| Container engine (builds WineASIO) | `podman` | `podman` | `podman` |
| Also | `python3`, `curl` | `python3`, `curl` | `python3`, `curl` |

`setup.sh` checks the 32-bit JACK library and the locked-memory limit and tells you what's
missing. Group changes need a **full** re-login (restarting only the X session is not enough).

Native Steam only: Flatpak Steam's sandbox blocks this setup.

## What setup.sh does

- Finds Steam, the game, its Proton prefix and Proton 10.
- Builds a 32-bit WineASIO against Wine 10 in a container (podman/docker), so it doesn't
  matter that most distros no longer ship 32-bit Wine libraries, and applies
  [`patches/wineasio-pipewire-callbacks.patch`](patches/wineasio-pipewire-callbacks.patch).
- Installs it into Proton 10 and registers it in Rocksmith's prefix.
- Downloads RS_ASIO 0.7.5 (checksum-verified) into the game folder and points it at WineASIO.
- Writes `~/.config/rocksmith-linux-asio/config` and installs `rocksmith-launch`.

## What rocksmith-launch does

- Runs Proton **outside** the Steam Linux Runtime container, because WineASIO can't reach
  PipeWire's JACK socket from inside it (Steam overlay/playtime still work).
- Turns off WineASIO's autoconnect (it grabs the *first* capture device, often a webcam mic)
  and links exactly the ports you chose in setup as soon as the game creates them.
- Optionally sets your input volume and refocuses the window (see config).
- Log: `~/.cache/rocksmith-launch.log`

## Config (`~/.config/rocksmith-linux-asio/config`)

| Key | Meaning |
|---|---|
| `INPUT_PORT`, `OUTPUT_PORT_L/R` | PipeWire ports to link. Re-run `setup.sh` to pick again. |
| `INPUT_VOLUME` | e.g. `160%` (+12 dB). Rocksmith expects Real Tone Cable levels; audio interfaces usually need a boost. Only affects the chosen input. |
| `REFOCUS` | `1` = refocus the game once after it goes fullscreen (tiling WMs). |
| `EXTRA_DLL_OVERRIDES` | e.g. `xinput1_3=n,b` if you use [RSMods](https://github.com/Lovrom8/RSMods). |
| `PIPEWIRE_LATENCY` | default `256/48000`. |

## Troubleshooting

**Calibration never finishes** (line rises, then drops to the bottom / "KEEP GOING!").
Pick **Disconnected** on the connection screen to skip it, then set the level in
**Tools → Options → Input Gain**. If notes still don't register, raise `INPUT_VOLUME`.
Don't raise RS_ASIO's `SoftwareMasterVolumePercent` above 100 for this: it makes the
calibration meter stick at the top.

**Crash right after audio starts** (`create_view: Assertion ... page_mask` or a SIGSEGV):
your locked-memory limit is too low. Check `ulimit -l` in a fresh login shell.

**"A debugger has been found in your system"**: you're on Proton 11, Proton Experimental or
GE-Proton 11. Use Proton 10.0.

**"No output device detected"**: WineASIO isn't loaded. Check the launch options, that
Compatibility is Proton 10.0, and re-run `setup.sh` (Proton may have updated).

**Game starts frozen until you alt-tab** (tiling WMs): re-run `setup.sh --tiling-wm`.

**Stuck on the grey "R" loading screen**: RSMods' "Fast Load" (intro skip) hangs with this
setup. Restore the original `cache.psarc` (Steam → Verify integrity of game files).

**Don't change the game's audio links by hand while it's running** unless you're
troubleshooting: older WineASIO builds crash on it (the patch fixes the known case).

## The WineASIO patch

With pipewire-jack, the buffer-size, latency and sample-rate notification callbacks run on a
thread Wine didn't create; WineASIO forwards them into the game, which segfaults
([wineasio#137](https://github.com/wineasio/wineasio/issues/137),
[pipewire#3542](https://gitlab.freedesktop.org/pipewire/pipewire/-/work_items/3542)). The
patch stops forwarding those three notifications. Rocksmith runs at a fixed 48 kHz and buffer
size, so it doesn't need them.

## Tested on

Arch Linux, kernel 7.2, PipeWire 1.6.8, Proton 10.0-4b, RS_ASIO 0.7.5, WineASIO 1.3.0,
Focusrite Scarlett Solo 4th Gen, dwm (X11), NVIDIA. Other setups are untested; reports
(working or not) are welcome as issues.

## Credits

- [nizo/linux-rocksmith](https://codeberg.org/nizo/linux-rocksmith), the guide this builds on
- [RS_ASIO](https://github.com/mdias/rs_asio) by mdias
- [WineASIO](https://github.com/wineasio/wineasio)
- The workaround in [wineasio#137](https://github.com/wineasio/wineasio/issues/137)

Not affiliated with Ubisoft. Rocksmith is a trademark of Ubisoft Entertainment.

## License

Scripts: MIT (see [LICENSE](LICENSE)). The WineASIO patch is a derivative of WineASIO and is
under WineASIO's license (LGPL-2.1-or-later).
