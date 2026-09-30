#!/bin/bash
# Rocksmith 2014 Remastered (Steam) on Linux with PipeWire:
#   guitar -> PipeWire (pipewire-jack) -> WineASIO (patched) -> RS_ASIO -> Rocksmith
#
# Usage: ./setup.sh [--tiling-wm] [--rebuild]
#   --tiling-wm   enable the focus workaround for dwm/i3/etc. (game starts frozen until refocused)
#   --rebuild     rebuild wineasio even if a build already exists
# Non-interactive: set RLA_INPUT_PORT (e.g. alsa_input...:capture_MONO) and RLA_OUTPUT_NODE.
#
# Safe to re-run (e.g. after Steam updates Proton 10 and wipes wineasio from it).
set -euo pipefail

APPID=221680
RS_ASIO_VERSION=0.7.5
RS_ASIO_SHA256=067088514ab0778c2f5ba04b22f9ad8566724b8dc45a50dfbc69581f5797d319
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/rocksmith-linux-asio"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/rocksmith-linux-asio"
BIN_DIR="$HOME/.local/bin"

TILING_WM=0 REBUILD=0
for a in "$@"; do
    case "$a" in
        --tiling-wm) TILING_WM=1 ;;
        --rebuild)   REBUILD=1 ;;
        -h|--help)   sed -n '2,11p' "$0"; exit 0 ;;
        *) echo "unknown option: $a" >&2; exit 2 ;;
    esac
done

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- Steam, game, Proton
STEAM=""
for d in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.steam/root"; do
    [ -d "$d/steamapps" ] && { STEAM="$(readlink -f "$d")"; break; }
done
[ -n "$STEAM" ] || { [ -d "$HOME/.var/app/com.valvesoftware.Steam" ] && die "Flatpak Steam isn't supported (its sandbox blocks the audio setup). Use your distro's native Steam package."; die "Steam not found."; }

