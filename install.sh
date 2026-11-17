#!/bin/sh
set -eu

IPA_URL="https://github.com/jh0rsten/aniworld/releases/download/v1.0/Aniworld.ipa"
WORK_DIR="$HOME/.aniworld-installer"
IPA_FILE="$WORK_DIR/Aniworld.ipa"

fail() {
  echo "Fehler: $1"
  exit 1
}

( : < /dev/tty ) 2>/dev/null || fail "Bitte fuehre diesen Befehl direkt im Open Minis Terminal aus."

echo "Starte Aniworld Installer fuer iPhone..."
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "[1/5] Installiere benoetigte Alpine-Pakete..."
apk update >/dev/null 2>&1 || true
apk add --no-cache ca-certificates wget curl python3 py3-pip openssl-dev libffi-dev gcc musl-dev python3-dev >/dev/null 2>&1 || true

echo "[2/5] Lade Aniworld.ipa herunter..."
wget -q -O "$IPA_FILE" "$IPA_URL" || fail "Aniworld.ipa konnte nicht heruntergeladen werden."
[ -s "$IPA_FILE" ] || fail "Die heruntergeladene IPA-Datei ist leer."

echo "[3/5] Richte iOS-Verbindung & Sideloader ein..."
pip install --break-system-packages -q pymobiledevice3 sideloader 2>/dev/null || pip install -q pymobiledevice3 sideloader || fail "Installation von pymobiledevice3/sideloader fehlgeschlagen."

echo "[4/5] Verbinde mit dem iPhone..."
echo "WICHTIG: Falls auf dem iPhone eine Pairing-Meldung erscheint:"
echo "  1. Oeffne Einstellungen -> Datenschutz & Sicherheit -> Entwicklermodus."
echo "  2. Scrolle nach unten und tippe auf Koppeln / Pair."
echo "  3. Gib deinen iPhone-Code ein."
python3 -m pymobiledevice3 remote start-tunnel >/dev/null 2>&1 &
TUNNEL_PID=$!
trap '[ -z "${TUNNEL_PID:-}" ] || kill "$TUNNEL_PID" 2>/dev/null || true; rm -rf "$WORK_DIR"' EXIT
sleep 5

echo "[5/5] Signiere und installiere Aniworld.ipa..."
printf "Apple-ID E-Mail: "
read APPLE_ID < /dev/tty
printf "Apple-ID Passwort: "
stty -echo < /dev/tty
read APPLE_PASS < /dev/tty
stty echo < /dev/tty
echo ""

sideloader install -i "$IPA_FILE" -u "$APPLE_ID" -p "$APPLE_PASS" < /dev/tty || python3 -m pymobiledevice3 apps install "$IPA_FILE"

echo "Fertig! Die Aniworld-App ist jetzt auf deinem iPhone."
echo "Hinweis: Falls sich die App nicht oeffnen laesst, gehe zu Einstellungen -> Allgemein -> VPN & Geraeteverwaltung und vertraue deinem Entwicklerprofil."
