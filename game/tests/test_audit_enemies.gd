extends TestBase
## Audit (enemies dimension): movement, lanes, limits, slots/refill, collisions (docs/REFERENCE_DE.md §B, §I).
## Experiments drive the pure GameWorld; only tests that document a rule or a defect are kept here.

const Autopilot := preload("res://scripts/game/autopilot.gd")
const STEP := LevelData.SIM_STEP


func _steps(seconds: float) -> int:
	return int(round(seconds / STEP))


## True when the straight segment r0 → r1 passes through the OPEN box |x| < hx, |y| < hy.
static func _segment_hits_box(r0: Vector2, r1: Vector2, hx: float, hy: float) -> bool:
	var t0 := 0.0
	var t1 := 1.0
	var d := r1 - r0
	for axis in 2:
		var p0: float = r0[axis]
		var dd: float = d[axis]
		var h := hx if axis == 0 else hy
		if absf(dd) < 1e-12:
			if absf(p0) >= h:
				return false
			continue
		var a := (-h - p0) / dd
		var b := (h - p0) / dd
		t0 = maxf(t0, minf(a, b))
		t1 = minf(t1, maxf(a, b))
	return t0 < t1


static func _inside(r: Vector2, hx: float, hy: float) -> bool:
	return absf(r.x) < hx and absf(r.y) < hy


## Deepest penetration (px) of the segment r0 → r1 into the open box: min(hx − |x|, hy − |y|), sampled.
static func _max_depth(r0: Vector2, r1: Vector2, hx: float, hy: float) -> float:
	var best := 0.0
	for i in 201:
		var p := r0.lerp(r1, float(i) / 200.0)
		best = maxf(best, minf(hx - absf(p.x), hy - absf(p.y)))
	return best


## A real tunnel: between two samples the relative position jumped over the WHOLE box extent on one axis.
static func _tunnels(r0: Vector2, r1: Vector2, hx: float, hy: float) -> bool:
	if not _segment_hits_box(r0, r1, hx, hy):
		return false
	return (r0.y >= hy and r1.y <= -hy) or (r0.y <= -hy and r1.y >= hy) \
		or (r0.x >= hx and r1.x <= -hx) or (r0.x <= -hx and r1.x >= hx)


