# Original-Vorgabe des Auftraggebers (Referenz, deutsch)

Dies ist der vom Auftraggeber hochgeladene Beispiel-Prompt (ursprünglich für eine andere KI geschrieben).
Verbindlich für dieses Projekt sind laut Auftraggeber:
- die **Spielregeln** (Abschnitte A/B ohne Überschrift, C, D, E, F, G, H),
- die **Farbgebung** (Farben in E, Farbaussagen in I: Gegnerfarben, Planetenfarben, Bodenfarben),
- **Menüs & Sequenzen** (J) und **Steuerung & Highscores** (L).
Frei/eigenes Design: Audio (K – ausdrücklich "gerne viel moderner", kein POKEY nötig) und die übrigen Grafik-Details aus I
(Stil, Formen, Effekte). Das Spiel heißt **"Planet Protector"**. Sprache im Spiel: Englisch.
Grafik: in Blender vorgerenderte Sprites.

---

Logische Auflösung 960 × 720, skalierbar mit unverändertem Seitenverhältnis. Bodenoberfläche y=685; Spielerschiff ungefähr bei y=659. Bewegung ausschließlich horizontal, x zwischen 30 und 930; Grundtempo 350 Pixel/Sekunde. HUD: Punkte, Leben, Level, Schwierigkeit, Spielzeit MM:SS,t. Ein gegnerischer Treffer kostet genau ein Leben. Mehrere Projektile im selben Simulationsschritt dürfen nicht mehrere Leben kosten. Nach einem Treffer eigene und gegnerische Projektile entfernen, Spielerexplosion zeigen und ungefähr 1,3 Sekunden Wiedererscheinungszeit geben; währenddessen Kampf pausieren. Bei null Leben endet der Lauf. Kein Lebensverlust allein durch Levelwechsel. Eigene Salven starten ungefähr bei y=639. Solange auch nur ein Projektil der vorigen eigenen Salve auf dem Spielfeld ist, darf keine neue Salve entstehen. Gedrückthalten der Feuertaste ist erlaubt. Doppelschüsse sind EINE Salve. Nicht durchschlagende Projektile verschwinden beim Treffer. Durchschlagende Projektile dürfen jeden einzelnen Gegner pro Projektil höchstens einmal treffen. Ein Teilungstreffer darf mit demselben Projektil nicht sofort die Kinder treffen. Eine zweite Kugel einer Doppelsalve bleibt ein eigenständiges Projektil. Gegner bewegen sich auf drei horizontalen Bahnen: Mittelpunkte y=180, 300, 420, entsprechend zweitem, drittem und viertem Bildschirmsechstel. Kleine vertikale Schwingung von etwa ±22 Pixeln, ohne Bahnwechsel. Horizontale Grenzen ungefähr x=50 und x=910. Gegner wenden an den Grenzen. Ab Level 10 kommen unabhängige Richtungswechsel nach zufällig 1,2–3,2 Spielsekunden hinzu. Gegnergrundbreite 90 Pixel; visuelle Planetenvarianten dürfen breiter sein, ohne die Trefferflächen zu vergrößern. Referenz für Trefferprüfung: eigene Schüsse gegen Gegner etwa |dx|<49 und |dy|<21, bei Fragmenten entsprechend skalieren. Gegnergeschosse gegen Spieler etwa |dx|<21 und |dy|<15. Verhindere übersprungene Kollisionen bei hoher Geschwindigkeit mittels geeigneter Simulationsschritte oder kontinuierlicher Kollisionsprüfung. Ein freier Gegnerplatz wird nach etwa zwei Spielsekunden nachbesetzt, bis die vorgegebene Gesamtzahl ORIGINALGEGNER erzeugt wurde. Bei Teilungsgegnern ist der Platz erst nach Zerstörung BEIDER Hälften frei. Gesamtzahl und Nachrücken dürfen niemals durch die Kinder verdoppelt werden.

