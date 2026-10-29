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
| Vollbild an/aus (Vollbild-Modi: Vollbild ↔ Fenster im selben Seitenverhältnis) | F11 | – |
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
| **FULLSCREEN 1280×800 (16:10, STEAM DECK)** | Vollbild, berechnet in genau 1280 × 800 – füllt den Steam-Deck-Bildschirm ohne Ränder | breiter: 1152 × 720 |
| **FULLSCREEN 1280×720 (16:9)** | Vollbild, berechnet in genau 1280 × 720 (kleine Bildschirme, schwächere Grafik) | breiter: 1280 × 720 |

- In den Vollbild-Modi ist das Spielfeld wirklich breiter (keine schwarzen Balken): alle Geschwindigkeiten, Abstände und
  Trefferzonen bleiben gleich, nur die seitlichen Grenzen liegen an den Bildschirmrändern (16:9: 1280 Punkte breit,
  16:10/Steam Deck: 1152 Punkte breit).
- Das Bild wird immer in der gewählten Auflösung berechnet und dann auf den Monitor skaliert (die Monitorauflösung selbst
  wird nicht umgestellt). Auf einem Monitor mit anderem Seitenverhältnis erscheinen schmale schwarze Ränder.
  Welcher Modus passt, zeigt das Spiel selbst: Der Startbildschirm nennt die Bildschirmauflösung („Your screen:
  …“) und markiert die passende Option mit **BEST FIT FOR YOUR SCREEN** (1280×800 auf einem 1280 × 800-Bildschirm wie
  dem Steam Deck, 1280×720 auf einem 1280 × 720-Bildschirm, 2560×1440 ab einem Monitor mit mindestens 2560 × 1440,
  sonst 1920×1080); im Titelmenü steht unter DISPLAY z. B. „best fit for your 1920×1080 screen“ oder
  „scaled down to your 1920×1080 screen“. Im Titelmenü heißt der Steam-Deck-Modus kurz „FULLSCREEN 1280×800 (16:10)“.
- Im Vollbild ist der Mauszeiger ausgeblendet (das Spiel braucht keine Maus), im Fenster ist er sichtbar.
- F11 schaltet in den Vollbild-Modi zwischen Vollbild und einem Fenster im selben Seitenverhältnis um – in den Modi
  1920×1080 und 2560×1440 1920 × 1080, 1600 × 900 oder 1280 × 720, im Steam-Deck-Modus 1280 × 800 oder 1152 × 720, im
  Modus 1280×720 1280 × 720 oder 1152 × 648 (jeweils das größte, das auf den Bildschirm passt; die Berechnungsauflösung
  bleibt gleich); beim nächsten Start ist es wieder Vollbild.
- In den kleinen Modi 1280×800 und 1280×720 sind die kleinsten Beschriftungen (HUD-Überschriften wie SCORE / LIVES,
  Tasten- und Knopfsymbole in den Hinweiszeilen, Werte in der Schiffsauswahl, das BEST-FIT-Schild) etwas größer: Ihre
  Großbuchstaben sind auf dem Bildschirm mindestens 9 Pixel hoch (Valves Lesbarkeitsrichtlinie für das Steam Deck),
  damit sie auf einem 7-Zoll-Bildschirm lesbar bleiben.
- Die Zeile „Your screen: …“ sagt auch, welche Modi auf diesem Bildschirm schwarze Ränder bekommen (auf 16:9 der
  16:10-Modus, auf 16:10 die 16:9-Modi). Auf einem 1280 × 800- oder 1280 × 720-Bildschirm ist beim ersten Start die
  passende Option schon ausgewählt, und das erste Fenster wird an den Bildschirm angepasst.
- Die Highscore-Listen gelten für alle Modi gemeinsam. Die Wahl steht in der Einstellungsdatei (`settings.cfg`).

## Steam Deck

Das Spiel läuft auf dem Steam Deck; empfohlen ist der **Linux-Build** (die Windows-Version läuft über Proton
ebenfalls, der Linux-Build ist aber die direkte und empfohlene Variante):

1. Am Deck in den **Desktop-Modus** wechseln (Steam-Taste → Ein/Aus → „Zum Desktop wechseln“).
2. `PlanetProtector-linux-x86_64.zip` herunterladen und entpacken (Rechtsklick → „Entpacken“ / „Extract“).
3. In Steam (Desktop-Modus): „Spiele“ → „Ein Nicht-Steam-Spiel zur Bibliothek hinzufügen …“ → „Durchsuchen …“ →
   `PlanetProtector.x86_64` im entpackten Ordner `PlanetProtector` auswählen → „Ausgewählte Programme hinzufügen“.
   (Startet die Datei nicht, im Dateimanager unter Eigenschaften → Berechtigungen „Ausführbar“ anhaken.)
4. Zurück in den **Spielmodus** wechseln und Planet Protector aus der Bibliothek (Rubrik „Nicht-Steam“) starten.
5. Beim ersten Start **FULLSCREEN 1280×800 (16:10, STEAM DECK)** wählen (das Spiel markiert ihn als „BEST FIT FOR
   YOUR SCREEN“ und hat ihn schon ausgewählt – einfach A drücken): Das Bild füllt den Bildschirm ohne Ränder. Ändern lässt sich das jederzeit im Titelmenü unter DISPLAY.

Die eingebauten Bedienelemente des Decks funktionieren ohne Einrichtung als Controller (siehe Tabelle „Steuerung“: Steuerkreuz
oder linker Stick bewegen, A/B feuern, Start pausiert). Einstellungen und Highscores liegen wie unter Linux in
`~/.local/share/planet_protector/`.

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