# --- Lanes, oscillation, slots and refill over whole levels ----------------------------------------
## Plays every level with random hits (no enemy fire, invincible) and checks the lane / oscillation / slot /
## total invariants in every single sub-step, plus the exact refill delay of every refill that happened.
func test_lanes_oscillation_slots_refill_invariants_all_levels() -> void:
	for lvl in range(1, 21):
		var w := GameWorld.new(lvl, 3, 0, 3, 100 + lvl)   # EXPERT: game time only, the rules are the same
		w.allow_enemy_fire = false
		w.invincible = true
		w.start_combat()
		var lane_of := {}
		var spawn_events := 0
		var free_since := {}       # slot → step_count when it became free
		var refills := 0
		var bad_refill := ""
		var rng := RandomNumberGenerator.new()
		rng.seed = 900 + lvl
		var guard := 0
		while not w.is_finished() and guard < _steps(300.0):
			guard += 1
			if guard % 20 == 0 and not w.enemies.is_empty():
				w.apply_hit(w.enemies[rng.randi_range(0, w.enemies.size() - 1)])
				for i in w.slots.size():
					if w.slots[i].alive == 0 and not free_since.has(i) and w.spawned < w.total:
						free_since[i] = w.step_count
			w.run_steps(1)
			for ev in w.events:
				if ev["type"] == "enemy_spawned":
					spawn_events += 1
					var ne := w.find_enemy(int(ev["id"]))
					if ne != null and free_since.has(ne.slot):
						refills += 1
						var waited := w.step_count - int(free_since[ne.slot])
						if waited != 480 and bad_refill == "":
							bad_refill = "level %d slot %d refilled after %d steps" % [lvl, ne.slot, waited]
						free_since.erase(ne.slot)
			w.events.clear()
			# slot bookkeeping
			var per_slot := {}
			var groups := {}
			for e in w.enemies:
				per_slot[e.slot] = int(per_slot.get(e.slot, 0)) + 1
				if not groups.has(e.slot):
					groups[e.slot] = {}
				groups[e.slot][e.group_id] = true
				if not lane_of.has(e.id):
					lane_of[e.id] = e.lane
				if e.lane != int(lane_of[e.id]):
					failures.append("level %d: enemy %d changed lane" % [lvl, e.id])
				if absf(e.y - LevelData.LANE_Y[e.lane]) > 22.0 + 1e-6:
					failures.append("level %d: |y - lane| = %f" % [lvl, absf(e.y - LevelData.LANE_Y[e.lane])])
				if e.slot < 0 or LevelData.slot_lanes(lvl)[e.slot] != e.lane:
					failures.append("level %d: enemy on the wrong lane for its slot" % lvl)
			for i in w.slots.size():
				var n := int(per_slot.get(i, 0))
				if n != w.slots[i].alive:
					failures.append("level %d slot %d: alive %d vs %d" % [lvl, i, w.slots[i].alive, n])
				if groups.has(i) and (groups[i] as Dictionary).size() > 1:
					failures.append("level %d slot %d holds two originals" % [lvl, i])
				if n > (2 if LevelData.hit_rule(lvl) == LevelData.Hit.SPLIT else 1):
					failures.append("level %d slot %d has %d figures" % [lvl, i, n])
				if n == 0 and not free_since.has(i) and w.spawned < w.total:
					failures.append("level %d slot %d free but not seen being freed" % [lvl, i])
			if w.spawned > w.total:
				failures.append("level %d: spawned %d > total %d" % [lvl, w.spawned, w.total])
			if failures.size() > 5:
				return
		check(w.is_finished(), "level %d finished (state %d, spawned %d/%d)" % [lvl, w.state, w.spawned, w.total])
		check_eq(w.spawned, w.total, "level %d: exactly the ORIGINAL total spawned" % lvl)
		check_eq(spawn_events, w.total, "level %d: spawn events (children never spawn)" % lvl)
		check(refills > 0, "level %d: refills observed" % lvl)
		check(bad_refill == "", bad_refill)
		if LevelData.hit_rule(lvl) == LevelData.Hit.SPLIT:
			check_eq(w.destroyed, 2 * w.total, "level %d: every original ends as two destroyed children" % lvl)


## The refill delay runs in GAME seconds: at Expert ×1.44 a free slot is refilled after 2.0/1.44 real seconds
## (driven through update() with real frame times, as GameScreen does).
func test_refill_delay_is_game_time_at_expert() -> void:
	var w := GameWorld.new(1, 3, 0, 5, 3)
	w.allow_enemy_fire = false
	w.update(LevelData.INTRO_TIME, 0.0, false)
	var e: GameWorld.Enemy = w.enemies[0]
	var slot := e.slot
	w.apply_hit(e)
	var frames := 0
	while w.slots[slot].alive == 0 and frames < 200:
		w.update(1.0 / 60.0, 0.0, false)
		frames += 1
	check_near(frames / 60.0, 2.0 / 1.44, 1.0 / 60.0 + 1e-9, "refill after 2.0 game s at Expert")


