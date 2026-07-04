#!/usr/bin/env bash
# =============================================================================
#  install.sh  —  One-Shot-Installer für FiveM nativ auf Linux
# =============================================================================
#  Baut den gepatchten FiveM-Client in der GitHub-Cloud (kein Windows nötig)
#  und richtet die komplette Laufzeit (umu + GE-Proton + Rockstar/Registry +
#  fivem://-Handler) automatisch ein.
#
#  Du musst dich nur selbst einloggen:
#    • einmalig  gh auth login        (GitHub CLI, für den Cloud-Build)
#    • im Spiel  Rockstar + Cfx.re    (Konten, kann kein Script übernehmen)
#
#  Ablauf:
#    Schritt 0 – System-Pakete installieren (apt/dnf/pacman/zypper) + gh-Check
#    Teil A – Client in GitHub Actions bauen (Fork, Branch, Workflow, Poll, DL)
#    Teil B – Laufzeit einrichten (umu, GE-Proton, Prefix, RGL, VC++, Handler)
#
#  Idempotent: mehrfach ausführbar. Fertige Schritte werden übersprungen.
#  Syntax-Check:  bash -n scripts/install.sh
# =============================================================================
set -euo pipefail

################################ CONFIG ########################################
# Alles per ENV überschreibbar, z. B.:  GTA_DIR=/pfad ./scripts/install.sh
#
# Zielordner für den Build-Artefakt/Release (enthält am Ende FiveM.exe):
RELEASE_DIR="${RELEASE_DIR:-$HOME/FiveM/release}"
# GTA V *Legacy* Ordner (muss GTA5.exe enthalten). Leer = automatisch suchen.
GTA_DIR="${GTA_DIR:-}"
# Steam-GTA-V-Proton-Prefix (…/steamapps/compatdata/271590/pfx). Leer = suchen.
STEAM_GTAV_PREFIX="${STEAM_GTAV_PREFIX:-}"
# GE-Proton-Installation. Leer = neuestes Release automatisch herunterladen.
PROTONPATH="${PROTONPATH:-}"
# Virtual-Desktop-Auflösung — sichtbare Wine-Dialoge UND Vollbild: MUSS deine native
# Auflösung sein, sonst rendert FiveM kleiner (schwarze Ränder). Auto-erkannt.
VDESK_RES="${VDESK_RES:-$(xrandr 2>/dev/null | grep -oE '[0-9]{3,}x[0-9]{3,}\+0\+0' | grep -oE '^[0-9]+x[0-9]+' | head -1)}"
VDESK_RES="${VDESK_RES:-$(xrandr 2>/dev/null | awk '/\*/{print $1; exit}')}"
VDESK_RES="${VDESK_RES:-1920x1080}"
# Fork-Quelle: UNSER fertiger Fork mit Wine-Patch (Branch wine-win10, ist Default)
# UND dem fork-unabhaengigen Build-Workflow bereits eingebaut -> du forkst nur noch
# und startest den Build. (Basiert auf Gogsi/fivem wine-win10.)
UPSTREAM_REPO="${UPSTREAM_REPO:-seltonmt012/fivem}"
BUILD_BRANCH="${BUILD_BRANCH:-wine-win10}"
DEFAULT_BRANCH="${DEFAULT_BRANCH:-wine-win10}"
WORKFLOW_FILE="${WORKFLOW_FILE:-build-linux-client.yml}"
# Auf true setzen, um Teil A (Cloud-Build) zu überspringen und nur Teil B zu machen:
SKIP_BUILD="${SKIP_BUILD:-false}"
# SKIP_SYSTEM_DEPS=1 überspringt Schritt 0 (System-Pakete via apt/dnf/pacman/zypper).
SKIP_SYSTEM_DEPS="${SKIP_SYSTEM_DEPS:-0}"
###############################################################################

# --help / Usage (vor allem anderen, braucht keine Runtime)
case "${1:-}" in
  -h|--help)
    cat <<'EOF'
install.sh — One-Shot-Installer für FiveM nativ auf Linux

Verwendung:
  ./scripts/install.sh [--help]

