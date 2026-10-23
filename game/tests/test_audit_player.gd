extends TestBase
## Audit tests – dimension "player" (reference: first paragraph + section C of docs/REFERENCE_DE.md).
## All tests are regression evidence that a rule holds (the former defect test of finding player-1 now
## passes after the fix and was renamed).

const STEP := LevelData.SIM_STEP
const GameScreenScript := preload("res://scripts/game/game_screen.gd")


class LogicOnlyScreen extends GameScreenScript:
	func _update_views(_dt: float, _game_dt: float) -> void:
		pass


# --- helpers -------------------------------------------------------------------------------------
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


func _router_step(dt: float = 1.0 / 60.0) -> void:
	Input.flush_buffered_events()
	InputRouter._process(dt)


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _screen(level: int, difficulty: int, ship: int) -> Node2D:
	if (InputRouter.get("_down") as Dictionary).is_empty():
		InputRouter._ready()
	InputRouter.set_text_mode(false)
	_router_step()
	Run.start_new(difficulty, ship, level)
	Run.dev_flags = {"invincible": true}
	var gs: Node2D = LogicOnlyScreen.new()
	gs.setup({"level": level})
	gs._ready()
	var w: GameWorld = gs.get("world")
	w.allow_enemy_fire = false
	var guard := 0
	while w.state == GameWorld.State.INTRO and guard < 400:
		_router_step()
		gs._process(1.0 / 60.0)
		guard += 1
	return gs


func _frames(gs: Node2D, n: int) -> void:
	for i in n:
		_router_step()
		gs._process(1.0 / 60.0)


func _cleanup(gs: Node, keys: Array) -> void:
	for k in keys:
		_key(k, false)
	_router_step()
	_router_step()
	gs.free()
	Run.dev_flags = {}
	AudioManager.stop_music()


# --- Regression evidence (pass) ------------------------------------------------------------------
## REFERENCE H: "Bonus = ungenutzte Versuche × Schiffsfaktor" / "Ein zusätzliches Leben nur bei Bonus >6000".
## A player who simply HOLDS the fire button (allowed: "Gedrückthalten der Feuertaste ist erlaubt") makes the
## 20th kill with a non-piercing single shot. In that very sub-step the shots list becomes empty, but no new
## salvo may be created once the goal is reached (audit finding player-1, fixed in GameWorld._try_fire()).
## Interceptor with 16 attempts left after the killing salvo: 16 × 400 = 6400 (> 6000 → extra life).
func test_audit_player_bonus_held_fire_no_attempt_after_20th_kill() -> void:
	var w := _world(13, 0)          # Interceptor, factor 400
	w.destroyed = 19
	w.spawned = 20
	w.attempts = 17                 # the killing salvo uses one → 16 unused attempts remain
	var e := w.add_enemy(1, 480.0)
	w.player_x = 480.0
	var guard := 0
	while w.enemies.has(e) and guard < 2000:
		w.run_steps(1, 0.0, true)   # fire button held the whole time
		guard += 1
	check(not w.enemies.has(e), "20th enemy destroyed")
	w.run_steps(_steps(2.0), 0.0, true)
	check_eq(w.state, GameWorld.State.COMPLETE, "bonus level complete")
	check_eq(w.salvos_fired, 1, "no salvo may be created after the 20th kill")
	check_eq(int(w.bonus_result.get("remaining", -1)), 16, "unused attempts")
	check_eq(int(w.bonus_result.get("bonus", -1)), 6400, "bonus = 16 × 400")
	check_eq(bool(w.bonus_result.get("extra_life", false)), true, "6400 > 6000 → extra life")


## Ship table (REFERENCE C) + same movement speed for all ships + ±12 offsets.
func test_audit_player_ship_table_matches_reference() -> void:
	var expect := [
		["INTERCEPTOR", 500.0, 1, false, false],
		["FIGHTER", 430.0, 1, true, false],
		["DOUBLE DART", 430.0, 2, false, false],
		["DOUBLE HUNTER", 350.0, 2, true, false],
		["BLASTER", 350.0, 1, false, true],
		["HUNTER", 270.0, 1, true, true],
	]
	for i in expect.size():
		var sh := ShipData.ship(i)
		check_eq(String(sh["name"]), String(expect[i][0]))
		check_eq(float(sh["speed"]), float(expect[i][1]), "speed %d" % i)
		check_eq(int(sh["count"]), int(expect[i][2]), "count %d" % i)
		check_eq(bool(sh["guided"]), bool(expect[i][3]), "guided %d" % i)
		check_eq(bool(sh["piercing"]), bool(expect[i][4]), "piercing %d" % i)
		var offs := ShipData.shot_offsets(i)
		check_eq(offs.size(), int(expect[i][2]))
		if offs.size() == 2:
			check_eq(offs[0], -12.0)
			check_eq(offs[1], 12.0)
		# every ship moves 350 px/s
		var w := _world(1, i)
		w.run_game_seconds(1.0, -1.0)
		check_near(w.player_x, 130.0, 1e-6, "ship %d moves 350 px/s" % i)


