extends TestBase
## Power-up rules of GameWorld (docs/SPEC.md §19.3): activation conditions, real-time timer (speed factors,
## frozen outside PLAYING), RAPID FIRE salvo spacing, TWIN patrol / own salvo rule / guided shots / invincibility /
## scoring, SHIELD absorption, events – and that powerup NONE leaves the classic world bit-for-bit unchanged.

const STEP := LevelData.SIM_STEP
const PU := LevelData.PowerUp
const Wide := preload("res://tests/test_wide_playfield.gd")
const Autopilot := preload("res://scripts/game/autopilot.gd")


# --- Helpers -------------------------------------------------------------------------------------
## A world in combat with no automatic spawns, frozen enemies and no enemy fire, with the given power-up.
func _world(level: int, powerup: int, ship := 0, diff := 1, lives := 3) -> GameWorld:
	var w := GameWorld.new(level, diff, ship, lives, 7)
	w.powerup = powerup
	w.auto_slots = false
	w.enemy_speed = 0.0
	w.osc_amplitude = 0.0
	w.allow_enemy_fire = false
	w.start_combat()
	w.events.clear()
	return w


func _events(w: GameWorld, type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in w.events:
		if e["type"] == type:
			out.append(e)
	return out


func _steps(seconds: float) -> int:
	return int(round(seconds / STEP))


## A level that has this power-up (Saturn 8 / Jupiter 11 / Mars 15).
func _level_of(kind: int) -> int:
	match kind:
		PU.RAPID_FIRE:
			return 8
		PU.TWIN:
			return 11
	return 15


## Kills everything and marks every original as spawned: the level goal is met in the next PLAYING sub-step.
## A far-away bullet keeps the state PLAYING (final phase).
func _meet_goal(w: GameWorld) -> void:
	w.spawned = w.total
	while not w.enemies.is_empty():
		w.enemies.erase(w.enemies[0])
	w.add_bullet(5.0, 200.0, 0.0, 0.0)
	w.run_steps(1)


func _own_shots(w: GameWorld, twin: bool) -> Array[GameWorld.Shot]:
	var out: Array[GameWorld.Shot] = []
	for s in w.shots:
		if s.twin == twin:
			out.append(s)
	return out


# --- Activation -----------------------------------------------------------------------------------
func test_none_cannot_be_activated() -> void:
	var w := _world(8, PU.NONE)
	check(not w.can_activate_powerup(), "NONE: nothing to activate")
	check(not w.activate_powerup(), "NONE: activate refused")
	check_eq(w.powerup_state, GameWorld.PowerState.READY)
	check_eq(w.events.size(), 0, "no event")
	check_eq(w.powerup_left, 0.0)


func test_default_world_has_no_powerup() -> void:
	var w := GameWorld.new(8, 1, 0, 3, 1)
	check_eq(w.powerup, PU.NONE, "a world without POWER-UPS has none")
	var d := AttractDirector.new(77, 11)
	check_eq(d.make_world().powerup, PU.NONE, "demo worlds have none")


func test_activation_conditions() -> void:
	# Not in the intro.
	var w := GameWorld.new(8, 1, 0, 3, 7)
	w.powerup = PU.RAPID_FIRE
	check_eq(w.state, GameWorld.State.INTRO)
	check(not w.activate_powerup(), "not during the intro banner")
	w.update(LevelData.INTRO_TIME + 0.01, 0.0, false)
	check_eq(w.state, GameWorld.State.PLAYING)
	check(w.can_activate_powerup(), "in combat")
	# Not during a respawn.
	w.allow_enemy_fire = false
	w.add_bullet(w.player_x, LevelData.PLAYER_Y, 0.0, 0.0)
	w.run_steps(1)
	check_eq(w.state, GameWorld.State.RESPAWN)
	check(not w.can_activate_powerup(), "not while respawning")
	check(not w.activate_powerup())
	w.run_game_seconds(LevelData.RESPAWN_DELAY + 0.05)
	check_eq(w.state, GameWorld.State.PLAYING)
	check(w.activate_powerup(), "after the respawn")
	check_eq(w.powerup_state, GameWorld.PowerState.ACTIVE)
	# Only once.
	check(not w.activate_powerup(), "not twice while active")
	w.run_steps(_steps(LevelData.POWERUP_TIME[PU.RAPID_FIRE]) + 2)
	check_eq(w.powerup_state, GameWorld.PowerState.USED)
	check(not w.can_activate_powerup(), "never again after it was used")
	check(not w.activate_powerup())


func test_not_after_the_goal_or_at_game_over() -> void:
	var w := _world(15, PU.SHIELD)
	_meet_goal(w)
	check(w.goal_met, "goal met")
	check_eq(w.state, GameWorld.State.PLAYING, "final phase (a bullet still flies)")
	check(not w.can_activate_powerup(), "not after the goal")
	check(not w.activate_powerup())
	var g := _world(15, PU.SHIELD, 0, 1, 1)
	g.add_bullet(g.player_x, LevelData.PLAYER_Y, 0.0, 0.0)
	g.run_steps(1)
	check_eq(g.state, GameWorld.State.GAME_OVER_WAIT)
	check(not g.activate_powerup(), "not after the last life")


func test_activation_event_and_state() -> void:
	for kind: int in [PU.RAPID_FIRE, PU.TWIN, PU.SHIELD]:
		var w := _world(_level_of(kind), kind)
		check_eq(LevelData.powerup_of(_level_of(kind)), kind)
		w.player_x = 300.0
		check(w.activate_powerup(), "activate %d" % kind)
		var ev := _events(w, "powerup_activated")
		check_eq(ev.size(), 1)
		check_eq(int(ev[0]["kind"]), kind, "event kind")
		check_eq(float(ev[0]["x"]), 300.0, "event x = ship x")
		check_eq(w.powerup_left, float(LevelData.POWERUP_TIME[kind]), "full time")
		check(w.powerup_active(kind))


# --- Timer (real seconds) -------------------------------------------------------------------------
## The power-up lasts exactly POWERUP_TIME REAL seconds of combat at every speed factor (1.0 / 1.2 / 1.44).
func test_timer_runs_in_real_seconds_at_every_speed() -> void:
	for diff in [1, 2, 3]:
		for kind: int in [PU.RAPID_FIRE, PU.TWIN, PU.SHIELD]:
			var w := _world(_level_of(kind), kind, 0, diff)
			w.invincible = true
			check(w.activate_powerup())
			var total := float(LevelData.POWERUP_TIME[kind])
			var real := 0.0
			var half_checked := false
			var dt := 1.0 / 120.0
			while w.powerup_state == GameWorld.PowerState.ACTIVE and real < total + 1.0:
				w.update(dt, 0.0, false)
				real += dt
				if not half_checked and real >= total * 0.5 - 1e-9:
					half_checked = true
					check_near(w.powerup_left, total - real, STEP / w.speed_factor + 1e-6,
						"diff %d kind %d: left at half time" % [diff, kind])
			check_eq(w.powerup_state, GameWorld.PowerState.USED, "diff %d kind %d ended" % [diff, kind])
			check_near(real, total, dt + 1e-6, "diff %d kind %d: lasts %.1f real s" % [diff, kind, total])
			check_eq(w.powerup_left, 0.0)


## Frozen while the ship is down (RESPAWN) – and it survives the hit.
func test_timer_frozen_during_respawn_and_survives_the_hit() -> void:
	var w := _world(8, PU.RAPID_FIRE)
	check(w.activate_powerup())
	w.run_game_seconds(3.0)
	var left := w.powerup_left
	check_near(left, 7.0, 1e-6, "7 s left")
	w.add_bullet(w.player_x, LevelData.PLAYER_Y, 0.0, 0.0)
	w.run_steps(1)
	check_eq(w.state, GameWorld.State.RESPAWN)
	left = w.powerup_left
	w.run_game_seconds(1.0)
	check_eq(w.state, GameWorld.State.RESPAWN)
	check_eq(w.powerup_left, left, "frozen during the respawn")
	check_eq(w.powerup_state, GameWorld.PowerState.ACTIVE, "still active")
	w.run_game_seconds(0.5)
	check_eq(w.state, GameWorld.State.PLAYING, "respawned")
	check(w.powerup_active(PU.RAPID_FIRE), "continues after the respawn")
	check(w.powerup_left < left, "runs again")


## Frozen in the intro (it cannot be active then), at the level end (CLEARING) and – trivially – in the pause
## (the screen does not update the world).
func test_timer_frozen_at_the_level_end() -> void:
	var w := _world(11, PU.TWIN)
	check(w.activate_powerup())
	w.run_game_seconds(2.0)
	w.spawned = w.total
	w.enemies.clear()
	# An explosion keeps the world in CLEARING for a while.
	var e := w.add_enemy(1, 500.0)
	w.apply_hit(e)   # split …
	for c in w.enemies.duplicate():
		w.apply_hit(c)   # … and destroy both children: two explosions
	w.run_steps(1)
	check_eq(w.state, GameWorld.State.CLEARING, "level end")
	var left := w.powerup_left
	var x0 := w.twin_x
	w.run_game_seconds(0.3)
	check_eq(w.state, GameWorld.State.CLEARING)
	check_eq(w.powerup_left, left, "frozen in CLEARING")
	check(w.twin_x != x0, "the twin keeps patrolling at the level end")


# --- RAPID FIRE -------------------------------------------------------------------------------------
## Collects the sub-step indices of the ship's own shot_fired events over n sub-steps with fire held.
func _fire_steps(w: GameWorld, n: int) -> Array[int]:
	var out: Array[int] = []
	for i in n:
		w.events.clear()
		w.run_steps(1, 0.0, true)
		for e in _events(w, "shot_fired"):
			if not bool(e.get("twin", false)):
				out.append(i)
	return out


func test_rapid_fire_single_ship_spacing() -> void:
	var w := _world(8, PU.RAPID_FIRE, 0)   # INTERCEPTOR: one shot per salvo
	check(w.activate_powerup())
	var steps := _fire_steps(w, _steps(5.0))
	check_eq(steps[0], 0, "fires at once")
	var gaps: Array[int] = []
	for i in range(1, steps.size()):
		gaps.append(steps[i] - steps[i - 1])
	for g in gaps:
		check(g == 43 or g == 44, "gap of 0.18 s on the 1/240 grid, got %d sub-steps" % g)
	# 25 gaps of 0.18 s = 4.5 s = 1080 sub-steps exactly (the remainder is carried over).
	check_eq(steps[25] - steps[0], 1080, "25 salvos in exactly 4.5 game s")
	check_eq(steps[20] - steps[0], 864, "20 shots in 3.6 game s (as many as a double ship)")
	check(w.shots.size() >= 6, "many salvos in flight at once (the one-salvo rule is suspended)")


func test_rapid_fire_double_ship_spacing() -> void:
	var w := _world(8, PU.RAPID_FIRE, 2)   # DOUBLE DART: two shots per salvo → 0.36 s
	check(w.activate_powerup())
	var steps := _fire_steps(w, _steps(5.0))
	check_eq(steps[0], 0)
	for i in range(1, steps.size()):
		var g := steps[i] - steps[i - 1]
		check(g == 86 or g == 87, "gap of 0.36 s, got %d" % g)
	check_eq(steps[10] - steps[0], 864, "10 double salvos = 20 shots in exactly 3.6 game s, like a single ship")
	check_eq(w.shots.size() % 2, 0, "whole double salvos")


func test_rapid_fire_needs_fire_held_and_stops_after_the_goal() -> void:
	var w := _world(8, PU.RAPID_FIRE, 0)
	check(w.activate_powerup())
	w.run_steps(100, 0.0, false)
	check_eq(_events(w, "shot_fired").size(), 0, "nothing without the fire button")
	w.events.clear()
	w.run_steps(1, 0.0, true)
	check_eq(_events(w, "shot_fired").size(), 1, "fires at once when pressed")
	_meet_goal(w)
	w.events.clear()
	w.run_steps(200, 0.0, true)
	check_eq(_events(w, "shot_fired").size(), 0, "no salvo after the level goal")


func test_normal_rule_after_rapid_fire() -> void:
	var w := _world(8, PU.RAPID_FIRE, 4)   # BLASTER: slow piercing shots (350 px/s, 2 s to leave the screen)
	check(w.activate_powerup())
	var n := 0
	while w.powerup_state == GameWorld.PowerState.ACTIVE and n < 5000:
		w.run_steps(1, 0.0, true)
		n += 1
	check_eq(w.powerup_state, GameWorld.PowerState.USED)
	check(w.shots.size() > 1, "salvos still in flight when it ends")
	w.events.clear()
	var first := -1
	for i in _steps(3.0):
		w.run_steps(1, 0.0, true)
		if not _events(w, "shot_fired").is_empty():
			first = i
			break
		check(not w.shots.is_empty(), "no new salvo while one of the ship's own is in flight")
	check(first > 0, "the next salvo leaves once all own salvos are gone (sub-step %d)" % first)
	check_eq(w.shots.size(), 1, "one salvo at a time again")


func test_rapid_fire_salvos_score_normally() -> void:
	var w := _world(8, PU.RAPID_FIRE, 0)
	var low := w.add_enemy(2, w.player_x, 1.0, 0.45, true)
	var high := w.add_enemy(0, w.player_x, 1.0, 0.45, true)
	check(w.activate_powerup())
	# The first salvo hits the lower child after 0.44 s; the second one left at 0.18 s and reaches the upper child
	# at 1.10 s (with the one-salvo rule it could only leave at 0.44 s and would arrive at 1.36 s).
	w.run_game_seconds(1.2, 0.0, true)
	check(w.find_enemy(low.id) == null, "the first salvo destroyed the lower child")
	check(w.find_enemy(high.id) == null, "a following salvo – already in flight – the upper one")
	check_eq(w.destroyed, 2)
	check_eq(w.score_delta, 2 * int(LevelData.level(8)["points"]), "normal points")


# --- TWIN ---------------------------------------------------------------------------------------------
func test_twin_appears_at_the_ship_and_patrols() -> void:
	var w := _world(10, PU.TWIN)
	check_eq(w.player_x, 480.0)
	check(w.activate_powerup())
	check_eq(w.twin_x, 480.0, "appears at the ship")
	check_eq(w.twin_dir, 1.0, "start position: a tie goes right")
	w.run_game_seconds(1.0)
	check_near(w.twin_x, 830.0, 1e-6, "350 px/s")
	w.run_game_seconds(0.5)
	# Clamped at the edge like the ship (at most one sub-step of 350 / 240 px is lost per turn).
	check_near(w.twin_x, 930.0 - (525.0 - 450.0), 350.0 * STEP, "turned at the right edge")
	check_eq(w.twin_dir, -1.0)
	w.run_game_seconds(2.5)
	check_eq(w.twin_dir, 1.0, "turned at the left edge")
	check(w.twin_x >= LevelData.PLAYER_MIN_X and w.twin_x <= LevelData.PLAYER_MAX_X)
	# The farther edge: from the right half it heads left.
	var w2 := _world(10, PU.TWIN)
	w2.player_x = 700.0
	check(w2.activate_powerup())
	check_eq(w2.twin_dir, -1.0, "heads for the farther (left) edge")
	# Wide playfield: the limits follow the width.
	var w3 := GameWorld.new(10, 1, 0, 3, 7, 1280.0)
	w3.powerup = PU.TWIN
	w3.auto_slots = false
	w3.allow_enemy_fire = false
	w3.start_combat()
	check(w3.activate_powerup())
	w3.run_game_seconds(2.0)
	check_eq(w3.twin_dir, -1.0, "turned at 1250 on the 1280 field")
	check_near(w3.twin_x, 1250.0 - (700.0 - 610.0), 350.0 * STEP)


func test_twin_fires_its_own_salvo_rule() -> void:
	var w := _world(10, PU.TWIN, 2)   # DOUBLE DART: a twin salvo is two shots
	w.player_x = 200.0
	check(w.activate_powerup())
	w.run_steps(1)
	var tev := _events(w, "shot_fired")
	check_eq(tev.size(), 1, "the twin fires at once (fire not held)")
	check(bool(tev[0].get("twin", false)), "marked twin")
	check_eq(int(tev[0]["ship_id"]), 2)
	check_eq(int(tev[0]["count"]), 2)
	check_eq(float(tev[0]["x"]), w.twin_x, "from the twin")
	var ts := _own_shots(w, true)
	check_eq(ts.size(), 2, "a double salvo")
	check_eq(ts[0].speed, 430.0, "normal DOUBLE DART shots")
	check_eq(ts[1].x - ts[0].x, 24.0, "±12 px")
	# A new twin salvo leaves exactly in the sub-step in which its previous one is gone – never earlier.
	var salvos := 0
	for i in _steps(5.0):
		var prev: Array[int] = []
		for s in _own_shots(w, true):
			prev.append(s.id)
		w.events.clear()
		w.run_steps(1)
		var fired := false
		for e in _events(w, "shot_fired"):
			fired = fired or bool(e.get("twin", false))
		if fired:
			salvos += 1
			for s in w.shots:
				check(not prev.has(s.id), "the previous twin salvo is gone before the next one")
		else:
			check(not _own_shots(w, true).is_empty(), "a twin salvo is always in flight while it is active")
	check_eq(salvos, 3, "a salvo every (639 + 40) / 430 s = 1.58 s")
	# The ship's own one-salvo rule ignores the twin's shots, and its events carry no twin key.
	var w2 := _world(10, PU.TWIN, 0)
	check(w2.activate_powerup())
	w2.run_steps(1)
	check(not _own_shots(w2, true).is_empty(), "twin salvo in flight")
	w2.events.clear()
	w2.run_steps(1, 0.0, true)
	var ev := _events(w2, "shot_fired")
	check_eq(ev.size(), 1, "the ship fires although a twin shot is in flight")
	check(not ev[0].has("twin"), "the ship's own event is the classic one")
	check_eq(float(ev[0]["x"]), w2.player_x)


func test_twin_guided_shots_follow_the_twin() -> void:
	var w := _world(10, PU.TWIN, 1)   # FIGHTER: guided
	w.player_x = 300.0
	check(w.activate_powerup())
	w.run_steps(1, 0.0, true)
	for i in 60:
		w.run_steps(1, -1.0, false)   # the ship flies left, the twin right
		for s in w.shots:
			if s.twin:
				check_eq(s.x, w.twin_x + s.offset, "twin shot follows the twin")
			else:
				check_eq(s.x, w.player_x + s.offset, "own shot follows the ship")
	# After it is gone, its guided shots keep following its last x.
	var w2 := _world(10, PU.TWIN, 5)   # HUNTER: slow guided shot (270 px/s)
	check(w2.activate_powerup())
	var n := 0
	while w2.powerup_state == GameWorld.PowerState.ACTIVE and n < 10000:
		w2.run_steps(1)
		n += 1
	var ts := _own_shots(w2, true)
	check(not ts.is_empty(), "a twin shot still flies when the twin is gone")
	var last := w2.twin_x
	w2.run_steps(20, 1.0)
	check_eq(w2.twin_x, last, "the twin no longer moves")
	for s in _own_shots(w2, true):
		check_eq(s.x, last + s.offset, "keeps following its last x")
	w2.events.clear()
	w2.run_steps(2000)
	for e in _events(w2, "shot_fired"):
		check(not bool(e.get("twin", false)), "no twin salvo after it ended")


func test_twin_is_invincible_and_scores() -> void:
	var w := _world(10, PU.TWIN, 0)
	w.player_x = 100.0
	check(w.activate_powerup())
	w.run_game_seconds(1.0)
	var b := w.add_bullet(w.twin_x, LevelData.PLAYER_Y, 0.0, 0.0)
	w.run_steps(1)
	check(w.bullets.has(b), "enemy bullets pass through the twin")
	check_eq(w.lives, 3)
	check(w.player_alive)
	w.bullets.clear()
	# A figure right above the twin's patrol: its shots destroy it with normal points.
	var w2 := _world(10, PU.TWIN, 4)   # BLASTER (piercing, 350 px/s)
	w2.player_x = 100.0
	var e := w2.add_enemy(1, 100.0)
	check(w2.activate_powerup())
	w2.run_game_seconds(1.5)
	check(w2.find_enemy(e.id) == null, "the twin's shot split it")
	var w3 := _world(10, PU.TWIN, 0)
	var e3 := w3.add_enemy(2, 480.0, 1.0, 0.45, true)
	check(w3.activate_powerup())
	w3.run_game_seconds(1.0)
	check(w3.find_enemy(e3.id) == null, "child destroyed by the twin")
	check_eq(w3.score_delta, int(LevelData.level(10)["points"]), "twin kills score")


func test_twin_does_not_fire_after_the_goal() -> void:
	var w := _world(11, PU.TWIN, 0)
	check(w.activate_powerup())
	w.run_steps(1)
	w.shots.clear()
	_meet_goal(w)
	w.events.clear()
	w.run_game_seconds(1.0)
	check_eq(_events(w, "shot_fired").size(), 0, "no twin salvo after the level goal")


func test_player_hit_clears_twin_shots_and_freezes_the_twin() -> void:
	var w := _world(10, PU.TWIN, 0)
	check(w.activate_powerup())
	w.run_steps(3, 0.0, true)
	check(not _own_shots(w, true).is_empty() and not _own_shots(w, false).is_empty())
	w.add_bullet(w.player_x, LevelData.PLAYER_Y, 0.0, 0.0)
	w.run_steps(1)
	check_eq(w.state, GameWorld.State.RESPAWN)
	check(w.shots.is_empty(), "shots.clear() on a hit clears the twin's shots too")
	var x := w.twin_x
	w.run_game_seconds(1.0)
	check_eq(w.twin_x, x, "the twin waits during the respawn")
	check(w.shots.is_empty(), "and does not fire")


# --- SHIELD -------------------------------------------------------------------------------------------
func test_shield_absorbs_bullets_in_its_zone() -> void:
	var w := _world(15, PU.SHIELD)
	check(w.activate_powerup())
	var px := w.player_x
	var inside := [Vector2(px, LevelData.PLAYER_Y), Vector2(px + 33.0, LevelData.PLAYER_Y - 29.0),
		Vector2(px - 33.0, LevelData.PLAYER_Y + 20.0)]
	var outside := [Vector2(px + 35.0, LevelData.PLAYER_Y), Vector2(px, LevelData.PLAYER_Y - 31.0)]
	for p: Vector2 in inside:
		w.add_bullet(p.x, p.y, 0.0, 0.0)
	var kept: Array[GameWorld.Bullet] = []
	for p: Vector2 in outside:
		kept.append(w.add_bullet(p.x, p.y, 0.0, 0.0))
	w.run_steps(1)
	var ab := _events(w, "shield_absorbed")
	check_eq(ab.size(), 3, "three absorbed")
	check(ab[0].has("x") and ab[0].has("y"))
	check_eq(float(ab[1]["x"]), px + 33.0)
	check_eq(w.bullets.size(), 2, "the two outside the zone fly on")
	for b in kept:
		check(w.bullets.has(b))
	check(w.player_alive and w.lives == 3, "not hit")
	check(w.flawless, "still flawless")


## A real barrage (level 15/16 enemy fire, the ship standing still under the bottom lane): never hit while the
## shield is up, hit by the first bullet after it is gone.
func test_shield_player_is_never_hit() -> void:
	for level in [15, 16]:
		var w := GameWorld.new(level, 3, 2, 3, 4242)
		w.powerup = PU.SHIELD
		w.update(LevelData.INTRO_TIME + 0.001, 0.0, false)
		check(w.activate_powerup())
		var absorbed := 0
		var hits := 0
		while w.powerup_state == GameWorld.PowerState.ACTIVE:
			# Seek the fireballs: stand under the lowest figure (sub-step by sub-step: the shield is up in every one).
			var axis := 0.0
			var low: GameWorld.Enemy = null
			for e in w.enemies:
				if low == null or e.y > low.y:
					low = e
			if low != null:
				axis = clampf((low.x - w.player_x) / 20.0, -1.0, 1.0)
			w.run_steps(1, axis, false)
			absorbed += _events(w, "shield_absorbed").size()
			hits += _events(w, "player_hit").size()
			w.events.clear()
		check_eq(hits, 0, "level %d: never hit while shielded" % level)
		check(absorbed > 0, "level %d: the shield absorbed %d fireballs" % [level, absorbed])
		check_eq(w.lives, 3)
		w.add_bullet(w.player_x, LevelData.PLAYER_Y, 0.0, 0.0)
		w.run_steps(1)
		check_eq(_events(w, "player_hit").size(), 1, "level %d: hit again once the shield is gone" % level)


# --- Events -----------------------------------------------------------------------------------------------
func test_expiry_events() -> void:
	var w := _world(10, PU.TWIN)
	check(w.activate_powerup())
	w.run_game_seconds(LevelData.POWERUP_TIME[PU.TWIN] - 0.5)
	check_eq(_events(w, "powerup_expired").size(), 0)
	w.events.clear()
	w.run_game_seconds(1.0, -1.0)
	var ex := _events(w, "powerup_expired")
	check_eq(ex.size(), 1, "one expiry")
	check_eq(int(ex[0]["kind"]), PU.TWIN)
	check_eq(float(ex[0]["x"]), w.twin_x, "x = the twin's")
	check(float(ex[0]["x"]) != w.player_x)
	var r := _world(15, PU.SHIELD)
	r.player_x = 222.0
	check(r.activate_powerup())
	r.run_game_seconds(11.0)
	var ex2 := _events(r, "powerup_expired")
	check_eq(ex2.size(), 1)
	check_eq(float(ex2[0]["x"]), 222.0, "x = the ship's")
	check_eq(int(ex2[0]["kind"]), PU.SHIELD)


func test_powerups_are_deterministic() -> void:
	var a := GameWorld.new(11, 2, 3, 3, 99)
	var b := GameWorld.new(11, 2, 3, 3, 99)
	for w in [a, b]:
		w.powerup = PU.TWIN
	var lines: Array[Array] = [[], []]
	for i in 1500:
		var axis := sin(float(i) * 0.03)
		for k in 2:
			var w: GameWorld = [a, b][k]
			if i == 200:
				check(w.activate_powerup(), "activated")
			w.update(1.0 / 60.0, axis, i % 5 != 0)
			for ev in w.events:
				lines[k].append(JSON.stringify(ev, "", true, true))
			w.events.clear()
	check_eq(lines[0], lines[1], "same event stream")
	check(lines[0].size() > 200, "%d events" % lines[0].size())
	var twin_salvos := 0
	for l: String in lines[0]:
		if l.contains("\"twin\":true"):
			twin_salvos += 1
	check(twin_salvos > 3, "the twin fired %d salvos" % twin_salvos)


# --- POWER-UPS OFF: the classic world --------------------------------------------------------------------
## The classic game is bit-for-bit unchanged with the power-up code in place: the digests recorded before the
## widescreen change (tests/test_wide_playfield.gd) come out exactly the same with powerup NONE set explicitly and
## a (refused) power-up press in every frame.
func test_none_is_bit_for_bit_the_classic_world() -> void:
	for row: Array in Wide.EXPECTED:
		var a: Array = row[0]
		var got := _digest_with_presses(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7])
		var want: Dictionary = row[1]
		for k: String in want:
			if want[k] is float:
				check_near(float(got.get(k, NAN)), want[k], 1e-9, "%s: %s" % [str(a), k])
			else:
				check_eq(got.get(k), want[k], "%s: %s" % [str(a), k])
		if not failures.is_empty():
			return


