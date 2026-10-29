# Windows-Version (Build- und Testnotizen)

Ergebnis: eine einzelne 64-Bit-EXE für Windows 10/11 mit eingebettetem PCK, wie bei der Linux-Version.

| Datei | Inhalt |
|---|---|
| `build/windows/PlanetProtector.exe` | Spiel (≈ 126 MB, GUI-Programm ohne Konsolenfenster) |
| `build/PlanetProtector-windows-x86_64.zip` | `PlanetProtector/PlanetProtector.exe` + `PlanetProtector/LIESMICH.txt` (≈ 54 MB) |

## Bauen

```bash
tools/build.sh            # beide Plattformen + Windows-ZIP
tools/build.sh windows    # nur Windows (bzw. "linux")
```

Voraussetzungen: Godot 4.7.2 (`godot` im PATH oder `GODOT=...`) mit den 4.7.2-Export-Templates für Linux und Windows
(`~/.local/share/godot/export_templates/4.7.2.stable/windows_release_x86_64.exe` usw.) sowie `python3` für die ZIP-Datei.
Die Linux-Datei liegt jetzt in `build/linux/PlanetProtector.x86_64`; `build/PlanetProtector.x86_64` ist ein Symlink darauf.
Der Text der `LIESMICH.txt` steht in `tools/build.sh` (wird als UTF-8 mit BOM und CRLF geschrieben, damit der Windows-Editor
Umlaute richtig zeigt).

## Export-Preset „Windows Desktop“ (`game/export_presets.cfg`)

- x86_64, Release, PCK eingebettet, kein Konsolen-Wrapper, dieselben Filter wie das Linux-Preset
  (`*.json, *.raw, *.bin, *.txt` dazu, `tests/*` und `dev/*` weg). Das Linux-Preset ist unverändert.
- EXE-Ressourcen setzt Godot 4.7 selbst (`application/modify_resources`, kein rcedit nötig): Icon aus `game/icon.ico`,
  Produktname und Dateibeschreibung „Planet Protector“, Datei- und Produktversion `1.6.0.0`, keine Firma, kein Copyright.
  Bei einer neuen Version `application/file_version` und `application/product_version` anpassen (Format `a.b.c.d`).
- `game/icon.ico` wurde aus `game/icon.png` erzeugt (16, 20, 24, 32, 40, 48, 64, 128 und 256 px); Godot übernimmt davon
  16/32/48/64/128/256 in die EXE. Neu erzeugen:
  `python3 -c "from PIL import Image; Image.open('game/icon.png').convert('RGBA').save('game/icon.ico', sizes=[(s, s) for s in (16, 20, 24, 32, 40, 48, 64, 128, 256)])"`

## Grafik: OpenGL und ANGLE

Der Renderer ist `gl_compatibility`. Unter Windows nutzt Godot zuerst natives OpenGL 3.3. ANGLE (OpenGL ES über
Direct3D 11) ist in den offiziellen Templates statisch eingebaut, es werden keine DLLs mitgeliefert.
`rendering/gl_compatibility/fallback_to_angle` ist der Godot-Standard `true` und steht deshalb nicht in `project.godot`.
Dazu kommt die Standardliste `force_angle_on_devices` (54 Einträge, alte Radeon- und Intel-HD-Chips). Im exportierten
Spiel unter Wine geprüft: `driver.windows=opengl3`, `fallback_to_angle=true`. Unter Linux ändert sich nichts.
ANGLE von Hand erzwingen: `PlanetProtector.exe --rendering-driver opengl3_angle`.

## Smoke-Test unter Wine 9

```bash
export WINEPREFIX=<scratch>/wineprefix WINEDEBUG=-all WINEDLLOVERRIDES="dinput8=d"
cd build/windows
xvfb-run -a -s "-screen 0 1280x960x24" wine PlanetProtector.exe --rendering-driver opengl3 --audio-driver Dummy \
  -- --screen=title '--screenshot=Z:\tmp\shots\title.png' --screenshot-delay=3
#   ... -- --level=17 --dev --autoplay --invincible '--screenshot=Z:\tmp\shots\l17.png' --screenshot-delay=14
#   ... -- --screen=attract --attract-level=10 --attract-seed=7 '--screenshot=Z:\tmp\shots\attract.png' --screenshot-delay=9
```