C. SCHIFFE UND EIGENE PROJEKTILE
Name | Projektiltempo px/s | Anzahl | mitgeführt | durchschlagend
INTERCEPTOR | 500 | 1 | nein | nein
FIGHTER | 430 | 1 | ja | nein
DOUBLE DART | 430 | 2 | nein | nein
DOUBLE HUNTER | 350 | 2 | ja | nein
BLASTER | 350 | 1 | nein | ja
HUNTER | 270 | 1 | ja | ja
Mitgeführt heißt: Die horizontale Position des bereits fliegenden Projektils folgt jederzeit der aktuellen Schiffsposition plus seinem ursprünglichen Seitenabstand. Keine automatische Zielsuche. Doppelschüsse: Abstände ±12 Pixel. Alle Schiffe haben dieselbe horizontale Bewegungsgeschwindigkeit. Modern-Darstellung: - Interceptor: einzelner blauer Laser mit Glow. - Fighter: eine Rakete mit sichtbarem Körper und Antrieb. - Double Dart: zwei blaue Laser. - Double Hunter: zwei Raketen. - Blaster: dicker roter Laser mit Glow. - Hunter: zwei nebeneinander dargestellte Raketen mit dicken Sprengköpfen; zusammen aber EIN logisches durchschlagendes Projektil, keine Doppelwirkung. Schiffsauswahl zeigt animierte Vorschauen mit denselben Projektilgrafiken.

D. SCHWIERIGKEIT, ZEIT UND ABSCHLUSS
Beginner: 5 Leben, Spieltempo ×1,00. Normal: 3 Leben, ×1,00. Hard: 3 Leben, ×1,20. Expert: 1 Leben, ×1,44 (20 % schneller als Hard). Schwierigkeit beim Start des Laufs festschreiben. Bewegung, Projektile, Feuertimer, Nachrücken und spielinterne Zeitfenster beschleunigen; Menüs, Ankunftssequenzen, Musik und die gemessene Echtzeit nicht beschleunigen. Spielzeit zählt nur während aktiven Levelspiels, ohne Pause und Respawn. Nach dem letzten Gegner bleiben vorhandene feindliche Projektile gefährlich; diese Zeit zählt weiterhin. Sobald das Ziel erfüllt ist und keine feindlichen Projektile mehr existieren, zählt reine Explosionswartezeit nicht mehr. Der Bildschirmwechsel wartet trotzdem auf das Ende der Explosionen. Im Bonuslevel zählt die Flugzeit des letzten Schusses, solange das Ziel noch nicht erfüllt ist. Bei null Versuchen endet die aktive Zeit erst, wenn auch die letzte eigene Salve verschwunden ist. Ein Lebensverlust in der Schlussphase verhindert den Flawless-Bonus. Levelbonus, Extra-Leben und Zustandswechsel dürfen jeweils nur einmal erfolgen.

E. LEVELDATEN
Notation: Bahnen = Anzahl originaler Gegnerplätze oben/mittig/unten, nicht Kinder. Tempo = Faktor auf Grundtempo 62 px/s vor Schwierigkeitsfaktor. Feuer = Frequenzfaktor, kein Intervallmultiplikator. Basisintervall zufällig 1,8–2,8 Spielsekunden; durch Feuerfaktor teilen. Punkte = pro endgültig vernichteter Figur; bei Teilung also pro Hälfte. Farben = möglichst stufenloser Verlauf von oben nach unten.
Lvl;Name;Gesamt;Bahnen;Tempo;Feuer;Farben;Punkte;Abschlussbonus
1;Neptune 1;10;1/1/1;1;1;blau bis hellcyan;10;100
2;Neptune 2;10;1/1/1;1;1.2;dunkelrot bis gelb;10;100
3;Neptune 3;12;1/1/2;1;1.2;dunkelviolett bis rosa;10;100
4;Uranus 1;12;1/1/2;1.2;1.25;dunkelgrün bis gelb;25;250
5;Uranus 2;16;2/1/2;1.2;1.3;hellgrau bis fast schwarz;25;250
6;Uranus 3;16;2/1/2;1.2;1.35;dunkelgrün bis fast schwarz;25;250
7;Saturn 1;10;1/1/1;1.2;1.25;dunkelgelb bis weiß;25;500
8;Saturn 2;12;1/1/1;1.38;1.3;dunkelblau bis hellblau/weiß;25;500
9;Saturn 3;12;1/1/1;1.518;1.35;dunkelrot bis hellrot/weiß;25;500
10;Jupiter 1;16;1/1/1;1.6698;1.4;dunkelrot bis hellrot/weiß;40;750
11;Jupiter 2;16;1/1/2;2.00376;1.75;türkis bis fast schwarz;40;750
12;Jupiter 3;16;1/1/2;2.404512;1.9;orange bis fast schwarz;50;900
13;Mars / Bonus;20;1/1/0;3.606768;0;braun bis fast schwarz;0;Sonderregel
14;Mars 1;12;1/1/1;1.5;1.9;violett bis fast schwarz;75;1000
15;Mars 2;20;1/2/1;1.8;2.2;violett bis fast schwarz;100;1500
16;Mars 3;25;2/2/1;2;2.5;violett bis fast schwarz;110;2000
17;Earth 1;40;2/2/2;2.2;2.6;Regenbogen violett oben bis gelb unten;120;2000
18;Earth 2;40;2/2/2;2.4;2.2;Regenbogen gelb oben bis violett unten;120;2000
19;Earth 3;12;1/1/1;2.6;2.4;schwarz;150;3000
20;Earth – Final Battle;30;2/2/2;2.9;2.5;schwarz;150;500
Extra-Leben für Abschluss OHNE Lebensverlust nur in 10,15,16,17,18. Bonuslevel 13 hat seine eigene Extra-Leben-Regel. Sonst keine zusätzlichen Flawless-Leben und keine frei erfundenen Score-Meilenstein-Leben.

