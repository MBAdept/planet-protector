#!/usr/bin/env bash
# Builds the single-file executables (PCK embedded) for Linux and Windows (x86_64):
#   build/linux/PlanetProtector.x86_64        Linux export preset "Linux"
#   build/PlanetProtector.x86_64              symlink to the above (old path, kept for existing callers)
#   build/windows/PlanetProtector.exe         Windows export preset "Windows Desktop" (Windows 10/11, 64 bit)
#   build/PlanetProtector-windows-x86_64.zip  PlanetProtector/PlanetProtector.exe + PlanetProtector/LIESMICH.txt
# Requires Godot 4.7.2 ("godot" on PATH, or GODOT=/path/to/godot) with the 4.7.2 export templates for Linux and
# Windows installed, and python3 (for the zip). See docs/WINDOWS.md.
# Usage: tools/build.sh [all|linux|windows]   (default: all)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
TARGET="${1:-all}"
case "$TARGET" in
	all|linux|windows) ;;
	*) echo "usage: $0 [all|linux|windows]" >&2; exit 2 ;;
esac

# Exports one preset to <out> and fails if Godot did not write a fresh file.
export_preset() {
	local preset="$1" out="$2"
	mkdir -p "$(dirname "$out")"
	rm -f "$out"
	"$GODOT" --headless --path "$ROOT/game" --export-release "$preset" "$out"
	if [ ! -s "$out" ]; then
		echo "ERROR: export '$preset' did not produce $out" >&2
		exit 1
	fi
}

