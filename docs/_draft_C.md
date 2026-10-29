# SPEC draft – package C: title rows, ship select with locks, the four match screens

(For the integrator: proposed text for docs/SPEC.md §11 (title), §11 (ship select) and a new §19.x "Menus and screens of
a two-player match". Player colours: `UiKit.COLOR_P1` cyan, `UiKit.COLOR_P2` pink. Every screen keeps the 960 × 720
content layout, centred on the wider canvases with `ox`; captions below 12 / 14 px are lifted in modes 3 / 4 with
`UiKit.label_size`.)

## Title (§11) [DESIGN – client request, forum round]

- 11 rows: START GAME, DIFFICULTY, **PLAYERS**, **POWER-UPS**, MUSIC, MUSIC VOLUME, SOUND EFFECTS, EFFECTS VOLUME,
  DISPLAY, HIGHSCORES, QUIT.
- PLAYERS `1` / `2` and POWER-UPS `OFF` / `ON` are binary like MUSIC / SOUND EFFECTS: left, right and confirm flip them
  once per press, auto-repeat steps of a held direction are ignored (`TitleScreen.TOGGLES`); stored at once
  (`Settings.set_players` / `set_powerups` → `[game] players / powerups`), menu blip. START stays `finished("start")` –
  Main branches on `Settings.players`.
- Line under the menu (y 636, Exo 2 15 px, dim) while the row is selected (`TitleScreen.info_line_text`):
  PLAYERS 1 "Solo run · choose 2 for a hotseat match on one controller", 2 "Hotseat match: take turns level by level
  and lock ships for each other"; POWER-UPS OFF "Classic rules · ON: one power-up per level on Saturn, Jupiter and
  Mars", ON "Once per level: Saturn RAPID FIRE · Jupiter TWIN · Mars SHIELD · own highscore lists". DISPLAY keeps its
  line (apply prompt / explanation); no line on the other rows.
- BEST line: the best entry of the selected difficulty in the selected category (classic or power-up list); caption
  "BEST · NORMAL" (classic, as before) / "BEST · NORMAL · POWER-UPS". It follows DIFFICULTY and POWER-UPS at once.
- Layout of the 11 rows (content coordinates, the same in every mode; replaces the 9-row numbers): logo 540 px wide
  (centre y 122; its letters stay below the BEST value), tagline, menu panel 640 px wide (rows 560 px, font 18, 33 px
  apart, first row y 253, panel 228…608), the explanation line at y 636, the hint rows at y 665 / 694. Checked in
  modes 0–4: nothing overlaps, the selection pill stays inside the panel and clear of the neighbouring labels, every
  row, line, BEST caption and hint row fits (`tests/test_volume.gd`, `test_display.gd`, `test_steamdeck.gd`,
  `test_hotseat_screens.gd`).

## Ship select (§11)

- setup adds `{"player": k (−1 = one player, default), "locked": ids player k may not fly}`. One player: unchanged.
- Two players: header "PLAYER k  –  CHOOSE YOUR SHIP" – "PLAYER k" in the player colour, the rest white, glow in the
  player colour (32 px; smaller only if wider than 660 px, so it stays clear of the DIFFICULTY caption).
- Locked ships: dark tile with a red border (pulsing while selected), name and stats dimmed; the preview stands
  still – a dark ship silhouette under a red padlock and "LOCKED BY PLAYER j". The cursor may rest on a locked
  ship; the line under the header then reads (padlock) "Locked by PLAYER j – choose a free ship". Confirm on it is
  refused: menu_back, the line shakes and lights up, the tile border flashes (0.9 s). No finish.
- Initial selection: the requested ship, or the lowest free id if that one is locked (`ShipSelect.initial_selection`).

## 19.x Screens of a two-player match

Title music on the setup screens (SHIP LOCK, setup HAND-OVER, LOCK REVEAL, like the ship select). Setup screens
confirm with Enter / Space / A / X / Y / Start (like the ship select), the in-match screens (turn HAND-OVER, MATCH
RESULT) with Enter / X / Y / Start (A / B are fire buttons in the game, like the interlevel).

### SHIP LOCK (`scripts/screens/ship_lock_screen.gd`)
- setup `{"player": k (who locks), "locked": initial ids (default none)}`; the locks are for player j = 1 − k.
- Header "PLAYER k LOCKS" (player colour, 34 px), "Lock up to 3 ships PLAYER j may not fly" (PLAYER j in its colour)
  and a pulsing pill "PLAYER j – LOOK AWAY!" in PLAYER j's colour with an eye-slash pictogram.
