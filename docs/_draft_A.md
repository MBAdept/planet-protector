# Draft (package A) – SPEC §19.3 Power-ups and the two-player HUD

Integrator: merge into SPEC.md §19 (and the cross-references noted at the end). Everything below is implemented and
tested in this package.

## 19.3 Power-ups [DESIGN – client request, forum round]

Only with POWER-UPS ON (`Run.powerups`). With POWER-UPS OFF – and in every demo – the world has `powerup = NONE` and is
bit-for-bit the classic one (the recorded digests of `tests/test_wide_playfield.gd` are reproduced with NONE set
explicitly and a refused power-up press in every frame, `tests/test_powerups.gd`).

- One power-up per level, triggered once by the player: Saturn (levels 7–9) RAPID FIRE 10 s, Jupiter (10–12) TWIN
  15 s, Mars (14–16) SHIELD 10 s; none on Neptune, Uranus, bonus level 13 and Earth (`LevelData.powerup_of`,
  `POWERUP_TIME`). GameScreen sets `world.powerup` right after constructing the world.
- Life cycle READY → ACTIVE → USED, never back. `can_activate_powerup()`: the level has one, it is READY, the state
  is PLAYING (not the intro banner, a respawn, the level end), the ship is alive and the level goal is not met.
  `activate_powerup()` returns false and changes nothing otherwise.
- Duration in REAL seconds of combat: the timer runs only in PLAYING sub-steps (each one = SIM_STEP / speed_factor
  real seconds, counted in sub-steps, so it lasts exactly POWERUP_TIME at speed 1.0 / 1.2 / 1.44); it is frozen in the
  intro, during a respawn, at the level end (CLEARING) and in the pause. A power-up active when the ship is hit
  continues after the respawn. Power-ups use no random numbers.
- RAPID FIRE: the one-salvo-at-a-time rule (§4) is suspended. With fire held and the ship alive a salvo leaves
  whenever the cooldown has run out; then the cooldown grows by RAPID_FIRE_INTERVAL (0.18 game s) × shots per salvo
  (single ships 0.18 s, double ships 0.36 s – the same shots per second). The cooldown counts down in PLAYING
  (game time) and carries the rest of a sub-step over, so the salvos come every 43 / 44 sub-steps, exactly 0.18 s on
  average. The first salvo leaves at once. Every guard of §4 / §10 still applies (no salvo after the goal is met).
  When it ends, the normal rule applies again: no new salvo until all of the ship's salvos are gone.
- TWIN: an invincible second ship of the player's ship type. It appears at the ship's x and heads for the farther
  screen edge (a tie – the start position – goes right), then patrols between the ship limits (30 … W − 30) at the
  ship's speed 350 px/s, clamped at the edges like the ship; it moves in PLAYING and CLEARING. It fires its own salvo
  whenever none of ITS shots is in flight (its own one-salvo rule, independent of the fire button; nothing after the
  goal is met). Its shots are normal shots of the ship type (speed, guided, piercing, points) marked `twin`; guided
  ones follow the TWIN's x, and after it is gone its shots fly on (guided ones keep following its last x). Enemy
  bullets pass through it. The ship's own fire rule counts only the ship's own shots. A player hit clears all shots,
  the twin's included (§3); the twin waits during the respawn.
- SHIELD: every enemy bullet whose centre comes within |dx| < SHIELD_DX (34) and |dy| < SHIELD_DY (30) of the ship
  centre (x, 659) is absorbed (removed) – a superset of the hit box (21 × 15), so the ship cannot be hit while the
  shield is up (the absorption runs right before the player collision in every sub-step).
