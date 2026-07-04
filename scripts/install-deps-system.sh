#!/usr/bin/env bash
# =============================================================================
#  install-deps-system.sh  —  System-Abhängigkeiten für FiveM-Linux
# =============================================================================
#  Installiert ALLE System-Pakete, die install.sh / launch.sh brauchen, auf
#  einem frischen System — distro-unabhängig (apt / dnf / pacman / zypper).
#
#  Deckt ab:
#    • Basis-Tools        git curl wget tar python3
#    • Wine/Proton-Deps   winetricks cabextract p7zip imagemagick
#    • Fenster-Steuerung  xdotool  + x11-utils + wmctrl/xrandr (Fenster/Auflösung — von launch.sh genutzt)
#    • AppImage/umu       fuse (libfuse2)
#    • GitHub CLI 'gh'    (für den Cloud-Build) inkl. Login-Check
#    • 32-bit/multiarch   (Debian/Ubuntu: dpkg --add-architecture i386)
#
#  Idempotent: mehrfach ausführbar, überspringt bereits Erledigtes.
#  Wird von install.sh automatisch am Anfang aufgerufen; kann aber auch
#  eigenständig laufen:   ./scripts/install-deps-system.sh
#
#  Flags / ENV:
#    SKIP_SYSTEM_DEPS=1   diesen Schritt komplett überspringen
#    SKIP_GH_AUTH=1       gh-Login-Prüfung überspringen (nicht abbrechen)
#    ASSUME_YES=1         Paketmanager ohne Rückfrage (-y) laufen lassen (Default)
#    --help               diese Hilfe zeigen
#
#  Syntax-Check:  bash -n scripts/install-deps-system.sh
# =============================================================================
set -euo pipefail

# ----------------------------- Ausgabe-Helfer --------------------------------
c_reset=$'\e[0m'; c_bold=$'\e[1m'; c_grn=$'\e[32m'; c_ylw=$'\e[33m'
c_red=$'\e[31m'; c_blu=$'\e[36m'
step()  { echo; echo "${c_bold}${c_blu}==> $*${c_reset}"; }
info()  { echo "   ${c_grn}•${c_reset} $*"; }
warn()  { echo "   ${c_ylw}⚠${c_reset}  $*" >&2; }
die()   { echo "${c_red}✖ $*${c_reset}" >&2; exit 1; }

usage() {
  cat <<EOF
${c_bold}install-deps-system.sh${c_reset} — System-Abhängigkeiten für FiveM-Linux

Verwendung:
  ./scripts/install-deps-system.sh [--help]

Installiert git, curl, wget, tar, python3, winetricks, xdotool, x11-utils, wmctrl, xrandr,
imagemagick, cabextract, p7zip, fuse und die GitHub CLI 'gh' — passend zu
deiner Distro (apt / dnf / pacman / zypper). Aktiviert auf Debian/Ubuntu die
i386-Architektur (multiarch) für Wine/Proton und prüft am Ende 'gh auth status'.

Umgebungsvariablen:
  SKIP_SYSTEM_DEPS=1   diesen Schritt komplett überspringen
  SKIP_GH_AUTH=1       gh-Login-Prüfung überspringen (nicht abbrechen)
  ASSUME_YES=0         Paketmanager interaktiv laufen lassen (Default: automatisch)
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac

# Early-out, damit auch der Aufruf aus install.sh sauber überspringt.
if [ "${SKIP_SYSTEM_DEPS:-0}" = "1" ]; then
  step "System-Abhängigkeiten übersprungen (SKIP_SYSTEM_DEPS=1)"
  exit 0
fi

ASSUME_YES="${ASSUME_YES:-1}"

# ----------------------------- sudo-Helfer -----------------------------------
# root -> kein sudo nötig; sonst sudo verwenden falls vorhanden; sonst abbrechen.
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    die "Weder root noch 'sudo' verfügbar. Bitte als root ausführen oder sudo installieren."
  fi
fi
run_root() { $SUDO "$@"; }

# ----------------------------- Distro erkennen -------------------------------
step "System-Abhängigkeiten installieren"

PM=""
if   command -v apt-get >/dev/null 2>&1; then PM="apt"
elif command -v dnf     >/dev/null 2>&1; then PM="dnf"
elif command -v pacman  >/dev/null 2>&1; then PM="pacman"
elif command -v zypper  >/dev/null 2>&1; then PM="zypper"
else
  warn "Kein unterstützter Paketmanager (apt/dnf/pacman/zypper) gefunden."
  warn "Bitte diese Pakete manuell installieren:"
  warn "  git curl wget tar python3 winetricks xdotool x11-utils wmctrl xrandr imagemagick"
  warn "  cabextract p7zip fuse  +  GitHub CLI (gh)"
  die  "Automatische Installation nicht möglich — manuell nachholen und erneut starten."
fi
info "Paketmanager erkannt: ${c_bold}$PM${c_reset}"

# yes-Flag pro Manager
YES=""
[ "$ASSUME_YES" = "1" ] && YES="-y"

# ----------------------------- Paket-Mapping ---------------------------------
# Reihenfolge/Namen pro Distro gemappt. 'gh' wird separat behandelt (Repo-Setup
# bei apt). Bei apt heisst libfuse2 je nach Version anders -> unten abgefangen.
case "$PM" in
  apt)
    # wmctrl + x11-xserver-utils(xrandr) needed for auto-fullscreen / native-res detection
    PKGS=(git curl wget tar python3 winetricks xdotool x11-utils wmctrl x11-xserver-utils
          imagemagick cabextract p7zip-full ca-certificates)
    ;;
  dnf)
    PKGS=(git curl wget tar python3 winetricks xdotool xorg-x11-utils wmctrl xrandr
          ImageMagick cabextract p7zip p7zip-plugins fuse fuse-libs)
    ;;
  pacman)
    # python -> python3; xorg-xdpyinfo liefert xdpyinfo (aus x11-utils); fuse2 für AppImages
    PKGS=(git curl wget tar python winetricks xdotool xorg-xdpyinfo wmctrl xorg-xrandr
          imagemagick cabextract p7zip fuse2)
    ;;
  zypper)
    PKGS=(git curl wget tar python3 winetricks xdotool xdpyinfo wmctrl xrandr
          ImageMagick cabextract p7zip-full fuse libfuse2)
    ;;