- Six rows (760 × 56, 64 px apart): ship icon, name in its accent colour, a stat line in table columns (SPEED, SHOTS,
  GUIDED YES/NO, PIERCING YES/NO, BONUS ×n). Locked rows are red-tinted with a padlock + "LOCKED" at the right end
  (the padlock lands with a short stamp). Last row DONE with three padlock pips and "n / 3 LOCKED".
- Up/down select (wrapping, controlled repeat). Confirm on a ship toggles its lock: lock → `locked_hit` ("clink"),
  unlock → menu_move; a 4th lock is refused: menu_back, the pips and the count flash red and "Only 3 ships can be
  locked – unlock one first" appears under DONE (2.2 s). Confirm on DONE → menu_confirm,
  `finished("done", {"locked": ids ascending})`. Escape / B → menu_back, `finished("back")` (setup aborted).
  The hint names the action of the selected row (Lock / Unlock / Done).

### HAND-OVER (`scripts/screens/handover_screen.gd`), confirm after 0.6 s → `finished("continue")`; Escape / B nothing
- `{"kind": "locks", "player": k}` (k takes the controller, j = 1 − k just locked): check badge + "PLAYER j READY",
  "Ship locks set – they stay secret until both players are done", "Pass the controller to" + big "PLAYER k",
  pulsing "PLAYER j – LOOK AWAY!". Shows no lock information (the code never reads lock data; tested). Hint
  "PLAYER k: Continue". Title music.
- `{"kind": "turn", "player": k, "level": n}`: the level's planet (sphere 130 px) above "LEVEL n – <NAME>" (bonus level:
  "LEVEL 13 – BONUS ROUND"), big "PLAYER k" (64 px, player colour, light band that sweeps open), "GET READY", a panel
  SCORE | LIVES (ship icons, more than 5 as one icon + "×n") | SHIP, the other player small ("PLAYER j", GAME OVER /
  EARTH SAVED, score), and with POWER-UPS on a power-up level a gold pill "POWER-UP THIS LEVEL: RAPID FIRE [SHIFT] /
  (X)". Hint "Start". **Silent** (`stop_music`): it sits between two levels like the interlevel; the title music would
  only start for a few seconds and be cut by the level start, and after an arrival the silence carries on.

### LOCK REVEAL (`scripts/screens/lock_reveal_screen.gd`)
- setup `{"locked": [ids PLAYER 1 may not fly, ids PLAYER 2 may not fly]}`. "SHIP LOCKS REVEALED", "Now each player
  chooses a ship from the ones still free", one panel per player: "PLAYER k" / "MAY NOT FLY", the locked ships (icon,
  name, "LOCKED BY PLAYER j", padlock) or "NO LOCKS – every ship is free", and a strip of all six ships (locked ones
  dark with a padlock) with "n OF 6 SHIPS FREE".
- The locks land with a stamp: both players' i-th lock at 0.25 + 0.15·i s, one `locked_hit` per moment; all landed
  before confirm is possible (0.8 s) → `finished("continue")`.

### MATCH RESULT (`scripts/screens/match_result_screen.gd`)
- setup `{}`; reads both players with `Run.player_get`. "MATCH RESULT", "<DIFFICULTY> · POWER-UPS / CLASSIC", one
  panel per player: "PLAYER k", EARTH SAVED / GAME OVER tag, the score (counts up 0.25–0.8 s with bonus ticks), LEVEL
  "n – <NAME>", PLAY TIME, SHIP (icon + name).
- Winner by score (`MatchResult.winner`; equal scores → draw, no time tie-break): at 0.9 s "PLAYER k WINS!" in the
  player colour (draw: "DRAW!" in gold) pops in with the level-complete fanfare; the winner panel glows and gets a
  gold WINNER badge. Silent otherwise (like the one-player end screens; the name entry / highscores start the title
  music). Confirm after 1.0 s → `finished("continue")`.

### UiKit helpers (appended)
`ship_icon`, `check_icon`, `eye_slash_icon`, `look_away_rect`, `look_away_banner`.

### Tests
`tests/test_hotseat_screens.gd`: ship lock (toggling, max 3 + refusal, DONE sorted, wrap, back, controller), ship
select (locked ships refused, first free start selection, header / captions fit in every mode), title rows (toggle,
persist, no auto-repeat flipping, explanation lines, BEST per category, 11-row layout in modes 0–4), hand-over (delay,
keys per kind, music, no lock data, level lines, power-up per level), lock reveal (exactly the locks, one clink per
stamp, landed before confirm), match result (winner / draw, sounds, keys) and the layout of all new screens on every
canvas.
