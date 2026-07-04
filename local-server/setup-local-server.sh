#!/usr/bin/env bash
# =============================================================================
#  setup-local-server.sh  —  Lokalen FiveM-Server für den Linux-Client bauen
# =============================================================================
#  Automatisiert Teil A–C aus der README:
#    A) neuesten nativen Linux-FiveM-Server (fx-server) laden & entpacken
#    B) DER KEY-FIX: "svadhesive" aus components.json entfernen, damit der
#       selbst gebaute (sticky) Client die Ressourcen mounten & spawnen kann
#    A2) Standard-Ressourcen (cfx-server-data) laden & entpacken
#    C) server.cfg (aus diesem Ordner) nach server-data/ kopieren
#
#  Danach musst du nur noch:
#    1. einen GRATIS-Lizenz-Key in server-data/server.cfg eintragen
#    2. den Server starten (siehe Ausgabe am Ende)
#
#  Idempotent-ish: lädt bereits vorhandene Downloads nicht erneut.
#  Kein privater Lizenz-Key wird hier hardcodiert — den holst du selbst.
#
#  Nutzung:      ./setup-local-server.sh
#  Ziel ändern:  FX_DIR=~/mein-server ./setup-local-server.sh
#  Syntax-Check: bash -n setup-local-server.sh
# =============================================================================
set -euo pipefail

# ----------------------------- Ausgabe-Helfer --------------------------------
c_reset=$'\e[0m'; c_bold=$'\e[1m'; c_grn=$'\e[32m'; c_ylw=$'\e[33m'
c_red=$'\e[31m'; c_blu=$'\e[36m'
step()  { echo; echo "${c_bold}${c_blu}==> $*${c_reset}"; }
info()  { echo "   ${c_grn}•${c_reset} $*"; }
warn()  { echo "   ${c_ylw}!${c_reset}  $*" >&2; }
die()   { echo "${c_red}x $*${c_reset}" >&2; exit 1; }

# ----------------------------- Pfade ----------------------------------------
# Verzeichnis dieses Skripts (damit server.cfg immer gefunden wird, egal von wo)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Zielordner für den Server (überschreibbar via FX_DIR)
FX_DIR="${FX_DIR:-$HOME/fx-server}"
SERVER_DATA_DIR="$FX_DIR/server-data"

ARTIFACTS_URL="https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/"
SERVER_DATA_URL="https://github.com/citizenfx/cfx-server-data/archive/refs/heads/master.tar.gz"

# ----------------------------- Vorbedingungen -------------------------------
step "Werkzeuge prüfen"
for tool in curl tar; do
  command -v "$tool" >/dev/null 2>&1 || die "'$tool' fehlt — bitte installieren (z. B. sudo apt install $tool)."
done
# Für den JSON-Fix nehmen wir python3 (überall vorhanden), jq als Fallback
JSON_TOOL=""
if command -v python3 >/dev/null 2>&1; then JSON_TOOL="python3"
elif command -v jq      >/dev/null 2>&1; then JSON_TOOL="jq"
else die "Weder python3 noch jq gefunden — eines davon wird für den components.json-Fix gebraucht."
fi
info "Alle Werkzeuge da (JSON-Fix via ${JSON_TOOL})."

mkdir -p "$FX_DIR"

# ============================================================================
#  A) Nativen Linux-FiveM-Server holen
# ============================================================================
step "A) Nativen FiveM-Server (fx-server) holen"
if [ -f "$FX_DIR/run.sh" ] && [ -d "$FX_DIR/alpine" ]; then
  info "fx-server ist bereits vorhanden ($FX_DIR/run.sh) — überspringe Download."
else
  info "Neuesten Build aus $ARTIFACTS_URL ermitteln ..."
  # Verzeichnisliste holen und den höchsten <num>-<hash>/fx.tar.xz-Eintrag wählen
  LATEST="$(curl -sL "$ARTIFACTS_URL" \
             | grep -oE '[0-9]+-[a-f0-9]+/fx\.tar\.xz' \
             | sort -t- -k1,1 -n | tail -1)"
  [ -n "$LATEST" ] || die "Konnte keinen Build in der Artefaktliste finden (Netzwerk? URL geändert?)."
  info "Neuester Build: $LATEST"

  if [ -f "$FX_DIR/fx.tar.xz" ]; then
    info "fx.tar.xz bereits geladen — überspringe Download."
  else
    info "Lade fx.tar.xz herunter ..."
    curl -# -L -o "$FX_DIR/fx.tar.xz" "${ARTIFACTS_URL}${LATEST}" \
      || die "Download des Servers fehlgeschlagen."
  fi

  info "Entpacke fx.tar.xz nach $FX_DIR ..."
  tar xf "$FX_DIR/fx.tar.xz" -C "$FX_DIR"
  [ -f "$FX_DIR/run.sh" ] || die "Nach dem Entpacken fehlt run.sh — Archiv defekt?"
  info "Server entpackt (run.sh + alpine/ vorhanden)."
fi

# ============================================================================
#  B) DER KEY-FIX: svadhesive (Server-Anti-Cheat) entfernen
# ============================================================================
step "B) Anti-Cheat serverseitig abschalten (svadhesive aus components.json)"
COMPONENTS_JSON="$FX_DIR/alpine/opt/cfx-server/components.json"
[ -f "$COMPONENTS_JSON" ] || die "components.json nicht gefunden: $COMPONENTS_JSON"