esac

# ----------------------------- multiarch (nur apt) ---------------------------
if [ "$PM" = "apt" ]; then
  if ! dpkg --print-foreign-architectures 2>/dev/null | grep -qx i386; then
    info "Aktiviere 32-bit-Architektur (i386) für Wine/Proton …"
    run_root dpkg --add-architecture i386
  else
    info "i386-Architektur bereits aktiv."
  fi
fi

# ----------------------------- Paketquellen aktualisieren --------------------
info "Aktualisiere Paketquellen …"
case "$PM" in
  apt)    run_root apt-get update ;;
  dnf)    run_root dnf -q makecache || true ;;
  pacman) run_root pacman -Sy --noconfirm || true ;;
  zypper) run_root zypper --non-interactive refresh || true ;;
esac

# ----------------------------- Basis-Pakete installieren ---------------------
info "Installiere Pakete: ${PKGS[*]}"
case "$PM" in
  apt)    run_root apt-get install $YES --no-install-recommends "${PKGS[@]}" ;;
  dnf)    run_root dnf install $YES "${PKGS[@]}" ;;
  pacman) run_root pacman -S --needed --noconfirm "${PKGS[@]}" ;;
  zypper) run_root zypper --non-interactive install "${PKGS[@]}" ;;
esac

# ----------------------------- fuse/libfuse2 (apt-Sonderfall) ----------------
# umu-Zipapp & AppImage-artige Tools brauchen libfuse.so.2. Der Paketname
# wechselte in neueren Ubuntu/Debian (libfuse2 -> libfuse2t64). Best effort.
if [ "$PM" = "apt" ]; then
  if ! ldconfig -p 2>/dev/null | grep -q 'libfuse\.so\.2'; then
    info "Installiere libfuse2 (für umu/AppImage) …"
    run_root apt-get install $YES libfuse2t64 2>/dev/null \
      || run_root apt-get install $YES libfuse2 2>/dev/null \
      || warn "libfuse2 nicht installierbar — umu läuft evtl. trotzdem (Fallback)."
  else
    info "libfuse.so.2 bereits vorhanden."
  fi
fi

# ----------------------------- GitHub CLI (gh) -------------------------------
step "GitHub CLI 'gh' bereitstellen"
if command -v gh >/dev/null 2>&1; then
  info "gh bereits installiert ($(gh --version 2>/dev/null | head -1))."
else
  info "gh fehlt — installiere …"
  case "$PM" in
    apt)
      # Offizielles cli.github.com-Repo einrichten (empfohlener Weg).
      run_root mkdir -p -m 755 /etc/apt/keyrings
      TMP_KEY="$(mktemp)"
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o "$TMP_KEY" \
        || die "Konnte gh-Signaturschlüssel nicht laden."
      run_root install -m 644 "$TMP_KEY" /etc/apt/keyrings/githubcli-archive-keyring.gpg
      rm -f "$TMP_KEY"
      ARCH="$(dpkg --print-architecture)"
      echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | run_root tee /etc/apt/sources.list.d/github-cli.list >/dev/null
      run_root apt-get update
      run_root apt-get install $YES gh
      ;;
    dnf)
      run_root dnf install $YES gh || {
        run_root dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo 2>/dev/null || true
        run_root dnf install $YES gh
      }
      ;;
    pacman)
      run_root pacman -S --needed --noconfirm github-cli
      ;;
    zypper)
      run_root zypper --non-interactive install gh || {
        run_root zypper --non-interactive addrepo -f https://cli.github.com/packages/rpm/gh-cli.repo 2>/dev/null || true
        run_root zypper --non-interactive --gpg-auto-import-keys install gh
      }
      ;;
  esac
  command -v gh >/dev/null 2>&1 || die "gh-Installation fehlgeschlagen — bitte manuell installieren: https://cli.github.com/"
  info "gh installiert ($(gh --version 2>/dev/null | head -1))."
fi

# ----------------------------- gh-Login prüfen -------------------------------
if [ "${SKIP_GH_AUTH:-0}" = "1" ]; then
  warn "gh-Login-Prüfung übersprungen (SKIP_GH_AUTH=1)."
elif gh auth status >/dev/null 2>&1; then
  info "gh ist eingeloggt ✔"
else
  warn "Du bist noch nicht bei GitHub eingeloggt."
  echo
  echo "   ${c_bold}Bitte einmal einloggen und dann install.sh erneut starten:${c_reset}"
  echo "     ${c_bold}gh auth login${c_reset}"
  echo
  die "GitHub-Login nötig für den Cloud-Build. Nach 'gh auth login' erneut ausführen."
fi

step "System-Abhängigkeiten fertig ✅"