- Events: `powerup_activated{kind, x}` (x = ship), `powerup_expired{kind, x}` (x = the twin's for TWIN, else the
  ship's), `shield_absorbed{x, y}`; the twin's salvos are `shot_fired{ship_id, count, x, twin: true}` (the ship's own
  `shot_fired` is unchanged, without a `twin` key).
- Input (§12): the power-up button is a fresh press of Shift or Ctrl (either side) or controller X / Y (Square /
  Triangle) / LB / RB (L1 / R1) – `InputRouter.powerup_pressed()`. Not in the pause (and a press made in the pause
  does not act afterwards); refused presses are silent; a held button does not trigger it later (fresh press only),
  and Main's release guard on every screen change keeps a confirm press (X / Y) from triggering it.
- Dev autoplay: the bot triggers the power-up as soon as it can (dev flag `manual_powerup`: only on a press).
  The bot steers guided salvos by the ship's own shots only.
- HUD (§15): a pill centred in the ground strip (685 … 720), nothing on levels without a power-up (bonus level, demo):
  READY – the name in the power-up colour, "READY" (gently pulsing) and the key hint [SHIFT] / (X); dimmed once the
  goal is met. ACTIVE – the name, a draining bar and the seconds left with one decimal (rounded up, "6.3"); in the
  last 2 s the bar blinks and the seconds turn red. USED – a dim "<NAME>  USED" for 2 s, then it fades out (0.6 s).
  The pill fits the strip in every display mode (modes 3 / 4 lift its caption size, `UiKit.label_size`).
  The intro banner of a power-up level has an extra line under the banner: "POWER-UP:  <NAME>" (name in its colour).
  Colours: RAPID FIRE orange, TWIN violet, SHIELD cyan (`Hud.POWERUP_COLORS`).
- Look (additive light, the FX vocabulary of §15): RAPID FIRE – the hull glows red-hot (throbbing), hot glowing gun
  muzzles, longer orange-white exhaust. TWIN – the same ship sprite, translucent and washed violet with a holographic
  sheen and violet engines, drawn behind the player's ship; it materializes (scan beam, closing ring, converging
  particles) and vanishes (flash, bursting ring, particles); its shots are drawn tinted violet. SHIELD – an energy
  bubble around the ship resting on the ground (soft inner light, bright rim, energy arcs running round it, its light
  on the ground), a white-hot flash with a hexagonal ripple where a fireball is absorbed, and a rim flash. Every
  effect blinks in its last 2 s (dips that come faster, 4 → 9 per second, driven by the world's timer so it freezes
  with it) and fades in / out. Triggering shows a burst (shock rings, light pillar, sparks) in the power-up colour,
  the end a collapsing ring.
- Sound (§14): `powerup_on` (charge-up sweep landing on a power-chord stab), `powerup_off` (power-down slide),
  `shield_hit` (electric zap), synthesised by `tools/audio/make_sfx.py` (docs/AUDIO.md); rapid-fire and twin salvos
  use the ship's normal shot sound (one per name and frame).

## 19.2 (addition) Two-player HUD

- Top bar: the SCORE caption reads "P1 SCORE" / "P2 SCORE" in the current player's colour (`UiKit.player_color`);
  nothing else is added (still fits 960 px; "P2 SCORE" stays clear of LIVES in every mode).
- Intro banner: the caption line starts with the player – "PLAYER 1  ·  SATURN  ·  NORMAL" ("PLAYER 1" in the player
  colour; bonus level "PLAYER 1  ·  LEVEL 13  ·  BONUS ROUND").
- One-player runs and demos: exactly as before.

## Cross-references for the integrator

- §16.7 SFX list: add `powerup_on, powerup_off, shield_hit`.
- §17.2 events: add the power-up events above; `GameWorld.powerup`, `powerup_state`, `powerup_left`,
  `can_activate_powerup()`, `activate_powerup()`, `twin_x`.
- §17.3 dev args of `res://dev/capture.tscn`: `--powerups`, `--powerup-at=<s>` (trigger at that time; the autoplay bot
  then leaves the button alone), `--players=2 [--player=K] [--ship2=S]`, `--when=powerup | powerup_warn |
  powerup_used | absorb`.
- Tests: `tests/test_powerups.gd` (world rules, timing at 1.0 / 1.2 / 1.44, frozen states, rapid-fire spacing for
  single / double ships, twin patrol / own salvo rule / guided shots / invincibility / scoring / goal, shield, events,
  determinism, classic digests with NONE), `tests/test_powerups_screen.gd` (GameScreen wiring, attract worlds,
  button mapping, pause, release guard, autoplay, sounds, HUD pill states / blink / fit in every mode, two-player
  captions).