if [ "$JSON_TOOL" = "python3" ]; then
  REMOVED="$(python3 - "$COMPONENTS_JSON" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
# components.json ist eine Liste von Komponenten-Namen (Strings)
before = len(data)
data = [c for c in data if c != "svadhesive"]
removed = before - len(data)
if removed:
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
print(removed)
PY
)"
else
  # jq-Fallback
  BEFORE="$(jq 'length' "$COMPONENTS_JSON")"
  tmp="$(mktemp)"
  jq 'map(select(. != "svadhesive"))' "$COMPONENTS_JSON" > "$tmp"
  AFTER="$(jq 'length' "$tmp")"
  REMOVED="$(( BEFORE - AFTER ))"
  [ "$REMOVED" -gt 0 ] && mv "$tmp" "$COMPONENTS_JSON" || rm -f "$tmp"
fi

if [ "${REMOVED:-0}" -gt 0 ]; then
  info "svadhesive entfernt — der selbst gebaute Client kann jetzt Ressourcen mounten."
else
  info "svadhesive war bereits entfernt — nichts zu tun."
fi

# ============================================================================
#  A2) Standard-Ressourcen (cfx-server-data) holen
# ============================================================================
step "A2) Standard-Ressourcen (cfx-server-data) holen"
if [ -d "$SERVER_DATA_DIR/resources" ]; then
  info "server-data/resources ist bereits vorhanden — überspringe Download."
else
  mkdir -p "$SERVER_DATA_DIR"
  if [ -f "$FX_DIR/server-data.tar.gz" ]; then
    info "server-data.tar.gz bereits geladen — überspringe Download."
  else
    info "Lade cfx-server-data herunter ..."
    curl -# -L -o "$FX_DIR/server-data.tar.gz" "$SERVER_DATA_URL" \
      || die "Download der Standard-Ressourcen fehlgeschlagen."
  fi
  info "Entpacke Ressourcen nach $SERVER_DATA_DIR (strip 1) ..."
  tar xf "$FX_DIR/server-data.tar.gz" -C "$SERVER_DATA_DIR" --strip-components=1
  info "Standard-Ressourcen entpackt."
fi

# ============================================================================
#  C) server.cfg aus diesem Ordner nach server-data/ kopieren
# ============================================================================
step "C) server.cfg bereitstellen"
SRC_CFG="$SCRIPT_DIR/server.cfg"
DST_CFG="$SERVER_DATA_DIR/server.cfg"
[ -f "$SRC_CFG" ] || die "server.cfg nicht neben dem Skript gefunden: $SRC_CFG"

if [ -f "$DST_CFG" ] && grep -q "sv_licenseKey" "$DST_CFG" \
   && ! grep -q "CHANGEME_free_key_from_portal.cfx.re" "$DST_CFG"; then
  warn "$DST_CFG existiert bereits und enthält scheinbar schon einen Key — überschreibe NICHT."
  warn "Falls du die Vorlage neu willst, lösche die Datei und starte das Skript erneut."
else
  cp "$SRC_CFG" "$DST_CFG"
  info "server.cfg nach $DST_CFG kopiert."
fi

# ============================================================================
#  Nächste Schritte
# ============================================================================
NEED_KEY=0
if grep -q "CHANGEME_free_key_from_portal.cfx.re" "$DST_CFG" 2>/dev/null; then NEED_KEY=1; fi

echo
echo "${c_bold}${c_grn}============================================================${c_reset}"
echo "${c_bold}${c_grn} Fertig! Der lokale Server ist vorbereitet.${c_reset}"
echo "${c_bold}${c_grn}============================================================${c_reset}"
echo
echo "${c_bold}Nächste Schritte:${c_reset}"
echo
if [ "$NEED_KEY" -eq 1 ]; then
  echo "  ${c_ylw}1) GRATIS-Lizenz-Key holen${c_reset} (auch im LAN Pflicht):"
  echo "       https://portal.cfx.re/servers/registration-keys"
  echo "     und in die Config eintragen — ersetze CHANGEME_... in:"
  echo "       ${c_bold}$DST_CFG${c_reset}"
  echo "     Zeile:  sv_licenseKey <DEIN_KEY>"
  echo
fi
echo "  ${c_ylw}2) Server starten${c_reset} (stdin muss offen bleiben — sonst beendet"
echo "     sich die Konsole sofort). Am einfachsten in tmux/screen:"
echo
echo "       ${c_bold}tmux new -s fx${c_reset}"
echo "       ${c_bold}cd \"$SERVER_DATA_DIR\" && \"$FX_DIR/run.sh\" +exec server.cfg${c_reset}"
echo
echo "     Erfolg = die Meldung:"
echo "       ${c_grn}\"Server license key authentication succeeded. Welcome!\"${c_reset}"
echo
echo "  ${c_ylw}3) Client verbinden${c_reset}: FiveM-Client zuerst ins Hauptmenü starten,"
echo "     dann Direct Connect / fivem:// auf  ${c_bold}127.0.0.1:30120${c_reset}"
echo "     -> du solltest voll in-game spawnen."
echo
echo "  ${c_blu}Hinweis:${c_reset} Das funktioniert nur auf DEINEM eigenen / lokalen"
echo "  Server (svadhesive entfernt). NIEMALS auf öffentlichen Servern."
echo
