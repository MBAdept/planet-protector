# Planet Protector

Ein moderner 2D-Arcade-Shooter für Linux: Verteidige das Sonnensystem in 20 Leveln von Neptun bis zur Erde gegen
Wellen geflügelter Dämonen. Gebaut mit Godot 4.7, Grafik in Blender vorgerendert, Musik und Soundeffekte vollständig
selbst synthetisiert.

## Herunterladen

[`download/PlanetProtector-linux-x86_64.zip`](download/PlanetProtector-linux-x86_64.zip) öffnen und auf GitHub
den Download-Button („Download raw file“) klicken. Die ZIP-Datei enthält das Spiel und diese Anleitung.

## Starten

```bash
unzip PlanetProtector-linux-x86_64.zip
cd PlanetProtector
chmod +x PlanetProtector.x86_64
./PlanetProtector.x86_64
```

Es ist eine einzelne Datei; alle Grafiken, Sounds und Daten sind eingebettet. Voraussetzungen: Linux x86_64 und eine
Grafikkarte mit OpenGL 3.3 (praktisch jede Grafikkarte der letzten 10 Jahre). Läuft unter X11 und unter Wayland (über XWayland).

Einstellungen und Highscores werden in `~/.local/share/planet_protector/` gespeichert.

## Steuerung

| Aktion | Tastatur | Controller (Xbox / PlayStation) |
|---|---|---|
| Bewegen | ← → oder A / D | D-Pad oder linker Stick |
| Feuern (gedrückt halten erlaubt) | Leertaste | A / B (Kreuz / Kreis) |
| Bestätigen | Enter (im Titel und in der Schiffsauswahl auch Leertaste) | X / Y (Quadrat / Dreieck), Start; im Titel und in der Schiffsauswahl auch A |
| Pause | P oder Escape | Start (Options) |
| Aus der Pause zum Titel | Q | Select / Back (Share) |
| Highscores im Titel | Menüpunkt HIGHSCORES | Select / Back |
| Zurück aus Untermenüs | Escape | B |
| Vollbild an/aus | F11 | – |
| Spiel beenden (im Titel) | Escape | – |
| Name eingeben | Tippen, Backspace löscht | ↑↓ ändert Zeichen, ←→ bewegt Cursor, B löscht |

## Spielablauf

- **Titel**: Schwierigkeit (Beginner, Normal, Hard, Expert), Musik und Soundeffekte an/aus, Highscores.
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

Voraussetzung: Godot 4.7.2 (`godot` im PATH) mit den passenden Export-Templates.

```bash
tools/build.sh          # erzeugt build/PlanetProtector.x86_64
```

Tests: `cd game && godot --headless --path . -s res://tests/run_tests.gd`

Die Assets lassen sich neu erzeugen:
- Grafik: `tools/blender/ships.py`, `enemies.py`, `planets.py`, `ground.py` (Blender als Python-Modul `bpy`)
- Audio: siehe `docs/AUDIO.md`

## Dokumente

- `docs/REFERENCE_DE.md`: die ursprüngliche Vorgabe (Spielregeln, Farben, Menüs, Steuerung)
- `docs/SPEC.md`: technische Spezifikation des Projekts
- `docs/AUDIO.md`: Musik und Soundeffekte

## Lizenzen

- Schriften: Orbitron und Exo 2, SIL Open Font License (siehe `game/assets/fonts/*-OFL.txt`).
- Alle Grafiken, Musikstücke und Soundeffekte wurden für dieses Projekt erzeugt (Blender-Skripte bzw. Python-Synthese).
