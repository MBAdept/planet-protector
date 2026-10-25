# Planet Protector

Ein moderner 2D-Arcade-Shooter für Linux und Windows: Verteidige das Sonnensystem in 20 Leveln von Neptun bis zur Erde
gegen Wellen geflügelter Dämonen. Gebaut mit Godot 4.7, Grafik in Blender vorgerendert, Musik und Soundeffekte vollständig
selbst synthetisiert.

## Herunterladen

Datei öffnen und auf GitHub den Download-Button („Download raw file“) klicken:

- **Linux:** [`download/PlanetProtector-linux-x86_64.zip`](download/PlanetProtector-linux-x86_64.zip)
- **Windows:** [`download/PlanetProtector-windows-x86_64.zip`](download/PlanetProtector-windows-x86_64.zip)

Beide ZIP-Dateien enthalten das Spiel als einzelne Datei (alle Grafiken, Sounds und Daten sind eingebettet) und eine Anleitung.

## Starten unter Linux

```bash
unzip PlanetProtector-linux-x86_64.zip
cd PlanetProtector
chmod +x PlanetProtector.x86_64
./PlanetProtector.x86_64
```

Voraussetzungen: Linux x86_64 und eine Grafikkarte mit OpenGL 3.3 (praktisch jede Grafikkarte der letzten 10 Jahre).
Läuft unter X11 und unter Wayland (über XWayland). Einstellungen und Highscores liegen in `~/.local/share/planet_protector/`.

## Starten unter Windows

1. ZIP-Datei entpacken (Rechtsklick → „Alle extrahieren“).
2. Im Ordner `PlanetProtector` doppelt auf `PlanetProtector` (Typ „Anwendung“) klicken.
3. Die Datei ist nicht digital signiert. Zeigt Windows „Der Computer wurde durch Windows geschützt“, auf
   „Weitere Informationen“ und dann „Trotzdem ausführen“ klicken. Blockiert Windows 11 das Spiel ohne diese Möglichkeit
   („Intelligente App-Steuerung“), steht in der beiliegenden `LIESMICH.txt`, was zu tun ist.

Voraussetzungen: Windows 10 oder 11 (64 Bit). Ohne passenden OpenGL-Treiber nutzt das Spiel automatisch Direct3D 11.
Einstellungen und Highscores liegen in `%APPDATA%\planet_protector`.

## Steuerung

| Aktion | Tastatur | Controller (Xbox / PlayStation) |
|---|---|---|
| Bewegen | ← → oder A / D | D-Pad oder linker Stick |
| Feuern (gedrückt halten erlaubt) | Leertaste | A / B (Kreuz / Kreis) |
| Bestätigen | Enter (im Titel und in der Schiffsauswahl auch Leertaste) | X / Y (Quadrat / Dreieck), Start; im Titel und in der Schiffsauswahl auch A |
| Pause | P oder Escape | Start (Options) |
| Lautstärke in der Pause | ↑ ↓ wählen, ← → ändern | D-Pad / Stick |
| Aus der Pause zum Titel | Q | Select / Back (Share bzw. Create) |
| Highscores im Titel | Menüpunkt HIGHSCORES | Select / Back |
| Zurück aus Untermenüs | Escape | B |
| Vollbild an/aus (16:9-Modi: Vollbild ↔ 16:9-Fenster) | F11 | – |
| Spiel beenden (im Titel) | Escape | – |
| Name eingeben | Tippen, Backspace löscht | ↑↓ ändert Zeichen, ←→ bewegt Cursor, B löscht |

## Anzeige und Auflösung

Beim ersten Start fragt das Spiel nach dem Anzeigemodus (Pfeiltasten/D-Pad wählen, Enter/A bestätigt, Escape beendet das
Spiel, ohne etwas zu speichern – dann kommt die Frage beim nächsten Start wieder). Später lässt sich der Modus jederzeit im
Titelmenü unter **DISPLAY** ändern: ←/→ wählt, Enter/A übernimmt („Press ENTER to apply“); der Wechsel wirkt sofort, ohne
Neustart.

| Modus | Bild | Spielfeld |
|---|---|---|
| **WINDOW 4:3 (CLASSIC)** | Fenster 1280 × 960, frei skalierbar, F11 = Vollbild | das Original (960 × 720) |
| **FULLSCREEN 1920×1080 (16:9)** | Vollbild, berechnet in genau 1920 × 1080 | breiter: 1280 × 720 |
| **FULLSCREEN 2560×1440 (16:9)** | Vollbild, berechnet in genau 2560 × 1440 | breiter: 1280 × 720 |