Macht in einem Rutsch:
  Schritt 0  System-Pakete installieren (git, curl, python3, winetricks,
             xdotool, x11-utils, imagemagick, cabextract, p7zip, fuse, gh …)
  Teil A     FiveM-Client in GitHub Actions bauen (Fork + Workflow, ~50 Min)
  Teil B     Laufzeit einrichten (umu, GE-Proton, Prefix, Rockstar, VC++, Handler)

Nützliche Umgebungsvariablen:
  SKIP_SYSTEM_DEPS=1   Schritt 0 (System-Pakete) überspringen
  SKIP_BUILD=true      Teil A (Cloud-Build) überspringen, nur Laufzeit einrichten
  RELEASE_DIR=<pfad>   Zielordner für den Client (Default: ~/FiveM/release)
  GTA_DIR=<pfad>       GTA-V-Legacy-Ordner (sonst automatisch gesucht)
  PROTONPATH=<pfad>    GE-Proton-Installation (sonst neuestes Release geladen)

Du loggst dich nur selbst ein: gh auth login (GitHub) sowie im Spiel bei
Rockstar und Cfx.re.
EOF
    exit 0
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BASE="$(cd "$(dirname "$RELEASE_DIR")" 2>/dev/null && pwd || echo "$(dirname "$RELEASE_DIR")")"
PREFIX="$BASE/pfx"

# ----------------------------- Ausgabe-Helfer --------------------------------
c_reset=$'\e[0m'; c_bold=$'\e[1m'; c_grn=$'\e[32m'; c_ylw=$'\e[33m'
c_red=$'\e[31m'; c_blu=$'\e[36m'
step()  { echo; echo "${c_bold}${c_blu}==> $*${c_reset}"; }
info()  { echo "   ${c_grn}•${c_reset} $*"; }
warn()  { echo "   ${c_ylw}⚠${c_reset}  $*" >&2; }
die()   { echo "${c_red}✖ $*${c_reset}" >&2; exit 1; }
ask()   { local p="$1" d="${2:-}" a; read -r -p "   ${c_ylw}?${c_reset} $p " a; echo "${a:-$d}"; }

on_err() { die "Abgebrochen in Zeile $1. Siehe Meldung oben."; }
trap 'on_err $LINENO' ERR

echo "${c_bold}🐧  FiveM-Linux One-Shot-Installer${c_reset}"
echo "    Release-Ziel : $RELEASE_DIR"
echo "    Wine-Prefix  : $PREFIX"

# =============================================================================
#  SCHRITT 0 — System-Abhängigkeiten (Pakete + gh) installieren
# =============================================================================
# Läuft ganz am Anfang, damit auf einem frischen System nichts von Hand nötig
# ist. Ausgelagert nach install-deps-system.sh (distro-unabhängig, idempotent).
# Überspringbar mit SKIP_SYSTEM_DEPS=1.
if [ "$SKIP_SYSTEM_DEPS" = "1" ]; then
  step "Schritt 0 übersprungen (SKIP_SYSTEM_DEPS=1)"
else
  DEPS_SCRIPT="$SCRIPT_DIR/install-deps-system.sh"
  if [ -f "$DEPS_SCRIPT" ]; then
    # In Subshell ausführen, damit dessen 'exit' den Installer nicht beendet;
    # bei echtem Fehler (z. B. gh-Login fehlt) brechen wir aber sauber ab.
    bash "$DEPS_SCRIPT" || die "System-Abhängigkeiten unvollständig (siehe oben). Nach Behebung install.sh erneut starten."
  else
    warn "install-deps-system.sh nicht gefunden — überspringe System-Pakete."
    warn "Stelle sicher, dass git curl python3 winetricks xdotool x11-utils gh installiert sind."
  fi
fi

# =============================================================================
#  TEIL A — Client in der GitHub-Cloud bauen
# =============================================================================
if [ "$SKIP_BUILD" = "true" ]; then
  step "Teil A übersprungen (SKIP_BUILD=true)"
elif [ -f "$RELEASE_DIR/FiveM.exe" ]; then
  step "Teil A übersprungen — FiveM.exe liegt bereits in $RELEASE_DIR"
  info "Neu bauen? Ordner leeren oder SKIP_BUILD=false + Release verschieben."
