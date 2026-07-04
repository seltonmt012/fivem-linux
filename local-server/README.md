# Lokaler / LAN Test-Server (funktioniert mit dem selbst gebauten Client!)

Der selbst kompilierte Client kann sich bei **öffentlichen** Servern nicht authentifizieren
(Cfx-Anti-Cheat-Design), aber bei einem Server mit `sv_lan 1` **komplett bis in-game**.

## Setup
```bash
# 1) nativen Linux-FiveM-Server holen
mkdir -p ~/fx-server && cd ~/fx-server
curl -sL 'https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/' \
  | grep -oE '[0-9]+-[a-f0-9]+/fx.tar.xz' | sort -t- -k1 -n | tail -1 \
  | xargs -I{} curl -sL -o fx.tar.xz "https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/{}"
tar xf fx.tar.xz
# 2) Standard-Ressourcen
curl -sL -o sd.tgz https://github.com/citizenfx/cfx-server-data/archive/refs/heads/master.tar.gz
mkdir -p server-data && tar xf sd.tgz -C server-data --strip-components=1
cp server.cfg server-data/server.cfg   # aus diesem Ordner
# 3) GRATIS Lizenz-Key holen: https://portal.cfx.re/servers/registration-keys
#    und in server-data/server.cfg bei sv_licenseKey eintragen
# 4) starten
cd server-data && ../run.sh +exec server.cfg
```
Dann im Client: **Direct Connect → `127.0.0.1:30120`** → man spawnt in-game. ✅
