extends TestBase
## AUDIT (hits dimension): hit rules, split, colour lock, rolling window, points (REFERENCE_DE.md §E, §G, §K bass).

const STEP := LevelData.SIM_STEP
const Autopilot := preload("res://scripts/game/autopilot.gd")
const GameScreenScript := preload("res://scripts/game/game_screen.gd")


class LogicOnlyScreen extends GameScreenScript:
	func _update_views(_dt: float, _game_dt: float) -> void:
		pass


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


func _count(evs: Array, type: String) -> int:
	var n := 0
	for e in evs:
		if e["type"] == type:
			n += 1
	return n


# --- Table E points / hit rule per level ---------------------------------------------------------
func test_points_and_rule_table() -> void:
	var pts := [0, 10, 10, 10, 25, 25, 25, 25, 25, 25, 40, 40, 50, 0, 75, 100, 110, 120, 120, 150, 150]
	for n in range(1, 21):
		check_eq(int(LevelData.level(n)["points"]), pts[n], "points L%d" % n)
		var r := LevelData.hit_rule(n)
		var exp := LevelData.Hit.SINGLE
		if n >= 7 and n <= 12:
			exp = LevelData.Hit.SPLIT
		elif n >= 14 and n <= 16:
			exp = LevelData.Hit.COLOR_LOCK
		elif n >= 19:
			exp = LevelData.Hit.ROLLING
		check_eq(int(r), int(exp), "hit rule L%d" % n)


# --- Split in every split level ------------------------------------------------------------------
func test_split_every_level() -> void:
	for n in range(7, 13):
		var w := _world(n)
		var e := w.add_enemy(1, 480.0)
		w.apply_hit(e)
		check_eq(w.enemies.size(), 2, "L%d two children" % n)
		check_eq(w.score_delta, 0, "L%d split gives no points" % n)
		for c in w.enemies:
			check_near(c.scale, 0.40 if n == 7 else 0.45, 1e-9, "L%d child scale" % n)
			check_eq(c.lane, 1, "L%d child on parent lane" % n)
			check(c.is_child)
			check_eq(c.flap_offset, e.flap_offset, "L%d synchronous flap" % n)
		var p := int(LevelData.level(n)["points"])
		w.apply_hit(w.enemies[0])
		check_eq(w.score_delta, p, "L%d one hit destroys a child" % n)
		w.apply_hit(w.enemies[0])
		check_eq(w.score_delta, 2 * p, "L%d pair" % n)
		check(w.enemies.is_empty())


# --- Bass: GameScreen forwards only FINAL destructions to AudioManager ----------------------------
func _screen(level: int) -> Node2D:
	if (InputRouter.get("_down") as Dictionary).is_empty():
		InputRouter._ready()
	Run.start_new(1, 0, level)
	Run.dev_flags = {"invincible": true}
	var gs: Node2D = LogicOnlyScreen.new()
	gs.setup({"level": level})
	gs._ready()
	return gs


