extends TestBase
## Fair spawning and stack breaking (docs/SPEC.md §5): a new original keeps its column free of the figures on
## the other lanes and starts away from the nearest one; from level 10 on a figure that stays covered by a lower
## one reverses early, within the 1.2–3.2 s direction-change rule.

const STEP := LevelData.SIM_STEP
const LO := LevelData.ENEMY_MIN_X
const HI := LevelData.ENEMY_MAX_X


# --- Helpers -------------------------------------------------------------------------------------
## A world in combat with no automatic spawns, no enemy fire and no oscillation (enemies DO move).
func _world(level: int, diff := 1, rng_seed := 7) -> GameWorld:
	var w := GameWorld.new(level, diff, 0, 3, rng_seed)
	w.auto_slots = false
	w.osc_amplitude = 0.0
	w.allow_enemy_fire = false
	w.start_combat()
	w.events.clear()
	return w


func _steps(seconds: float) -> int:
	return int(round(seconds / STEP))


## Index of the first slot on `lane` (slots follow LevelData.slot_lanes()).
func _slot_on(w: GameWorld, lane: int) -> int:
	for i in w.slots.size():
		if w.slots[i].lane == lane:
			return i
	return -1


## Smallest |dx| from x to any figure on another lane than `lane` (ignoring `skip`).
func _column_gap(w: GameWorld, lane: int, x: float, skip: GameWorld.Enemy = null) -> float:
	var d := INF
	for o in w.enemies:
		if o != skip and o.lane != lane:
			d = minf(d, absf(o.x - x))
	return d


func _lane_gap(w: GameWorld, lane: int, x: float, skip: GameWorld.Enemy = null) -> float:
	var d := INF
	for o in w.enemies:
		if o != skip and o.lane == lane:
			d = minf(d, absf(o.x - x))
	return d


## Two figures stacked on lanes 0 and 2 at x, both moving right; random changes pushed far away.
func _stack(w: GameWorld, x := 300.0) -> Array[GameWorld.Enemy]:
	var up := w.add_enemy(0, x, 1.0)
	var low := w.add_enemy(2, x, 1.0)
	for e in [up, low]:
		e.dir_timer = 100.0 if e.dir_timer != INF else INF
	return [up, low]


# --- Spawn position ------------------------------------------------------------------------------
func test_spawn_keeps_column_clear_of_other_lanes_including_children() -> void:
	var seen_segments := {}
	for sd in 40:
		var w := _world(8, 1, 100 + sd)
		w.add_enemy(1, 200.0)                       # original on the middle lane
		w.add_enemy(2, 480.0, 1.0, 0.45, true)      # children on the bottom lane block their column too
		w.add_enemy(1, 760.0, -1.0, 0.45, true)
		# Free columns (|dx| ≥ 110): [50, 90], [310, 370], [590, 650], [870, 910].
		var e := w._spawn_original(_slot_on(w, 0))
		check_eq(e.lane, 0)
		check(e.x >= LO and e.x <= HI, "inside the limits: %.2f" % e.x)
		check(_column_gap(w, 0, e.x, e) >= LevelData.SPAWN_COLUMN_CLEARANCE - 1e-9,
			"seed %d: column free (|dx| %.2f ≥ 110)" % [sd, _column_gap(w, 0, e.x, e)])
		seen_segments[floori(e.x / 250.0)] = true
	check(seen_segments.size() >= 3, "still random: spawns spread over the free columns (%d)" % seen_segments.size())


func test_spawn_at_combat_start_columns_free_and_uniform_on_empty_screen() -> void:
	for sd in 30:
		var w := GameWorld.new(14, 1, 0, 3, 500 + sd)
		w.start_combat()
		check_eq(w.enemies.size(), 3, "all three slots filled")
		for e in w.enemies:
			check(_column_gap(w, e.lane, e.x, e) >= LevelData.SPAWN_COLUMN_CLEARANCE - 1e-9,
				"seed %d lane %d: column free at combat start" % [sd, e.lane])
	# An empty screen leaves the whole range free: the first spawn is spread over [50, 910].
	var lo_hit := false
	var hi_hit := false
	for sd in 60:
		var w := _world(1, 1, 900 + sd)
		var x := w._spawn_original(0).x
		lo_hit = lo_hit or x < 200.0
		hi_hit = hi_hit or x > 760.0
	check(lo_hit and hi_hit, "first spawn uses the whole range")


