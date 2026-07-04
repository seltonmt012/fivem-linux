# FiveM nativ auf Linux 🐧

**FiveM (GTA V Multiplayer) auf Ubuntu/Linux zum Laufen bringen — komplett, Schritt für Schritt.**

Kein Dual-Boot, keine VM. Der FiveM-Client wird selbst kompiliert (in der GitHub-Cloud, keine Windows-Installation nötig) und läuft über **GE-Proton** direkt auf Linux — bis ins Hauptmenü, mit Rockstar-Login und Server-Beitritt.

![FiveM Hauptmenü auf Linux](images/01-fivem-main-menu.png)
*Das FiveM-Hauptmenü mit Live-Serverliste — nativ auf Ubuntu.*

---

## ⚖️ Wichtig / Rechtliches (bitte lesen)

- Der FiveM-Client ist **quelloffen** (Cfx.re). Das **Weitergeben von selbst kompilierten Client-Binaries verstößt gegen die Cfx.re-TOS** — deshalb **kompiliert hier jeder seine eigene Version selbst** (genau das macht diese Anleitung). In diesem Repo sind **nur Skripte & Doku, keine Binaries**.
- Du brauchst ein **legitimes GTA V** (Steam/Epic/Rockstar) und einen **eigenen Rockstar-Games-Account** + **Cfx.re-Account**.
- Unter Wine läuft der Client im **„Insecure Mode"** — das Anti-Cheat (`adhesive`) funktioniert auf Wine nicht. Du kannst nur auf **Server ohne aktives Anti-Cheat** (z. B. deinen eigenen Server). Offiziell ist das **experimentell/unsupported**.

Getestet auf **Ubuntu 26.04**, GNOME/Wayland, NVIDIA GTX 1060. Sollte auf den meisten modernen Distros mit GE-Proton laufen.

---

## 🧩 Warum es früher nicht ging (und jetzt schon)