else
  step "Teil A — Client in GitHub Actions bauen"

  command -v gh  >/dev/null || die "GitHub CLI 'gh' fehlt. Installieren: https://cli.github.com/"
  command -v base64 >/dev/null || die "'base64' fehlt (coreutils)."

  # 1) gh-Login prüfen
  gh auth status >/dev/null 2>&1 || die "Nicht bei GitHub eingeloggt. Bitte:  gh auth login"
  USER_LOGIN="$(gh api user --jq .login)"
  [ -n "$USER_LOGIN" ] || die "Konnte GitHub-Login nicht ermitteln."
  FORK="$USER_LOGIN/fivem"
  info "GitHub-Account: $USER_LOGIN  →  Fork-Ziel: $FORK"

  # 2) Fork anlegen (falls nicht vorhanden)
  if gh repo view "$FORK" >/dev/null 2>&1; then
    info "Fork $FORK existiert bereits — überspringe Fork."
  else
    info "Forke $UPSTREAM_REPO → $FORK …"
    gh repo fork "$UPSTREAM_REPO" --clone=false >/dev/null 2>&1 || \
      gh api -X POST "repos/$UPSTREAM_REPO/forks" >/dev/null
    # Fork ist asynchron — kurz auf Verfügbarkeit warten
    for _ in $(seq 1 30); do
      gh repo view "$FORK" >/dev/null 2>&1 && break
      sleep 3
    done
    gh repo view "$FORK" >/dev/null 2>&1 || die "Fork $FORK wurde nicht rechtzeitig angelegt."
    info "Fork bereit."
  fi

  # 3) Build-Branch im Fork sicherstellen
  if gh api "repos/$FORK/branches/$BUILD_BRANCH" >/dev/null 2>&1; then
    info "Branch '$BUILD_BRANCH' existiert im Fork."
  else
    info "Lege Branch '$BUILD_BRANCH' aus $UPSTREAM_REPO an …"
    SHA="$(gh api "repos/$UPSTREAM_REPO/branches/$BUILD_BRANCH" --jq .commit.sha)"
    [ -n "$SHA" ] || die "Konnte SHA von $UPSTREAM_REPO@$BUILD_BRANCH nicht holen."
    gh api -X POST "repos/$FORK/git/refs" \
      -f ref="refs/heads/$BUILD_BRANCH" -f sha="$SHA" >/dev/null
    info "Branch '$BUILD_BRANCH' → $SHA"
  fi

  # 4) Actions am Fork aktivieren (Forks haben Actions standardmäßig aus)
  info "Aktiviere GitHub Actions am Fork …"
  gh api -X PUT "repos/$FORK/actions/permissions" \
    -F enabled=true -f allowed_actions=all >/dev/null 2>&1 || \
    warn "Konnte Actions-Permissions nicht setzen (evtl. bereits aktiv)."

  # 5) Workflow-Datei in den Fork laden — auf BEIDE Branches.
  #    workflow_dispatch wird nur erkannt, wenn die Datei auch auf dem
  #    Default-Branch (master) liegt. Die hardcodierte Fork-URL im Workflow
  #    ersetzen wir durch die des aktuellen Nutzers.
  SRC_WF="$REPO_DIR/workflow/$WORKFLOW_FILE"
  [ -f "$SRC_WF" ] || die "Workflow-Vorlage fehlt: $SRC_WF"
  TMP_WF="$(mktemp)"
  # 'github.com/<irgendwer>/fivem.git' → aktueller Fork
  sed -E "s#github\.com/[^/\"' ]+/fivem\.git#github.com/$FORK.git#g" "$SRC_WF" > "$TMP_WF"
  WF_B64="$(base64 -w0 "$TMP_WF")"

  put_workflow() {   # $1 = branch
    local branch="$1" path=".github/workflows/$WORKFLOW_FILE" sha
    sha="$(gh api "repos/$FORK/contents/$path?ref=$branch" --jq .sha 2>/dev/null || true)"
    local args=(-X PUT "repos/$FORK/contents/$path"
                -f "message=Add Linux client build workflow"
                -f "content=$WF_B64" -f "branch=$branch")
    [ -n "$sha" ] && args+=(-f "sha=$sha")
    gh api "${args[@]}" >/dev/null
  }
  for b in "$DEFAULT_BRANCH" "$BUILD_BRANCH"; do
    info "Lade $WORKFLOW_FILE nach Branch '$b' …"
    put_workflow "$b" || warn "Upload auf '$b' meldete Fehler (evtl. unverändert)."
  done
  rm -f "$TMP_WF"

  # 6) Build starten
  step "Build wird gestartet (Windows-Runner, ~45–50 Min) …"
  # kleine Wartezeit, damit GitHub die neue Workflow-Datei registriert
  sleep 5
  gh workflow run "$WORKFLOW_FILE" --repo "$FORK" --ref "$BUILD_BRANCH" >/dev/null \
    || die "Konnte Workflow nicht starten. Prüfe Actions-Tab im Fork."

  # Run-ID des frisch gestarteten Laufs ermitteln
  RUN_ID=""
  for _ in $(seq 1 20); do
    RUN_ID="$(gh run list --repo "$FORK" --workflow "$WORKFLOW_FILE" \
                --branch "$BUILD_BRANCH" --limit 1 \
                --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)"
    [ -n "$RUN_ID" ] && [ "$RUN_ID" != "null" ] && break
    sleep 3
  done
  [ -n "$RUN_ID" ] && [ "$RUN_ID" != "null" ] || die "Konnte gestarteten Run nicht finden."
  info "Run-ID: $RUN_ID"
  info "Live-Log:  https://github.com/$FORK/actions/runs/$RUN_ID"

  # 7) Auf Fertigstellung pollen
  step "Warte auf den Build … (das dauert ~45–50 Min, Kaffee ☕)"
  START_TS=$(date +%s)
  while true; do
    read -r STATUS CONCLUSION < <(gh run view "$RUN_ID" --repo "$FORK" \
        --json status,conclusion --jq '"\(.status) \(.conclusion)"' 2>/dev/null || echo "unknown ")
    ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))
    printf "\r   ${c_grn}•${c_reset} Status: %-12s | Laufzeit: %3d min " "$STATUS" "$ELAPSED"
    if [ "$STATUS" = "completed" ]; then
      echo
      if [ "$CONCLUSION" = "success" ]; then
        info "Build erfolgreich ✅"
        break
      else
        warn "Build fehlgeschlagen (conclusion=$CONCLUSION). Letzte Log-Zeilen:"
        gh run view "$RUN_ID" --repo "$FORK" --log-failed 2>/dev/null | tail -60 || \
          gh run view "$RUN_ID" --repo "$FORK" --log 2>/dev/null | tail -60 || true
        die "Cloud-Build fehlgeschlagen. Log oben / im Actions-Tab prüfen."
      fi
    fi
    sleep 30
  done

  # 8) Artefakt herunterladen
  step "Lade Artefakt 'fivem-five-release' → $RELEASE_DIR"
  mkdir -p "$RELEASE_DIR"
  gh run download "$RUN_ID" --repo "$FORK" --name fivem-five-release --dir "$RELEASE_DIR" \
    || die "Download des Artefakts fehlgeschlagen."
  [ -f "$RELEASE_DIR/FiveM.exe" ] || die "FiveM.exe fehlt nach Download — Build-Layout unvollständig?"
  info "FiveM.exe vorhanden ✔"
