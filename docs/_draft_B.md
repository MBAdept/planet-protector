# Draft (package B): SPEC §19.2 – two players (hotseat): run flow

To be merged into docs/SPEC.md by the integrator (§11 flow diagram gets a pointer to this section, §13 gets the power-up
lists, §17.3 the new dev arguments). Screens of package C (ship lock, hand-over / TURN, lock reveal, match result, title,
ship select) are described in their own draft; this section only says when they appear and what Main passes them.

### 19.2 Two players (hotseat): run flow [DESIGN – client request, forum round]

Two players take turns LEVEL BY LEVEL on one screen with one controller / keyboard. Shared: difficulty, POWER-UPS
setting, level sequence. Per player: ship, score, lives, level, play time, results (`Run`'s per-player fields always
hold the player whose turn it is; `Run.switch_to(k)` before player k's turn). The rules of each level are exactly those
of a one-player run. A one-player run (title PLAYERS = 1) is the classic flow of §11, unchanged.

**Setup** (title START with PLAYERS = 2):
```
TITLE ─start─▶ SHIP LOCK (P1 locks for P2) ─done─▶ HANDOVER ("locks", P2) ─continue─▶ SHIP LOCK (P2 locks for P1)
  ─done─▶ LOCK REVEAL ─continue─▶ SHIP SELECT (P1, locked = locks on P1) ─confirm─▶ SHIP SELECT (P2, locked = locks on P2)
  ─confirm─▶ Run.start_match(difficulty, ships, locks, 1, POWER-UPS) ─▶ TURN (P1, level 1) ─▶ LEVEL 1 …
Escape / B on a SHIP LOCK or SHIP SELECT screen ─▶ TITLE (setup aborted)
```
Both ship selects start on the ship the player flew last (the first free one if that is locked).

**Match** – round n: every player who is still in the match plays level n, PLAYER 1 first.
```
TURN(k, n) [only on a player change] ─▶ LEVEL n (k) ─completed─▶ n ≠ 13: INTERLEVEL (k)   n = 13: BONUS RESULT (k)
                                                    ─game over─▶ GAME OVER (k)
then: the next player of the round who is not out ─▶ TURN(j, n) ─▶ LEVEL n (j) …, or – the round is over –
      nobody left (both out)         ─▶ MATCH RESULT ─▶ name entries ─▶ HIGHSCORES ─▶ TITLE
      n = 20 (someone completed it)  ─▶ VICTORY ─▶ MATCH RESULT ─▶ name entries ─▶ HIGHSCORES ─▶ TITLE
      n = 13                         ─▶ MARS RULES ─▶ round 14
      n ∈ {3, 6, 9, 12, 16}          ─▶ ARRIVAL(n) ─▶ round n+1
      else                           ─▶ round n+1
PAUSE: Q / Back ─▶ TITLE (match aborted, no highscore entries)
```
- A player who loses the last life is out (`Run.out`) and skipped from then on; the other plays on alone to the end.
  Completing level 20 sets `Run.won`.
- The arrival sequences and the Mars rules come once per round, after the round's last turn.
- TURN screen (hand-over screen of kind "turn"): before a level whenever its player differs from the player of the
  previous level (and at the start of the match) – before every level while both play; once one is out only after the
  switch, then the remaining player's levels follow each other like in a one-player run.
- Name entries at the end of the match: the players by score (descending; equal scores: shorter play time first, then
  PLAYER 1). Each one is checked with `Settings.qualifies(difficulty, score, time, powerups)` (score > 0) at the moment
  it is his/her turn, i.e. after the better player's entry was inserted. HIGHSCORES then shows the match's list
  (difficulty + power-up category) with every entry of the match highlighted (rows recomputed after the last insert).
- One-player end of run: unchanged, but qualifies / insert / highscores use the run's power-up category.

**Screen variants in a match** (setup args from Main; without them the screens are the one-player screens):
- INTERLEVEL `{"player", "next_player", "next_screen"}`: "PLAYER k" (player colour) above the title; while the other
  player still has to play this level the progress line reads "Next: PLAYER 2 – LEVEL n" (that player's colour), else
  the usual progress text. The confirm sound follows the real next screen: silent only when the arrival comes next
  (after the round's last turn), §11/§14.
- BONUS RESULT `{"player", "next_player"}`: "PLAYER k" above the title, "Next: PLAYER 2 – LEVEL 13" above the hint.
- GAME OVER `{"player", "other_status"}`: "PLAYER k" above GAME OVER; no NEW HIGHSCORE (entries come at the end);
  instead "PLAYER j PLAYS ON" / "PLAYER j SAVED EARTH!" (j's colour) or "MATCH OVER" (both out).
- MARS RULES `{"ships"}` (ships of the players still in): the locked-hit line follows the ships (§8, REFERENCE G); if
  they differ in "piercing", rule 4 gets two lines: "Locked hits: no points." / "Normal shots are wasted, piercing shots
  fly on." The subtitle says "pilots" with two players.
- VICTORY `{"match": true}`: the stats row shows PLAYER 1's score | DIFFICULTY | PLAYER 2's score (labels in the player
  colours), under each score "EARTH SAVED" or "GAME OVER · LEVEL n". The victory text is unchanged.
- NAME ENTRY `{"player", "powerups"}`: "PLAYER k" above NEW HIGHSCORE!; the rank line names the power-up category
  ("RANK 2 · NORMAL · POWER-UPS"); classic runs read as before. finished("done") also reports the stored entry.

**Highscores** (§13 addition): four classic lists and four POWER-UPS lists. Under the difficulty tabs a smaller tab row
CLASSIC / POWER-UPS, switched with up/down (once per press, no auto-repeat); left/right switches the difficulty as
before. setup `{"difficulty", "powerups", "ranks": Array[int]}` (`"rank"` single still accepted). Title → HIGHSCORES
opens the category of the title's POWER-UPS setting. Layout at 960 × 720: title 58, difficulty tabs 94, category row 139,
panel 166–640, hint row 680.

**Dev / test command line** (§17.3 additions):
- `--players=2 --level=N [--ship=K] [--ship2=K2]` starts a match directly at PLAYER 1's TURN screen of level N (no locks;
  PLAYER 2 flies K2, default K); `--powerups` turns POWER-UPS on for direct starts (one or two players).
- `--screen=<name> --players=2 [--player=k] [--other-out]`: the two-player variant with a fake match (interlevel,
  bonus_result, game_over, victory, name_entry, mars_rules, ship_select, highscores with two highlighted rows);
  `--screen=ship_lock|handover [--kind=locks|turn]|lock_reveal|match_result|turn` are always two-player screens.
  `--screen=highscores --powerups` shows the power-up lists.
- dev/playthrough.tscn plays whole matches (`--players=2 --level=1 [--powerups]`); its log names the player of every
  screen (P1 / P2, "--" for shared screens) and lists both players in the RESULT lines.
