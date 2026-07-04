#!/usr/bin/env bash
# Forwards a fivem:// URL (Cfx.re auth callback OR fivem://connect/<server>) to FiveM.
# Placeholders (__UMU__ etc.) are filled in by setup.sh.
URL="$1"
export WINEPREFIX="__PREFIX__"
export GAMEID="umu-fivem"
export STORE="none"
export PROTONPATH="__PROTON__"
export UMU_RUNTIME_UPDATE=0
export PROTON_VERB="run"
export DISPLAY=":0"
export WAYLAND_DISPLAY="wayland-0"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
export WINEDEBUG="-all"
logger -t fivem-url "handling: $URL"
exec python3 "__UMU__" "__RELEASE__/FiveM.exe" "$URL"
