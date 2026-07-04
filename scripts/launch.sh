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
export PROTONPATH="${PROTONPATH:-$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton10-34}"
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
export STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_COMPAT_CLIENT_INSTALL_PATH:-$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam}"

# Quiet by default. Debug crashes with: WINEDEBUG=+seh,+tid PROTON_LOG=1 ./launch.sh
export PROTON_LOG="${PROTON_LOG:-0}"
export WINEDEBUG="${WINEDEBUG:-fixme-all}"

UMU="$(find "$BASE/umu" -name umu-run -type f 2>/dev/null | head -1)"
[ -z "$UMU" ] && UMU="$(command -v umu-run)"
[ -z "$UMU" ] && { echo "umu-run not found (run setup.sh first)"; exit 1; }

SWITCH_FILE="${XDG_RUNTIME_DIR}/fivem_switchcl_url"
cd "$RELEASE_DIR" || exit 1
CONNECT_ARG="$1"

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