func test_bass_rises_only_on_final_destruction() -> void:
	for n in [8, 14, 19]:
		var gs := _screen(n)
		var w: GameWorld = gs.get("world")
		w.start_combat()
		w.auto_slots = false
		for e in w.enemies.duplicate():
			w.enemies.erase(e)
		w.events.clear()
		gs.call("_handle_events")
		var b0: int = AudioManager.bass_semitone()
		var a := w.add_enemy(2, 480.0)
		w.apply_hit(a)   # split / stage / rolling 1
		gs.call("_handle_events")
		check_eq(AudioManager.bass_semitone(), b0, "L%d no rise on non-final hit" % n)
		if n == 8:
			# Client decision (feedback round 1): one semitone per ORIGINAL, i.e. when the pair is gone.
			w.apply_hit(w.enemies[0])
			gs.call("_handle_events")
			check_eq(AudioManager.bass_semitone(), b0, "L8 first child destroyed: no rise yet")
			w.apply_hit(w.enemies[0])
			gs.call("_handle_events")
			check_eq(AudioManager.bass_semitone(), b0 + 1, "L8 second child destroyed: pair gone, +1")
		elif n == 14:
			var v := w.add_enemy(0, 150.0)
			w.apply_hit(a)   # locked (violet v alive)
			gs.call("_handle_events")
			check_eq(AudioManager.bass_semitone(), b0, "L14 locked hit")
			w.apply_hit(v)
			w.apply_hit(v)
			w.apply_hit(a)
			gs.call("_handle_events")
			check_eq(AudioManager.bass_semitone(), b0, "L14 stage changes")
			w.apply_hit(a)
			gs.call("_handle_events")
			check_eq(AudioManager.bass_semitone(), b0 + 1, "L14 final destruction")
		else:
			w.apply_hit(a)
			gs.call("_handle_events")
			check_eq(AudioManager.bass_semitone(), b0, "L19 second non-lethal")
			w.apply_hit(a)
			gs.call("_handle_events")
			check_eq(AudioManager.bass_semitone(), b0 + 1, "L19 destruction")
		gs.free()
		Run.dev_flags = {}
		AudioManager.stop_music()


# --- Mars rules screen (REFERENCE G: "durchschlagende fliegen weiter") ---------------------------
## The rules screen before level 14 must not tell a pilot of a piercing ship (Blaster, Hunter) that locked
## hits waste the shot: the reference says piercing shots fly on after a locked hit. Pilots of normal ships
## are told that their shot is used up. Every rule line must fit inside the panel (right edge x = 920).
## (Audit finding hits-1, regression test.)
func test_mars_rules_screen_locked_hit_text_matches_ship() -> void:
	if Assets.font_body == null:
		Assets._ready()   # font loading only; not run yet inside the test runner
	var script: GDScript = load("res://scripts/screens/mars_rules_screen.gd")
	var consts := script.get_script_constant_map()
	var saved_ship := Run.ship_id
	for ship in ShipData.SHIPS.size():
		Run.ship_id = ship
		var s: Node2D = script.new()
		s.setup({"level": 13})
		s.call("_enter")
		var text := ""
		for row in (s.get("_rules") as Array):
			for line in row:
				var w := 0.0
				var line_text := ""
				for seg in line:
					line_text += String(seg[0])
					var plain: bool = seg[1] == consts["C_W"] or seg[1] == consts["C_D"]   # same fonts as _rich()
					w += UiKit.text_width(Assets.font_body if plain else Assets.font_body_bold, String(seg[0]), 19)
				text += line_text + "\n"
				check(float(consts["TEXT_X"]) + w <= 910.0,
					"ship %d: rule line fits the panel (ends at %.0f): %s" % [ship, float(consts["TEXT_X"]) + w, line_text])
		s.free()
		var low := text.to_lower()
		if bool(ShipData.ship(ship)["piercing"]):
			check(not low.contains("wasted"), "ship %d (piercing): no 'wasted shots' claim:\n%s" % [ship, text])
			check(low.contains("flies on") or low.contains("fly on"), "ship %d (piercing): shot flies on:\n%s" % [ship, text])
		else:
			check(low.contains("wasted"), "ship %d (normal): locked hits waste the shot:\n%s" % [ship, text])
	Run.ship_id = saved_ship
	AudioManager.stop_music()


# --- Rolling window on HARD ----------------------------------------------------------------------
func test_rolling_window_hard_is_game_time() -> void:
	var w := _world(19, 0, 2)   # HARD ×1.2
	var a := w.add_enemy(0, 150.0)
	w.apply_hit(a)
	w.update(10.0 / 1.2 + 0.02, 0.0, false)   # 10.02 game s
	w.apply_hit(a)
	w.apply_hit(a)
	check(w.enemies.has(a), "HARD: hit expired after 10 game seconds (8.35 real s)")
	var w2 := _world(19, 0, 2)
	var b := w2.add_enemy(0, 150.0)
	w2.apply_hit(b)
	w2.update(10.0 / 1.2 - 0.05, 0.0, false)
	w2.apply_hit(b)
	w2.apply_hit(b)
	check(not w2.enemies.has(b), "HARD: three hits within 10 game s")