func test_spawn_keeps_same_lane_distance() -> void:
	for sd in 40:
		var w := _world(16, 1, 300 + sd)
		w.add_enemy(0, 480.0, 1.0, 1.0, false, 0)   # slot 0, top lane
		w.add_enemy(1, 150.0)
		w.add_enemy(2, 800.0)
		# Free: [260, 320] ∪ [640, 690] (same lane ≥ 160 from 480, columns ≥ 110 from 150 / 800).
		var e := w._spawn_original(1)
		check_eq(e.lane, 0, "slot 1 is on the top lane")
		check(_lane_gap(w, 0, e.x, e) >= LevelData.SPAWN_MIN_DISTANCE - 1e-9,
			"seed %d: same-lane distance %.2f ≥ 160" % [sd, _lane_gap(w, 0, e.x, e)])
		check(_column_gap(w, 0, e.x, e) >= LevelData.SPAWN_COLUMN_CLEARANCE - 1e-9,
			"seed %d: column free %.2f" % [sd, _column_gap(w, 0, e.x, e)])
	# Only the own lane occupied: the old 160 px rule still holds.
	for sd in 20:
		var w := _world(16, 1, 700 + sd)
		w.add_enemy(1, 300.0, 1.0, 1.0, false, 2)
		var e := w._spawn_original(3)
		check(_lane_gap(w, 1, e.x, e) >= LevelData.SPAWN_MIN_DISTANCE - 1e-9, "same lane only: ≥ 160")


func test_spawn_crowded_screen_falls_back_to_best_compromise() -> void:
	for sd in 30:
		var w := _world(17, 1, 40 + sd)
		# Columns of five other-lane figures cover the whole range at 110 px; at 0.9 · 110 = 99 px slivers
		# around x = 200, 400, 600, 800 stay free – the compromise must find them.
		for i in 5:
			w.add_enemy(1 + (i % 2), 100.0 + 200.0 * i)
		var e := w._spawn_original(_slot_on(w, 0))
		check(e.x >= LO and e.x <= HI, "inside the limits")
		var gap := _column_gap(w, 0, e.x, e)
		check(gap >= 0.9 * LevelData.SPAWN_COLUMN_CLEARANCE - 1e-6 and gap < LevelData.SPAWN_COLUMN_CLEARANCE,
			"seed %d: best compromise keeps 99 px of column (%.3f)" % [sd, gap])
	# Hopelessly crowded (a figure every 40 px on both other lanes and the own lane): still a valid x,
	# and deterministic for the same seed.
	var xs: Array[float] = []
	for rep in 2:
		var w := _world(17, 1, 1234)
		for i in 22:
			w.add_enemy(i % 3, LO + 40.0 * i)
		var e := w._spawn_original(_slot_on(w, 0))
		check(e.x >= LO and e.x <= HI and is_finite(e.x), "crowded: valid x %.2f" % e.x)
		xs.append(e.x)
	check_eq(xs[0], xs[1], "deterministic with the world rng")