Der aktuelle FiveM-Bootstrapper nutzt einen **WinUI/XAML-Splash**, der unter Wine crasht (`Windows.UI.Xaml.Hosting.WindowsXamlManager` nicht implementiert). Der Community-Fork **[`Gogsi/fivem`](https://github.com/Gogsi/fivem/tree/wine-win10)** (Branch `wine-win10`) behebt das mit nur **4 Dateien**, alle über `CfxIsWine()` abgesichert:

| Datei | Änderung |
|---|---|
| `UpdaterUI.cpp` | Schaltet den XAML-Splash unter Wine ab (der alte Crash) |
| `NUIWindow.cpp` | Aktiviert DXVK-Shared-Textures unter Wine → CEF/Menü rendert |
| `DllGameComponent.Win32.cpp` | Überspringt Windows-Speicherlayout-Hack unter Wine |
| `SEHTableHandler.Win32.cpp` | Überspringt SEH-Hook unter Wine |

---

## ✅ Voraussetzungen

1. **GTA V — Legacy Edition** (nicht „Enhanced"!) installiert, **einmal via Steam gestartet** — dabei installiert GTA V den **Rockstar Games Launcher + Social Club** in seinen Proton-Prefix (den übernehmen wir).
2. **GE-Proton** (z. B. `GE-Proton10-34`) → nach `~/.local/share/Steam/compatibilitytools.d/` (Download: [GloriousEggroll/proton-ge-custom](https://github.com/GloriousEggroll/proton-ge-custom/releases)).
3. Pakete: `git`, `curl`, `python3`, `winetricks`, `xdotool`, `x11-utils`, `imagemagick`, und die [GitHub CLI `gh`](https://cli.github.com/) (eingeloggt: `gh auth login`).
4. Ein **GitHub-Account** (zum Kompilieren in der Cloud).

---

## 📦 Teil A — Client kompilieren (GitHub Actions, ~50 Min)

Du baust den gepatchten Client **in der Cloud** auf einem Windows-Runner — kein lokales Windows nötig.

1. **Forke** [`Gogsi/fivem`](https://github.com/Gogsi/fivem) in deinen GitHub-Account und aktiviere **Actions** (Tab „Actions" → „I understand… enable").
2. Stelle sicher, dass der Branch **`wine-win10`** existiert. Falls nicht, per API aus dem Original anlegen:
   ```bash
   SHA=$(gh api repos/Gogsi/fivem/branches/wine-win10 --jq .commit.sha)
   gh api -X POST repos/<DU>/fivem/git/refs -f ref=refs/heads/wine-win10 -f sha="$SHA"
   ```
3. Lade den Workflow [`workflow/build-linux-client.yml`](workflow/build-linux-client.yml) aus diesem Repo in deinen Fork nach `.github/workflows/build-linux-client.yml` — **auch auf `master`** (sonst wird `workflow_dispatch` nicht erkannt).
4. Starte ihn: Actions → „build-linux-client" → „Run workflow" → Branch `wine-win10`.
5. Nach ~50 Min: Artefakt **`fivem-five-release`** herunterladen und nach z. B. `~/FiveM/release/` **entpacken**.

**Die 6 Build-Hürden, die der Workflow löst** (falls du ihn selbst schreibst):
- `runs-on: windows-2022` — **nicht** `windows-latest`! Das hat inzwischen VS 2026, das FiveMs altes node-gyp nicht kennt (`ffi-napi`-Fehler).
- `ilammy/msvc-dev-cmd` statt hardcodiertem VS-Pfad (setzt `VSINSTALLDIR` für node-gyp) + `GYP_MSVS_VERSION=2022`.
- MSBuild mit `-p:WindowsTargetPlatformVersion=10.0.22621.0` (Runner hat nicht die gepinnte 22000).
- Extra-Schritt: `run_postbuild.ps1` mit `env: CI: ''` ausführen — sonst fehlen **components.json, citizen/ui.zip, CEF (`bin/`), citizen/ros, data/** im Artefakt.

---

## ⚙️ Teil B — Linux-Setup (automatisch)

Alle Laufzeit-Schritte macht [`scripts/setup.sh`](scripts/setup.sh). **Oben im Skript die 5 Pfade anpassen** (RELEASE_DIR, GTA_DIR, STEAM_GTAV_PREFIX, PROTONPATH, VDESK_RES), dann:

```bash
chmod +x scripts/*.sh
RELEASE_DIR=~/FiveM/release ./scripts/setup.sh
```

Das erledigt: umu-launcher laden · `CitizenFX.ini` schreiben · Wine-Prefix anlegen · **Rockstar Games Launcher + Registry aus deinem Steam-GTA-V-Prefix importieren** · **Wine-Virtual-Desktop** aktivieren (Fenster sichtbar) · **VC++-Runtime installieren** (Pflicht!) · **`fivem://`-Handler** registrieren.

<details><summary>Was genau (manuell nachvollziehbar)</summary>

- **`CitizenFX.ini`** neben `FiveM.exe`: `[Game]` / `IVPath=Z:\pfad\zu\Grand Theft Auto V`
- **Rockstar Games Launcher**: FiveM braucht ihn unter `C:\Program Files\Rockstar Games\Launcher\Launcher.exe`. Wir kopieren `Program Files/Rockstar Games`, `Program Files (x86)/Rockstar Games`, `ProgramData/Rockstar Games`, `AppData/Local/Rockstar Games` aus `…/compatdata/271590/pfx` und mergen die `Rockstar`-Registry-Sektionen aus dessen `system.reg`/`user.reg`.
- **Virtual Desktop** (`user.reg`): `[Software\\Wine\\Explorer] "Desktop"="Default"` + `[…\\Desktops] "Default"="1600x900"` — ohne das sind Wine-Dialoge & das Rockstar-Login **unsichtbar**.
- **VC++-Runtime**: `winetricks -q vcrun2022 vcrun2019 d3dcompiler_47 corefonts` — **ohne die crasht der GTA5-GameProcess sofort.**
</details>

---

## ▶️ Teil C — Starten & Anmelden

```bash
RELEASE_DIR=~/FiveM/release ./scripts/launch.sh
```

- **Erststart** lädt ~2 GB Spieldaten-Cache. Die Box **„Cfx.re: Insecure mode"** mit **OK/Enter** bestätigen.

  ![Insecure Mode](images/02-insecure-mode.png)

- **Rockstar-Login:** Ist **Steam offen und eingeloggt**, meldet sich der Rockstar Launcher **automatisch über deinen Steam-Account** an (GTA V ist Steam-Besitz). Sonst meldest du dich **einmal manuell** im Rockstar-Fenster an (Haken „Automatisch anmelden") — die Session bleibt dann gespeichert.

  ![Rockstar Login](images/04-rockstar-login.png)

> **Warum Steam für den Auto-Login?** GTA V gehört deinem Steam-Account. Der Rockstar Launcher holt sich das „Entitlement" (Besitznachweis) über den laufenden Steam-Client → kein Passwort nötig. Ist Steam zu, geht der manuelle Rockstar-Login.

---

## 🔗 Teil D — Cfx.re-Account & `fivem://`-Handler

Im Menü kommt **„Cfx.re — Awaiting sign in confirmation — Click authorize in browser"**. FiveM verlangt einen **Cfx.re-Account** (Forum-Account) als deine **feste Identität** — Server erkennen dich daran (Bans, Whitelist, Rollen). Das ist normal, nicht Linux-spezifisch.

Nach dem Autorisieren im Browser leitet dieser auf `fivem://accept-auth/…` weiter. Damit Linux das an FiveM übergibt, registriert `setup.sh` einen **`fivem://`-Protokoll-Handler** ([`scripts/fivem-url-handler.sh`](scripts/fivem-url-handler.sh) + [`config/fivem-url.desktop`](config/fivem-url.desktop)). Ohne den sagt der Browser „Keine Anwendung verfügbar". Der Handler wird **auch zum Server-Beitritt** gebraucht (der „Connect"-Button nutzt `fivem://connect/…`).

![Server-Verbindung](images/03-connecting-server.png)

---

## 🎮 Teil E — Spielen & Game-Build-Wechsel

Viele Server verlangen einen bestimmten **GTA-Build** (z. B. `b3570`). FiveM lädt/patcht den dann und **muss sich neu starten**. Auf Windows macht FiveM das selbst; unter umu wird der Neustart-Prozess aber vom Container gekillt.

**Lösung:** [`scripts/launch.sh`](scripts/launch.sh) ist ein **Relaunch-Loop** — er fängt FiveMs `-switchcl:… "fivem://connect/<server>"`-Neustart ab und startet automatisch wieder in den neuen Build + verbindet erneut. Du musst nichts manuell tun.

---

## 🛠️ Troubleshooting

| Problem | Lösung |
|---|---|
| GameProcess startet & schließt sofort | **VC++-Runtime fehlt** → `winetricks -q vcrun2022 vcrun2019` |
| „Rockstar Games Launcher could not be found" | RGL aus dem Steam-Prefix importieren (Teil B) |
| Rockstar-Login/Insecure-Box **unsichtbar** | Wine-**Virtual Desktop** aktivieren (Teil B) |
| `FatalError: Unknown component adhesive` | `adhesive` **nicht** aus `components.json` entfernen — Wine ersetzt es durch `sticky` |
| Browser: „Keine Anwendung verfügbar" bei Auth | `fivem://`-Handler registrieren (Teil D) |
| Build-Switch startet nicht neu | den Loop-`launch.sh` benutzen (Teil E) |
| Absturz debuggen | `WINEDEBUG=+seh,+tid PROTON_LOG=1 ./launch.sh` → `~/steam-fivem.log` |
| Schriftart sieht falsch aus | `winetricks -q corefonts` (Web-Fonts der UI fallen sonst zurück) |

---

## 🙏 Credits

- **[Gogsi](https://github.com/Gogsi/fivem/tree/wine-win10)** — der 4-Datei-Wine-Patch, ohne den nichts davon ginge.
- **Cfx.re / FiveM** — der quelloffene Client.
- **[umu-launcher](https://github.com/Open-Wine-Components/umu-launcher)** & **[GE-Proton](https://github.com/GloriousEggroll/proton-ge-custom)**.

*Diese Anleitung dokumentiert einen realen, funktionierenden Aufbau. „Results may vary" — Wine/Proton-Versionen ändern sich. PRs & Ergänzungen willkommen.*