fi

# =============================================================================
#  TEIL B — Laufzeit einrichten
# =============================================================================
step "Teil B — Linux-Laufzeit einrichten"

[ -f "$RELEASE_DIR/FiveM.exe" ] || die "FiveM.exe nicht in $RELEASE_DIR — erst Teil A (Build) durchlaufen."

# ---- Pfade auto-detecten -----------------------------------------------------
# Kandidaten-Steam-Roots (native, Flatpak, externe Laufwerke)
steam_roots() {
  local r
  for r in \
    "$HOME/.steam/steam" \
    "$HOME/.local/share/Steam" \
    "$HOME/.steam/root" \
    "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam" \
    /run/media/*/*/Steam \
    /media/*/*/Steam \
    /mnt/*/Steam; do
    [ -d "$r/steamapps" ] && echo "$r"
  done
}

# Alle Steam-Library-Ordner (inkl. via libraryfolders.vdf referenzierte)
steam_libraries() {
  local root
  steam_roots | while read -r root; do
    echo "$root"
    local vdf="$root/steamapps/libraryfolders.vdf"
    [ -f "$vdf" ] && grep -oE '"path"[[:space:]]+"[^"]+"' "$vdf" \
      | sed -E 's/.*"path"[[:space:]]+"([^"]+)".*/\1/' | sed 's/\\\\/\//g'
  done | sort -u
}