## Projectile speed and player speed run on game time (REFERENCE D: Bewegung, Projektile beschleunigen).
func test_audit_player_projectile_and_movement_speed_scale_with_difficulty() -> void:
	for d in [0, 1, 2, 3]:
		var f := float(ShipData.difficulty(d)["speed_factor"])
		for ship in [0, 5]:
			var w := _world(1, ship, d)
			w.update(STEP / f * 1.0001, 0.0, true)   # exactly one sub-step: create the salvo
			check_eq(w.shots.size(), 1)
			var y0: float = w.shots[0].y
			w.update(0.5, 1.0, false)               # 0.5 REAL seconds
			var expected := float(ShipData.ship(ship)["speed"]) * 0.5 * f
			check_near(y0 - w.shots[0].y, expected, 4.0, "shot travel diff %d ship %d" % [d, ship])
			check_near(w.player_x - 480.0, 350.0 * 0.5 * f, 4.0, "move diff %d ship %d" % [d, ship])


## Guided: x = CURRENT ship x + ORIGINAL offset at all times, also while the ship is clamped at the border
## and also during CLEARING; never homing towards an enemy.
func test_audit_player_guided_offsets_follow_every_step_no_homing() -> void:
	var w := _world(1, 3)            # Double Hunter guided ±12
	var e := w.add_enemy(0, 100.0)   # far left target – must not attract the shots
	w.run_steps(1, 0.0, true)
	var axis := 1.0
	for i in 300:
		if i == 120:
			axis = -1.0
		w.run_steps(1, axis, false)
		if w.shots.size() == 2:
			check_near(w.shots[0].x, w.player_x - 12.0, 1e-9, "left guided step %d" % i)
			check_near(w.shots[1].x, w.player_x + 12.0, 1e-9, "right guided step %d" % i)
	check(w.enemies.has(e), "no homing hit")
	# Clamped at the right border.
	var c := _world(1, 3)
	c.player_x = 930.0
	c.run_steps(1, 0.0, true)
	c.run_steps(30, 1.0, false)
	check_near(c.shots[1].x, 942.0, 1e-9, "offset kept at the border")


## Non-piercing + double + split: the second bullet of a double salvo may hit a child of the enemy that the
## first bullet split (independent projectile), the splitting bullet itself is gone.
func test_audit_player_double_second_bullet_may_hit_child() -> void:
	var w := _world(8, 2)            # Double Dart, level 8 (children 45 %)
	var e := w.add_enemy(2, 480.0)
	w.player_x = 480.0               # bullets at 468 / 492 – both overlap the parent
	w.run_steps(1, 0.0, true)
	var guard := 0
	while not w.shots.is_empty() and guard < 2000:
		w.run_steps(1, 0.0, false)
		guard += 1
	check(not w.enemies.has(e), "parent split")
	check_eq(_count(w, "enemy_split"), 1)
	check_eq(_count(w, "enemy_destroyed"), 1, "the second (independent) bullet destroyed one child")
	check_eq(w.enemies.size(), 1)


## GameScreen input path: keyboard arrows / A / D move at 350 px/s × speed factor, Space holds fire.
func test_audit_player_game_screen_keyboard_input_path() -> void:
	for d in [1, 3]:
		var gs := _screen(1, d, 0)
		var w: GameWorld = gs.get("world")
		var f := float(ShipData.difficulty(d)["speed_factor"])
		check_eq(w.state, GameWorld.State.PLAYING)
		var x0 := w.player_x
		_key(KEY_RIGHT, true)
		_frames(gs, 30)
		check_near(w.player_x - x0, 350.0 * 0.5 * f, 3.0, "Right arrow moves at 350 px/s × %.2f" % f)
		_key(KEY_RIGHT, false)
		_router_step()
		x0 = w.player_x
		_key(KEY_A, true)
		_frames(gs, 30)
		check_near(x0 - w.player_x, 350.0 * 0.5 * f, 3.0, "A moves left")
		_key(KEY_A, false)
		_router_step()
		check(w.shots.is_empty(), "no shot without fire")
		_key(KEY_SPACE, true)
		_frames(gs, 2)
		check_eq(w.salvos_fired, 1, "Space fires")
		_frames(gs, 120)
		check(w.salvos_fired >= 2, "held Space refires automatically")
		_cleanup(gs, [KEY_SPACE, KEY_A, KEY_RIGHT])