F. FEINDLICHES FEUER
Geschosstempo vor Schwierigkeit immer 220 px/s. Alle Geschosse einer Salve fliegen parallel, keine aufgespreizte Fächerbewegung und keine Nachverfolgung. Richtung wird beim Abschuss nach Spielerposition links/rechts gewählt. Senkrecht: (vx,vy)=(0,220). 5/7 Uhr: (±110,190.5255888). 4/8 Uhr: (±190.5255888,110). Breitenprozent bezeichnet die volle Salvenbreite inklusive Geschossbreite, bezogen auf die ursprüngliche 90-Pixel-Grundbreite, bei Kindern skaliert.
Lvl;volle Figur: Geschosse/Breite/Richtung;Schussberechtigung
1;1/zentral/senkrecht;nur die aktuell unterste Figur
2;4/70%/senkrecht;nur die aktuell unterste Figur
3;4/70%/senkrecht;die zwei aktuell untersten Figuren
4;6/55%/5-7 Uhr;die zwei aktuell untersten Figuren
5;6/65%/5-7 Uhr;die zwei aktuell untersten Figuren
6;8/75%/5-7 Uhr;die zwei aktuell untersten Figuren
7;6/55%/5-7 Uhr;die zwei aktuell untersten Figuren, Kinderregel beachten
8;6/60%/5-7 Uhr;die zwei aktuell untersten Figuren, Kinderregel beachten
9;6/60%/5-7 Uhr;die zwei aktuell untersten Figuren, Kinderregel beachten
10;8/80%/5-7 Uhr;nur die aktuell unterste Figur, Kinderregel beachten
11,12;8/80%/5-7 Uhr;alle Figuren auf der untersten Bahn
13;keine;niemand
14;8/80%/5-7 Uhr;nur unterste Bahn
15,16;10/90%/5-7 Uhr;nur unterste Bahn
17;12/100%/4-8 Uhr;alle Figuren auf der untersten Bahn
18,19;12/100%/4-8 Uhr;alle Figuren auf mittlerer und unterster Bahn
20;12/100%/4-8 Uhr;alle Figuren
Nur in Level 10: vier nebeneinanderliegende Spalten mit jeweils zwei vertikal um ungefähr 18 Pixel versetzten Geschossen. Kinder: zwei Spalten à zwei. Sonst Geschosse nebeneinander in einer Reihe. Level 1–10: ein Timer für die unterste, gegebenenfalls ein zweiter Timer für die zweitunterste Figur. Initial 2,0 bzw. 2,5 Sekunden / Feuerfaktor, danach zufällig 1,8–2,8 / Feuerfaktor. Eine wehrlose Figur gibt ihr Schussrecht nicht an eine höhere Figur weiter. Ab Level 11 pro berechtigter Figur eigener Timer. Projektile sehen wie brennende Feuerbälle mit heißem Kern und Schweif aus. Beim Erreichen des Bodens werden sie verschluckt. Auch Glow und Schweif dürfen nicht unterhalb der Oberfläche gezeichnet werden. Entferne sie spätestens, wenn das gesamte Projektil unter dem Boden liegt; auch seitlich entsorgen.