- In den 16:9-Modi ist das Spielfeld wirklich breiter (keine schwarzen Balken): alle Geschwindigkeiten, Abstände und
  Trefferzonen bleiben gleich, nur die seitlichen Grenzen liegen an den Bildschirmrändern.
- Das Bild wird immer in der gewählten Auflösung berechnet und dann auf den Monitor skaliert (die Monitorauflösung selbst
  wird nicht umgestellt). Auf einem Monitor mit anderem Seitenverhältnis erscheinen schmale schwarze Ränder.
  Welcher 16:9-Modus passt, zeigt das Spiel selbst: Der Startbildschirm nennt die Bildschirmauflösung („Your screen:
  …“) und markiert die passende Option mit **BEST FIT FOR YOUR SCREEN** (2560×1440 ab einem Monitor mit mindestens
  2560 × 1440, sonst 1920×1080); im Titelmenü steht unter DISPLAY z. B. „best fit for your 1920×1080 screen“ oder
  „scaled down to your 1920×1080 screen“.
- Im Vollbild ist der Mauszeiger ausgeblendet (das Spiel braucht keine Maus), im Fenster ist er sichtbar.
- F11 schaltet in den 16:9-Modi zwischen Vollbild und einem 16:9-Fenster um (1920 × 1080, 1600 × 900 oder 1280 × 720 –
  das größte, das auf den Bildschirm passt); beim nächsten Start ist es wieder Vollbild.
- Die Highscore-Listen gelten für alle Modi gemeinsam. Die Wahl steht in der Einstellungsdatei (`settings.cfg`).

## Spielablauf

- **Titel**: Schwierigkeit (Beginner, Normal, Hard, Expert), Musik und Soundeffekte an/aus, Lautstärke für Musik und
  Effekte (0–100 %, auch in der Pause einstellbar), Anzeigemodus (DISPLAY, siehe oben), Highscores.
  Nach 90 Sekunden ohne Eingabe startet eine kurze Demo (Attract-Modus); jede Taste führt zurück zum Titel.
- **Schiffsauswahl**: sechs Schiffe mit unterschiedlichen Waffen (schnelle Laser, mitgeführte Raketen, Doppelschüsse,
  durchschlagende Schüsse). Animierte Vorschau zeigt jede Waffe in Aktion.
- **20 Level** auf sechs Planeten. Sonderregeln:
  - Saturn und Jupiter (Level 7–12): Getroffene Gegner teilen sich in zwei kleine Gegner.
  - Level 13: Bonuslevel „Prove Your Accuracy!“ mit 100 Schuss.
  - Mars (Level 14–16): Farbsperre violett → gelb → grün (wird vor Level 14 erklärt).
  - Erde (Level 19–20): Schwarze Gegner brauchen drei Treffer innerhalb von 10 Sekunden.
- Zwischen den Planeten gibt es Ankunftssequenzen, nach Level 20 einen Siegesbildschirm und eine Highscore-Eintragung.
- Vier getrennte Top-10-Listen, eine pro Schwierigkeitsgrad.

## Selbst bauen

Voraussetzung: Godot 4.7.2 (`godot` im PATH) mit den passenden Export-Templates für Linux und Windows.

```bash
tools/build.sh            # beide Plattformen; oder: tools/build.sh linux | windows
```

Ergebnis: `build/linux/PlanetProtector.x86_64`, `build/windows/PlanetProtector.exe` und
`build/PlanetProtector-windows-x86_64.zip`. Details zum Windows-Build und zum Test unter Wine: `docs/WINDOWS.md`.

Tests: `cd game && godot --headless --path . -s res://tests/run_tests.gd`

Die Assets lassen sich neu erzeugen:
- Grafik: `tools/blender/ships.py`, `enemies.py`, `planets.py`, `ground.py` (Blender als Python-Modul `bpy`)
- Audio: siehe `docs/AUDIO.md`

## Dokumente

- `docs/REFERENCE_DE.md`: die ursprüngliche Vorgabe (Spielregeln, Farben, Menüs, Steuerung)
- `docs/SPEC.md`: technische Spezifikation des Projekts
- `docs/AUDIO.md`: Musik und Soundeffekte
- `docs/WINDOWS.md`: Windows-Build, Test unter Wine, Hinweise zu SmartScreen

## Lizenzen

- Schriften: Orbitron und Exo 2, SIL Open Font License (siehe `game/assets/fonts/*-OFL.txt`).
- Alle Grafiken, Musikstücke und Soundeffekte wurden für dieses Projekt erzeugt (Blender-Skripte bzw. Python-Synthese).