# --- Spawn direction -----------------------------------------------------------------------------
func test_spawn_starts_opposite_to_nearest_other_lane_figure() -> void:
	var w := _world(4)
	w.add_enemy(2, 300.0, 1.0)
	w.add_enemy(1, 700.0, -1.0)
	w.add_enemy(0, 470.0, -1.0)   # same lane: ignored
	check_eq(w._pick_spawn_dir(0, 420.0), -1.0, "nearest (x 300) moves right → start left")
	check_eq(w._pick_spawn_dir(0, 600.0), 1.0, "nearest (x 700) moves left → start right")
	check_eq(w._pick_spawn_dir(0, 510.0), 1.0, "210 vs 190 px: x 700 is nearer")
	var w8 := _world(8)
	w8.add_enemy(2, 500.0, 1.0)
	w8.add_enemy(1, 640.0, -1.0, 0.45, true)   # a child counts too
	check_eq(w8._pick_spawn_dir(0, 680.0), 1.0, "nearest is the child (moving left) → start right")
	# Nothing within 250 px: random as before (both directions occur).
	var dirs := {}
	for sd in 30:
		var wr := _world(4, 1, 60 + sd)
		wr.add_enemy(2, 100.0, 1.0)
		dirs[wr._pick_spawn_dir(0, 351.0)] = true
	check_eq(dirs.size(), 2, "random start direction without a near figure")
	# Full spawn flow: the new original separates from the nearest other-lane figure.
	for sd in 40:
		var ws := _world(14, 1, 10 + sd)
		ws.add_enemy(1, 380.0, 1.0 if sd % 2 == 0 else -1.0)
		ws.add_enemy(2, 640.0, -1.0 if sd % 3 == 0 else 1.0)
		var e := ws._spawn_original(0)
		var nearest: GameWorld.Enemy = null
		for o in ws.enemies:
			if o != e and o.lane != e.lane and (nearest == null or absf(o.x - e.x) < absf(nearest.x - e.x)):
				nearest = o
		if absf(nearest.x - e.x) <= LevelData.SPAWN_DIR_RANGE:
			check_eq(e.dir, -nearest.dir, "seed %d: opposite to the nearest figure's direction" % sd)


# --- Stack breaking ------------------------------------------------------------------------------
func test_stack_break_level14_after_half_a_second() -> void:
	var w := _world(14)
	var pair := _stack(w)
	var up := pair[0]
	var low := pair[1]
	up.turn_age = 5.0   # last direction change long ago
	check(w.is_covered(up) and not w.is_covered(low), "upper is covered, lower is not")
	w.run_steps(_steps(0.5) - 1)
	check_eq(up.dir, 1.0, "still stacked just before 0.5 s")
	w.run_steps(1)
	check_eq(up.dir, -1.0, "upper reversed after 0.5 s covered")
	check_eq(low.dir, 1.0, "the lower figure keeps its direction")
	check(up.dir_timer >= LevelData.DIR_CHANGE_MIN and up.dir_timer <= LevelData.DIR_CHANGE_MAX,
		"random timer restarted with rand(1.2, 3.2): %.3f" % up.dir_timer)
	check_eq(up.turn_age, 0.0)
	w.run_steps(_steps(1.0))
	check(absf(up.x - low.x) > LevelData.STACK_OVERLAP_DX, "the two separated")


func test_stack_break_never_sooner_than_1_2_s_after_last_change() -> void:
	var w := _world(14)
	var pair := _stack(w)
	var up := pair[0]
	up.turn_age = 0.0   # e.g. it has just turned
	w.run_steps(_steps(LevelData.DIR_CHANGE_MIN) - 1)
	check_eq(up.dir, 1.0, "covered for 1.2 s but its last change was < 1.2 s ago")
	check(up.cover_time >= LevelData.STACK_COVER_TIME, "cover time kept accumulating")
	w.run_steps(1)
	check_eq(up.dir, -1.0, "reverses exactly 1.2 s after its last change")
	# A limit turn counts as a direction change too.
	var w2 := _world(14)
	w2.enemy_speed = 93.0
	var up2 := w2.add_enemy(0, LO + 0.1, -1.0)
	var low2 := w2.add_enemy(2, LO + 30.0, 1.0)
	up2.dir_timer = 100.0
	low2.dir_timer = 100.0
	w2.run_steps(1)
	check_eq(up2.dir, 1.0, "turned at the limit")
	check(w2.is_covered(up2), "covered right after the limit turn")
	w2.run_steps(_steps(LevelData.DIR_CHANGE_MIN) - 1)
	check_eq(up2.dir, 1.0, "no break before 1.2 s after the limit turn")
	w2.run_steps(1)
	check_eq(up2.dir, -1.0, "break 1.2 s after the limit turn")


func test_stack_break_applies_to_children() -> void:
	var w := _world(10)
	var low := w.add_enemy(2, 400.0, -1.0)
	var kid := w.add_enemy(1, 420.0, -1.0, 0.45, true)
	low.dir_timer = 100.0
	kid.dir_timer = 100.0
	kid.turn_age = 3.0
	w.run_steps(_steps(0.5))
	check_eq(kid.dir, 1.0, "a covered child breaks away too")