G. TREFFERREGELN
Level 1–6,13,17,18: ein Treffer zerstört einen Gegner. Level 7–12: erster Treffer teilt einen Originalgegner in zwei Kinder. 7: Kindergröße je 40 %, 8–12: je 45 % der ursprünglichen linearen Größe. Kinder bleiben auf der Bahn des Elterngegners, bewegen sich unabhängig und schlagen synchron mit den Flügeln. Ein Treffer zerstört ein Kind. Teilung selbst gibt keine Punkte; jedes zerstörte Kind gibt Tabellenpunkte. Beispiel Level 7: vollständig beseitigtes Paar = 50 Punkte. 7–8: Genau ein Kind darf schießen, das andere bleibt dauerhaft wehrlos, auch nach Tod seines bewaffneten Partners. Bewaffnetes Kind feuert zwei Projektile. 9: Beide Kinder dürfen auf der untersten Bahn je zwei Projektile schießen; Kinder auf oberen Bahnen sind wehrlos. Zusätzlich gilt die Rangregel aus F. 10: Kinder auf unterster Bahn können vier Projektile schießen; obere Kinder nicht. Zusätzlich darf insgesamt nur die unterste Figur schießen. 11–12: Alle Kinder der untersten Bahn können vier Projektile schießen; Kinder auf den beiden höheren Bahnen nicht.
Level 14–16: globale Farbstufen-Sperre, keine gewöhnlichen drei Trefferpunkte. Start violett. Ein Treffer macht einen violetten Gegner gelb. Ein gelber Gegner darf erst grün werden, wenn KEIN sichtbarer violetter Gegner mehr lebt. Ein grüner Gegner darf erst zerstört werden, wenn ALLE sichtbaren Gegner grün sind. Höhere Stufen bleiben während einer Sperre erhalten. Nachrückende violette Gegner sperren die höheren Aktionen wieder. Gesperrte Treffer geben keinen Fortschritt und keine Punkte. Normale Schüsse werden auch bei gesperrten Treffern verbraucht; durchschlagende fliegen weiter, dürfen denselben Gegner aber pro Projektil nur einmal berühren. Gelb-Verlauf hellgelb bis dunkelgelb; Grün-Verlauf hellgrün bis dunkelgrün. Punkte nur bei endgültiger Zerstörung. Vor Level 14 einen englischen, verständlich illustrierten Regelbildschirm zeigen; Enter bestätigt.
Level 19–20: schwarze Gegner, orangefarbener Trefferblitz etwa 0,18 Sekunden. Zerstörung bei drei Treffern innerhalb eines ROLLENDEN Fensters von zehn Spielsekunden. Speichere einzelne Trefferzeiten und entferne veraltete Treffer. Kein pauschaler Reset aller Treffer zehn Sekunden nach dem ersten Treffer. Beispiel: Treffer t=0,8,11 zerstören nicht; t=8,11,12 zerstören. Das Zeitfenster wird mit Hard/Expert beschleunigt. Punkte nur bei Zerstörung.

H. BONUSLEVEL 13
Titel „Prove Your Accuracy!“. 100 Schussversuche, Doppelsalve kostet einen. Keine feindlichen Geschosse. Ende bei 20 vernichteten Gegnern oder wenn alle Versuche verbraucht und die letzte Salve fertig geflogen ist. Kein Score für Abschüsse. Bonus = ungenutzte Versuche × Schiffsfaktor: Interceptor 400; Double Dart und Blaster 300; übrige Schiffe 200. Ein zusätzliches Leben nur bei Bonus >6000, nicht bei genau 6000. Ergebnisbildschirm: verbleibende Versuche, Faktor, Bonus, gegebenenfalls Extra-Leben. Bis Enter stehen lassen; danach Mars-Regelerklärung und Level 14.

