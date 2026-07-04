#!/usr/bin/env bash
# One-time runtime setup for the self-built FiveM client on Linux (umu + GE-Proton).
# Edit the CONFIG block, then run.  Re-runnable (idempotent-ish).
set -e

################################ CONFIG ########################################
# Where you extracted the CI build artifact (must contain FiveM.exe):
RELEASE_DIR="${RELEASE_DIR:-$HOME/FiveM/release}"
# Your GTA V *Legacy* folder (must contain GTA5.exe):
GTA_DIR="${GTA_DIR:-$HOME/.steam/steam/steamapps/common/Grand Theft Auto V}"
# Your Steam GTA V Proton prefix (has Rockstar Games Launcher installed).
# Usually: <SteamLibrary>/steamapps/compatdata/271590/pfx
STEAM_GTAV_PREFIX="${STEAM_GTAV_PREFIX:-$HOME/.steam/steam/steamapps/compatdata/271590/pfx}"
# GE-Proton install (download from GloriousEggroll/proton-ge-custom releases):
PROTONPATH="${PROTONPATH:-$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton10-34}"
# Virtual-desktop resolution — makes Wine dialogs/Rockstar-login visible AND
# determines fullscreen: it MUST match your native resolution, otherwise FiveM
# renders smaller and you get black bars. Auto-detected from your primary display.
VDESK_RES="${VDESK_RES:-$(xrandr 2>/dev/null | grep -oE '[0-9]{3,}x[0-9]{3,}\+0\+0' | grep -oE '^[0-9]+x[0-9]+' | head -1)}"
VDESK_RES="${VDESK_RES:-$(xrandr 2>/dev/null | awk '/\*/{print $1; exit}')}"
VDESK_RES="${VDESK_RES:-1920x1080}"
###############################################################################

BASE="$(cd "$(dirname "$RELEASE_DIR")" && pwd)"
PREFIX="$BASE/pfx"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ">> release: $RELEASE_DIR"
echo ">> prefix : $PREFIX"
[ -f "$RELEASE_DIR/FiveM.exe" ] || { echo "!! FiveM.exe not found in RELEASE_DIR"; exit 1; }
[ -f "$GTA_DIR/GTA5.exe" ]      || { echo "!! GTA5.exe not found in GTA_DIR (Legacy edition!)"; exit 1; }

# --- 1. umu-launcher (self-contained zipapp) --------------------------------
UMU_DIR="$BASE/umu"
if [ ! -f "$UMU_DIR/umu/umu-run" ]; then
  echo ">> downloading umu-launcher zipapp"
  mkdir -p "$UMU_DIR"; cd "$UMU_DIR"
  gh release download --repo Open-Wine-Components/umu-launcher \
     --pattern 'umu-launcher-*-zipapp.tar' --clobber 2>/dev/null \
     || curl -fSL -o umu.tar "$(curl -fsSL https://api.github.com/repos/Open-Wine-Components/umu-launcher/releases/latest | grep -oE 'https://[^"]+zipapp.tar' | head -1)"
  tar xf umu-launcher-*-zipapp.tar 2>/dev/null || tar xf umu.tar
fi
UMU="$(find "$UMU_DIR" -name umu-run -type f | head -1)"
echo ">> umu-run: $UMU"

# --- 2. CitizenFX.ini pointing at your GTA V --------------------------------
WINE_PATH="Z:$(echo "$GTA_DIR" | sed 's#/#\\#g')"
printf '[Game]\nIVPath=%s\n' "$WINE_PATH" > "$RELEASE_DIR/CitizenFX.ini"
echo ">> wrote CitizenFX.ini (IVPath=$WINE_PATH)"

# --- 3. first umu run to create the prefix ----------------------------------
export WINEPREFIX="$PREFIX" GAMEID=umu-fivem STORE=none PROTONPATH UMU_RUNTIME_UPDATE=0
mkdir -p "$PREFIX"
echo ">> initialising Wine prefix (creates DXVK/vkd3d)"
python3 "$UMU" wineboot --init 2>/dev/null || true