# --- Collisions without skips at the highest speed ---------------------------------------------------
## Expert ×1.44 with the fastest projectiles and the fastest enemies (level 13, tempo 3.6) and with the smallest
## hit boxes (children 0.40 / 0.45): no own projectile may pass through an enemy hit box between two sub-steps
## without a hit. Checked with an exact segment-vs-box test on the relative motion of every pair.
func test_no_skipped_shot_enemy_collisions_at_expert() -> void:
	var configs := [[13, 0], [13, 1], [12, 0], [7, 2], [10, 4]]
	for c in configs:
		var lvl: int = c[0]
		var ship: int = c[1]
		var w := GameWorld.new(lvl, 3, ship, 1, 40 + lvl)
		w.invincible = true
		w.allow_enemy_fire = false
		w.start_combat()
		var hits := 0
		var skipped := 0
		var grazes := 0
		var graze_depth := 0.0
		var n := 0
		var d := Vector2.ZERO
		while not w.is_finished() and n < _steps(45.0):
			n += 1
			var sp := {}
			for s in w.shots:
				sp[s.id] = Vector2(s.x, s.y)
			var ep := {}
			for e in w.enemies:
				ep[e.id] = Vector2(e.x, e.y)
			if n % 3 == 1:
				d = Autopilot.decide(w)
			w.run_steps(1, d.x, d.y > 0.5)
			for ev in w.events:
				if ev["type"] in ["enemy_destroyed", "enemy_split", "locked_hit", "enemy_hit_nonlethal"]:
					hits += 1
			w.events.clear()
			for s in w.shots:
				if not sp.has(s.id):
					continue
				for e in w.enemies:
					if not ep.has(e.id) or s.hit_ids.has(e.id):
						continue
					var hx := LevelData.HIT_DX * e.scale
					var hy := LevelData.HIT_DY * e.scale
					var r0: Vector2 = sp[s.id] - ep[e.id]
					var r1 := Vector2(s.x, s.y) - Vector2(e.x, e.y)
					if _segment_hits_box(r0, r1, hx, hy) and not _inside(r0, hx, hy) and not _inside(r1, hx, hy):
						if _tunnels(r0, r1, hx, hy):
							skipped += 1
						else:
							grazes += 1   # sub-step corner graze (inherent to fixed steps), measured below
							graze_depth = maxf(graze_depth, _max_depth(r0, r1, hx, hy))
		check(hits >= 15, "level %d ship %d: meaningful run (%d hits)" % [lvl, ship, hits])
		check_eq(skipped, 0, "level %d ship %d: tunnelled shot/enemy crossings" % [lvl, ship])
		check(graze_depth < 0.5, "level %d ship %d: corner grazes (%d) only sub-pixel (max %.3f px)" % [lvl, ship, grazes, graze_depth])
		if grazes > 0:
			print("    info: level %d ship %d: %d corner graze(s), deepest %.3f px" % [lvl, ship, grazes, graze_depth])


## Enemy bullets vs player (|dx| < 21, |dy| < 15) at Expert with the fastest (4–8 o'clock) bullets and a
## player that keeps moving: no bullet may cross the player box between two sub-steps without a hit.
func test_no_skipped_bullet_player_collisions_at_expert() -> void:
	for lvl in [20, 10]:
		var w := GameWorld.new(lvl, 3, 0, 100000, 70 + lvl)
		w.start_combat()
		var rng := RandomNumberGenerator.new()
		rng.seed = lvl
		var axis := 1.0
		var hits := 0
		var skipped := 0
		for n in _steps(60.0):
			if n % 50 == 0:
				axis = [-1.0, 0.0, 1.0][rng.randi_range(0, 2)]
			if w.is_finished():
				break
			var bp := {}
			for b in w.bullets:
				bp[b.id] = Vector2(b.x, b.y)
			var px0 := w.player_x
			var alive0 := w.player_alive
			w.run_steps(1, axis, false)
			var hit_now := false
			for ev in w.events:
				if ev["type"] == "player_hit":
					hit_now = true
					hits += 1
			w.events.clear()
			if hit_now or not alive0 or not w.player_alive:
				continue
			for b in w.bullets:
				if not bp.has(b.id):
					continue
				var r0: Vector2 = bp[b.id] - Vector2(px0, LevelData.PLAYER_Y)
				var r1 := Vector2(b.x, b.y) - Vector2(w.player_x, LevelData.PLAYER_Y)
				var hx := LevelData.PLAYER_HIT_DX
				var hy := LevelData.PLAYER_HIT_DY
				if _segment_hits_box(r0, r1, hx, hy) and not _inside(r0, hx, hy) and not _inside(r1, hx, hy):
					if _tunnels(r0, r1, hx, hy) or _max_depth(r0, r1, hx, hy) >= 0.5:
						skipped += 1
		check(hits >= 5, "level %d: meaningful run (%d player hits)" % [lvl, hits])
		check_eq(skipped, 0, "level %d: skipped bullet/player crossings" % lvl)