I. MODERN-GRAFIK (nur Farbaussagen verbindlich)
Moderner 2D-Arcade-Look: klare Silhouetten, metallische Schiffe, weiche Farbverläufe, kräftige Lichtakzente, lesbare englische UI. Keine verpflichtenden gekauften Assets. Prozedurale Texturen, Shader und eigene Vektorgeometrie sind geeignet. Verfügbarkeit von Blender/Krita ist keine Pflicht, sie zu benutzen. Sterne: viele überwiegend kleine schwache Lichtpunkte, wenige helle Sterne mit weichen Halos; subtile weißliche, bläuliche und warme Töne. Mehrere langsam bewegte Tiefenebenen, ungleichmäßige Verteilung. Kein gleichmäßiges Konfetti und kein starkes Flackern. Texturen/Geometrie cachen statt pro Frame neu bauen. Gegner pro Planet zunehmend bedrohlich: Neptun schlank; Uranus sichelförmig; Saturn gegabelte Insektenform; Jupiter breite Panzerplatten; Mars Hakenflügel; Erde schwere Kronenform. Breitenfaktoren 1.00/1.02/1.04/1.06/1.08/1.10, rein kosmetisch. Deutlich sichtbarer weicher Flügelschlag ungefähr 2,5 Zyklen pro Spielsekunde, auch bei Kindern. Keine selbstüberschneidenden Polygone, keine flimmernden Gradientstreifen. Farben aus Leveltabelle haben Vorrang vor Materialdetails. Schwarze Erdgegner durch dezente Kontur und Augen erkennbar halten. Explosionen: heller kurzer Kernblitz, glühende Wolken, Funken/Trümmer und expandierende Schockwelle. Gegner ungefähr 0,9 Sekunden; Spieler größer, ungefähr 1,3 Sekunden. Nichttödliche Treffer erhalten kleinere Trefferimpulse. Effekte sollen spektakulär sein, das Ausweichen aber weiterhin erlauben. Planeten oben rechts, weiche Beleuchtung und plastische Oberfläche: Neptun blau; Uranus heller blaugrün mit sichtbarem Ring; Saturn hellbraun mit mehrfarbigen Ringen; Jupiter dunkler braun mit Bändern und rotem Fleck; Mars rötlich mit natürlichen Oberflächenstrukturen; Erde klar erkennbar durch blaue Ozeane, Kontinente und Wolken. Bodenfarben passen zum jeweiligen Planeten. Sichtbarer Kugeldurchmesser ungefähr 174 px zu Beginn eines Planetenabschnitts, zweite Stufe Faktor 220/192, dritte Stufe Faktor 275/192. Ringe kommen außen hinzu. Zoomstufen: Neptun 1/2/3, Uranus 1/2/3, Saturn 1/2/3, Jupiter 1/2/3, Bonus 13 Stufe 1, Mars 14/15/16 Stufe 1/2/3, Erde 17/18/19/20 Stufe 1/1/2/3. Erdanzeige in Level 18 bleibt bewusst klein.

J. MENÜS UND SEQUENZEN
Title -> Schiffsauswahl -> Levelspiel. Im Titel Schwierigkeit, Music On/Off, Sound Effects On/Off und Highscores anbieten; Optionen dauerhaft speichern. Zwischen gewöhnlichen Leveln Punkte/Bonus und verbleibende Kämpfe bis zum nächsten Planeten anzeigen. Keine falschen Planetenzähler nach Bonuslevel 13. Ankunftssequenzen nach 3,6,9,12,16: 0–3 s: kleine Sterne von rechts nach links. 3–6 s: passende Nachricht einblenden. 6–7 s: Nachricht nach links hinausschieben. 7–12 s: Zielplanet erscheint klein in Bildschirmmitte und zoomt etwa fünf Sekunden heran. Anschließend Bestätigung zum Fortfahren ermöglichen. Nachrichten exakt: „Neptun has been secured - approaching Uranus“ „Uranus has been secured - approaching Saturn“ „Saturn has been secured - approaching Jupiter“ „Jupiter has been secured - approaching Mars“ „Mars has been secured - protect EARTH!“ Ankunftssequenzen vollständig stumm. Nach Level 20 vor der Namenseingabe: Erde im Hintergrund, Gratulationstext: „You are a real champion on the trigger. You moved smoothly through enemy lines, you destroyed them all! Everlasting love to You, oh great PLANET PROTECTOR!“ Enter führt zur Highscoreeingabe.