func test_no_stack_break_below_level_10() -> void:
	for lvl in [4, 9]:
		var w := _world(lvl)
		var pair := _stack(w, 200.0)
		var up := pair[0]
		var low := pair[1]
		up.turn_age = 5.0
		check_eq(up.dir_timer, INF, "level %d: no random changes" % lvl)
		w.run_steps(_steps(6.0))   # 200 → ≈ 646 / 750 px: no limit reached
		check_eq(up.dir, 1.0, "level %d: upper keeps flying with the lower one" % lvl)
		check_near(up.x, low.x, 1e-9, "level %d: still stacked" % lvl)
		check_eq(up.cover_time, 0.0, "level %d: nothing counted" % lvl)
	# Full level 4 flow: every direction change below level 10 happens at a limit.
	for sd in 4:
		var w := GameWorld.new(4, 1, 0, 3, 20 + sd)
		w.invincible = true
		w.osc_amplitude = 0.0
		w.start_combat()
		var last: Array[float] = []
		for e in w.enemies:
			last.append(e.dir)
		for i in _steps(60.0):
			w.run_steps(1)
			for k in w.enemies.size():
				var e := w.enemies[k]
				if e.dir != last[k]:
					check(e.x == LO or e.x == HI, "level 4: turn away from a limit at x %.2f" % e.x)
					last[k] = e.dir


func test_stack_break_runs_in_game_time() -> void:
	var w := _world(14, 3)   # EXPERT: game time 1.44 × real time
	var pair := _stack(w)
	var up := pair[0]
	up.turn_age = 5.0
	w.update(0.34, 0.0, false)   # 117 sub-steps = 0.4875 game s
	check_eq(up.dir, 1.0, "0.49 game s: not yet")
	w.update(0.01, 0.0, false)   # 120 sub-steps = 0.5 game s after 0.35 real s
	check_eq(up.dir, -1.0, "0.5 GAME seconds suffice on Expert (0.35 real s)")


func test_stack_break_pauses_during_respawn() -> void:
	var w := _world(14)
	var pair := _stack(w)
	var up := pair[0]
	up.turn_age = 5.0
	w.run_steps(_steps(0.3))
	w.add_bullet(w.player_x, LevelData.PLAYER_Y)
	var combat := 0
	var guard := 0
	while up.dir == 1.0 and guard < 5000:
		if w.state == GameWorld.State.PLAYING:
			combat += 1
		var x0 := up.x
		var c0 := up.cover_time
		var paused := w.state == GameWorld.State.RESPAWN
		w.run_steps(1)
		if paused:
			check(up.x == x0 and up.cover_time == c0, "respawn: nothing moves, nothing counts")
		guard += 1
	check(w.flawless == false, "a life was lost (respawn happened)")
	check_eq(combat + _steps(0.3), _steps(LevelData.STACK_COVER_TIME), "exactly 0.5 s of combat covered")


func test_stack_breaks_in_level14_play_follow_the_rules() -> void:
	var breaks := 0
	for sd in 5:
		var w := GameWorld.new(14, 1, 0, 3, 70 + sd)
		w.invincible = true
		w.start_combat()
		for i in _steps(60.0):
			var prev := {}
			for e in w.enemies:
				prev[e.id] = [e.dir, e.dir_timer, e.turn_age, e.cover_time]
			w.run_steps(1)
			for e in w.enemies:
				if not prev.has(e.id) or e.dir == prev[e.id][0] or e.x == LO or e.x == HI:
					continue
				if float(prev[e.id][1]) - STEP <= GameWorld.EPS:
					continue   # random timer fired
				breaks += 1
				check(float(prev[e.id][2]) + STEP >= LevelData.DIR_CHANGE_MIN - 1e-6,
					"seed %d: break %.3f s after the last change (≥ 1.2)" % [sd, float(prev[e.id][2]) + STEP])
				check(float(prev[e.id][3]) + STEP >= LevelData.STACK_COVER_TIME - 1e-6, "covered ≥ 0.5 s")
				check(e.dir_timer >= LevelData.DIR_CHANGE_MIN and e.dir_timer <= LevelData.DIR_CHANGE_MAX,
					"timer restarted 1.2–3.2")
	check(breaks > 0, "stack breaks occur in level 14 play (%d)" % breaks)