# --- Randomised invariants over whole levels -----------------------------------------------------
## Plays whole levels with a random/autopilot player (invincible) and checks after every sub-step:
## colour-lock transitions only when allowed, points only on destruction, rolling destruction only with
## 3 hits in 10 game s, split levels destroy 2 × total figures.
## (The audit ran levels 7, 9, 10, 12, 14, 15, 16, 19, 20 × ships 0/2/4/5 × 2 seeds without a violation;
## a small subset is kept as a regression test to keep the suite fast.)
func test_invariants_random_play() -> void:
	for spec in [[8, 2, 1], [15, 4, 1], [20, 3, 2]]:
		_play_level(int(spec[0]), int(spec[1]), int(spec[2]))


func _play_level(n: int, ship: int, sd: int) -> void:
	var w := GameWorld.new(n, 1, ship, 3, sd * 101 + ship)
	w.invincible = true
	var rng := RandomNumberGenerator.new()
	rng.seed = sd * 7 + ship
	var axis := 0.0
	var hits := {}    # id -> Array of step_count of non-lethal rolling hits
	var pts_sum := 0
	var tag := "L%d ship%d seed%d" % [n, ship, sd]
	var guard := 0
	var max_steps := 240 * 900
	while not w.is_finished() and guard < max_steps:
		guard += 1
		if guard % 30 == 0:
			if n >= 14 and n <= 16:
				# target a random enemy so colour-lock levels make progress
				axis = rng.randf_range(-1.0, 1.0)
				if not w.enemies.is_empty():
					var t: GameWorld.Enemy = w.enemies[rng.randi_range(0, w.enemies.size() - 1)]
					axis = clampf((t.x - w.player_x) / 20.0, -1.0, 1.0)
			else:
				var d: Vector2 = Autopilot.decide(w)
				axis = d.x if rng.randf() < 0.8 else rng.randf_range(-1.0, 1.0)
		w.update(STEP, axis, true)
		for ev in w.events:
			match String(ev["type"]):
				"enemy_destroyed":
					pts_sum += int(ev["points"])
					if n >= 14 and n <= 16:
						for e in w.enemies:
							if e.stage != LevelData.Stage.GREEN:
								failures.append("%s destroyed while a non-green enemy is alive" % tag)
								break
						if int(ev["stage"]) != LevelData.Stage.GREEN:
							failures.append("%s destroyed a non-green enemy" % tag)
					if n >= 19:
						var hs: Array = hits.get(int(ev["id"]), [])
						var recent := 0
						for t in hs:
							if w.step_count - int(t) <= 2400:
								recent += 1
						if recent < 2:
							failures.append("%s rolling destruction with only %d recent hits" % [tag, recent])
					if n >= 7 and n <= 12 and not bool(ev["is_child"]):
						failures.append("%s original destroyed without split" % tag)
				"enemy_hit_nonlethal":
					if String(ev["kind"]) == "rolling":
						if not hits.has(int(ev["id"])):
							hits[int(ev["id"])] = []
						hits[int(ev["id"])].append(w.step_count)
					elif int(ev["stage"]) == LevelData.Stage.GREEN:
						for e in w.enemies:
							if e.stage == LevelData.Stage.VIOLET:
								failures.append("%s turned green while violet alive" % tag)
								break
		w.events.clear()
	if not w.is_finished():
		failures.append("%s did not finish (destroyed %d/%d spawned %d)" % [tag, w.destroyed, w.total, w.spawned])
		return
	var mult := 2 if (n >= 7 and n <= 12) else 1
	check_eq(w.destroyed, w.total * mult, "%s destroyed count" % tag)
	check_eq(pts_sum, w.total * mult * int(LevelData.level(n)["points"]), "%s points sum" % tag)
	check_eq(w.score_delta, pts_sum + w.completion_bonus, "%s score = kills + bonus" % tag)