K. AUDIO (nicht verbindlich – eigenes, modernes Design; nur zur Information)
Eigenständig erzeugte Musik, keine fremden Melodien kopieren. Titelmelodie bedrohlich und motivierend, klanglich an Atari POKEY angelehnt, mehrstimmige synthetische Arpeggien und markante Melodie. Als brauchbarer Gestaltungsrahmen: 16 Takte, 150 BPM, nahtlose Schleife. Gesamte Titelmelodie mit linearem Lautstärkefaktor 0,70 gegenüber ihrer normalen Mischung abspielen. Spielmusik: 4/4, ein Takt 1,2 Sekunden = 200 BPM. Vier Viertel pro Takt. Kick: xxxx; Snare: --x-; Bass: xxxx. Bass beginnt auf E1 ≈41,203 Hz, steigt um einen Halbton bei endgültiger Zerstörung einer Figur; bei Teilungsgegnern also pro zerstörtem Kind. Kein Anstieg beim Teilungstreffer, Farbwechsel oder nichttödlichen Erdtreffer. Bei jedem Level E1. In 17,18,20 zusätzlich nach je zehn Zerstörungen auf E1 zurückspringen; nicht in 19. Ohne Zyklus Anstieg auf maximal 40 Halbtöne begrenzen. Bassfortschritt auch bei ausgeschalteter Musik intern weiterführen. Kleiner Explosions-/Treffersound beim Gegnertreffer. Spielerexplosion lauter und höherfrequent, ohne Clipping. Musik/Effekte unabhängig abschaltbar; Schalter müssen sofort wirken. Im Titel nur Titelmusik; in Auswahl, Ankunft, Highscores und Endscreen keine Spielmusik. Während Pause und Respawn stumm; bei Rückkehr darf der Beat am Taktanfang neu starten. Kein Tempoanstieg der Musik durch Schwierigkeitsgrad. Audioassets vollständig mit exportieren.

L. STEUERUNG UND HIGHSCORES
Tastatur: Pfeile/A/D bewegen, Leertaste feuern, Enter bestätigen, P/Escape Pause, Q aus Pause zum Titel, F11 Vollbild. Escape im Titel darf beenden. Controller: D-Pad oder linker Analogstick links/rechts; A/B feuern; X/Y bestätigen; A darf auch im Titel und in Schiffsauswahl bestätigen. Start pausiert im Spiel und bestätigt in Menüs; Select/Back öffnet im Titel Highscores und führt aus Pause zurück. B geht aus Untermenüs zurück, wird im Titel ignoriert. PlayStation: Kreuz/Kreis feuern, Quadrat/Dreieck bestätigen, Options pausiert. Eingabewiederholung in Menüs kontrollieren; keine Mehrfach- Bestätigung durch gehaltene Taste. Analoge Bewegung mit vernünftiger Deadzone. Vier getrennte Top-10-Listen nach Schwierigkeit. Primär Score absteigend, sekundär echte Spielzeit aufsteigend. Zeit intern ausreichend genau speichern, Anzeige Zehntelsekunden. Namenseingabe höchstens fünf Zeichen aus A–Z,0–9,_,-; leer -> PILOT. Spaltenüberschriften müssen über den zugehörigen Werten stehen. Controller-Namenseditor: horizontal bewegt nur den Cursor; vertikal verändert das Zeichen. Auf leerem Endfeld fügt eine vertikale Eingabe zunächst A ein, ohne es sofort weiterzuschalten. Cursor höchstens auf bestehende Zeichen oder nächste freie Stelle, niemals über fünf Zeichen hinaus. Bei diagonaler Stickbewegung nur stärkste Achse, Gleichstand horizontal. Auch D-Pad-Diagonalen abfangen. B löscht letztes Zeichen, X/Y bestätigt. Tastatur Backspace löscht.