# --- Hit areas -----------------------------------------------------------------------------------------
## The cosmetic planet width factors (1.00 … 1.10) never enlarge the hit area: |dx| < 49·s, |dy| < 21·s in
## every planet section.
func test_hit_area_independent_of_planet_width_factor() -> void:
	for lvl in [1, 4, 7, 10, 13, 14, 17, 19]:
		for c in [[48.9, 0.0, true], [49.1, 0.0, false], [0.0, 20.9, true], [0.0, 21.1, false]]:
			var w := GameWorld.new(lvl, 1, 0, 3, 1)
			w.auto_slots = false
			w.enemy_speed = 0.0
			w.osc_amplitude = 0.0
			w.allow_enemy_fire = false
			w.start_combat()
			var e := w.add_enemy(1, 480.0)
			var s := GameWorld.Shot.new()
			s.x = 480.0 + float(c[0])
			s.y = 300.0 + float(c[1])
			w.shots.append(s)
			w.run_steps(1)
			var touched := w.events.size() > 0 and w.shots.is_empty()
			check_eq(touched, bool(c[2]), "level %d (wf %.2f) dx %s dy %s" % [lvl, LevelData.width_factor(lvl), c[0], c[1]])
			check(e != null)


# --- Wing flap -----------------------------------------------------------------------------------------
## 2.5 flap cycles per GAME second (3.6 per real second at Expert), also during the respawn pause, children in
## sync with each other.
func test_flap_rate_game_time_children_sync() -> void:
	var w := GameWorld.new(8, 3, 0, 5, 2)
	w.auto_slots = false
	w.allow_enemy_fire = false
	w.update(LevelData.INTRO_TIME, 0.0, false)
	var p := w.add_enemy(2, 480.0)
	p.flap_offset = 0.0
	var a0 := w.anim_time
	w.update(1.0, 0.0, false)
	check_near((w.anim_time - a0) * LevelData.FLAP_HZ, 3.6, 0.02, "cycles per real second at Expert")
	w.apply_hit(p)
	check_eq(w.enemies.size(), 2)
	var k0: GameWorld.Enemy = w.enemies[0]
	var k1: GameWorld.Enemy = w.enemies[1]
	w.add_bullet(w.player_x, LevelData.PLAYER_Y, 0.0, 0.0)
	w.run_steps(1)
	check_eq(w.state, GameWorld.State.RESPAWN)
	var f0 := w.flap_phase(k0)
	w.run_steps(24)   # 0.1 game s inside the respawn pause
	check_near(fposmod(w.flap_phase(k0) - f0, 1.0), 0.25, 1e-6, "flap keeps running during respawn")
	check_eq(w.flap_phase(k0), w.flap_phase(k1), "children flap in sync")


# --- Horizontal limits ----------------------------------------------------------------------------------
## REFERENCE §B: "Horizontale Grenzen ungefähr x=50 und x=910. Gegner wenden an den Grenzen."
## Like every other coordinate of the reference (player x 30…930, lane centres y 180/300/420, salvo y 639)
## these are positions of the figure (its centre). 50/910 = 5 px screen margin for the 90 px base body and
## exactly 0.5 px for the widest cosmetic variant (Earth 99 px). An enemy must therefore get to ≈ x 50 / 910.
func test_enemies_reach_reference_limits_x50_x910() -> void:
	for lvl in [1, 7, 17]:
		var w := GameWorld.new(lvl, 1, 0, 3, 5)
		w.auto_slots = false
		w.osc_amplitude = 0.0
		w.allow_enemy_fire = false
		w.start_combat()
		var e := w.add_enemy(1, 480.0, -1.0)
		e.dir_timer = INF   # only the turning at the limits matters here
		var lo := INF
		var hi := -INF
		for i in _steps(30.0):
			w.run_steps(1)
			lo = minf(lo, e.x)
			hi = maxf(hi, e.x)
		check(lo <= 50.0 + 5.0, "level %d: leftmost enemy centre %.1f (reference ≈ 50)" % [lvl, lo])
		check(hi >= 910.0 - 5.0, "level %d: rightmost enemy centre %.1f (reference ≈ 910)" % [lvl, hi])
	# The same limits hold for every "Gegner", children included (the reference gives ONE pair of limits).
	var c := GameWorld.new(7, 1, 0, 3, 5)
	c.auto_slots = false
	c.osc_amplitude = 0.0
	c.allow_enemy_fire = false
	c.start_combat()
	var k := c.add_enemy(1, 480.0, -1.0, LevelData.child_scale(7), true)
	var klo := INF
	var khi := -INF
	for i in _steps(30.0):
		c.run_steps(1)
		klo = minf(klo, k.x)
		khi = maxf(khi, k.x)
	check(klo <= 55.0 and khi >= 905.0, "level 7 child turns at %.1f / %.1f (reference ≈ 50 / 910)" % [klo, khi])