## The same scenarios played WITH the level's power-up (pressed as soon as possible) differ – the comparison above
## is not vacuous – except on levels without one.
func test_powerup_changes_the_game() -> void:
	for row: Array in Wide.EXPECTED:
		var a: Array = row[0]
		var kind := LevelData.powerup_of(a[0])
		var got := _digest_with_presses(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], kind)
		if kind == PU.NONE:
			check_eq(got["md5"], row[1]["md5"], "%s: no power-up on this level" % str(a))
		else:
			check(got["md5"] != row[1]["md5"], "%s: the power-up changes the game" % str(a))


## Wide.digest() with a power-up press in every frame (and the world's power-up set to `kind`).
func _digest_with_presses(level: int, diff: int, ship: int, rng_seed: int, lives: int, invincible: bool,
		policy: String, seconds: float, kind: int = PU.NONE) -> Dictionary:
	var w := GameWorld.new(level, diff, ship, lives, rng_seed)
	w.powerup = kind
	w.invincible = invincible
	var lines := PackedStringArray()
	var frames := int(seconds * 60.0)
	for i in frames:
		var axis := 0.0
		var fire := false
		if policy == "bot":
			var d: Vector2 = Autopilot.decide(w)
			axis = d.x
			fire = d.y > 0.5
		else:
			var t := float(i) / 60.0
			axis = 1.0 if fposmod(t, 7.0) < 3.6 else -1.0
			if fposmod(t, 11.0) > 9.5:
				axis = 0.0
			fire = fposmod(t, 4.0) < 3.0
		if w.activate_powerup() and kind == PU.NONE:
			failures.append("NONE activated")
		w.update(1.0 / 60.0, axis, fire)
		for ev in w.events:
			lines.append("%d %s" % [i, JSON.stringify(ev, "", true, true)])
		w.events.clear()
		if w.is_finished():
			break
	var es := []
	for e in w.enemies:
		es.append([e.id, e.x, e.y, e.dir])
	return {"events": lines.size(), "md5": "\n".join(lines).md5_text(), "score": w.score_delta, "lives": w.lives,
		"destroyed": w.destroyed, "steps": w.step_count, "player_x": w.player_x, "state": int(w.state),
		"enemies_md5": JSON.stringify(es, "", true, true).md5_text()}