if [ -z "$GTA_DIR" ]; then
  info "Suche GTA V (Legacy, GTA5.exe) …"
  while read -r lib; do
    cand="$lib/steamapps/common/Grand Theft Auto V"
    if [ -f "$cand/GTA5.exe" ]; then GTA_DIR="$cand"; break; fi
  done < <(steam_libraries)
fi
if [ -z "$GTA_DIR" ] || [ ! -f "$GTA_DIR/GTA5.exe" ]; then
  warn "GTA V (Legacy) nicht automatisch gefunden."
  GTA_DIR="$(ask "Pfad zum GTA-V-Ordner (mit GTA5.exe):" "")"
fi
[ -f "$GTA_DIR/GTA5.exe" ] || die "GTA5.exe nicht in '$GTA_DIR'. Legacy-Edition nötig (nicht Enhanced!)."
info "GTA V: $GTA_DIR"

if [ -z "$STEAM_GTAV_PREFIX" ]; then
  info "Suche Steam-GTA-V-Proton-Prefix (271590) …"
  while read -r lib; do
    cand="$lib/steamapps/compatdata/271590/pfx"
    if [ -d "$cand/drive_c" ]; then STEAM_GTAV_PREFIX="$cand"; break; fi
  done < <(steam_libraries)
fi
if [ -z "$STEAM_GTAV_PREFIX" ] || [ ! -d "$STEAM_GTAV_PREFIX/drive_c" ]; then
  warn "Steam-GTA-V-Prefix nicht gefunden — RGL-Import evtl. unvollständig."
  STEAM_GTAV_PREFIX="$(ask "Pfad zum Prefix (…/compatdata/271590/pfx), leer=überspringen:" "")"
fi
[ -n "$STEAM_GTAV_PREFIX" ] && info "Steam-GTA-V-Prefix: $STEAM_GTAV_PREFIX"

# ---- 1. umu-launcher (self-contained Zipapp) --------------------------------
step "umu-launcher bereitstellen"
UMU_DIR="$BASE/umu"
if [ ! -f "$UMU_DIR/umu/umu-run" ] && ! find "$UMU_DIR" -name umu-run -type f 2>/dev/null | grep -q .; then
  info "Lade umu-launcher-Zipapp …"
  mkdir -p "$UMU_DIR"
  ( cd "$UMU_DIR"
    gh release download --repo Open-Wine-Components/umu-launcher \
       --pattern 'umu-launcher-*-zipapp.tar' --clobber >/dev/null 2>&1 \
     || curl -fSL -o umu.tar "$(curl -fsSL https://api.github.com/repos/Open-Wine-Components/umu-launcher/releases/latest \
          | grep -oE 'https://[^"]+zipapp\.tar' | head -1)"
    tar xf umu-launcher-*-zipapp.tar 2>/dev/null || tar xf umu.tar )
fi
UMU="$(find "$UMU_DIR" -name umu-run -type f 2>/dev/null | head -1)"
[ -n "$UMU" ] || die "umu-run nicht gefunden nach Download."
info "umu-run: $UMU"

# ---- 2. GE-Proton automatisch beschaffen ------------------------------------
step "GE-Proton bereitstellen"
CT_DIR="$HOME/.local/share/Steam/compatibilitytools.d"
mkdir -p "$CT_DIR"
if [ -z "$PROTONPATH" ]; then
  # Neuestes bereits installiertes GE-Proton bevorzugen
  PROTONPATH="$(find "$CT_DIR" -maxdepth 1 -type d -name 'GE-Proton*' 2>/dev/null | sort -V | tail -1)"
