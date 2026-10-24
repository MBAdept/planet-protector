# PLANET PROTECTOR – Binding Specification


This is the single source of truth for everyone working on this project.
Engine: **Godot 4.7.2** (GDScript, `gl_compatibility` renderer). Art: **Blender 5.2 (bpy, Cycles CPU)**.
Audio: offline synthesis with Python (numpy/scipy) + a small runtime sequencer in Godot.
Deliverables: single executables with embedded PCK for Linux x86_64 (`build/linux/PlanetProtector.x86_64`) and Windows x86_64 (`build/windows/PlanetProtector.exe`), see docs/WINDOWS.md.
All in-game text is **English**.

Tooling paths (this machine):
- Godot editor binary: `godot` (on PATH, 4.7.2). Export templates installed.
- Blender as Python module: `/tmp/claude-0/-home-user/0a1ab13c-d1d4-5f9b-bc34-b18cd450004b/scratchpad/tools/bpyenv/bin/python` (bpy 5.2.3).
  Use **Cycles on CPU** (Eevee works but is ~30x slower here). Render paths must be absolute.
- Python 3.13 with numpy + scipy: `python3`. ffmpeg with libvorbis is available.
- Headless test run: `godot --headless --path game -s res://tests/run_tests.gd`
- Visual check (real rendering via Mesa llvmpipe):
  `xvfb-run -a -s "-screen 0 1280x960x24" godot --rendering-driver opengl3 --audio-driver Dummy --path game -- <user args>`
- Re-import after adding/changing assets: `godot --headless --path game --import`

Rules marked **[RULE]** are mandatory gameplay rules taken from the client's reference document.
Everything marked **[DESIGN]** is our own design decision (may be refined, but stay consistent).

---------------------------------------------------------------------------------------------------

## 1. Screen, coordinates, timing

- [RULE] Logical resolution 960 × 720; window scalable, aspect ratio preserved (stretch mode `canvas_items`, aspect `keep`, letterbox).
- [RULE] Ground surface at **y = 685**. Player ship center at **y ≈ 659**. Player moves only horizontally, center x clamped to **[30, 930]**, base speed **350 px/s**.
- [RULE] HUD shows: score, lives, level, difficulty, play time as `MM:SS.t`.
- Coordinates: game pixels, origin top-left, +y down.
- **Game time vs. real time** [RULE]: difficulty multiplies the speed of the simulation.
  `game_dt = real_dt * speed_factor`. Everything in the simulation (player movement, projectiles, enemy movement,
  fire timers, refill timers, respawn delay, explosion lifetimes, hit-flash, the 10 s rolling window, direction-change timers)
  runs on game time. Menus, arrival sequences, music tempo and the measured **play time** (real seconds) are NOT accelerated.
- [RULE] Simulation uses **fixed sub-steps** (1/240 game-second) so that no collision can be skipped at high speed.

## 2. Difficulty

| id | name     | lives | speed_factor |
|----|----------|-------|--------------|
| 0  | BEGINNER | 5     | 1.00         |
| 1  | NORMAL   | 3     | 1.00         |
| 2  | HARD     | 3     | 1.20         |
| 3  | EXPERT   | 1     | 1.44         |

[RULE] The difficulty is fixed at the start of a run.

## 3. Player, lives, respawn

- [RULE] An enemy hit costs exactly one life. Several enemy projectiles hitting in the same simulation step cost only ONE life.
- [RULE] After a hit: remove all own and all enemy projectiles, show the player explosion, respawn after ≈ **1.3 game-seconds**. During that time combat is paused (enemies do not move, do not fire, refill timers do not run). Enemy wing-flap animation and explosion effects keep animating. [DESIGN] The ship respawns at x = 480. On respawn the level-1..10 rank fire timers are reset to their initial values (2.0/F and 2.5/F), per-figure timers (level ≥ 11) are reset to `2.0/F + rand(0, 0.8)/F`.
- [RULE] At zero lives the run ends (after the player explosion finished → Game Over).
- [RULE] No life is lost just because a level changes.
- [RULE] Losing a life in the final phase of a level (after the last enemy died but enemy bullets are still flying) prevents the flawless bonus.

## 4. Own projectiles (salvos)

