#!/usr/bin/env bash
set -x
BASE=/run/media/seltonmt/tb2/FiveM-build
export WINEPREFIX="$BASE/pfx"
export GAMEID="umu-fivem"
export STORE="none"
export PROTONPATH="$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton10-34"
export UMU_RUNTIME_UPDATE=0
export DISPLAY=":0"
export WAYLAND_DISPLAY="wayland-0"
export XDG_RUNTIME_DIR="/run/user/1000"
UMU=/tmp/claude-1000/-home-seltonmt/6323a575-b309-45ce-a5c1-d7e53550f648/scratchpad/umu/umu/umu-run
# GTA V needs the VC++ runtimes; also d3dcompiler for DXVK shader fallback
python3 "$UMU" winetricks -q vcrun2022 vcrun2019 d3dcompiler_47
echo "=== winetricks deps done rc=$? ==="