# --- 4. copy Rockstar Games Launcher + registry from the Steam GTA V prefix --
if [ -d "$STEAM_GTAV_PREFIX/drive_c/Program Files/Rockstar Games" ]; then
  echo ">> importing Rockstar Games Launcher + Social Club from Steam prefix"
  for d in "Program Files/Rockstar Games" "Program Files (x86)/Rockstar Games" "ProgramData/Rockstar Games"; do
    [ -d "$STEAM_GTAV_PREFIX/drive_c/$d" ] && cp -a "$STEAM_GTAV_PREFIX/drive_c/$d" "$PREFIX/drive_c/$(dirname "$d")/"
  done
  cp -a "$STEAM_GTAV_PREFIX/drive_c/users/steamuser/AppData/Local/Rockstar Games" \
        "$PREFIX/drive_c/users/steamuser/AppData/Local/" 2>/dev/null || true
  python3 - "$STEAM_GTAV_PREFIX" "$PREFIX" <<'PY'
import re,sys
src,dst=sys.argv[1],sys.argv[2]
def extract(f):
    out=[]; L=open(f,encoding='utf-8',errors='replace').readlines(); i=0
    while i<len(L):
        if L[i].startswith('[') and re.search(r'rockstar',L[i],re.I):
            j=i+1
            while j<len(L) and not L[j].startswith('['): j+=1
            out.append(''.join(L[i:j]).rstrip()+'\n\n'); i=j
        else: i+=1
    return out
for n in ('system.reg','user.reg'):
    b=extract(f"{src}/{n}")
    if b: open(f"{dst}/{n}",'a',encoding='utf-8').write('\n'+''.join(b)); print("merged",len(b),"Rockstar keys ->",n)
PY
else
  echo "!! Steam GTA V prefix has no Rockstar Games Launcher."
  echo "   Run GTA V once via Steam (Proton) so it installs RGL + Social Club, then re-run."
fi

# --- 5. Wine virtual desktop (so dialogs / Rockstar login are visible) -------
python3 - "$PREFIX/user.reg" "$VDESK_RES" <<'PY'
import sys
f,res=sys.argv[1],sys.argv[2]
d=open(f,encoding='utf-8',errors='replace').read(); add=""
if 'Software\\\\Wine\\\\Explorer]' not in d:
    add+='\n[Software\\\\Wine\\\\Explorer] 1\n"Desktop"="Default"\n'
if 'Software\\\\Wine\\\\Explorer\\\\Desktops]' not in d:
    add+=f'\n[Software\\\\Wine\\\\Explorer\\\\Desktops] 1\n"Default"="{res}"\n'
if add: open(f,'a',encoding='utf-8').write(add); print("enabled virtual desktop",res)
PY

# --- 6. VC++ runtimes (REQUIRED - GTA5 GameProcess crashes without them) -----
echo ">> installing VC++ runtimes (vcrun2022/2019) - required"
python3 "$UMU" winetricks -q vcrun2022 vcrun2019 d3dcompiler_47 corefonts || true

# --- 7. register fivem:// protocol handler ----------------------------------
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
sed "s#__UMU__#$UMU#g; s#__PREFIX__#$PREFIX#g; s#__PROTON__#$PROTONPATH#g; s#__RELEASE__#$RELEASE_DIR#g" \
    "$SCRIPT_DIR/fivem-url-handler.sh" > "$HOME/.local/bin/fivem-url-handler.sh"
chmod +x "$HOME/.local/bin/fivem-url-handler.sh"
cat > "$HOME/.local/share/applications/fivem-url.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=FiveM URL Handler
Exec=$HOME/.local/bin/fivem-url-handler.sh %u
MimeType=x-scheme-handler/fivem;
NoDisplay=true
Terminal=false
EOF
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
xdg-mime default fivem-url.desktop x-scheme-handler/fivem 2>/dev/null || true

echo ""
echo ">> DONE. Launch with:  RELEASE_DIR=$RELEASE_DIR $SCRIPT_DIR/launch.sh"
echo ">> First run downloads ~2GB game cache. Confirm the 'Insecure mode' box (OK)."
echo ">> Open Steam (logged in) for automatic Rockstar sign-in, or sign in manually once."