- **Wine-Absturz beim Start:** Wine 9.0 stürzt mit *jeder* Godot-4.7.2-EXE (auch mit den unveränderten Templates) beim
  Start ab: Godot ruft `VirtualProtect(..., NULL)` auf, als es Einsprünge in `dinput8` umbiegt. Echtes Windows gibt
  dort nur `FALSE` zurück, Wine 9.0 liest über den NULL-Zeiger. Abhilfe nur für Wine: `WINEDLLOVERRIDES="dinput8=d"`.
- Pfade in Spielargumenten müssen Windows-Pfade sein (`Z:\...`); `/tmp/...` funktioniert nicht.
- Ergebnisse (Build vom 24.10.2026): Titel, Level 17 mit Autopilot und Attract-Modus werden korrekt dargestellt
  (OpenGL 4.5, Mesa llvmpipe) und erzeugen keine Skriptfehler. Alle 78 Assets sind in der EXE (26 `.raw`/`.json` mit
  korrekter Größe, 52 importierte Ressourcen), der Musik-Sequencer lädt seine `.raw`-Samples. `user://` ist
  `%APPDATA%\planet_protector` und beschreibbar: Eine geänderte Schwierigkeit landet in `settings.cfg`, ein
  Highscore über die Namenseingabe in `highscores.json`, und Escape im Titel beendet das Spiel mit Exit-Code 0.
  Das Fenster wird auf den Bildschirm verkleinert (1280 × 938 auf einem 960 px hohen Bildschirm). Ohne Audiogerät
  wechselt Godot ohne Absturz von WASAPI auf Dummy.
- Icon und Versionsdaten mit einem kleinen Win32-Testprogramm geprüft (`ExtractIconExW`, `PrivateExtractIconsW` mit
  16/32/48/256 px, `GetFileVersionInfoW`): Das Icon ist korrekt, ProductName/FileDescription sind „Planet Protector“,
  die Version ist 1.6.0.0, CompanyName und LegalCopyright fehlen. (Eigenheit von Godot 4.7.2: Der Name der
  Icon-Gruppe in der EXE ist leer statt „ICON“. Für Explorer und die Icon-APIs ist das ohne Folgen.)
- Unter Wine nicht prüfbar: die Darstellung mit ANGLE (der HLSL-Compiler von Wine kann die Geometry-Shader von ANGLE
  nicht übersetzen, das Bild bleibt weiß; Windows bringt dafür `d3dcompiler_47` mit), der automatische Wechsel zu
  ANGLE, echter Ton, Controller, SmartScreen und die intelligente App-Steuerung. Vor der Auslieferung einmal auf einem
  echten Windows-10/11-PC starten.

## Hinweise für die Auslieferung

- Die EXE ist nicht signiert. SmartScreen warnt beim ersten Start („Weitere Informationen“ → „Trotzdem ausführen“),
  manche Virenscanner melden unsignierte Godot-Spiele fälschlich. Unter Windows 11 mit eingeschalteter
  *intelligenter App-Steuerung* (Smart App Control, auf manchen neu installierten PCs aktiv) wird die EXE ganz
  blockiert, ohne „Trotzdem ausführen“; dann hilft nur, die Funktion auszuschalten (Windows-Sicherheit →
  App- & Browsersteuerung), was auf älteren Windows-11-Ständen nur durch Zurücksetzen von Windows rückgängig zu
  machen ist. Beides steht in der `LIESMICH.txt` (Abschnitte STARTEN und PROBLEME?). Abhilfe wäre ein
  Code-Signing-Zertifikat (`codesign/*` im Preset): Signierte Programme lässt die intelligente App-Steuerung zu, die
  SmartScreen-Warnung verschwindet aber erst, wenn die Signatur genug Reputation gesammelt hat.
- Einstellungen und Highscores: `%APPDATA%\planet_protector\` (`settings.cfg`, `highscores.json`).