# German readme for the Windows zip (UTF-8 with BOM and CRLF line endings, so every Notepad shows it correctly).
write_liesmich() {
	python3 -c 'import sys; sys.stdout.buffer.write(b"\xef\xbb\xbf" + sys.stdin.buffer.read().replace(b"\n", b"\r\n"))' \
		> "$1" <<'EOF'
PLANET PROTECTOR 1.6 für Windows
================================

Ein moderner 2D-Arcade-Shooter: Verteidige das Sonnensystem in 20 Leveln von
Neptun bis zur Erde gegen Wellen geflügelter Dämonen.


STARTEN
-------
1. Die ZIP-Datei entpacken (Rechtsklick -> "Alle extrahieren...").
2. Im Ordner "PlanetProtector" doppelt auf "PlanetProtector" (Typ
   "Anwendung") klicken. Das ist die Datei PlanetProtector.exe, Windows
   blendet die Endung ".exe" meist aus.

Das Spiel ist eine einzelne Datei, alle Grafiken, Sounds und Daten sind
eingebettet. Eine Installation ist nicht nötig; zum Entfernen genügt es,
den Ordner zu löschen.

Hinweis zu Windows SmartScreen: Die Datei ist nicht digital signiert. Beim
ersten Start zeigt Windows deshalb eventuell "Der Computer wurde durch
Windows geschützt". Dann auf "Weitere Informationen" und danach auf
"Trotzdem ausführen" klicken. Blockiert Windows 11 das Spiel ohne diese
Möglichkeit, hilft der Abschnitt "PROBLEME?" weiter unten.

Voraussetzungen: Windows 10 oder 11 (64 Bit) und eine Grafikkarte mit
OpenGL 3.3 (praktisch jede Grafikkarte der letzten 10 Jahre). Fehlt ein
passender OpenGL-Treiber, schaltet das Spiel automatisch auf Direct3D 11 um.


STEUERUNG
---------
Tastatur
  Bewegen ............ Pfeiltasten links/rechts oder A / D
  Feuern ............. Leertaste (gedrückt halten erlaubt)
  Power-up ........... Shift oder Strg (nur mit POWER-UPS ON)
  Bestätigen ......... Enter (im Titel und in der Schiffsauswahl auch Leertaste)
  Pause .............. P oder Esc
  Pause -> Titel ..... Q
  Zurück ............. Esc (aus Untermenüs)
  Vollbild an/aus .... F11
  Spiel beenden ...... Esc im Titel oder Menüpunkt QUIT
  Name eingeben ...... Tippen, Rücktaste löscht, Enter bestätigt

Controller (Xbox / PlayStation)
  Bewegen ............ Steuerkreuz oder linker Stick
  Feuern ............. A / B (Kreuz / Kreis)
  Power-up ........... X / Y oder LB / RB (nur mit POWER-UPS ON)
  Bestätigen ......... X / Y (Quadrat / Dreieck) oder Start,
                       im Titel und in der Schiffsauswahl auch A
  Pause .............. Start (Options)
  Pause -> Titel ..... Select / Back (Share bzw. Create)
  Highscores ......... Select / Back im Titel
  Zurück ............. B (aus Untermenüs)
  Name eingeben ...... hoch/runter ändert das Zeichen, links/rechts bewegt
                       den Cursor, B löscht

Im Titelmenü lassen sich Schwierigkeit, Spieleranzahl (PLAYERS 1 / 2),
Power-ups (POWER-UPS OFF / ON), Musik und Soundeffekte (an/aus und
Lautstärke) und der Anzeigemodus einstellen; dort sind auch die Highscores
zu finden. Die Lautstärken lassen sich zusätzlich im Pausenmenü ändern.

Zwei Spieler (PLAYERS 2): Gespielt wird abwechselnd Level für Level an
einem Bildschirm. Vorher sperrt jeder verdeckt bis zu drei Schiffe für den
anderen. Wer alle Leben verloren hat, scheidet aus, der andere spielt
weiter. Am Ende dürfen sich beide in die Highscoreliste eintragen.

Power-ups (POWER-UPS ON): einmal pro Level selbst auslösen - Saturn:
Dauerfeuer (10 s), Jupiter: unverwundbarer Zwilling (15 s), Mars:
Schutzschild (10 s). Spiele mit Power-ups haben eigene Highscorelisten.


EINSTELLUNGEN UND HIGHSCORES
----------------------------
Werden automatisch gespeichert in

  %APPDATA%\planet_protector\

(also z. B. C:\Users\<Name>\AppData\Roaming\planet_protector\) in den
Dateien settings.cfg und highscores.json. Den Ordner öffnet man am
einfachsten, indem man %APPDATA%\planet_protector in die Adresszeile des
Explorers eingibt. Wer den Ordner löscht, setzt Einstellungen und
Highscores zurück.


PROBLEME?
---------
Bleibt das Fenster schwarz oder startet das Spiel nicht, zuerst den
Grafiktreiber aktualisieren. Als Notlösung kann Direct3D 11 erzwungen werden:
Verknüpfung zu PlanetProtector.exe anlegen und im Feld "Ziel" hinter dem
Pfad  --rendering-driver opengl3_angle  anhängen.

Meldet Windows 11, dass die intelligente App-Steuerung (englisch "Smart App
Control") eine App blockiert hat, gibt es kein "Trotzdem ausführen": Diese
Schutzfunktion lässt nur digital signierte oder Microsoft bekannte Programme
starten. Das Spiel läuft dann nur, wenn sie unter Windows-Sicherheit ->
App- & Browsersteuerung -> Einstellungen für intelligente App-Steuerung auf
"Aus" steht. Achtung: Auf älteren Windows-11-Ständen lässt sie sich danach
nur durch Zurücksetzen oder Neuinstallation von Windows wieder einschalten.
EOF
}

"$GODOT" --headless --path "$ROOT/game" --import

if [ "$TARGET" != windows ]; then
	export_preset "Linux" "$ROOT/build/linux/PlanetProtector.x86_64"
	chmod +x "$ROOT/build/linux/PlanetProtector.x86_64"
	ln -sfn linux/PlanetProtector.x86_64 "$ROOT/build/PlanetProtector.x86_64"
	ls -la "$ROOT/build/linux/PlanetProtector.x86_64" "$ROOT/build/PlanetProtector.x86_64"
fi

if [ "$TARGET" != linux ]; then
	export_preset "Windows Desktop" "$ROOT/build/windows/PlanetProtector.exe"
	write_liesmich "$ROOT/build/windows/LIESMICH.txt"
	ZIP="$ROOT/build/PlanetProtector-windows-x86_64.zip"
	rm -f "$ZIP"
	python3 - "$ZIP" "$ROOT/build/windows" <<'EOF'
import os, sys, time, zipfile
zip_path, src = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
	folder = zipfile.ZipInfo("PlanetProtector/", date_time=time.localtime()[:6])
	folder.external_attr = (0o40755 << 16) | 0x10   # directory (Unix mode + MS-DOS directory flag)
	z.writestr(folder, b"")
	for name in ("PlanetProtector.exe", "LIESMICH.txt"):
		z.write(os.path.join(src, name), "PlanetProtector/" + name)
EOF
	ls -la "$ROOT/build/windows/PlanetProtector.exe" "$ZIP"
fi
