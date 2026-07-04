#!/usr/bin/env bash
# Launch the self-built FiveM client (Gogsi wine-win10) via umu + GE-Proton,
# with automatic self-restart on game-build switch.
#
# Config via env (defaults match setup.sh):
#   RELEASE_DIR  - folder containing FiveM.exe            (default ~/FiveM/release)
#   PROTONPATH   - GE-Proton install                      (default GE-Proton10-34)
#
# Usage: ./launch.sh  [fivem://connect/<server>]

RELEASE_DIR="${RELEASE_DIR:-$HOME/FiveM/release}"
BASE="$(cd "$(dirname "$RELEASE_DIR")" && pwd)"
export WINEPREFIX="${WINEPREFIX:-$BASE/pfx}"
# Use the newest installed GE-Proton (install.sh downloads whatever is latest, so
# don't hardcode a version — auto-pick the highest GE-Proton* dir).
_CT="$HOME/.local/share/Steam/compatibilitytools.d"
PROTONPATH="${PROTONPATH:-$(find "$_CT" -maxdepth 1 -type d -name 'GE-Proton*' 2>/dev/null | sort -V | tail -1)}"
export PROTONPATH="${PROTONPATH:-$_CT/GE-Proton10-34}"
export GAMEID="umu-fivem"
export STORE="none"
export PROTON_VERB="run"
export UMU_RUNTIME_UPDATE=0

export DISPLAY="${DISPLAY:-:0}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# Do NOT set SteamAppId: it makes steam_api64.dll spam SteamAPI_Init() for a missing
# steamclient64.dll and destabilises the GTA5 GameProcess. Rockstar sign-in persists
# via the saved RGL session (open Steam once, logged in, if you ever need to re-auth).
# Steam install path — prefer native, fall back to Flatpak, then a sane default.
if [ -z "${STEAM_COMPAT_CLIENT_INSTALL_PATH:-}" ]; then
  for _s in "$HOME/.steam/steam" "$HOME/.local/share/Steam" \
            "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
    [ -d "$_s" ] && { STEAM_COMPAT_CLIENT_INSTALL_PATH="$_s"; break; }
  done
fi
export STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_COMPAT_CLIENT_INSTALL_PATH:-$HOME/.steam/steam}"

# Quiet by default. Debug crashes with: WINEDEBUG=+seh,+tid PROTON_LOG=1 ./launch.sh
export PROTON_LOG="${PROTON_LOG:-0}"
export WINEDEBUG="${WINEDEBUG:-fixme-all}"

UMU="$(find "$BASE/umu" -name umu-run -type f 2>/dev/null | head -1)"
[ -z "$UMU" ] && UMU="$(command -v umu-run)"
[ -z "$UMU" ] && { echo "umu-run not found (run setup.sh first)"; exit 1; }

SWITCH_FILE="${XDG_RUNTIME_DIR}/fivem_switchcl_url"
cd "$RELEASE_DIR" || exit 1
CONNECT_ARG="$1"

# --- pre-launch cleanup: kill stale FiveM/wine processes so every start is clean ---
# (Leftover crashed instances leak X11 connections and make the next launch hang.)
for pat in 'release\\FiveM.exe' 'FiveM_GTAProcess' 'FiveM_ROSLauncher' 'FiveM_ROSService' \
           'FiveM_DumpServer' 'GTA5.exe' 'b3[0-9][0-9][0-9]_GameProc' '-switchcl' \
           'Launcher.exe' 'RockstarService.exe' 'SocialClubHelper' 'umu-fivem'; do
  pkill -9 -f "$pat" 2>/dev/null
done
sleep 1
rm -f "$WINEPREFIX/drive_c/Program Files (x86)/Steam/steamclient64.dll" \
      "$WINEPREFIX/drive_c/Program Files (x86)/Steam/steamclient.dll" 2>/dev/null

# --- force native render resolution + fullscreen in FiveM's own settings -------
# FiveM persists ScreenWidth/Height in gta5_settings.xml; if it was ever created at
# a smaller virtual-desktop size it stays there (black bars). Patch it to native.
_GSET="$WINEPREFIX/drive_c/users/steamuser/AppData/Roaming/CitizenFX/gta5_settings.xml"
if [ -f "$_GSET" ]; then
  _NRES="$(xrandr 2>/dev/null | grep -oE '[0-9]{3,}x[0-9]{3,}\+0\+0' | grep -oE '^[0-9]+x[0-9]+' | head -1)"
  _NRES="${_NRES:-$(xrandr 2>/dev/null | awk '/\*/{print $1; exit}')}"
  if [ -n "$_NRES" ]; then
    _NW="${_NRES%x*}"; _NH="${_NRES#*x}"
    sed -i \
      -e "s|<ScreenWidth value=\"[0-9]*\" />|<ScreenWidth value=\"$_NW\" />|" \
      -e "s|<ScreenHeight value=\"[0-9]*\" />|<ScreenHeight value=\"$_NH\" />|" \
      -e "s|<Windowed value=\"[0-9]*\" />|<Windowed value=\"0\" />|" "$_GSET" 2>/dev/null
  fi
fi

# --- auto-dismiss the "Insecure mode" dialog + make the game window fullscreen ---
# (Fullscreen needs BOTH: a native-resolution virtual desktop — set by setup.sh —
#  and the window flagged fullscreen here, so there is no title bar / black border.)
if command -v xdotool >/dev/null 2>&1; then
  (
    fs_done=""
    for _ in $(seq 1 120); do
      iw=$(xdotool search --name 'Insecure' 2>/dev/null | head -1)
      [ -n "$iw" ] && xdotool key --window "$iw" Return 2>/dev/null
      if [ -z "$fs_done" ] && command -v wmctrl >/dev/null 2>&1; then
        gw=$(xdotool search --name 'Wine Desktop' 2>/dev/null | head -1)
        [ -z "$gw" ] && gw=$(xdotool search --name 'FiveM® by Cfx.re' 2>/dev/null | head -1)
        [ -n "$gw" ] && wmctrl -i -r "$gw" -b add,fullscreen 2>/dev/null && fs_done=1
      fi
      sleep 2
    done
  ) >/dev/null 2>&1 &
  DISMISS=$!
fi

while true; do
  rm -f "$SWITCH_FILE"
  # FiveM relaunches itself with `-switchcl:<h> "fivem://connect/<srv>"` for a game-build
  # switch; umu kills that child, so we capture the URL here and relaunch it ourselves.
  (
    while true; do
      url=$(pgrep -af -- '-switchcl' 2>/dev/null | grep -oE 'fivem://connect/[^"[:space:]]+' | head -1)
      [ -n "$url" ] && echo "$url" > "$SWITCH_FILE"
      pgrep -f 'release\\FiveM.exe' >/dev/null 2>&1 || { sleep 1; pgrep -f 'release\\FiveM.exe' >/dev/null 2>&1 || break; }
      sleep 0.3
    done
  ) &
  WATCHER=$!

  python3 "$UMU" "$RELEASE_DIR/FiveM.exe" $CONNECT_ARG
  kill "$WATCHER" 2>/dev/null; wait "$WATCHER" 2>/dev/null

  if [ -s "$SWITCH_FILE" ]; then
    CONNECT_ARG="$(cat "$SWITCH_FILE")"
    echo "[launch.sh] game-build switch -> relaunching into: $CONNECT_ARG"
    sleep 2; continue
  fi
  break
done
[ -n "${DISMISS:-}" ] && kill "$DISMISS" 2>/dev/null
