extends TestBase
## Audit (dimension "time"): lives, respawn, time accounting, level end, bonus level 13, difficulty.
## All tests are regression evidence for rules of docs/REFERENCE_DE.md that hold (the former defect test of
## finding time-1 now passes after the fix and was renamed).

const STEP := LevelData.SIM_STEP


func _world(level: int, ship := 0, diff := 1, lives := 3, rng_seed := 7) -> GameWorld:
	var w := GameWorld.new(level, diff, ship, lives, rng_seed)
	w.auto_slots = false
	w.enemy_speed = 0.0
	w.osc_amplitude = 0.0
	w.allow_enemy_fire = false
	w.start_combat()
	w.events.clear()
	return w


func _steps(seconds: float) -> int:
	return int(round(seconds / STEP))


func _count(w: GameWorld, type: String) -> int:
	var n := 0
	for e in w.events:
		if e["type"] == type:
			n += 1
	return n


# --- Bonus level 13 (REFERENCE H) ----------------------------------------------------------------
## REFERENCE H: "Ende bei 20 vernichteten Gegnern" / "Bonus = ungenutzte Versuche × Schiffsfaktor" /
## "Ein zusätzliches Leben nur bei Bonus >6000". Holding fire is allowed (REFERENCE first paragraph).
## Interceptor, 17 attempts left, 19 kills: the player HOLDS fire, one salvo kills the 20th demon.
## Expected: 16 attempts left → bonus 16 × 400 = 6400 → extra life. The held button must not re-fire a
## salvo in the very sub-step of the 20th kill (after the level has ended) and so must not cost an attempt
## (audit finding time-1, regression test).
func test_audit_time_bonus_held_fire_no_attempt_after_20th_kill() -> void:
	for ship in [0, 1]:   # Interceptor (×400), Fighter (×200): single, non-piercing projectile
		var w := _world(13, ship)
		w.destroyed = 19
		w.spawned = 20
		w.attempts = 17
		var e := w.add_enemy(1, 480.0)
		w.player_x = 480.0
		var guard := 0
		while not w.is_finished() and guard < 4000:
			w.run_steps(1, 0.0, true)   # fire button held the whole time
			guard += 1
		check(not w.enemies.has(e), "20th demon destroyed (ship %d)" % ship)
		check_eq(w.state, GameWorld.State.COMPLETE, "bonus level complete (ship %d)" % ship)
		check_eq(_count(w, "shot_fired"), 1, "exactly one salvo fired for one kill (ship %d)" % ship)
		check_eq(w.bonus_result.get("remaining", -1), 16, "remaining attempts after ONE salvo (ship %d)" % ship)
		var f := int(ShipData.ship(ship)["bonus_factor"])
		check_eq(w.bonus_result.get("bonus", -1), 16 * f, "bonus = 16 × %d (ship %d)" % [f, ship])
		if ship == 0:
			check_eq(w.bonus_result.get("extra_life", false), true, "6400 > 6000 → extra life (Interceptor)")
			check_eq(w.lives, 4, "extra life awarded (Interceptor)")
	# The same with real frames (60 fps update(), exactly what GameScreen passes while Space is held).
	var w2 := _world(13, 0)
	w2.destroyed = 19
	w2.spawned = 20
	w2.attempts = 17
	w2.add_enemy(1, 480.0)
	w2.player_x = 480.0
	var g2 := 0
	while not w2.is_finished() and g2 < 600:
		w2.update(1.0 / 60.0, 0.0, true)
		g2 += 1
	check_eq(w2.bonus_result.get("remaining", -1), 16, "60 fps frames, fire held: remaining attempts")
	check_eq(w2.bonus_result.get("extra_life", false), true, "60 fps frames, fire held: 6400 → extra life")


# --- Regression evidence (pass) ------------------------------------------------------------------
const GameScreenScript := preload("res://scripts/game/game_screen.gd")


class LogicOnlyScreen extends GameScreenScript:
	func _update_views(_dt: float, _game_dt: float) -> void:
		pass


func _screen(level: int, diff: int, flags: Dictionary) -> Node2D:
	if (InputRouter.get("_down") as Dictionary).is_empty():
		InputRouter._ready()
	Run.start_new(diff, 0, level)
	Run.dev_flags = flags
	var gs: Node2D = LogicOnlyScreen.new()
	gs.setup({"level": level})
	gs._ready()
	return gs


func _cleanup(gs: Node) -> void:
	gs.free()
	Run.dev_flags = {}
	AudioManager.stop_music()


## REFERENCE D: "Menüs, Ankunftssequenzen, Musik und die gemessene Echtzeit nicht beschleunigen. Spielzeit
## zählt nur während aktiven Levelspiels, ohne Pause und Respawn." – HUD/Run time on HARD and EXPERT is
## REAL seconds, the intro and a pause are not counted, lives survive the level change.
func test_audit_time_run_active_time_real_on_hard_and_expert_pause_excluded() -> void:
	for diff in [2, 3]:
		var gs := _screen(1, diff, {"invincible": true, "autoplay": true})
		var w: GameWorld = gs.get("world")
		var frame := 1.0 / 60.0
		var guard := 0
		while w.state == GameWorld.State.INTRO and guard < 400:
			gs._process(frame)
			guard += 1
		check_eq(w.state, GameWorld.State.PLAYING, "combat started (diff %d)" % diff)
		check(Run.active_time < 2.0 * frame, "intro not counted (diff %d)" % diff)
		var t0 := Run.active_time
		for i in 120:
			gs._process(frame)   # 2.0 real seconds of play
		var t1 := Run.active_time
		check_near(t1 - t0, 2.0, LevelData.SIM_STEP, "2 real s of play = 2.0 s play time (diff %d)" % diff)
		check(w.combat_time() > 2.0 * w.speed_factor - 0.02, "game time runs ×%.2f (diff %d)" % [w.speed_factor, diff])
		gs.call("_set_paused", true)
		for i in 120:
			gs._process(frame)
		check_near(Run.active_time, t1, 1e-12, "pause not counted (diff %d)" % diff)
		gs.call("_set_paused", false)
		var lives0 := Run.lives
		guard = 0
		while not bool(gs.get("_done")) and guard < 20000:
			gs._process(frame)
			guard += 1
		check_eq(w.state, GameWorld.State.COMPLETE, "level completed (diff %d)" % diff)
		check_eq(Run.lives, lives0, "no life lost by the level change (diff %d)" % diff)
		check_eq(Fmt.time(Run.active_time).length(), 7, "MM:SS.t")
		_cleanup(gs)