libraries=("$STEAM")
if [ -f "$STEAM/steamapps/libraryfolders.vdf" ]; then
    while IFS= read -r p; do libraries+=("$p"); done < <(sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"/\1/p' "$STEAM/steamapps/libraryfolders.vdf")
fi

LIB="" PROTON=""
for l in "${libraries[@]}"; do
    [ -z "$LIB" ] && [ -f "$l/steamapps/appmanifest_$APPID.acf" ] && LIB="$l"
    [ -z "$PROTON" ] && [ -x "$l/steamapps/common/Proton 10.0/proton" ] && PROTON="$l/steamapps/common/Proton 10.0"
done
[ -n "$LIB" ] || die "Rocksmith 2014 isn't installed in any Steam library."
GAME="$LIB/steamapps/common/Rocksmith2014"
PREFIX="$LIB/steamapps/compatdata/$APPID"
[ -n "$PROTON" ] || die "Proton 10.0 not found. In Steam, search your Library for 'Proton 10.0' and install it.
  (Proton 11 / Experimental / GE-Proton 11 trip Rocksmith's copy protection: 'A debugger has been found'.)"
[ -f "$PREFIX/pfx/system.reg" ] || die "Rocksmith's Proton prefix doesn't exist yet. In Steam set Rocksmith -> Properties -> Compatibility -> 'Proton 10.0', launch the game once until the first screen, quit, then re-run this."
pgrep -f '^Z:.*Rocksmith2014\.exe' >/dev/null && die "Rocksmith is running. Quit it first."
say "Steam: $STEAM"
say "Game:  $GAME"
say "Proton: $PROTON"

# ---------------------------------------------------------------- system requirements
command -v pw-link >/dev/null || die "pw-link not found: this needs PipeWire (install your distro's pipewire package)."

libjack32=""
for f in /usr/lib32/libjack.so.0 /usr/lib/i386-linux-gnu/libjack.so.0 /usr/lib/i386-linux-gnu/pipewire-0.3/jack/libjack.so.0 /usr/lib/libjack.so.0; do
    [ -e "$f" ] || continue
    if command -v file >/dev/null; then file -L "$f" | grep -q '32-bit' || continue
    elif [ "$f" = /usr/lib/libjack.so.0 ]; then continue; fi   # can't tell its arch without `file`
    libjack32="$f"; break
done
if [ -z "$libjack32" ]; then
    warn "32-bit JACK library (from pipewire-jack) not found. Install it, e.g.:
    Arch:          sudo pacman -S lib32-pipewire-jack
    Debian/Ubuntu: sudo dpkg --add-architecture i386 && sudo apt install pipewire-jack:i386
    Fedora:        sudo dnf install pipewire-jack-audio-connection-kit-libs.i686"
    missing=1
fi

memlock="$(ulimit -l)"
if [ "$memlock" != unlimited ] && [ "$memlock" -lt 262144 ]; then
    warn "Your locked-memory limit is ${memlock} KB. Too low for real-time audio: the game crashes with
    'create_view: Assertion ... page_mask' as soon as audio starts. Give your user real-time privileges, e.g.:
    Arch:          sudo pacman -S realtime-privileges && sudo usermod -aG realtime,audio \$USER
    Debian/Ubuntu: sudo usermod -aG audio \$USER   (check /etc/security/limits.d/audio.conf exists)
    Fedora:        sudo usermod -aG pipewire \$USER
    then log out and back in (a full re-login or reboot; restarting only the X session isn't enough)."
    missing=1
fi
[ "${missing:-0}" = 1 ] && die "Fix the above, then re-run ./setup.sh"

# ---------------------------------------------------------------- build wineasio
WINEASIO_OUT="$DATA_DIR/wineasio"
if [ "$REBUILD" = 1 ] || [ ! -f "$WINEASIO_OUT/wineasio32.dll.so" ]; then
    ENGINE="$(command -v podman || command -v docker || true)"
    [ -n "$ENGINE" ] || die "Need podman or docker to build wineasio (install podman: it runs rootless)."
    say "Building patched 32-bit wineasio against Wine 10 with $(basename "$ENGINE") (first time takes a few minutes)"
    "$ENGINE" build -t rocksmith-linux-asio-wineasio -f "$REPO_DIR/Containerfile" "$REPO_DIR"
    mkdir -p "$WINEASIO_OUT"
    "$ENGINE" run --rm -v "$WINEASIO_OUT:/host:Z" rocksmith-linux-asio-wineasio sh -c 'cp /out/* /host/'
fi
[ -f "$WINEASIO_OUT/wineasio32.dll.so" ] || die "wineasio build failed."

say "Installing wineasio into Proton 10 and registering it in Rocksmith's prefix"
install -m644 "$WINEASIO_OUT/wineasio32.dll.so" "$PROTON/files/lib/wine/i386-unix/wineasio32.dll.so"
install -m644 "$WINEASIO_OUT/wineasio32.dll"    "$PROTON/files/lib/wine/i386-windows/wineasio32.dll"

proton_run() {
    env STEAM_COMPAT_DATA_PATH="$PREFIX" STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM" \
        SteamAppId=$APPID SteamGameId=$APPID WINEDEBUG=-all "$PROTON/proton" run "$@" >/dev/null 2>&1
}
proton_run 'C:\windows\syswow64\regsvr32.exe' /s wineasio32.dll || true
WINEPREFIX="$PREFIX/pfx" "$PROTON/files/bin/wineserver" -w || true   # registry hits disk when wineserver exits
grep -q 'Wow6432Node\\\\ASIO\\\\WineASIO' "$PREFIX/pfx/system.reg" || die "Registering wineasio in the prefix failed."
if [ "$TILING_WM" = 1 ]; then
    # Let the WM focus Wine windows normally instead of relying on WM_TAKE_FOCUS
    proton_run reg add 'HKCU\Software\Wine\X11 Driver' /v UseTakeFocus /t REG_SZ /d N /f || true
    WINEPREFIX="$PREFIX/pfx" "$PROTON/files/bin/wineserver" -w || true
fi

# ---------------------------------------------------------------- RS_ASIO
say "Installing RS_ASIO $RS_ASIO_VERSION"
zip="$DATA_DIR/rs_asio-$RS_ASIO_VERSION.zip"
mkdir -p "$DATA_DIR"
[ -f "$zip" ] || curl -fL --retry 3 -o "$zip" "https://github.com/mdias/rs_asio/releases/download/v$RS_ASIO_VERSION/release-$RS_ASIO_VERSION.zip"
echo "$RS_ASIO_SHA256  $zip" | sha256sum -c --quiet - || { rm -f "$zip"; die "RS_ASIO download checksum mismatch."; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
python3 -m zipfile -e "$zip" "$tmp"
cp "$tmp/avrt.dll" "$tmp/RS_ASIO.dll" "$GAME/"
[ -f "$GAME/RS_ASIO.ini" ] && cp -n "$GAME/RS_ASIO.ini" "$GAME/RS_ASIO.ini.bak"
# point the output and the first input at WineASIO (the ini uses CRLF line endings)
sed -e '/^\[Asio.Output\]/,/^\[/{s/^Driver=\r\?$/Driver=WineASIO\r/}' \
    -e '/^\[Asio.Input.0\]/,/^\[/{s/^Driver=\r\?$/Driver=WineASIO\r/}' \
    "$tmp/RS_ASIO.ini" > "$GAME/RS_ASIO.ini"

# RS_ASIO needs exclusive mode (the game's default)
if [ -f "$GAME/Rocksmith.ini" ]; then
    sed -i -e 's/^ExclusiveMode=0/ExclusiveMode=1/' -e 's/^Win32UltraLowLatencyMode=0/Win32UltraLowLatencyMode=1/' "$GAME/Rocksmith.ini"
fi

# ---------------------------------------------------------------- pick audio devices
pick() {   # pick <prompt> <items...>  -> echoes chosen item
    local prompt="$1"; shift
    [ $# -gt 0 ] || { echo ""; return; }
    local i=1; for it in "$@"; do printf '  %2d) %s\n' "$i" "$it" >&2; i=$((i+1)); done
    local n; while :; do
        read -rp "$prompt [1-$#]: " n </dev/tty
        [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le $# ] && { echo "${!n}"; return; }
    done
}
say "Choose the audio input your guitar is plugged into"
mapfile -t inports < <(pw-link -o | grep -E '^alsa_input[^ ]*:capture_' | grep -v monitor)
[ ${#inports[@]} -gt 0 ] || die "No PipeWire capture ports found."
INPUT_PORT="${RLA_INPUT_PORT:-$(pick "Guitar input" "${inports[@]}")}"
INPUT_NODE="${INPUT_PORT%%:*}"

say "Choose where the game's sound should play"
mapfile -t sinks < <(pw-link -i | grep -E '^alsa_output[^ ]*:playback_FL$' | sed 's/:playback_FL$//')
[ ${#sinks[@]} -gt 0 ] || die "No stereo PipeWire outputs found."
OUT_NODE="${RLA_OUTPUT_NODE:-$(pick "Output" "${sinks[@]}")}"

mkdir -p "$CONFIG_DIR"
cfg="$CONFIG_DIR/config"
INPUT_VOLUME="$( [ -f "$cfg" ] && sed -n 's/^INPUT_VOLUME=//p' "$cfg" | tr -d '"' || true)"
cat > "$cfg" <<EOF
# rocksmith-linux-asio config (read by rocksmith-launch on every game launch)
INPUT_PORT="$INPUT_PORT"
INPUT_NODE="$INPUT_NODE"
OUTPUT_PORT_L="$OUT_NODE:playback_FL"
OUTPUT_PORT_R="$OUT_NODE:playback_FR"
# Rocksmith expects Real Tone Cable levels. If notes don't register, raise this (e.g. 160% = +12 dB)
# rather than RS_ASIO's SoftwareMasterVolumePercent. Empty = leave the input volume alone.
INPUT_VOLUME="${INPUT_VOLUME:-}"
# 1 = refocus the game once after it goes fullscreen (tiling WMs)
REFOCUS=$TILING_WM
# extra WINEDLLOVERRIDES, e.g. "xinput1_3=n,b" for RSMods
EXTRA_DLL_OVERRIDES=""
PIPEWIRE_LATENCY="256/48000"
EOF

mkdir -p "$BIN_DIR"
install -m755 "$REPO_DIR/bin/rocksmith-launch" "$REPO_DIR/bin/rocksmith-refocus" "$BIN_DIR/"

say "Done. Config: $cfg"
cat <<EOF

Now in Steam, right-click Rocksmith 2014 -> Properties:
  Compatibility:  force "Proton 10.0"
  Launch options: $BIN_DIR/rocksmith-launch %command%

In the game choose "Real Tone Cable". If calibration never finishes, pick "Disconnected"
to skip it and set Tools -> Options -> Input Gain instead (see README).
Re-run ./setup.sh whenever Steam updates Proton 10.
EOF
