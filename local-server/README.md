# Lokaler Server — und rein bis in-game 🎮

**So hostest du einen eigenen FiveM-Server auf Linux und spawnst mit dem selbst
gebauten Client komplett im Spiel.**

Das ist der **Durchbruch**: Ein **selbst kompilierter** FiveM-Client auf Linux
(GE-Proton/Wine, „Insecure Mode" / `sticky`) kann sich bei öffentlichen Servern
prinzipbedingt **nicht** authentifizieren — aber bei einem **eigenen, lokal
gehosteten Server** verbindet er sich **voll bis in-game**.

> **Bestätigt:** Der Server loggte `PLAYER: <name> id 1 ping 13`, der Client
> meldete `^2Game finished loading` — der Spieler stand in der Welt. ✅

Diese Anleitung deckt alles ab: den nativen Linux-Server holen, den
entscheidenden Anti-Cheat-Fix, die Config, den Start und das Verbinden.

---

## ⚡ Der schnelle Weg (ein Skript)

Das Skript [`setup-local-server.sh`](setup-local-server.sh) automatisiert die
Teile **A–C** (Server laden, Anti-Cheat-Fix, Ressourcen laden, Config kopieren):

```bash
cd local-server
chmod +x setup-local-server.sh
./setup-local-server.sh
```

Danach fehlt nur noch: **Lizenz-Key eintragen** (Teil C) und **Server starten**
(Teil D). Das Skript sagt dir am Ende genau, was zu tun ist.

Willst du es lieber von Hand verstehen? Die Teile **A–E** einzeln:

---

## 🍺 Was du brauchst

- Den **selbst gebauten Linux-FiveM-Client** — siehe die
  [Haupt-Anleitung](../README.md) (`git clone` + `./scripts/install.sh`).
- Einen **kostenlosen Cfx.re-Lizenz-Key** (Teil C — auch im LAN Pflicht, aber gratis).
- `curl`, `tar` und `python3` **oder** `jq` (für den JSON-Fix). Auf den meisten
  Distros bereits vorhanden.

---

## 📦 Teil A — Nativen Linux-FiveM-Server (fx-server) holen

Der Server (fx-server) läuft **nativ** auf Linux — kein Wine nötig.

```bash
# Zielordner anlegen
mkdir -p ~/fx-server && cd ~/fx-server

# Neuesten Build ermitteln und laden (<num>-<hash>/fx.tar.xz mit höchster Nummer)
curl -sL 'https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/' \
  | grep -oE '[0-9]+-[a-f0-9]+/fx.tar.xz' | sort -t- -k1,1 -n | tail -1 \
  | xargs -I{} curl -# -L -o fx.tar.xz \
      "https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/{}"

# Entpacken -> ergibt run.sh + einen alpine/-Baum
tar xf fx.tar.xz
```

```bash
# Standard-Ressourcen (Maps, Chat, Spawnmanager ...) holen
curl -# -L -o server-data.tar.gz \
  https://github.com/citizenfx/cfx-server-data/archive/refs/heads/master.tar.gz
mkdir -p server-data
tar xf server-data.tar.gz -C server-data --strip-components=1
```

Jetzt hast du:

```
~/fx-server/
├── run.sh                # Server-Starter
├── alpine/               # Server-Laufzeit
└── server-data/          # deine Ressourcen + gleich die server.cfg
    └── resources/
```

---

## 🔑 Teil B — DER entscheidende Fix: Anti-Cheat serverseitig abschalten

Das ist der **Kern des Ganzen.** Der selbst gebaute Client läuft im
„Insecure Mode" mit `sticky` statt echtem `adhesive`. Damit der Server ihn die
Ressourcen **mounten** und ihn **spawnen** lässt, muss der Server-Anti-Cheat
**`svadhesive`** raus.

Öffne `~/fx-server/alpine/opt/cfx-server/components.json` und **entferne die
Zeile** `"svadhesive",`.

Als Einzeiler (mit Python, sauber über JSON):

```bash
python3 - "$HOME/fx-server/alpine/opt/cfx-server/components.json" <<'PY'
import json, sys
p = sys.argv[1]
d = [c for c in json.load(open(p)) if c != "svadhesive"]
json.dump(d, open(p, "w"), indent=2)
print("svadhesive entfernt")
PY
```

> **Ohne diesen Fix** bekommst du die Fehlermeldung
> *„Could not get resource mounter for resource sessionmanager"* — und der
> Client **spawnt nie**. Genau das behebt das Entfernen von `svadhesive`.

---

## ⚙️ Teil C — server.cfg & Lizenz-Key

Kopiere die fertige Vorlage [`server.cfg`](server.cfg) aus diesem Ordner nach
`~/fx-server/server-data/server.cfg`:

```bash
cp local-server/server.cfg ~/fx-server/server-data/server.cfg
```

Die Vorlage enthält bereits alles Nötige: `sv_lan 1`, die TCP/UDP-Endpunkte auf
`0.0.0.0:30120`, `sv_maxclients`, die Standard-`ensure`-Ressourcen
(mapmanager, chat, spawnmanager, sessionmanager, fivem, hardcap, baseevents)
und einen `sv_hostname`.

**Was du noch tun musst:** einen **GRATIS-Lizenz-Key** eintragen.

> **Wichtig:** Auch im **LAN-Modus** verlangt FiveM einen Lizenz-Key — er ist
> aber **kostenlos** und an deinen **eigenen Cfx.re-Account** gebunden.
> Hol ihn hier: **<https://portal.cfx.re/servers/registration-keys>**

Trage ihn in `server-data/server.cfg` ein und ersetze den Platzhalter:

```cfg
sv_licenseKey CHANGEME_free_key_from_portal.cfx.re   # <- durch deinen Key ersetzen
```

---

## ▶️ Teil D — Server starten

**Gotcha:** Die Server-Konsole **beendet sich bei stdin-EOF sofort.** Starte den
Server deshalb so, dass stdin offen bleibt — am einfachsten in **tmux** oder
**screen** (oder einfach in einem Terminal, das du offen lässt).

```bash
# tmux-Session, die offen bleibt
tmux new -s fx

# im tmux: aus dem server-data-Ordner starten
cd ~/fx-server/server-data && ../run.sh +exec server.cfg
```

Ein erfolgreicher Start zeigt:

```
Server license key authentication succeeded. Welcome!
```

…und lädt danach eine Map. Läuft der Server, kannst du das tmux-Fenster mit
`Ctrl-b d` in den Hintergrund legen (Server läuft weiter).

---

## 🎮 Teil E — Client verbinden & spawnen

1. Starte deinen **FiveM-Linux-Client zuerst ins Hauptmenü** (`./scripts/launch.sh`
   aus der Haupt-Anleitung) und bestätige die „Insecure mode"-Box.
2. Dann per **Direct Connect** (oder `fivem://`-Handler) verbinden auf:

   ```
   127.0.0.1:30120
   ```

Der Client authentifiziert sich (dank `sv_lan 1`), lädt die GTA-V-Inhalte,
**mountet die Ressourcen** und **spawnt dich in-game.** 🎉

Zur Kontrolle: In der Server-Konsole erscheint eine Zeile wie
`PLAYER: <dein-name> id 1 ping 13`, im Client-Log steht `^2Game finished loading`.

---

## ⚖️ Ehrliche Grenzen (bitte lesen)

- ✅ **Funktioniert:** **deine eigenen / lokalen** Server mit `sv_lan 1` und
  **entferntem `svadhesive`**. Basis-, Freeroam- und eigene Custom-Server laufen.
- ❌ **Funktioniert NICHT:** **öffentliche / offizielle** Server. Die brauchen das
  echte Anti-Cheat, das wiederum echtes **Windows** verlangt (Dual-Boot). Kein
  selbst gebauter Client kommt da rein — das ist Absicht von Cfx.re.
- ❌ **ESX / QBCore** & ähnliche Frameworks laufen **lokal ebenfalls nicht** —
  sie brauchen die Spieler-Identifier, die nur das echte `adhesive` liefert.
  Für Framework-RP führt kein Weg an Windows vorbei.

Kurz: Perfekt für **eigenes Freeroam, LAN und Entwicklung** auf deinem Rechner —
nicht als Ersatz für öffentliche RP-Server.

---

## 🛠️ Troubleshooting

| Problem | Lösung |
|---|---|
| „Could not get resource mounter for resource sessionmanager" (Client spawnt nie) | **`svadhesive` aus `components.json` entfernen** (Teil B) — das ist der Kern-Fix. |
| Server-Konsole beendet sich sofort nach dem Start | stdin bleibt nicht offen → in **tmux/screen** starten (Teil D). |
| „Server license key was not set" / Auth schlägt fehl | GRATIS-Key von <https://portal.cfx.re/servers/registration-keys> in `server.cfg` eintragen (Teil C). |
| Client verbindet nicht / Timeout | Läuft der Server (tmux)? Port `30120` frei? Wirklich `127.0.0.1:30120` im Direct Connect? |
| `sort` wählt den falschen Build | Der Einzeiler in Teil A sortiert numerisch nach der Build-Nummer — nimm bei Bedarf manuell den neuesten `<num>-<hash>/fx.tar.xz`. |

---

*Diese Anleitung dokumentiert einen realen, verifizierten Aufbau — der erste
bestätigte Fall, in dem ein selbst gebauter Linux-Client vollständig in-game
spawnt. „Results may vary" — Build-/Wine-Versionen ändern sich. PRs willkommen.*