fi
if [ -z "$PROTONPATH" ] || [ ! -x "$PROTONPATH/proton" ]; then
  info "Kein GE-Proton gefunden — lade neuestes Release …"
  REL_JSON="$(curl -fsSL https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest)"
  GE_URL="$(echo "$REL_JSON"  | grep -oE 'https://[^"]+GE-Proton[^"]+\.tar\.gz' | head -1)"
  GE_TAG="$(echo "$REL_JSON"  | grep -oE '"tag_name":[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/')"
  [ -n "$GE_URL" ] || die "Konnte GE-Proton-Download-URL nicht ermitteln."
  info "Lade $GE_TAG …"
  TMP_GE="$(mktemp -d)"
  curl -fSL -o "$TMP_GE/geproton.tar.gz" "$GE_URL"
  info "Entpacke nach $CT_DIR …"
  tar -xzf "$TMP_GE/geproton.tar.gz" -C "$CT_DIR"
  rm -rf "$TMP_GE"
  PROTONPATH="$(find "$CT_DIR" -maxdepth 1 -type d -name 'GE-Proton*' | sort -V | tail -1)"
fi
[ -x "$PROTONPATH/proton" ] || die "GE-Proton nicht nutzbar unter '$PROTONPATH'."
info "GE-Proton: $PROTONPATH"

# ---- 3. CitizenFX.ini auf deine GTA-V-Installation zeigen -------------------
step "CitizenFX.ini schreiben"
WINE_PATH="Z:$(echo "$GTA_DIR" | sed 's#/#\\#g')"
printf '[Game]\nIVPath=%s\nPoolSizesIncrease=\nReplaceExecutable=0\n' "$WINE_PATH" > "$RELEASE_DIR/CitizenFX.ini"
info "IVPath=$WINE_PATH"

# ---- 4. Wine-Prefix per erstem umu-Run anlegen ------------------------------
step "Wine-Prefix initialisieren (DXVK/vkd3d)"
export WINEPREFIX="$PREFIX" GAMEID="umu-fivem" STORE="none" PROTONPATH UMU_RUNTIME_UPDATE=0
mkdir -p "$PREFIX"
python3 "$UMU" wineboot --init >/dev/null 2>&1 || warn "wineboot meldete Fehler (oft unkritisch)."
# Auf user.reg warten (wineboot legt es asynchron an)
for _ in $(seq 1 20); do [ -f "$PREFIX/user.reg" ] && break; sleep 1; done
info "Prefix: $PREFIX"

# ---- 5. Rockstar Games Launcher + Registry aus dem Steam-Prefix importieren --
step "Rockstar Games Launcher + Social Club importieren"
if [ -n "$STEAM_GTAV_PREFIX" ] && [ -d "$STEAM_GTAV_PREFIX/drive_c/Program Files/Rockstar Games" ]; then
  for d in "Program Files/Rockstar Games" "Program Files (x86)/Rockstar Games" "ProgramData/Rockstar Games"; do
    if [ -d "$STEAM_GTAV_PREFIX/drive_c/$d" ]; then
      mkdir -p "$PREFIX/drive_c/$(dirname "$d")"
      cp -a "$STEAM_GTAV_PREFIX/drive_c/$d" "$PREFIX/drive_c/$(dirname "$d")/"
      info "kopiert: $d"
    fi
  done
  if [ -d "$STEAM_GTAV_PREFIX/drive_c/users/steamuser/AppData/Local/Rockstar Games" ]; then
    mkdir -p "$PREFIX/drive_c/users/steamuser/AppData/Local"
    cp -a "$STEAM_GTAV_PREFIX/drive_c/users/steamuser/AppData/Local/Rockstar Games" \
          "$PREFIX/drive_c/users/steamuser/AppData/Local/" 2>/dev/null || true
    info "kopiert: AppData/Local/Rockstar Games"
  fi
  # Alle Registry-Sektionen mit "Rockstar" aus system.reg/user.reg mergen
  python3 - "$STEAM_GTAV_PREFIX" "$PREFIX" <<'PY'
import re, sys, os
src, dst = sys.argv[1], sys.argv[2]
def extract(f):
    if not os.path.exists(f): return []
    out = []; L = open(f, encoding='utf-8', errors='replace').readlines(); i = 0
    while i < len(L):
        if L[i].startswith('[') and re.search(r'rockstar', L[i], re.I):
            j = i + 1
            while j < len(L) and not L[j].startswith('['): j += 1
            out.append(''.join(L[i:j]).rstrip() + '\n\n'); i = j
        else:
            i += 1
    return out
for n in ('system.reg', 'user.reg'):
    b = extract(os.path.join(src, n))
    if b and os.path.exists(os.path.join(dst, n)):
        open(os.path.join(dst, n), 'a', encoding='utf-8').write('\n' + ''.join(b))
        print("   • gemergt: %d Rockstar-Keys -> %s" % (len(b), n))
PY
else
  warn "Kein Rockstar Games Launcher im Steam-Prefix gefunden."
  warn "GTA V einmal über Steam (Proton) starten (installiert RGL+Social Club), dann install.sh erneut."
fi

# ---- 6. Wine-Virtual-Desktop aktivieren (Dialoge / Rockstar-Login sichtbar) --
step "Wine-Virtual-Desktop aktivieren ($VDESK_RES)"
python3 - "$PREFIX/user.reg" "$VDESK_RES" <<'PY'
import sys, os
f, res = sys.argv[1], sys.argv[2]
if not os.path.exists(f):
    print("   ⚠ user.reg fehlt – übersprungen"); sys.exit(0)
d = open(f, encoding='utf-8', errors='replace').read(); add = ""
if 'Software\\\\Wine\\\\Explorer]' not in d:
    add += '\n[Software\\\\Wine\\\\Explorer] 1\n"Desktop"="Default"\n'
if 'Software\\\\Wine\\\\Explorer\\\\Desktops]' not in d:
    add += '\n[Software\\\\Wine\\\\Explorer\\\\Desktops] 1\n"Default"="%s"\n' % res
if add:
    open(f, 'a', encoding='utf-8').write(add); print("   • Virtual Desktop %s aktiviert" % res)
else:
    print("   • Virtual Desktop bereits gesetzt")
PY

# ---- 7. VC++-Runtime + corefonts (PFLICHT!) ---------------------------------
step "VC++-Runtime + corefonts installieren (Pflicht – sonst crasht GTA5-GameProcess)"
python3 "$UMU" winetricks -q vcrun2022 vcrun2019 d3dcompiler_47 corefonts \
  || warn "winetricks meldete Fehler — bei Crash manuell nachinstallieren."

# ---- 8. fivem://-Protokoll-Handler registrieren -----------------------------
step "fivem://-Protokoll-Handler registrieren"
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
xdg-mime default fivem-url.desktop x-scheme-handler/fivem >/dev/null 2>&1 || true
info "Handler: ~/.local/bin/fivem-url-handler.sh  (+ fivem-url.desktop)"

# --- desktop launcher icon "FiveM (Linux)" (click to start → menu) -----------
cat > "$HOME/.local/share/applications/fivem.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=FiveM (Linux)
Comment=Selbst gebauter FiveM-Client via GE-Proton
Exec=env RELEASE_DIR=$RELEASE_DIR $SCRIPT_DIR/launch.sh
Icon=applications-games
Terminal=false
Categories=Game;
EOF
# also drop it on the desktop, if a Desktop/Schreibtisch folder exists
for dd in "$HOME/Desktop" "$HOME/Schreibtisch" "$(xdg-user-dir DESKTOP 2>/dev/null)"; do
  [ -d "$dd" ] && cp -f "$HOME/.local/share/applications/fivem.desktop" "$dd/" 2>/dev/null \
    && chmod +x "$dd/fivem.desktop" 2>/dev/null
done
update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
info "Icon: „FiveM (Linux)\" im App-Menü (und auf dem Desktop)"

# =============================================================================
#  FERTIG
# =============================================================================
echo
echo "${c_bold}${c_grn}✅  Installation abgeschlossen!${c_reset}"
echo
echo "   ${c_bold}Starten:${c_reset} Klick auf das Icon ${c_bold}„FiveM (Linux)\"${c_reset} (App-Menü / Desktop)"
echo "     …oder im Terminal:  RELEASE_DIR=$RELEASE_DIR $SCRIPT_DIR/launch.sh"
echo
echo "   ${c_bold}Beim Erststart:${c_reset}"
echo "     • ~2 GB Spieldaten-Cache werden geladen (einmalig)."
echo "     • Die Box „Cfx.re: Insecure mode\" mit ${c_bold}OK/Enter${c_reset} bestätigen."
echo "     • ${c_bold}Steam offen & eingeloggt${c_reset} halten → Rockstar meldet sich automatisch an."
echo "       (sonst einmal manuell im Rockstar-Fenster anmelden – Session bleibt gespeichert)."
echo "     • Im Menü einmal bei ${c_bold}Cfx.re${c_reset} autorisieren (Browser) → fivem://-Handler übernimmt."
echo