- [RULE] A salvo starts at **y = 639** (projectile center), x = ship x (+ offset).
- [RULE] While at least one projectile of the previous own salvo is still on the field, no new salvo may be created. Holding the fire button is allowed (auto-refire as soon as the previous salvo is gone).
- [RULE] Double shots are ONE salvo. Offsets **±12 px**. The second bullet of a double salvo is an independent projectile (each one can hit on its own; each disappears on its own).
- [RULE] Non-piercing projectiles disappear on a hit. Piercing projectiles may hit each individual enemy at most once per projectile.
- [RULE] A split hit must not let the same projectile immediately hit the resulting children (add both children to the projectile's "already hit" set).
- Projectiles move straight up; removed when center y < -40.

### Ships

| id | name          | proj. speed px/s | count | guided ("mitgeführt") | piercing | bonus-level factor |
|----|---------------|------------------|-------|------------------------|----------|--------------------|
| 0  | INTERCEPTOR   | 500              | 1     | no                     | no       | 400                |
| 1  | FIGHTER       | 430              | 1     | yes                    | no       | 200                |
| 2  | DOUBLE DART   | 430              | 2     | no                     | no       | 300                |
| 3  | DOUBLE HUNTER | 350              | 2     | yes                    | no       | 200                |
| 4  | BLASTER       | 350              | 1     | no                     | yes      | 300                |
| 5  | HUNTER        | 270              | 1     | yes                    | yes      | 200                |

- [RULE] Guided means: the x position of an already flying projectile always equals the CURRENT ship x plus its original lateral offset. No homing.
- [RULE] All ships have the same movement speed (350 px/s base).
- [RULE] Projectile looks:
  - Interceptor: single blue laser with glow.
  - Fighter: one rocket with visible body and engine flame.
  - Double Dart: two blue lasers.
  - Double Hunter: two rockets.
  - Blaster: thick red laser with glow.
  - Hunter: two side-by-side rockets with thick warheads, drawn together but it is ONE logical piercing projectile (no double effect; hit test uses its center).

## 5. Enemies – movement, slots, refill

- [RULE] Three horizontal lanes with centers **y = 180, 300, 420** (lane 0 = top, 1 = middle, 2 = bottom). Enemies never change lanes.
- [RULE] Small vertical oscillation of about ±22 px. [DESIGN] `y = lane_y + 22*sin(phase + 2π*0.55*t)`, random phase per original; children inherit the parent's phase.
- [RULE] Horizontal limits ≈ x = 50 … 910. [DESIGN] Like all other reference coordinates these are CENTER positions: center x ∈ [50, 910] for all figures, children included (the widest cosmetic variant, 99 px, still stays on screen). Enemies turn around at the limits; spawn x and child placement use the same range.
- [RULE] From level 10 on: additionally independent random direction changes after a random 1.2–3.2 game-seconds (per figure, children included).
  [DESIGN] Stack breaking (only from level 10 on – below level 10 there are no direction changes except at the limits):
  a figure counts as *covered* while a figure on a LOWER lane (larger lane index, children included) is within |dx| < 60 px
  and moves in the SAME direction – without this, equally fast figures stay stacked until one turns, and a non-piercing
  shot always hits the lowest overlapping figure (in levels 14–16 often a locked one). After 0.5 game-seconds covered in a
  row the upper figure reverses early, but never sooner than 1.2 game-seconds after its own last direction change (limit
  turn, random change or earlier stack break; spawn / split counts as one); its random timer then restarts with
  rand(1.2, 3.2). A stack break thus only brings the next random change forward – never to less than 1.2 s after the
  previous change, and the restarted timer keeps the next interval ≤ 3.2 s. Runs with the enemy movement: game time,
  nothing counts during RESPAWN. (`LevelData.STACK_OVERLAP_DX`, `STACK_COVER_TIME`.)
- Enemy base speed: **62 px/s × level tempo** (× speed_factor through game time).
- [RULE] Enemy nominal width 90 px. Visual planet variants may be wider (cosmetic width factors per planet: Neptune 1.00, Uranus 1.02, Saturn 1.04, Jupiter 1.06, Mars 1.08, Earth 1.10) WITHOUT enlarging the hit area.
- [RULE] Hit tests: own projectile vs. enemy: `|dx| < 49·s` and `|dy| < 21·s` (s = enemy scale: 1, 0.40 or 0.45). Enemy bullet vs. player: `|dx| < 21` and `|dy| < 15` (player center (x, 659)).
- [RULE] Slots: the level table defines the number of ORIGINAL enemy slots per lane (top/middle/bottom). At combat start every slot is filled (as long as the total is not reached). A free slot is refilled after ≈ **2.0 game-seconds** until the level's total number of ORIGINAL enemies has been spawned.
- [RULE] For split enemies a slot is only free after BOTH halves are destroyed. Children never count towards the total or the refill.
- [DESIGN] Spawn (fair spawning, all levels): x uniformly random among all x within the limits that keep ≥ 160 px to every
  figure on the same lane AND a free column, i.e. ≥ 110 px to every figure on the OTHER lanes (children included), so a new
  enemy does not appear hidden behind a lower one. If the screen is too crowded for that, both distances are relaxed by the
  same factor (1.0, 0.9, … 0.0) and the first factor that leaves room is used (best compromise; the free set is computed
  exactly, one random number per spawn). Start direction: if a figure on another lane is within 250 px horizontally, the
  opposite of the CURRENT direction of the nearest such figure (the two separate instead of flying on as a stack);
  otherwise random. Short 0.45 s materialize effect (already hittable, already "visible").
  (`LevelData.SPAWN_MIN_DISTANCE`, `SPAWN_COLUMN_CLEARANCE`, `SPAWN_RELAX_STEPS`, `SPAWN_DIR_RANGE`.)
- Level goal: all ORIGINAL enemies spawned AND no enemy (incl. children) alive.

## 6. Level table [RULE]

Tempo = factor on base speed 62 px/s (before difficulty). Fire = frequency factor F (interval = rand(1.8, 2.8) / F).
Points per finally destroyed figure (per child for split enemies). Bonus = completion bonus added on completion.

| Lvl | Name                 | Total | Lanes (top/mid/bot) | Tempo    | Fire | Colors (top → bottom)                  | Points | Bonus |
|-----|----------------------|-------|---------------------|----------|------|----------------------------------------|--------|-------|
| 1   | Neptune 1            | 10    | 1/1/1               | 1        | 1    | blue → light cyan                      | 10     | 100   |
| 2   | Neptune 2            | 10    | 1/1/1               | 1        | 1.2  | dark red → yellow                      | 10     | 100   |
| 3   | Neptune 3            | 12    | 1/1/2               | 1        | 1.2  | dark violet → pink                     | 10     | 100   |
| 4   | Uranus 1             | 12    | 1/1/2               | 1.2      | 1.25 | dark green → yellow                    | 25     | 250   |
| 5   | Uranus 2             | 16    | 2/1/2               | 1.2      | 1.3  | light grey → almost black              | 25     | 250   |
| 6   | Uranus 3             | 16    | 2/1/2               | 1.2      | 1.35 | dark green → almost black              | 25     | 250   |
| 7   | Saturn 1             | 10    | 1/1/1               | 1.2      | 1.25 | dark yellow → white                    | 25     | 500   |
| 8   | Saturn 2             | 12    | 1/1/1               | 1.38     | 1.3  | dark blue → light blue/white           | 25     | 500   |
| 9   | Saturn 3             | 12    | 1/1/1               | 1.518    | 1.35 | dark red → light red/white             | 25     | 500   |
| 10  | Jupiter 1            | 16    | 1/1/1               | 1.6698   | 1.4  | dark red → light red/white             | 40     | 750   |
| 11  | Jupiter 2            | 16    | 1/1/2               | 2.00376  | 1.75 | turquoise → almost black               | 40     | 750   |
| 12  | Jupiter 3            | 16    | 1/1/2               | 2.404512 | 1.9  | orange → almost black                  | 50     | 900   |
| 13  | Mars / Bonus         | 20    | 1/1/0               | 3.606768 | 0    | brown → almost black                   | 0      | special |
| 14  | Mars 1               | 12    | 1/1/1               | 1.5      | 1.9  | violet → almost black                  | 75     | 1000  |
| 15  | Mars 2               | 20    | 1/2/1               | 1.8      | 2.2  | violet → almost black                  | 100    | 1500  |
| 16  | Mars 3               | 25    | 2/2/1               | 2        | 2.5  | violet → almost black                  | 110    | 2000  |
| 17  | Earth 1              | 40    | 2/2/2               | 2.2      | 2.6  | rainbow: violet (top) → yellow (bottom)| 120    | 2000  |
| 18  | Earth 2              | 40    | 2/2/2               | 2.4      | 2.2  | rainbow: yellow (top) → violet (bottom)| 120    | 2000  |
| 19  | Earth 3              | 12    | 1/1/1               | 2.6      | 2.4  | black                                  | 150    | 3000  |
| 20  | Earth – Final Battle | 30    | 2/2/2               | 2.9      | 2.5  | black                                  | 150    | 500   |

- [RULE] Extra life for completing a level WITHOUT losing a life ("flawless") only in levels **10, 15, 16, 17, 18**. Level 13 has its own extra-life rule. No other extra lives (no score milestones).
- [RULE] Level bonus, extra life and state transitions happen exactly once each.
- Colors: smooth gradient from top to bottom of the figure (no banding; dither in the shader). Exact RGB values live in `scripts/data/level_data.gd`. Table colors have priority over material details.

## 7. Enemy fire [RULE]

- Enemy bullet speed (before difficulty) is always 220 px/s. All bullets of one salvo fly parallel (no fan, no tracking).
- Direction chosen at the moment of firing from the player's position (left/right of the firing figure):
  - straight down: (vx, vy) = (0, 220)
  - "5–7 o'clock": (±110, 190.5255888) (player right of figure → +vx = 5 o'clock, left → −vx = 7 o'clock; tie → +)
  - "4–8 o'clock": (±190.5255888, 110)
- Width % = full salvo width INCLUDING bullet width, relative to the original 90 px base width, scaled for children.
  [DESIGN] Bullet nominal width w = 10 px. For n bullets in a row over width W = pct·90·s: centers evenly from
  `cx − (W−w)/2` to `cx + (W−w)/2` (n = 1 → center). Bullets spawn at y = figure_y + 18·s.

| Level | full figure: bullets / width / direction | who may fire |
|-------|------------------------------------------|--------------|
| 1     | 1 / central / straight down              | only the currently lowest figure |
| 2     | 4 / 70% / straight down                  | only the currently lowest figure |
| 3     | 4 / 70% / straight down                  | the two currently lowest figures |
| 4     | 6 / 55% / 5–7                            | the two currently lowest figures |
| 5     | 6 / 65% / 5–7                            | the two currently lowest figures |
| 6     | 8 / 75% / 5–7                            | the two currently lowest figures |
| 7     | 6 / 55% / 5–7                            | the two currently lowest figures, child rule |
| 8     | 6 / 60% / 5–7                            | the two currently lowest figures, child rule |
| 9     | 6 / 60% / 5–7                            | the two currently lowest figures, child rule |
| 10    | 8 / 80% / 5–7                            | only the currently lowest figure, child rule |
| 11,12 | 8 / 80% / 5–7                            | all figures on the bottom lane (lane 2) |
| 13    | none                                     | nobody |
| 14    | 8 / 80% / 5–7                            | only the bottom lane |
| 15,16 | 10 / 90% / 5–7                           | only the bottom lane |
| 17    | 12 / 100% / 4–8                          | all figures on the bottom lane |
| 18,19 | 12 / 100% / 4–8                          | all figures on middle and bottom lane |
| 20    | 12 / 100% / 4–8                          | all figures |

- "Currently lowest figure" = ranking of all alive figures (children included) by current y, largest y first.
  "Bottom lane" is the fixed lane 2 (y = 420).
- Only level 10: four adjacent columns of two bullets each, vertically offset by ≈ 18 px (second bullet 18 px above). Children: two columns of two. All other levels: bullets side by side in one row.
- Levels 1–10: one timer for the lowest figure, and (if the table allows two) a second timer for the second-lowest figure. Initial values 2.0 s / F and 2.5 s / F, afterwards rand(1.8, 2.8) / F. When a timer fires, the figure that currently holds that rank fires if it is armed. **A defenceless figure does not pass its right to fire to a higher figure** (that shot is simply skipped, timer restarts).
- From level 11: every eligible figure has its own timer (start `2.0/F + rand(0,0.8)/F` at spawn / split; afterwards rand(1.8, 2.8)/F).
- Child rule (levels 7–12, see §8): which children are armed and how many bullets they fire.
- Look: burning fireballs with a hot core and a tail. Bullets are swallowed by the ground: nothing (not even glow or tail) may be drawn below y = 685. Remove a bullet at the latest when it is entirely below the ground, and also when it leaves the screen sideways.
  [DESIGN] A bullet is removed sideways once its 10 px body is entirely off-screen (x < −5 / > 965). So that its still visible tail does not pop away, the view fades it out before that – only in the band where it can no longer hit any player position (head x ≤ 9 / ≥ 951, i.e. 30 − 21 / 930 + 21); the simulation is unaffected.

## 8. Hit rules [RULE]

- **Levels 1–6, 13, 17, 18**: one hit destroys an enemy.
- **Levels 7–12 (split)**: the first hit on an ORIGINAL splits it into two children. Child size per child: level 7 → 40 %, levels 8–12 → 45 % of the original linear size. Children stay on the parent's lane, move independently (left child moves left, right child moves right, spawned at parent x ∓ 24 px, clamped) and flap their wings in sync. One hit destroys a child. The split itself gives no points; each destroyed child gives the table points (level 7: a fully eliminated pair = 50 points).
  - 7–8: exactly ONE child (random) is armed and fires 2 bullets; the other stays defenceless permanently, even after its armed partner died.
  - 9: both children may fire 2 bullets each, but only on the bottom lane; children on upper lanes are defenceless. Rank rule from §7 applies additionally.
  - 10: children on the bottom lane fire 4 bullets (2 columns × 2); upper children don't. Additionally only the overall lowest figure may fire.
  - 11–12: all children on the bottom lane fire 4 bullets (one row); children on the two upper lanes don't.
  - Child salvo width = table width % · 90 · child scale.
- **Levels 14–16 (global colour-stage lock)**: no ordinary "three hit points". Every enemy starts VIOLET.
  - A hit turns a violet enemy YELLOW.
  - A yellow enemy may only turn GREEN when NO visible violet enemy is alive.
  - A green enemy may only be destroyed when ALL visible enemies are green.
  - Higher stages persist during a lock. Newly spawned (violet) enemies re-establish the lock.
  - Locked hits give no progress and no points. Normal (non-piercing) shots are consumed even by locked hits; piercing shots fly on but may touch the same enemy only once per projectile.
  - Colours: violet stage = level colours (violet → almost black); yellow stage gradient light yellow → dark yellow; green stage gradient light green → dark green. Points only on final destruction.
  - Before level 14 an English, clearly illustrated rules screen is shown; Enter confirms. [DESIGN] Its locked-hit line matches
    the chosen ship: "Locked hits are wasted shots: no points." (normal shots) / "Locked hits: no points. Your shot flies on." (piercing).
- **Levels 19–20**: black enemies; on a non-lethal hit an orange hit-flash for ≈ 0.18 s. An enemy is destroyed by THREE hits within a ROLLING window of 10 game-seconds. Store the individual hit times, drop hits older than 10 s (keep a hit while `now − t ≤ 10.0`). No blanket reset 10 s after the first hit. Example: hits at t = 0, 8, 11 → not destroyed; t = 8, 11, 12 → destroyed. The window runs in game time (so it is faster on Hard/Expert). Points only on destruction.

## 9. Play time, level end, flawless

- [RULE] Play time (real seconds, unscaled) counts only during active level play: not during pause, respawn, level intro banner, menus.
- [RULE] After the last enemy is destroyed, remaining enemy bullets stay dangerous; that time still counts. As soon as the goal is met and no enemy bullet exists, pure explosion waiting time no longer counts. The screen change still waits until all explosions have finished.
- [RULE] Bonus level: the flight time of the last shot counts as long as the goal is not met. With zero attempts left, active time ends only when the last own salvo has disappeared.
- [RULE] Losing a life in the final phase prevents the flawless extra life.
- [DESIGN] Level start: banner "LEVEL n – NAME" for 1.8 s real time (state INTRO, nothing moves, no time counted); then combat starts and all slots spawn.

## 10. Bonus level 13 [RULE]

- Title "Prove Your Accuracy!". 100 shot attempts; a double salvo costs ONE attempt. No enemy bullets at all.
- Ends at 20 destroyed enemies, or when all attempts are used and the last salvo has finished flying.
  [DESIGN] Once the goal is met no new salvo is created – not even with fire held in the very sub-step of the 20th kill –
  so the end of the level never costs an attempt (the same gate stops a stray salvo at LEVEL CLEAR in normal levels).
- Kills give no score. Bonus = unused attempts × ship factor (Interceptor 400; Double Dart and Blaster 300; others 200).
- One extra life only if bonus **> 6000** (not at exactly 6000).
- Result screen: remaining attempts, factor, bonus, extra life (if any). Stays until Enter; then the Mars rules screen, then level 14.

## 11. Run flow and screens [RULE unless marked]

```
TITLE ──Start──▶ SHIP SELECT ──confirm──▶ LEVEL 1
LEVEL n completed:
   n ≠ 13 → INTERLEVEL(n) (score, level bonus, extra life if any, battles remaining until next planet)
            → if n ∈ {3,6,9,12,16}: ARRIVAL(n) → next level
            → if n = 20: VICTORY → NAME ENTRY (if score qualifies, else HIGHSCORES) → HIGHSCORES → TITLE
            → else LEVEL n+1
   n = 13 → BONUS RESULT → MARS RULES → LEVEL 14
LEVEL game over → GAME OVER → NAME ENTRY (if qualifies) → HIGHSCORES → TITLE
PAUSE: Q (or controller Back) → TITLE (no highscore entry)
```
- Title: logo, START, DIFFICULTY (cycle), MUSIC On/Off, SOUND EFFECTS On/Off, HIGHSCORES, QUIT. Options persist on disk.
  [DESIGN – client request, feedback round 3] Two more rows directly under the switches: MUSIC VOLUME (under MUSIC) and
  EFFECTS VOLUME (under SOUND EFFECTS), each a 10-segment bar plus the percentage, 0–100 % in 10 % steps (§14). Left/right
  step ±10 % with the controlled menu repeat, clamped at 0 % / 100 %; MUSIC VOLUME is heard live in the title music,
  EFFECTS VOLUME plays a short preview effect (`shot_laser`) at the new gain; confirm on a volume row only previews (no
  wrap). A bar is dimmed while its ON/OFF switch is OFF. The ON/OFF rows and every other key/button keep their behaviour.
  Layout of the 8 rows at 960 × 720: logo 620 px wide below the BEST line, tagline, menu panel (rows 41 px apart), the two
  hint rows (`tests/test_volume.gd` checks that nothing overlaps).
- Interlevel: "LEVEL n COMPLETE – <name>", score, level bonus, extra life (if awarded), total time, and the remaining battles
  until the next planet, e.g. "2 more battles until Uranus". After levels 3, 6, 9, 12, 16 show "<Planet> secured!" instead.
  For levels 17–19 show "<20−n> more battle(s) to defend Earth". No wrong planet counters after bonus level 13 (the bonus result
  screen shows no counter). Confirm continues (ignore confirm for the first 0.6 s).
- Arrival sequences after levels 3, 6, 9, 12, 16 (completely silent):
  0–3 s small stars stream from right to left; 3–6 s the message fades in; 6–7 s the message slides out to the left;
  7–12 s the target planet appears small in the screen center and zooms in for ≈ 5 s; afterwards "Press ENTER to continue".
  Messages, EXACTLY:
  - after 3: `Neptun has been secured - approaching Uranus`
  - after 6: `Uranus has been secured - approaching Saturn`
  - after 9: `Saturn has been secured - approaching Jupiter`
  - after 12: `Jupiter has been secured - approaching Mars`
  - after 16: `Mars has been secured - protect EARTH!`
- Victory (after level 20, before name entry): Earth in the background, text EXACTLY:
  `You are a real champion on the trigger. You moved smoothly through enemy lines, you destroyed them all! Everlasting love to You, oh great PLANET PROTECTOR!`
  Enter leads to the highscore entry.
- Ship select: six ships with animated previews that use the SAME projectile graphics as the game (guided shots follow the preview ship).

### 11.1 Attract mode (demo) [DESIGN – client request, feedback round 2]

```
TITLE ──90 s without input──▶ ATTRACT (demo run) ──over / any input──▶ TITLE
```
- Idle timer: 90 REAL seconds without player input while the TITLE screen is shown start the demo (title emits
  `finished("attract")`). Player input = a key (also its auto-repeat), a mouse button, a joypad button (D-pad included) or a
  stick deflected beyond 0.5 (mouse motion and triggers do not count); every input event – and anything held – resets the
  timer. Only the title counts; a new title instance starts at 0 again.
- The demo is the normal GameScreen in attract mode (`setup({"attract": {"seed", "level"}})`), choreographed by the pure
  class `AttractDirector` (`scripts/game/attract_director.gd`): random level 1–20 EXCEPT 13 (no enemy fire there, the ship
  could not be hit), random ship, difficulty NORMAL (speed factor 1.0) and ONE life regardless of the settings. It never
  touches the run: no writes to `Run` (score, lives, level, play time, results; `Run.active` stays false), no highscores, no
  `Settings` changes – the HUD shows the demo world's own score, lives, NORMAL and time.
- Audio: the title music keeps playing seamlessly (never stopped or restarted, no game music); no sound effects at all and no
  bass changes (every sound of the GameScreen goes through one output that a demo never calls).
- Look: the normal level rendering incl. the intro banner, plus an unobtrusive overlay that covers no gameplay: "DEMO"
  (Orbitron, letter-spaced, accent colour) in the free band between the top bar and the top lane, and a gently blinking
  "PRESS ANY BUTTON" (Exo 2) on a dark pill in the ground strip.
- Choreography (all times real seconds since the demo screen started, intro banner included):
  - D = rand(15, 40) is the total length (screen start → back to the title). t_die = D − 1.9;
    vulnerable window [max(13.1, t_die − 3), t_die].
  - Before the window the ship is invincible; the autopilot (`Autopilot.demo`) aims (in levels 14–16 at figures of the
    lowest colour stage, whose hits are not locked) and fires until it has landed N = rand(3…6) hits on enemies – every
    hit that affects an enemy counts: split, destruction, colour-stage change, non-lethal Earth hit (locked hits do not).
    It presses the trigger only for a NEW salvo (none in flight) that is predicted to land such a hit (unguided: the
    salvo's flight against the figures' known paths, pending random turn included; guided: the target within steering
    reach). That press lasts exactly one world sub-step that starts without a shot in flight, so no shot can hit
    anything before the salvo leaves: no salvo ever leaves after the N-th hit, not even in the same sub-step.
    Afterwards it keeps dodging without firing (the salvo already in flight may still touch a figure or two).
    Simulated (900 demos): at least 3 hits before the ship is hit in all of them, the full N in all but 2.
  - Dodging: the ship only moves within its escape set – the positions from which it can still avoid every fireball
    in the air (computed backwards over 4.8 s, longer than any fireball needs to reach the ship). While the ship is
    invincible the director withdraws, in the slice it was fired, any enemy salvo that would leave the ship no escape:
    its fireballs and its event (muzzle flash) are removed before anything is drawn, as if that figure had not fired
    (≈ 0.02 salvos per demo on average, ≈ 0.3 on level 20). So no fireball passes through the invincible ship.
  - In the window it stops dodging and steers under the nearest falling enemy fireball (the first to arrive among those it
    can still get under). If it is still alive 0.1 s before t_die, a fireball appears right above the ship (`add_bullet`)
    and the ship holds still; the fireball enters the hit box right after t_die, so the ship is hit in the first
    sub-step after t_die (also when the window is the single instant 13.1 s; a fireball on the ship 2 sub-steps after
    t_die is the failsafe).
  - With its one life the normal player explosion plays (1.3 s); 0.6 s later the demo ends → TITLE. End = min(hit + 1.9, D).
    The hit always lies in [13.1, t_die + 1 sub-step], so the demo lasts 15 ≤ total ≤ D ≤ 40 s (the director cuts its
    update slices exactly at these marks). It can never complete a level: the smallest level needs 10 kills, the demo
    fires its last salvo with at most N − 1 hits landed, so only that salvo's few hits come on top.
- Any player input during the demo (as above; P / Escape / Start included – there is no pause) ends it at once → TITLE. No
  game-over screen, no name entry. The press does not act on the title: `Main` calls `InputRouter.require_release()` on the
  screen change, so the held key/button/direction is latched until released (Enter does not start, Escape does not quit).
- Back on the title: the title music is still running, the menu stands on START GAME and the idle timer restarts (another
  demo after 90 s).
- Dev/test: `--attract-after=<s>` (shorter idle time), `--screen=attract` (start a demo directly), `--attract-level=N`
  (1–20 except 13) and `--attract-seed=S` (deterministic choice of level/ship/hits/D and world seed; with `--fixed-fps 60`
  the whole demo is reproducible). Tests: `tests/test_attract.gd`, `tests/test_attract_review.gd`.

## 12. Controls [RULE]

Keyboard: Left/Right arrows or A/D move; Space fires; Enter confirms; P or Escape pauses; Q in pause → title; F11 toggles fullscreen
(global); Escape on the title screen quits. Backspace deletes in name entry. [DESIGN] Escape in sub-menus = back; Space also
confirms on title and ship select (mirrors controller A).

[DESIGN – feedback round 3] Pause overlay with volumes: up/down (keys, D-pad, stick) selects MUSIC VOLUME / EFFECTS VOLUME,
left/right steps it by 10 % (controlled repeat, persisted and applied at once; EFFECTS VOLUME plays the preview effect, the
music row says "Music is paused" because the game music is silent in a pause by rule). P / Escape / Start still resume,
Q / Back still quit to the title, A/B (fire) do nothing there. Release guards for directions only: a direction held when
the pause opens (e.g. the ship's movement) steps nothing there until it was released and pressed again, and a movement
direction still held when the pause closes does not move the ship until it is released. Fire is not latched: a fire button
held through the pause (or pressed in it) fires at once after the resume (hold-to-fire, §4). P/Escape/Start/Q/Back
act on a fresh press only, so a held one does nothing. No pause and no volume menu in a demo (§11.1).

Controller (Godot/SDL positional mapping; PlayStation: Cross = A, Circle = B, Square = X, Triangle = Y, Options = Start, Share/Create = Back):
- D-pad or left stick left/right moves (analog with sensible deadzone, 0.25).
- A/B fire. X/Y confirm. A also confirms on the title screen and in ship select.
- Start pauses in game and confirms in menus.
- Select/Back opens the highscores on the title screen and from pause returns to the title.
- B goes back from sub-menus, is ignored on the title screen.
- Menu input repeat is controlled (initial delay 0.35 s, repeat 0.11 s). A held key/button must never confirm several times or
  skip several screens: after each screen change, confirm/back/fire require a release first. [DESIGN] A direction held across
  a screen change does not step until it is released (or changed); this includes W/A/S/D held while leaving the name entry,
  where they only become directions again after text mode ends.
- [DESIGN] Left stick as menu direction with hysteresis: from rest it engages at 0.5 deflection on the stronger axis
  (tie → horizontal); an engaged direction is kept until its axis drops below 0.35, and it switches to the other axis only when
  that axis reaches 0.5 and is stronger by ≥ 0.2. Stick tremor around 0.5 or around the 45° diagonal therefore produces no
  extra steps (only the controlled repeat).

## 13. Highscores [RULE]

- Four separate top-10 lists (one per difficulty). Sort: score descending, then real play time ascending.
- Time stored with full float precision; displayed with tenths `MM:SS.t`.
- Name: max 8 chars from `A–Z 0–9 _ -` (client decision, originally 5); empty → `PILOT`. Highscore files with
  names of up to 5 characters stay valid and load unchanged; longer names in a hand-edited file are cut to 8 on load.
  Every screen that shows a name fits 8 of the widest characters (`WWWWWWWW`): 8 boxes in the name entry, the
  highscore NAME column (clear of SCORE with a 6-digit score) and the title BEST line.
- Column headings must stand exactly above their values (same x anchor and alignment).
- Controller name editor: horizontal moves only the cursor; vertical changes the character. On the empty end field a vertical
  input first inserts `A` without advancing the cursor. The cursor can only be on existing characters or the next free position,
  never beyond 8 characters (index ≤ 7). On a diagonal stick input only the stronger axis counts; a tie counts as horizontal
  (stick hysteresis: §12).
  D-pad diagonals are treated the same way (tie → horizontal). B deletes the last character, X/Y (and Start) confirm.
  Keyboard: typing appends, Backspace deletes, Enter confirms; arrow keys behave like the D-pad.
- Character cycle for vertical input: `ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-` (up = next, down = previous, wrapping).
- Stored entry: `{name, score, time, level, ship}`; persisted in `user://highscores.json`.

## 14. Audio [DESIGN – our own, modern]

- Modern electronic sound (no chiptune requirement). Everything is generated by our own Python scripts, no samples from elsewhere.
- Title music: modern dark synthwave / cinematic electronic, menacing but motivating, seamless loop (~16 bars).
  Plays on title, ship select, highscores and name entry. Stops for gameplay.
- Game music: runtime sequencer at 200 BPM (one 4/4 bar = 1.2 s): kick on every quarter, snare on beat 3, hats on 8ths,
  a bass hit on every quarter. The bass starts on E1 (41.203 Hz, with enough harmonics to be audible on small speakers) and rises
  one semitone per destroyed ORIGINAL enemy: for split enemies only when the LAST child of the pair is destroyed (client
  decision, feedback round 1; GameWorld marks it with enemy_destroyed.group_cleared); never on split hits, colour changes or
  non-lethal Earth hits. Reset to E1 at every level start. In levels 17, 18, 20 it drops back to E1 after every 10 destructions; elsewhere
  it is capped at +40 semitones. The bass progress continues internally even with music switched off.
  Silent during pause and respawn; on return the beat restarts at a bar start. No tempo change by difficulty.
- Arrival sequences are completely silent. No game music in ship select, arrival, highscores, end screens.
- Sound effects: per-ship shot sounds, enemy fire, enemy hit (small), enemy explosion, locked hit "clink", player explosion
  (louder, brighter, never clipping), extra life, level complete, materialize, menu move/confirm/back, bonus tick, game over.
- Music and effects can be switched independently and switches act immediately (bus mute).
- [DESIGN – client request, feedback round 3] Player volumes MUSIC VOLUME / EFFECTS VOLUME: 0–100 % in 10 % steps, default
  100 % = the original mix, stored in `user://settings.cfg` (`[audio] music_volume / sfx_volume`; files without the keys
  read as 100 %). `AudioManager.apply_settings()` sets the Music / SFX bus gain at once with amplitude = v² (40·log10 v dB:
  90 % −1.8 dB, 50 % −12 dB, 10 % −40 dB; 0 % mutes); never above 0 dB, so the Master limiter guarantee is unchanged.
  The ON/OFF switches mute on top regardless of the volume. Unaffected: the arrival silence (it fades/mutes the SFX bus from
  the player's gain and re-applies the settings on exit), the title-music-only demo, pause/respawn silence of the game music.
- All audio files are exported with the game.

## 15. Graphics [DESIGN]

Modern arcade look made of **Blender-rendered sprites** + procedural Godot effects:
- Player ships: six distinct metallic ships (top-down, nose up), Blender renders.
- Enemies: six demon designs, one per planet, increasingly menacing: Neptune slender; Uranus sickle-shaped; Saturn forked insect;
  Jupiter broad armour plates; Mars hooked wings; Earth heavy crown. Blender renders as channel-packed flap animations that are
  colourised in Godot with the level gradient (§16.2). Clearly visible soft wing flap, ≈ 2.5 cycles per game-second, children too.
  Black Earth enemies stay readable through a subtle outline and glowing eyes: on black enemies ONLY the eyes glow (the emissive
  B channel and its halo are masked to the sheet's `eye_rect`; wing veins, chest sigil and crown jewels stay dark).
- Planets top-right (behind enemies), soft lighting: Neptune blue; Uranus lighter blue-green with visible ring; Saturn light brown
  with multi-coloured rings; Jupiter darker brown with bands and red spot; Mars reddish with natural surface structures; Earth with
  blue oceans, continents and clouds. Ground colours fit the planet.
  Visible sphere diameter 174 px for zoom stage 1, ×220/192 for stage 2, ×275/192 for stage 3 (rings extend outside).
  Stages: Neptune L1/2/3 → 1/2/3, Uranus 4/5/6 → 1/2/3, Saturn 7/8/9 → 1/2/3, Jupiter 10/11/12 → 1/2/3, Bonus 13 → Mars stage 1,
  Mars 14/15/16 → 1/2/3, Earth 17/18/19/20 → 1/1/2/3.
- Starfield: many small faint points, few bright stars with soft halos, subtle white/bluish/warm tints, several slowly moving depth
  layers, uneven distribution, no strong flicker. Cache textures; never rebuild per frame.
- Explosions (procedural): bright short core flash, glowing clouds, sparks/debris, expanding shock ring. Enemy ≈ 0.9 s; player bigger
  ≈ 1.3 s. Non-lethal hits get smaller hit impulses. Spectacular but must not hide enemy bullets.
- Fonts: `assets/fonts/Orbitron.ttf` (titles, HUD numbers), `assets/fonts/Exo2.ttf` (body text). Both OFL.

## 16. Asset contracts (file names/formats are binding)

All sprites are rendered at **2 sprite pixels per game pixel** unless noted. PNG RGBA, straight alpha.

### 16.1 Player ships – `assets/sprites/ships/<id>.png`
ids: `interceptor, fighter, double_dart, double_hunter, blaster, hunter`. Canvas **160 × 112 px** (80 × 56 game px).
Ship centered in the canvas (canvas center = ship center at y = 659). Visual ship size ≈ 64–72 game px wide, ≈ 44–50 game px tall.
Top-down view, nose pointing up (−y). Full colour, metallic, each ship with its own colour accent:
interceptor = blue, fighter = green, double_dart = cyan, double_hunter = orange, blaster = red, hunter = purple.
Gun muzzles must visually match the shot offsets (single: center; double: ±12 game px = ±24 sprite px).
Also `assets/sprites/ships/<id>_glow.png` (optional, same canvas): engine glow only, used additively.

### 16.2 Enemies – `assets/sprites/enemies/<planet>.png` + `<planet>.json`
planets: `neptune, uranus, saturn, jupiter, mars, earth`.
- Horizontal strip of **16 frames**, one seamless wing-flap cycle. Frame size **256 × 160 px** (128 × 80 game px). The frame center
  is the enemy's logical center. Wing-span at the widest point ≈ 90 × width_factor game px (= 180 × wf sprite px).
- **Channel packing** (NOT a colour image):
  - R = diffuse lighting of a white material (0…1),
  - G = specular / rim highlight intensity (0…1),
  - B = emissive mask (eyes, glowing details) (0…1),
  - A = coverage alpha.
- JSON: `{"frames":16,"frame_w":256,"frame_h":160,"px_per_game_px":2.0,"content_top":<px>,"content_bottom":<px>,"width_factor":<wf>}`
  where content_top/bottom are the union bounding rows (in frame px) of all frames; the colour gradient maps top→bottom onto it.
  Optional `"eye_rect":[x0,y0,x1,y1]` (frame px, inclusive; required for `earth`): the area of B that may glow on black enemies
  (both eyes in every frame).
- Shader colourisation (Godot, `shaders/enemy.gdshader`): `base = gradient(t)` with t from content_top→content_bottom,
  `col = base*(0.18 + 1.0*R) + G*mix(vec3(1.0), base, 0.35)*0.9 + B*eye_color`, plus subtle outline for very dark gradients.
  For black enemies B (and the eye halo) is multiplied by the `eye_rect` mask.

### 16.3 Planets – `assets/sprites/planets/<planet>.png` + `<planet>.json`
Square or wide canvas, sphere diameter ≥ 600 px. JSON: `{"sphere_diameter_px":D,"center":[x,y]}` (center of the sphere in image px).
Light from the upper left. Rings included in the image (Uranus, Saturn).

### 16.4 Ground – `assets/sprites/ground/<planet>.png`
**1920 × 70 px** (= 960 × 35 game px, drawn at y 685…720). Row 0 is the surface line. Tileable horizontally is a plus.

### 16.5 Projectiles – `assets/sprites/projectiles/rocket.png`, `rocket_heavy.png`
Rocket body WITHOUT flame, nose up, 2 px/game px. rocket: canvas 24 × 64 (≈ 6 × 26 game px visual). rocket_heavy: canvas 40 × 72
with a thick warhead. Flames are procedural.

### 16.6 UI – `assets/sprites/ui/logo.png`
Title logo "PLANET PROTECTOR" (3D metallic/fiery letters), ≈ 1600 × 420 px canvas, transparent background. Displayed at ≈ 760 px wide.
Optional: `assets/sprites/ui/title_demon.png` key art.

### 16.7 Audio – `assets/audio/...`
- `music/title.ogg` (loop).
- Game music sequencer source samples in `music/game/` (formats chosen by the audio agent; beware: Godot imports WAV with
  compression by default – use raw PCM or set the import option; files must be included in the export).
- `sfx/<name>.wav` for names: `shot_laser, shot_rocket, shot_blaster, enemy_fire, enemy_hit, enemy_explode, locked_hit,
  player_explode, extra_life, level_complete, materialize, menu_move, menu_confirm, menu_back, bonus_tick, game_over`.

Everything must work with missing assets (fallbacks in `Assets`), so code and art can be developed in parallel.

## 17. Code architecture (binding interfaces)

```
game/
  project.godot, export_presets.cfg
  scripts/autoload/assets.gd        Assets       – loads textures/fonts with generated fallbacks           (owner: lead)
  scripts/autoload/run_state.gd     Run          – current run: difficulty, ship, score, lives, level, time  (owner: lead)
  scripts/autoload/settings.gd      Settings     – options + highscores persistence                          (owner: ui)
  scripts/autoload/input_router.gd  InputRouter  – keyboard/controller abstraction, repeat, release guard     (owner: ui)
  scripts/autoload/audio_manager.gd AudioManager – music, game-music sequencer, sfx, bass logic              (owner: audio)
  scripts/data/level_data.gd        LevelData    – level/fire/colour tables (class_name, static)             (owner: lead)
  scripts/data/ship_data.gd         ShipData     – ships + difficulties (class_name, static)                 (owner: lead)
  scripts/main.gd                   Main         – screen manager / run flow (§11)                           (owner: ui)
  scripts/screens/*.gd              title, ship_select, interlevel, arrival, mars_rules, bonus_result,
                                    victory, game_over, name_entry, highscores                               (owner: ui)
  scripts/common/starfield.gd       Starfield (class_name) – layered star background                         (owner: ui)
  scripts/common/ui_kit.gd          UiKit (class_name, static) – text/panel helpers                          (owner: ui)
  scripts/common/projectile_art.gd  ProjectileArt (class_name, static) – drawing of all projectiles           (owner: gameplay)
  scripts/common/enemy_art.gd       EnemyArt (class_name, Node2D) – colourised enemy sprite                  (owner: gameplay)
  scripts/game/game_world.gd        GameWorld (class_name, RefCounted) – PURE simulation, headless-testable  (owner: gameplay)
  scripts/game/game_screen.gd       GameScreen – renders the world, HUD, FX, pause; signals result           (owner: gameplay)
  scripts/game/*.gd                 any further gameplay files                                               (owner: gameplay)
  shaders/*.gdshader                                                                                         (owner: gameplay)
  tests/run_tests.gd                headless test runner                                                     (owner: lead)
  tests/test_*.gd                   test files (each owner adds their own)
```

### 17.1 Screen protocol
Every screen is a `Node` (usually `Node2D` or `Control`) created by `Main` with `ScreenClass.new()`, configured through
`setup(args: Dictionary)` BEFORE it is added to the tree, and it emits `signal finished(result: String, data: Dictionary)`.
`Main` frees the old screen and calls `InputRouter.require_release()` on every change.

GameScreen: `setup({"level": n})`, emits `finished("completed"|"game_over"|"quit", {})`. It reads/writes `Run`
(score, lives, active_time, last_level_result, last_bonus_result). Results it must store before emitting "completed":
- `Run.last_level_result = {"level": n, "completion_bonus": int, "extra_life": bool, "flawless": bool}`
- level 13 additionally `Run.last_bonus_result = {"remaining": int, "factor": int, "bonus": int, "extra_life": bool}`

### 17.2 GameWorld (pure simulation)
```gdscript
class_name GameWorld extends RefCounted
func _init(level: int, difficulty: int, ship_id: int, lives: int, rng_seed: int = 0)
func update(real_dt: float, move_axis: float, fire_held: bool) -> void   # does the fixed sub-stepping itself
var events: Array[Dictionary]   # appended during update; consumer drains: {"type": String, ...}
```
No nodes, no autoload access except the static data classes. Event types (at least): `shot_fired{ship_id,count}`,
`enemy_fire{x,y,count}`, `enemy_spawned{id,x,y,scale}`, `enemy_split{id,x,y,children:[ids]}`, `enemy_destroyed{id,x,y,scale,points}`,
`enemy_hit_nonlethal{id,x,y,kind}` (kind: "color_stage" | "rolling"), `locked_hit{id,x,y}`, `player_hit{x,y,lives_left}`,
`player_respawn`, `extra_life{reason}`, `level_goal_met`, `level_complete{completion_bonus,extra_life,flawless}`, `game_over`.
GameWorld keeps its own score delta/lives/active_time; GameScreen syncs them into `Run`.

### 17.3 Dev / test command line (user args after `--`)
`--level=N` (start directly at level N, skipping menus), `--ship=K`, `--difficulty=D`, `--dev` (enables the following),
`--invincible`, `--autoplay` (simple bot moves under the lowest enemy and fires), `--screen=<name>` (open a single screen for
screenshots), `--screenshot=<path>` + `--screenshot-delay=<seconds>` (save a viewport PNG and quit), `--quit-after=<s>`.
`Main` parses these (owner: ui); GameScreen honours invincible/autoplay through `Run.dev_flags`.
