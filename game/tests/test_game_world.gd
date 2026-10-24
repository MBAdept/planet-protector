extends TestBase
## Rules suite for GameWorld (docs/SPEC.md §1, §3–§10). Drives the pure simulation with sub-steps.

const STEP := LevelData.SIM_STEP


# --- Helpers -------------------------------------------------------------------------------------
## A world in combat with no automatic spawns, frozen enemy movement and no oscillation.
func _world(level: int, ship := 0, diff := 1, lives := 3, rng_seed := 7) -> GameWorld:
	var w := GameWorld.new(level, diff, ship, lives, rng_seed)
	w.auto_slots = false
	w.enemy_speed = 0.0
	w.osc_amplitude = 0.0
	w.allow_enemy_fire = false
	w.start_combat()
	w.events.clear()
	return w


## Same as _world() but with enemy fire enabled and an invincible player (fire-rule tests).
func _fire_world(level: int, rng_seed := 7) -> GameWorld:
	var w := _world(level, 0, 1, 3, rng_seed)
	w.allow_enemy_fire = true
	w.invincible = true
	return w


func _kill_all(w: GameWorld) -> void:
	var guard := 0
	while not w.enemies.is_empty() and guard < 100:
		w.apply_hit(w.enemies[0])
		guard += 1


## Steps until at least one enemy bullet exists (the bullets are then exactly at their spawn positions).
func _until_fire(w: GameWorld, max_steps := 5000) -> void:
	var n := 0
	while w.bullets.is_empty() and n < max_steps:
		w.run_steps(1)
		n += 1


## Fires one salvo from x and runs until all own projectiles are gone.
func _shoot(w: GameWorld, x: float, max_steps := 3000) -> void:
	w.player_x = x
	w.run_steps(1, 0.0, true)
	var n := 0
	while not w.shots.is_empty() and n < max_steps and not w.is_finished():
		w.run_steps(1, 0.0, false)
		n += 1


func _count(w: GameWorld, type: String) -> int:
	var n := 0
	for e in w.events:
		if e["type"] == type:
			n += 1
	return n


func _events(w: GameWorld, type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in w.events:
		if e["type"] == type:
			out.append(e)
	return out


func _steps(seconds: float) -> int:
	return int(round(seconds / STEP))


# --- Intro, player -------------------------------------------------------------------------------
func test_intro_is_1_8_real_seconds_nothing_moves_no_time() -> void:
	var w := GameWorld.new(1, 2, 0, 3, 1)   # HARD: game time runs faster, intro is still real time
	w.update(1.0, 1.0, true)
	check_eq(w.state, GameWorld.State.INTRO, "intro after 1.0 s")
	check_eq(w.player_x, 480.0, "player does not move during intro")
	check(w.enemies.is_empty() and w.shots.is_empty(), "nothing spawned/fired during intro")
	w.update(0.79, 1.0, true)
	check_eq(w.state, GameWorld.State.INTRO, "still intro at 1.79 s")
	check_near(w.active_time, 0.0, 1e-9, "no time during intro")
	w.update(0.51, 0.0, false)
	check_eq(w.state, GameWorld.State.PLAYING, "combat after 1.8 s")
	check_eq(w.enemies.size(), 3, "all slots filled at combat start")
	check_near(w.active_time, 0.5, 1.0 / 240.0, "leftover real time is active")


func test_player_speed_limits_and_difficulty() -> void:
	var w := _world(1)
	w.update(1.0, 1.0, false)
	check_near(w.player_x, 830.0, 0.01, "350 px/s")
	w.update(1.0, 1.0, false)
	check_eq(w.player_x, 930.0, "clamped right")
	w.update(5.0, -1.0, false)
	check_eq(w.player_x, 30.0, "clamped left")
	var h := _world(1, 0, 2)   # HARD 1.2
	h.update(1.0, -1.0, false)
	check_near(h.player_x, 480.0 - 420.0, 0.01, "game time ×1.2")
	check_near(h.active_time, 1.0, 1e-6, "play time stays real seconds")


func test_slots_filled_at_combat_start() -> void:
	for lvl in [1, 3, 5, 13, 16, 17]:
		var w := GameWorld.new(lvl, 1, 0, 3, 3)
		w.start_combat()
		var lanes: Array[int] = []
		for e in w.enemies:
			lanes.append(e.lane)
		lanes.sort()
		check_eq(lanes, LevelData.slot_lanes(lvl), "lanes of level %d" % lvl)
		check_eq(w.spawned, LevelData.slot_lanes(lvl).size())
		for e in w.enemies:
			check(e.x >= GameWorld.min_x(1.0) and e.x <= GameWorld.max_x(1.0), "spawn within limits")
			check_eq(e.materialize(), 0.0, "materialize starts")


# --- Own salvos (SPEC §4) ------------------------------------------------------------------------
func test_salvo_blocking_and_hold_to_refire() -> void:
	var w := _world(1, 0)   # Interceptor 500 px/s
	w.run_steps(1, 0.0, true)
	check_eq(w.shots.size(), 1)
	check_eq(w.shots[0].y, 639.0, "salvo starts at y=639")
	check_eq(w.shots[0].x, 480.0)
	# The shot needs (639+40)/500 s; while it is on the field no new salvo appears although fire is held.
	w.run_steps(325, 0.0, true)
	check_eq(w.salvos_fired, 1, "blocked while previous salvo is on the field")
	check_eq(w.shots.size(), 1)
	w.run_steps(1, 0.0, true)
	check_eq(w.salvos_fired, 2, "auto refire as soon as the previous salvo is gone")
	check_eq(w.shots.size(), 1)
	check_eq(w.shots[0].y, 639.0)
	# Releasing fire: no new salvo.
	w.run_steps(400, 0.0, false)
	check_eq(w.salvos_fired, 2)
	check(w.shots.is_empty(), "removed above y=-40")


func test_shot_removed_only_above_minus_40() -> void:
	var w := _world(1, 0)
	w.run_steps(1, 0.0, true)
	var s: GameWorld.Shot = w.shots[0]
	while not w.shots.is_empty():
		var before := s.y
		w.run_steps(1)
		if w.shots.is_empty():
			check(before - 500.0 * STEP < -40.0, "removed when center y < -40")
		else:
			check(s.y >= -40.0, "still alive above -40")


func test_double_salvo_independent_projectiles() -> void:
	var w := _world(1, 2)   # Double Dart ±12
	var e := w.add_enemy(2, 428.0)   # only the left bullet (x=468) overlaps (|dx|=40 < 49)
	w.run_steps(1, 0.0, true)
	check_eq(w.shots.size(), 2)
	check_eq(w.shots[0].x, 468.0)
	check_eq(w.shots[1].x, 492.0)
	check_eq(_count(w, "shot_fired"), 1, "one salvo")
	var n := 0
	while w.enemies.has(e) and n < 500:
		w.run_steps(1, 0.0, true)
		n += 1
	check(not w.enemies.has(e), "left bullet destroyed the enemy")
	check_eq(w.shots.size(), 1, "the hitting bullet disappeared on its own")
	check_eq(w.shots[0].x, 492.0, "the other bullet flies on")
	check_eq(w.salvos_fired, 1, "no new salvo while the second bullet flies")
	while w.salvos_fired == 1 and n < 2000:
		w.run_steps(1, 0.0, true)
		n += 1
	check_eq(w.salvos_fired, 2, "refire once the whole salvo is gone")


func test_guided_follow_and_unguided() -> void:
	var w := _world(1, 1)   # Fighter, guided
	w.run_steps(1, 0.0, true)
	w.run_steps(60, 1.0, false)
	check_near(w.shots[0].x, w.player_x, 1e-6, "guided x = ship x")
	w.run_steps(30, -1.0, false)
	check_near(w.shots[0].x, w.player_x, 1e-6, "guided x follows back")
	var d := _world(1, 3)   # Double Hunter, guided ±12
	d.run_steps(1, 0.0, true)
	d.run_steps(50, -1.0, false)
	check_near(d.shots[0].x, d.player_x - 12.0, 1e-6)
	check_near(d.shots[1].x, d.player_x + 12.0, 1e-6)
	var u := _world(1, 0)   # unguided
	u.run_steps(1, 0.0, true)
	u.run_steps(60, 1.0, false)
	check_eq(u.shots[0].x, 480.0, "unguided keeps its x")
	var h := _world(1, 5)   # Hunter: ONE logical projectile
	h.run_steps(1, 0.0, true)
	check_eq(h.shots.size(), 1, "hunter salvo = one projectile")
	check(h.shots[0].piercing and h.shots[0].guided)


func test_non_piercing_hits_lowest_overlapping_enemy() -> void:
	var w := _world(1, 0)
	w.osc_amplitude = 22.0
	var high := w.add_enemy(2, 470.0)
	var low := w.add_enemy(2, 490.0)
	high.osc_phase = 0.0
	low.osc_phase = 0.3       # ≈ 6.5 px lower
	var s := GameWorld.Shot.new()
	s.x = 480.0
	s.y = 425.0
	s.speed = 0.0
	w.shots.append(s)
	w.run_steps(1)
	check(w.enemies.has(high), "upper enemy survives")
	check(not w.enemies.has(low), "lowest overlapping enemy is hit")
	check(w.shots.is_empty(), "non-piercing shot consumed")


func test_piercing_hits_each_enemy_once() -> void:
	var w := _world(19, 4)   # rolling level, Blaster (piercing)
	var a := w.add_enemy(2, 480.0)
	var b := w.add_enemy(1, 480.0)
	_shoot(w, 480.0)
	check_eq(a.hit_steps.size(), 1, "lower enemy touched once although overlapping for many steps")
	check_eq(b.hit_steps.size(), 1, "upper enemy touched once")
	check_eq(_count(w, "enemy_hit_nonlethal"), 2)
	check(w.enemies.has(a) and w.enemies.has(b))
	# a second projectile may hit again
	_shoot(w, 480.0)
	check_eq(a.hit_steps.size(), 2)


func test_split_children_not_hit_by_splitting_projectile() -> void:
	for ship in [4, 5]:   # Blaster and Hunter pierce
		var w := _world(8, ship)
		var e := w.add_enemy(2, 480.0)
		_shoot(w, 470.0)   # left child (x=456) would overlap this projectile (|dx| 14 < 22)
		check(not w.enemies.has(e), "parent split")
		check_eq(w.enemies.size(), 2, "both children alive (ship %d)" % ship)
		check_eq(w.score_delta, 0, "split gives no points")
		var sp := _events(w, "enemy_split")
		check_eq(sp.size(), 1)
		check_eq((sp[0]["children"] as Array).size(), 2)
		check_near(w.enemies[0].x, 456.0, 1e-6, "left child at x-24")
		check_near(w.enemies[1].x, 504.0, 1e-6, "right child at x+24")
		check_eq(w.enemies[0].dir, -1.0, "left child moves left")
		check_eq(w.enemies[1].dir, 1.0, "right child moves right")
		check_near(w.enemies[0].scale, 0.45, 1e-9)


func test_split_child_scale_level7_and_child_points() -> void:
	var w := _world(7, 0)
	var e := w.add_enemy(1, 480.0)
	_shoot(w, 480.0)
	check_eq(w.enemies.size(), 2)
	check_near(w.enemies[0].scale, 0.40, 1e-9, "level 7 children are 40 %")
	check(w.shots.is_empty(), "non-piercing shot consumed by the split")
	check(not w.enemies.has(e))
	var left := w.enemies[0]
	var right := w.enemies[1]
	_shoot(w, left.x)
	check(not w.enemies.has(left), "one hit destroys a child")
	check_eq(w.score_delta, 25)
	_shoot(w, right.x)
	check_eq(w.score_delta, 50, "level 7: fully eliminated pair = 50 points")


func test_split_children_within_limits_at_the_edges() -> void:
	for lvl in [7, 8]:
		var w := _world(lvl, 0)
		w.add_enemy(2, 50.0)
		_shoot(w, 50.0)
		check_near(w.enemies[0].x, 50.0, 1e-6, "left child clamped to the limit x = 50")
		check_near(w.enemies[1].x, 74.0, 1e-6, "right child at x + 24")
		var r := _world(lvl, 0)
		r.add_enemy(2, 910.0)
		_shoot(r, 910.0)
		check_near(r.enemies[0].x, 886.0, 1e-6, "left child at x - 24")
		check_near(r.enemies[1].x, 910.0, 1e-6, "right child clamped to the limit x = 910")
		for e in w.enemies + r.enemies:
			check(e.x >= GameWorld.min_x(e.scale) and e.x <= GameWorld.max_x(e.scale), "children inside [50, 910]")


# --- Slots / refill (SPEC §5) --------------------------------------------------------------------
func test_slot_refill_after_two_seconds() -> void:
	var w := GameWorld.new(1, 1, 0, 3, 11)
	w.enemy_speed = 0.0
	w.osc_amplitude = 0.0
	w.allow_enemy_fire = false
	w.start_combat()
	check_eq(w.enemies.size(), 3)
	var low: GameWorld.Enemy = w.ranked_enemies()[0]
	w.player_x = low.x
	w.run_steps(1, 0.0, true)
	var n := 0
	while w.enemies.has(low) and n < 1000:
		w.run_steps(1)
		n += 1
	check_eq(w.enemies.size(), 2)
	check_near(w.slots[low.slot].refill, 2.0, 1e-9, "refill pending")
	w.run_steps(479)
	check_eq(w.enemies.size(), 2, "not yet after 479 steps")
	check_eq(w.spawned, 3)
	w.run_steps(1)
	check_eq(w.enemies.size(), 3, "refilled after exactly 2.0 game s")
	check_eq(w.spawned, 4)
	check_eq(w.enemies[w.enemies.size() - 1].lane, 2, "same lane as the slot")


func test_refill_stops_at_total() -> void:
	var w := GameWorld.new(1, 1, 0, 3, 5)
	w.allow_enemy_fire = false
	w.start_combat()
	var guard := 0
	while w.state == GameWorld.State.PLAYING and guard < 3000:
		guard += 1
		var e: GameWorld.Enemy = w.ranked_enemies()[0] if not w.enemies.is_empty() else null
		if e == null:
			w.run_steps(10)
			continue
		w.apply_hit(e)
		w.run_steps(1)
	check_eq(w.spawned, 10, "exactly the total of originals spawned")
	check_eq(w.destroyed, 10)
	check(w.goal_met)


func test_split_slot_free_only_after_both_children_and_totals() -> void:
	var w := GameWorld.new(7, 1, 0, 3, 9)
	w.enemy_speed = 0.0
	w.osc_amplitude = 0.0
	w.allow_enemy_fire = false
	w.start_combat()
	check_eq(w.spawned, 3)
	var e: GameWorld.Enemy = w.enemies[0]
	var slot := e.slot
	w.apply_hit(e)
	check_eq(w.enemies.size(), 4, "parent replaced by two children")
	check_eq(w.spawned, 3, "children never count towards the total")
	check_eq(w.slots[slot].alive, 2)
	var kids: Array[GameWorld.Enemy] = []
	for k in w.enemies:
		if k.parent_id == e.id:
			kids.append(k)
	check_eq(kids.size(), 2)
	w.apply_hit(kids[0])
	check_eq(w.slots[slot].refill, -1.0, "slot not free after one child")
	w.run_steps(_steps(3.0))
	check_eq(w.spawned, 3, "no refill while a child lives")
	w.apply_hit(kids[1])
	check_near(w.slots[slot].refill, 2.0, 1e-9, "slot free after both children")
	w.run_steps(480)
	check_eq(w.spawned, 4)


# --- Player hit / respawn / game over (SPEC §3) -------------------------------------------------
func test_multiple_bullets_in_one_step_cost_one_life() -> void:
	var w := _world(1)
	w.run_steps(1, 0.0, true)   # an own salvo in flight
	w.add_bullet(480.0, 655.0, 0.0, 0.0)
	w.add_bullet(470.0, 660.0, 0.0, 0.0)
	w.add_bullet(490.0, 650.0, 0.0, 0.0)
	w.run_steps(1)
	check_eq(w.lives, 2, "exactly one life lost")
	check_eq(_count(w, "player_hit"), 1)
	check(w.bullets.is_empty(), "all enemy bullets removed")
	check(w.shots.is_empty(), "all own projectiles removed")
	check_eq(w.state, GameWorld.State.RESPAWN)
	check(not w.flawless)


func test_player_hitbox() -> void:
	var cases := [[20.9, 0.0, true], [21.0, 0.0, false], [0.0, 14.9, true], [0.0, 15.0, false], [-20.9, -14.9, true]]
	for c in cases:
		var w := _world(1)
		w.add_bullet(480.0 + float(c[0]), 659.0 + float(c[1]), 0.0, 0.0)
		w.run_steps(1)
		check_eq(w.lives < 3, bool(c[2]), "player hit dx=%s dy=%s" % [c[0], c[1]])


func test_respawn_pauses_combat_and_resets_timers() -> void:
	var w := GameWorld.new(3, 1, 0, 3, 21)   # RANK2 level, F = 1.2
	w.start_combat()
	w.run_steps(_steps(1.0), 1.0, false)
	var e: GameWorld.Enemy = w.enemies[0]
	var ex := e.x
	var t0: Array[float] = w.rank_timers.duplicate()
	# Free a slot so that a refill timer is pending.
	var victim: GameWorld.Enemy = w.enemies[1]
	w.apply_hit(victim)
	var victim_slot := victim.slot
	var refill0 := w.slots[victim_slot].refill
	var steps0 := w.combat_steps
	w.add_bullet(w.player_x, 659.0, 0.0, 0.0)
	w.run_steps(1)
	check_eq(w.state, GameWorld.State.RESPAWN)
	w.run_steps(_steps(1.3) - 2, 1.0, true)
	check_eq(w.state, GameWorld.State.RESPAWN, "still respawning before 1.3 s")
	check_near(e.x, ex + e.dir * 0.0, 2.0, "enemy frozen (moved at most the hit step)")
	var ex2 := e.x
	var ey2 := e.y
	w.run_steps(1, 1.0, true)
	check_eq(e.x, ex2, "no movement during respawn")
	check_eq(e.y, ey2, "no oscillation during respawn")
	check_eq(w.combat_steps, steps0 + 1, "combat clock paused")
	check_near(w.slots[victim_slot].refill, refill0 - STEP, 1e-9, "refill timer paused")
	check(w.bullets.is_empty() and w.shots.is_empty(), "no fire during respawn")
	check(w.flap_phase(e) >= 0.0)
	w.run_steps(1, 0.0, false)
	check_eq(w.state, GameWorld.State.PLAYING, "respawn after 1.3 game s")
	check_eq(w.player_x, 480.0, "respawn at x=480")
	check_eq(_count(w, "player_respawn"), 1)
	check_near(w.rank_timers[0], 2.0 / 1.2, 1e-9, "rank 1 timer reset")
	check_near(w.rank_timers[1], 2.5 / 1.2, 1e-9, "rank 2 timer reset")
	check(t0.size() == 2)


func test_respawn_resets_per_figure_timers() -> void:
	var w := GameWorld.new(11, 1, 0, 3, 4)
	w.allow_enemy_fire = false
	w.start_combat()
	w.run_steps(_steps(1.7))
	w.add_bullet(w.player_x, 659.0, 0.0, 0.0)
	w.run_steps(1)
	w.run_steps(_steps(1.3))
	check_eq(w.state, GameWorld.State.PLAYING)
	for e in w.enemies:
		check(e.fire_timer >= 2.0 / 1.75 - 1e-9 and e.fire_timer <= 2.8 / 1.75 + 1e-9, "per-figure reset 2.0/F + rand(0,0.8)/F")


func test_respawn_time_counts_no_active_time() -> void:
	var w := _world(1)
	w.add_enemy(0, 100.0)
	w.add_bullet(480.0, 659.0, 0.0, 0.0)
	w.run_steps(1)
	var t := w.active_time
	w.run_steps(_steps(1.3) - 1)
	check_near(w.active_time, t, 1e-12, "respawn does not count")
	w.run_steps(10)
	check(w.active_time > t)


func test_game_over_after_player_explosion() -> void:
	var w := _world(1, 0, 3, 1)   # EXPERT, 1 life
	w.add_enemy(0, 100.0)
	w.add_bullet(480.0, 659.0, 0.0, 0.0)
	w.run_steps(1)
	check_eq(w.lives, 0)
	check_eq(w.state, GameWorld.State.GAME_OVER_WAIT)
	w.run_steps(_steps(1.3) - 2)
	check_eq(w.state, GameWorld.State.GAME_OVER_WAIT, "waits for the player explosion")
	w.run_steps(3)
	check_eq(w.state, GameWorld.State.GAME_OVER)
	check_eq(_count(w, "game_over"), 1)
	w.update(1.0, 0.0, true)
	check_eq(_count(w, "game_over"), 1, "game over exactly once")


func test_invincible_ignores_bullets() -> void:
	var w := _world(1)
	w.invincible = true
	w.add_bullet(480.0, 659.0, 0.0, 0.0)
	w.run_steps(1)
	check_eq(w.lives, 3)
	check_eq(w.state, GameWorld.State.PLAYING)


# --- Level end, active time, flawless (SPEC §9) --------------------------------------------------
func test_final_phase_time_and_clearing() -> void:
	var w := _world(1, 0, 2)   # HARD
	w.spawned = w.total
	var e := w.add_enemy(2, 480.0)
	var b := w.add_bullet(100.0, 500.0)   # still flying after the kill, gone before the explosion ends
	var steps_before := 0
	w.player_x = 480.0
	w.run_steps(1, 0.0, true)
	while w.enemies.has(e):
		w.run_steps(1)
	check(w.goal_met, "goal met")
	check_eq(_count(w, "level_goal_met"), 1)
	check_eq(w.state, GameWorld.State.PLAYING, "final phase while bullets fly")
	var t_goal := w.active_time
	while w.bullets.has(b):
		w.run_steps(1)
		steps_before += 1
	check_eq(w.state, GameWorld.State.CLEARING, "clearing once no bullet is left")
	check_near(w.active_time - t_goal, float(steps_before) * STEP / 1.2, 1e-9, "final phase counts (real seconds)")
	var t_clear := w.active_time
	w.run_steps(_steps(0.3))
	check_near(w.active_time, t_clear, 1e-12, "explosion waiting time does not count")
	check_eq(w.state, GameWorld.State.CLEARING, "waits for the explosion")
	w.run_steps(_steps(0.5))
	check_eq(w.state, GameWorld.State.COMPLETE, "complete after explosions")
	check_eq(_count(w, "level_complete"), 1)
	check_eq(w.result["completion_bonus"], 100)
	check_eq(w.score_delta, 10 + 100)


func test_flawless_extra_life_exactly_once() -> void:
	for lvl in [10, 15, 16, 17, 18]:
		var w := _world(lvl)
		w.spawned = w.total
		w.add_enemy(2, 480.0)
		_kill_all(w)
		w.run_steps(_steps(1.0))
		check_eq(w.state, GameWorld.State.COMPLETE, "level %d complete" % lvl)
		check_eq(w.lives, 4, "flawless extra life in level %d" % lvl)
		check_eq(_count(w, "extra_life"), 1)
		w.run_steps(500)
		w.update(1.0, 0.0, true)
		check_eq(w.lives, 4, "only once")
		check_eq(_count(w, "level_complete"), 1, "completion only once")
		check_eq(w.result["extra_life"], true)
		check_eq(w.result["flawless"], true)
	for lvl in [1, 9, 11, 12, 14, 19, 20]:
		var w := _world(lvl)
		w.spawned = w.total
		w.add_enemy(2, 480.0)
		_kill_all(w)
		w.run_steps(_steps(1.0))
		check_eq(w.state, GameWorld.State.COMPLETE, "level %d complete" % lvl)
		check_eq(w.lives, 3, "no flawless life in level %d" % lvl)
		check_eq(w.result["extra_life"], false)


func test_life_lost_in_final_phase_prevents_flawless() -> void:
	var w := _world(10)
	w.spawned = w.total
	w.add_enemy(0, 100.0)
	w.add_bullet(480.0, 600.0)   # will hit the player after the last kill
	_kill_all(w)
	w.run_steps(1)
	check(w.goal_met)
	check_eq(w.state, GameWorld.State.PLAYING, "final phase")
	w.run_steps(_steps(0.5))
	check_eq(w.lives, 2)
	w.run_steps(_steps(2.0))
	check_eq(w.state, GameWorld.State.COMPLETE)
	check_eq(w.result["flawless"], false)
	check_eq(w.result["extra_life"], false)
	check_eq(w.lives, 2, "no extra life")


func test_lost_life_earlier_prevents_flawless() -> void:
	var w := _world(15)
	w.add_bullet(480.0, 659.0, 0.0, 0.0)
	w.run_steps(1)
	w.run_steps(_steps(1.4))
	w.spawned = w.total
	w.add_enemy(1, 300.0)
	_kill_all(w)
	w.run_steps(_steps(1.0))
	check_eq(w.state, GameWorld.State.COMPLETE)
	check_eq(w.lives, 2)
	check_eq(w.result["extra_life"], false)


# --- Bonus level 13 (SPEC §10) -------------------------------------------------------------------
func test_bonus_attempts_double_salvo_costs_one() -> void:
	var w := _world(13, 2)   # Double Dart
	check_eq(w.attempts, 100)
	w.add_enemy(0, 100.0)
	_shoot(w, 700.0)
	check_eq(w.attempts, 99, "a double salvo costs ONE attempt")
	check(not w.allow_enemy_fire or w.rank_timers.is_empty(), "no enemy fire timers")


func test_bonus_no_enemy_fire_and_no_kill_score() -> void:
	var w := GameWorld.new(13, 1, 0, 3, 2)
	w.start_combat()
	w.run_steps(_steps(20.0))
	check(w.bullets.is_empty(), "no enemy bullets at all")
	check_eq(_count(w, "enemy_fire"), 0)
	var e: GameWorld.Enemy = w.enemies[0]
	w.apply_hit(e)
	check_eq(w.score_delta, 0, "kills give no score")


func test_bonus_ends_when_attempts_used_and_last_salvo_gone() -> void:
	var w := _world(13, 0, 1)
	w.attempts = 1
	w.add_enemy(0, 100.0)
	w.player_x = 700.0
	w.run_steps(1, 0.0, true)
	check_eq(w.attempts, 0)
	var t0 := w.active_time
	var n := 0
	while not w.shots.is_empty():
		w.run_steps(1, 0.0, true)
		n += 1
		if not w.shots.is_empty():
			check_eq(w.state, GameWorld.State.PLAYING, "flight time of the last shot counts")
	check_eq(w.state, GameWorld.State.COMPLETE, "ends when the last salvo is gone (no explosions pending)")
	check_near(w.active_time - t0, float(n) * STEP, 1e-9, "time counted until the shot disappeared")
	check_eq(w.salvos_fired, 1, "no salvo without attempts")
	check_eq(w.bonus_result["remaining"], 0)
	check_eq(w.bonus_result["bonus"], 0)


func test_bonus_ends_at_20_kills_bonus_and_extra_life() -> void:
	for c in [[15, 0, 6000, false], [16, 0, 6400, true], [30, 2, 9000, true], [20, 4, 6000, false], [31, 5, 6200, true]]:
		var w := _world(13, int(c[1]))
		w.destroyed = 19
		w.spawned = 20
		w.attempts = int(c[0]) + 1
		var e := w.add_enemy(1, 480.0)
		_shoot(w, 480.0)
		check(not w.enemies.has(e))
		check(w.goal_met, "20 kills end the bonus level")
		check_eq(w.attempts, int(c[0]))
		var t := w.active_time
		w.run_steps(_steps(1.0))
		check_near(w.active_time, t, 1e-12, "no time after the goal")
		check_eq(w.state, GameWorld.State.COMPLETE)
		check_eq(w.bonus_result["bonus"], int(c[2]), "bonus = remaining × factor")
		check_eq(w.bonus_result["factor"], int(ShipData.ship(int(c[1]))["bonus_factor"]))
		check_eq(w.bonus_result["extra_life"], bool(c[3]), "extra life only if > 6000")
		check_eq(w.lives, 4 if bool(c[3]) else 3)
		check_eq(w.score_delta, int(c[2]))
		check_eq(w.result["completion_bonus"], int(c[2]))


func test_bonus_no_fire_after_goal() -> void:
	var w := _world(13, 0)
	w.destroyed = 19
	w.spawned = 20
	var e := w.add_enemy(1, 480.0)
	w.apply_hit(e)
	w.run_steps(1)
	var a := w.attempts
	w.run_steps(100, 0.0, true)
	check_eq(w.attempts, a, "no attempts consumed after the goal")


# --- Colour lock (SPEC §8, levels 14–16) ---------------------------------------------------------
func test_color_lock_rules() -> void:
	var w := _world(14, 0)
	var a := w.add_enemy(2, 480.0)
	var b := w.add_enemy(0, 150.0)
	check_eq(a.stage, LevelData.Stage.VIOLET, "every enemy starts violet")
	_shoot(w, 480.0)
	check_eq(a.stage, LevelData.Stage.YELLOW, "violet → yellow")
	w.events.clear()
	_shoot(w, 480.0)
	check_eq(a.stage, LevelData.Stage.YELLOW, "locked while a violet enemy lives")
	check_eq(_count(w, "locked_hit"), 1)
	check_eq(w.shots.size(), 0, "non-piercing shot consumed by a locked hit")
	_shoot(w, 150.0)
	check_eq(b.stage, LevelData.Stage.YELLOW)
	_shoot(w, 480.0)
	check_eq(a.stage, LevelData.Stage.GREEN, "yellow → green once no violet is alive")
	w.events.clear()
	_shoot(w, 480.0)
	check(w.enemies.has(a), "green locked while not all are green")
	check_eq(_count(w, "locked_hit"), 1)
	check_eq(w.score_delta, 0, "locked/stage hits give no points")
	# New violet enemy re-establishes the lock.
	_shoot(w, 150.0)
	check_eq(b.stage, LevelData.Stage.GREEN)
	var c := w.add_enemy(1, 800.0)
	w.events.clear()
	_shoot(w, 480.0)
	check(w.enemies.has(a), "re-locked by the new violet enemy")
	check_eq(_count(w, "locked_hit"), 1)
	_shoot(w, 800.0)
	check_eq(c.stage, LevelData.Stage.YELLOW)
	_shoot(w, 800.0)
	check_eq(c.stage, LevelData.Stage.GREEN)
	_shoot(w, 480.0)
	check(not w.enemies.has(a), "destroyed once all are green")
	check_eq(w.score_delta, 75, "points only on destruction")
	_shoot(w, 150.0)
	_shoot(w, 800.0)
	check(w.enemies.is_empty())
	check_eq(w.score_delta, 225)


func test_color_lock_piercing_touches_once() -> void:
	var w := _world(15, 4)   # Blaster
	var lo := w.add_enemy(2, 480.0)
	var hi := w.add_enemy(1, 480.0)
	var far := w.add_enemy(0, 150.0)
	_shoot(w, 480.0)
	check_eq(lo.stage, LevelData.Stage.YELLOW, "one stage per projectile")
	check_eq(hi.stage, LevelData.Stage.YELLOW)
	w.events.clear()
	w.player_x = 480.0
	w.run_steps(1, 0.0, true)
	var locked_seen := false
	while not w.shots.is_empty():
		w.run_steps(1)
		if _count(w, "locked_hit") > 0 and not w.shots.is_empty():
			locked_seen = true
	check(locked_seen, "piercing shot flies on after a locked hit")
	check_eq(_count(w, "locked_hit"), 2, "each enemy touched only once per projectile")
	check_eq(far.stage, LevelData.Stage.VIOLET)


# --- Rolling window (SPEC §8, levels 19–20) ------------------------------------------------------
func test_rolling_window_examples() -> void:
	var w := _world(19, 0)
	w.allow_enemy_fire = false
	var a := w.add_enemy(0, 150.0)   # hits at 0, 8, 11 → survives
	var b := w.add_enemy(1, 480.0)   # hits at 8, 11, 12 → destroyed
	var c := w.add_enemy(2, 800.0)   # hits at 0, 5, 10.0 → destroyed (kept while now − t ≤ 10)
	w.apply_hit(a)
	w.apply_hit(c)
	check_near(a.flash, LevelData.HIT_FLASH_TIME, 1e-9, "orange flash on a non-lethal hit")
	w.run_steps(43)
	check(a.flash > 0.0, "flash still visible at 0.179 s")
	w.run_steps(1)
	check(a.flash <= 1e-6, "flash lasts 0.18 s")
	w.run_steps(_steps(5.0) - 44)
	w.apply_hit(c)
	w.run_steps(_steps(3.0))
	w.apply_hit(a)
	w.apply_hit(b)
	w.run_steps(_steps(2.0))
	w.apply_hit(c)
	check(not w.enemies.has(c), "0, 5, 10.0 → destroyed")
	w.run_steps(_steps(1.0))
	w.apply_hit(a)
	w.apply_hit(b)
	check(w.enemies.has(a), "0, 8, 11 → not destroyed")
	check_eq(a.hit_steps.size(), 2)
	w.run_steps(_steps(1.0))
	w.apply_hit(b)
	check(not w.enemies.has(b), "8, 11, 12 → destroyed")
	check_eq(w.score_delta, 300, "points only on destruction")
	check_eq(_count(w, "enemy_hit_nonlethal"), 7)


func test_rolling_window_runs_in_game_time() -> void:
	var w := _world(20, 0, 3)   # EXPERT ×1.44
	w.allow_enemy_fire = false
	var a := w.add_enemy(0, 150.0)
	w.apply_hit(a)
	w.update(10.0 / 1.44 + 0.01, 0.0, false)   # > 10 game seconds in fewer real seconds
	w.apply_hit(a)
	w.apply_hit(a)
	check(w.enemies.has(a), "first hit expired after 10 GAME seconds")


# --- Enemy movement (SPEC §5) --------------------------------------------------------------------
func test_enemy_limits_and_turning() -> void:
	var w := _world(1)
	w.enemy_speed = 62.0
	var e := w.add_enemy(0, 55.0, -1.0)
	w.run_steps(_steps(0.2))
	check_eq(e.dir, 1.0, "turned at the left limit")
	check(e.x >= 50.0 - 1e-9 and e.x < 60.0, "center turned at x = 50 (not further inside): %.2f" % e.x)
	var c := w.add_enemy(1, 52.0, -1.0, 0.45, true)
	w.run_steps(_steps(0.2))
	check(c.x >= 50.0 - 1e-9 and c.x < 65.0, "child center turned at x = 50 (same limit as originals): %.2f" % c.x)
	check_eq(c.dir, 1.0, "child turned at x = 50")
	var r := w.add_enemy(2, 905.0, 1.0)
	w.run_steps(_steps(0.2))
	check(r.x <= 910.0 + 1e-9 and r.x > 900.0, "center turned at x = 910 (not further inside): %.2f" % r.x)
	check_eq(r.dir, -1.0, "turned at the right limit")


func test_enemy_speed_tempo_and_oscillation() -> void:
	var w := GameWorld.new(8, 1, 0, 3, 1)
	w.auto_slots = false
	w.start_combat()
	var e := w.add_enemy(1, 480.0, 1.0)
	e.osc_phase = 0.0
	w.run_steps(240)
	check_near(e.x, 480.0 + 62.0 * 1.38, 1e-6, "62 px/s × tempo")
	check_near(e.y, 300.0 + 22.0 * sin(TAU * 0.55 * 1.0), 1e-6, "lane y + 22 sin(phase + 2π·0.55·t)")


func test_direction_changes_from_level_10() -> void:
	var w9 := _world(9)
	var e9 := w9.add_enemy(1, 480.0)
	check_eq(e9.dir_timer, INF, "no random direction changes before level 10")
	w9.run_steps(_steps(8.0))
	check_eq(e9.dir, 1.0)
	for lvl in [10, 14, 20]:
		var w := _world(lvl)
		w.allow_enemy_fire = false
		var e := w.add_enemy(1, 480.0)
		check(e.dir_timer >= 1.2 and e.dir_timer <= 3.2, "timer 1.2–3.2 s")
		var flips := 0
		var last := e.dir
		for i in _steps(16.0):
			w.run_steps(1)
			if e.dir != last:
				flips += 1
				last = e.dir
				check(e.dir_timer >= 1.2 - 1e-9 and e.dir_timer <= 3.2 + 1e-9, "re-armed 1.2–3.2 s")
		check(flips >= 5 and flips <= 14, "level %d: random flips (%d) in 16 s" % [lvl, flips])
	var w10 := _world(10)
	w10.allow_enemy_fire = false
	var p := w10.add_enemy(2, 480.0)
	w10.apply_hit(p)
	for k in w10.enemies:
		check(k.dir_timer >= 1.2 and k.dir_timer <= 3.2, "children get their own timers")


func test_scaled_hit_boxes() -> void:
	var cases := [[1.0, 48.9, true], [1.0, 49.1, false], [0.45, 22.0, true], [0.45, 22.1, false],
		[0.40, 19.5, true], [0.40, 19.7, false]]
	for c in cases:
		var w := _world(8)
		var e := w.add_enemy(1, 480.0 + float(c[1]), 1.0, float(c[0]), float(c[0]) < 1.0)
		_shoot(w, 480.0)
		check_eq(not w.enemies.has(e) or w.enemies.size() == 2, bool(c[2]),
			"scale %s dx %s" % [c[0], c[1]])
	# |dy| < 21·s: a stationary shot just above/below a child
	for c in [[9.4, true], [9.5, false]]:
		var w := _world(8)
		var e := w.add_enemy(1, 480.0, 1.0, 0.45, true)
		var s := GameWorld.Shot.new()
		s.x = 480.0
		s.y = 300.0 + float(c[0])
		w.shots.append(s)
		w.run_steps(1)
		check_eq(not w.enemies.has(e), bool(c[1]), "dy %s" % c[0])


func test_materializing_enemy_is_hittable() -> void:
	var w := GameWorld.new(1, 1, 0, 3, 8)
	w.enemy_speed = 0.0
	w.osc_amplitude = 0.0
	w.start_combat()
	var e: GameWorld.Enemy = w.ranked_enemies()[0]
	check_eq(e.materialize(), 0.0)
	var s := GameWorld.Shot.new()
	s.x = e.x
	s.y = e.y
	w.shots.append(s)
	w.run_steps(1)
	check(not w.enemies.has(e), "hittable while materializing")
	var w2 := GameWorld.new(1, 1, 0, 3, 8)
	w2.start_combat()
	w2.run_steps(_steps(0.45))
	check_near(w2.enemies[0].materialize(), 1.0, 1e-6, "materialize takes 0.45 s")


# --- Enemy fire (SPEC §7) ------------------------------------------------------------------------
func test_rank1_only_lowest_fires_with_initial_timer() -> void:
	var w := _fire_world(1)
	var top := w.add_enemy(0, 200.0)
	var low := w.add_enemy(2, 700.0)
	w.run_steps(_steps(2.0) - 1)
	check_eq(_count(w, "enemy_fire"), 0, "nothing before 2.0/F")
	w.run_steps(1)
	var f := _events(w, "enemy_fire")
	check_eq(f.size(), 1, "first salvo at 2.0/F")
	check_eq(f[0]["id"], low.id, "only the lowest figure fires")
	check_eq(w.bullets.size(), 1, "level 1: one bullet")
	check_eq(w.bullets[0].x, 700.0, "central")
	check_near(w.bullets[0].y, 420.0 + 18.0, 1e-9, "spawn at figure y + 18·s")
	check_eq(Vector2(w.bullets[0].vx, w.bullets[0].vy), Vector2(0, 220), "straight down")
	check(w.rank_timers[0] >= 1.8 - 1e-9 and w.rank_timers[0] <= 2.8 + 1e-9, "then rand(1.8, 2.8)/F")
	w.run_steps(_steps(30.0))
	check(_count(w, "enemy_fire") >= 10, "keeps firing")
	for ev in _events(w, "enemy_fire"):
		check_eq(ev["id"], low.id, "the upper figure never fires")
	check(top.armed)


func test_rank_follows_current_y() -> void:
	var w := _fire_world(2)
	w.osc_amplitude = 22.0
	var a := w.add_enemy(2, 200.0)
	var b := w.add_enemy(2, 700.0)
	a.osc_phase = 0.0
	b.osc_phase = PI
	# At t = 2.0/1.2 s: sin(2π·0.55·t) decides which of the two is lower right now.
	var t := 2.0 / 1.2
	var ya := 420.0 + 22.0 * sin(TAU * 0.55 * t)
	var yb := 420.0 + 22.0 * sin(PI + TAU * 0.55 * t)
	_until_fire(w)
	check_eq(_events(w, "enemy_fire")[0]["id"], a.id if ya > yb else b.id, "currently lowest figure fires")


func test_rank2_second_lowest_fires_at_2_5_over_f() -> void:
	var w := _fire_world(3)   # F = 1.2, RANK2
	var a := w.add_enemy(0, 200.0)
	var b := w.add_enemy(1, 500.0)
	var c := w.add_enemy(2, 800.0)
	w.run_steps(_steps(2.0 / 1.2))
	var f := _events(w, "enemy_fire")
	check_eq(f.size(), 1)
	check_eq(f[0]["id"], c.id, "rank 1 = lowest")
	w.run_steps(_steps(2.5 / 1.2) - _steps(2.0 / 1.2) - 1)
	check_eq(_events(w, "enemy_fire").size(), 1, "rank 2 not before 2.5/F")
	w.run_steps(1)
	f = _events(w, "enemy_fire")
	check_eq(f.size(), 2)
	check_eq(f[1]["id"], b.id, "rank 2 = second lowest")
	w.run_steps(_steps(40.0))
	for ev in _events(w, "enemy_fire"):
		check(ev["id"] != a.id, "third figure never fires")


func test_defenceless_figure_does_not_pass_its_right() -> void:
	# Level 8 (RANK2, ONE_ARMED): the lowest figure is a defenceless child.
	var w := _fire_world(8)   # F = 1.3
	var d := w.add_enemy(2, 300.0, 1.0, 0.45, true)
	d.armed = false
	var o1 := w.add_enemy(1, 600.0)
	var o2 := w.add_enemy(0, 800.0)
	w.run_steps(_steps(2.0 / 1.3) + 1)
	check_eq(_count(w, "enemy_fire"), 0, "rank-1 shot skipped, not passed to a higher figure")
	w.run_steps(_steps(2.5 / 1.3) - _steps(2.0 / 1.3))
	var f := _events(w, "enemy_fire")
	check_eq(f.size(), 1, "rank 2 fires normally")
	check_eq(f[0]["id"], o1.id)
	w.run_steps(_steps(60.0))
	for ev in _events(w, "enemy_fire"):
		check_eq(ev["id"], o1.id, "only the rank-2 holder ever fires")
	check(w.enemies.has(o2))
	# Level 9: a child on an upper lane is the lowest figure → its rank is skipped.
	var w9 := _fire_world(9)
	var up := w9.add_enemy(1, 300.0, 1.0, 0.45, true)
	check(not up.armed, "level 9: upper-lane child defenceless")
	w9.add_enemy(0, 700.0)
	w9.run_steps(_steps(2.0 / 1.35) + 1)
	check_eq(_count(w9, "enemy_fire"), 0, "no passing in level 9")
	# Level 10 (RANK1): a defenceless upper child that is the lowest figure blocks all fire.
	var w10 := _fire_world(10)
	var up10 := w10.add_enemy(1, 300.0, 1.0, 0.45, true)
	check(not up10.armed)
	w10.add_enemy(0, 700.0)
	w10.run_steps(_steps(20.0))
	check_eq(_count(w10, "enemy_fire"), 0, "level 10: only the overall lowest may fire")


func test_level10_only_lowest_and_columns() -> void:
	var w := _fire_world(10)   # F = 1.4, RANK1, columns
	var top := w.add_enemy(0, 300.0)
	var low := w.add_enemy(2, 600.0)
	w.player_x = 900.0
	w.run_steps(_steps(2.0 / 1.4) - 1)
	check(w.bullets.is_empty(), "not before 2.0/F")
	_until_fire(w)
	var f := _events(w, "enemy_fire")
	check_eq(f.size(), 1)
	check_eq(f[0]["id"], low.id)
	check_eq(w.bullets.size(), 8, "4 columns × 2")
	var offs := LevelData.salvo_offsets(4, 0.80, 1.0)
	var y0 := 420.0 + 18.0
	var xs := {}
	var ys := {}
	for b in w.bullets:
		xs[snappedf(b.x - 600.0, 0.001)] = true
		ys[snappedf(b.y, 0.001)] = true
		check_near(b.vx, 110.0, 1e-6, "5 o'clock toward the player")
	check_eq(xs.size(), 4, "four columns")
	for o in offs:
		check(xs.has(snappedf(o, 0.001)), "column at %f" % o)
	check_eq(ys.size(), 2, "two rows")
	check(ys.has(snappedf(y0, 0.001)) and ys.has(snappedf(y0 - 18.0, 0.001)), "second bullet 18 px above")
	check(w.enemies.has(top))
	# Children on the bottom lane: 2 columns × 2.
	var wc := _fire_world(10)
	var p := wc.add_enemy(2, 500.0)
	wc.apply_hit(p)
	check(wc.enemies[0].armed and wc.enemies[1].armed, "bottom-lane children armed")
	_until_fire(wc)
	check_eq(wc.bullets.size(), 4, "child: 2 columns × 2")
	var cx := {}
	var cy := {}
	for b in wc.bullets:
		cx[snappedf(b.x, 0.001)] = true
		cy[snappedf(b.y, 0.001)] = true
	check_eq(cx.size(), 2)
	check_eq(cy.size(), 2)
	var keys := cx.keys()
	check_near(absf(float(keys[0]) - float(keys[1])), 0.80 * 90.0 * 0.45 - 10.0, 1e-3, "child width scaled")
	# Upper children never fire.
	var wu := _fire_world(10)
	var q := wu.add_enemy(1, 500.0)
	wu.apply_hit(q)
	check(not wu.enemies[0].armed and not wu.enemies[1].armed, "upper children defenceless")


func test_child_arming_levels_7_8_one_armed_permanently() -> void:
	for lvl in [7, 8]:
		for s in 6:
			var w := _fire_world(lvl, 100 + s)
			var p := w.add_enemy(0, 480.0)
			w.apply_hit(p)
			var armed := 0
			var armed_kid: GameWorld.Enemy = null
			var other: GameWorld.Enemy = null
			for k in w.enemies:
				if k.armed:
					armed += 1
					armed_kid = k
				else:
					other = k
			check_eq(armed, 1, "exactly one child armed (level %d)" % lvl)
			w.apply_hit(armed_kid)
			check(not other.armed, "partner stays defenceless after the armed one died")
			w.run_steps(_steps(10.0))
			check_eq(_count(w, "enemy_fire"), 0, "defenceless survivor never fires")


func test_child_bullets_one_armed_two_bullets() -> void:
	var w := _fire_world(7)
	var p := w.add_enemy(2, 480.0)
	w.apply_hit(p)
	var armed: GameWorld.Enemy = w.enemies[0] if w.enemies[0].armed else w.enemies[1]
	var unarmed: GameWorld.Enemy = w.enemies[1] if armed == w.enemies[0] else w.enemies[0]
	unarmed.lane = 1   # make the armed child the lowest figure
	_until_fire(w)
	check_eq(_events(w, "enemy_fire")[0]["id"], armed.id)
	check_eq(w.bullets.size(), 2, "armed child fires 2 bullets")
	var span := absf(w.bullets[0].x - w.bullets[1].x)
	check_near(span, 0.55 * 90.0 * 0.40 - 10.0, 1e-6, "child salvo width = pct·90·scale")
	check_near(w.bullets[0].y, armed.y + 18.0 * 0.40, 1e-9, "spawn at y + 18·s")


func test_level9_children_bottom_lane_two_bullets() -> void:
	var w := _fire_world(9)
	var p := w.add_enemy(2, 480.0)
	w.apply_hit(p)
	check(w.enemies[0].armed and w.enemies[1].armed, "both bottom-lane children armed")
	_until_fire(w)
	check_eq(w.bullets.size(), 2)
	w.run_steps(_steps(2.5 / 1.35) - _steps(2.0 / 1.35) + 1)
	check_eq(_count(w, "enemy_fire"), 2, "rank 2 is held by the tied pair too (both armed) and fires")


func test_level11_12_bottom_lane_children_four_in_a_row() -> void:
	for lvl in [11, 12]:
		var f := float(LevelData.level(lvl)["fire"])
		var w := _fire_world(lvl)
		var p := w.add_enemy(2, 480.0)
		var u := w.add_enemy(1, 200.0)
		check(p.armed and not u.armed, "only the bottom lane may fire")
		w.apply_hit(p)
		w.apply_hit(u)
		for k in w.enemies:
			check_eq(k.armed, k.lane == 2, "child armed iff bottom lane")
			check(k.fire_timer >= 2.0 / f - 1e-9 and k.fire_timer <= 2.8 / f + 1e-9, "child timer starts at split")
		w.run_steps(_steps(2.8 / f) + 2)
		var evs := _events(w, "enemy_fire")
		check_eq(evs.size(), 2, "both bottom children fired once")
		var by_owner := {}
		for b in w.bullets:
			if not by_owner.has(b.owner_id):
				by_owner[b.owner_id] = []
			by_owner[b.owner_id].append(b)
		for ev in evs:
			check_eq(ev["count"], 4)
			var group: Array = by_owner.get(ev["id"], [])
			check_eq(group.size(), 4, "4 bullets per child")
			var xs: Array[float] = []
			for b in group:
				check_eq(b.y, group[0].y, "one row")
				xs.append(b.x)
			xs.sort()
			check_near(xs[3] - xs[0] + 10.0, 0.80 * 90.0 * 0.45, 1e-6, "child width 80 % × 0.45")


func test_per_figure_lane_permissions() -> void:
	var expect := {11: [false, false, true], 14: [false, false, true], 15: [false, false, true],
		17: [false, false, true], 18: [false, true, true], 19: [false, true, true], 20: [true, true, true]}
	for lvl in expect:
		var w := _fire_world(lvl)
		var es: Array[GameWorld.Enemy] = [w.add_enemy(0, 150.0), w.add_enemy(1, 480.0), w.add_enemy(2, 800.0)]
		var f := float(LevelData.level(lvl)["fire"])
		for i in 3:
			check_eq(es[i].armed, bool(expect[lvl][i]), "level %d lane %d" % [lvl, i])
			check(es[i].fire_timer >= 2.0 / f - 1e-9 and es[i].fire_timer <= 2.8 / f + 1e-9, "start 2.0/F + rand(0,0.8)/F")
		w.run_steps(_steps(12.0))
		var fired := {}
		for ev in _events(w, "enemy_fire"):
			fired[ev["id"]] = true
		for i in 3:
			check_eq(fired.has(es[i].id), bool(expect[lvl][i]), "level %d lane %d fires" % [lvl, i])


func test_bullet_counts_widths_directions() -> void:
	var table := {1: [1, 0.0, 0], 2: [4, 0.70, 0], 3: [4, 0.70, 0], 4: [6, 0.55, 1], 5: [6, 0.65, 1], 6: [8, 0.75, 1],
		7: [6, 0.55, 1], 8: [6, 0.60, 1], 9: [6, 0.60, 1], 11: [8, 0.80, 1], 12: [8, 0.80, 1], 14: [8, 0.80, 1],
		15: [10, 0.90, 1], 16: [10, 0.90, 1], 17: [12, 1.0, 2], 18: [12, 1.0, 2], 19: [12, 1.0, 2], 20: [12, 1.0, 2]}
	for lvl in table:
		for side in [-1.0, 1.0]:
			var w := _fire_world(lvl)
			var e := w.add_enemy(2, 480.0)
			w.player_x = 480.0 + side * 200.0
			_until_fire(w)
			var cnt := int(table[lvl][0])
			check_eq(w.bullets.size(), cnt, "level %d count" % lvl)
			var xs: Array[float] = []
			for b in w.bullets:
				xs.append(b.x)
				check_near(b.y, 420.0 + 18.0, 1e-9, "level %d spawn y" % lvl)
			xs.sort()
			if cnt > 1:
				check_near(xs[cnt - 1] - xs[0] + 10.0, float(table[lvl][1]) * 90.0, 1e-6, "level %d full width" % lvl)
				check_near((xs[cnt - 1] + xs[0]) * 0.5, e.x, 1e-6, "centred")
				for i in range(1, cnt):
					check_near(xs[i] - xs[i - 1], (xs[cnt - 1] - xs[0]) / float(cnt - 1), 1e-6, "evenly spaced")
			else:
				check_eq(xs[0], e.x)
			var v := Vector2(w.bullets[0].vx, w.bullets[0].vy)
			match int(table[lvl][2]):
				0:
					check_eq(v, Vector2(0, 220), "straight down")
				1:
					check_near(v.x, side * 110.0, 1e-6, "5/7 o'clock")
					check_near(v.y, 190.5255888, 1e-6)
				2:
					check_near(v.x, side * 190.5255888, 1e-6, "4/8 o'clock")
					check_near(v.y, 110.0, 1e-6)
			check_near(v.length(), 220.0, 1e-3)
			for b in w.bullets:
				check_eq(Vector2(b.vx, b.vy), v, "all bullets parallel")
			# Direction is fixed at fire time.
			var b0: GameWorld.Bullet = w.bullets[0]
			var vx0 := b0.vx
			w.player_x = 480.0 - side * 300.0
			w.run_steps(20)
			check_eq(b0.vx, vx0, "no tracking")


func test_direction_tie_goes_right() -> void:
	var w := _fire_world(4)
	w.add_enemy(2, 480.0)
	w.player_x = 480.0
	_until_fire(w)
	check(w.bullets.size() > 0 and w.bullets[0].vx > 0.0, "tie → +vx")


func test_bullets_removed_below_ground_and_sideways() -> void:
	var w := _world(1)
	w.invincible = true
	var b := w.add_bullet(100.0, 600.0)
	var last_y := b.y
	while w.bullets.has(b):
		last_y = b.y
		w.run_steps(1)
		if w.bullets.has(b):
			check(b.y - 5.0 <= 685.0, "kept only while not entirely below the ground")
	check(last_y + 220.0 * STEP - 5.0 > 685.0, "removed as soon as entirely below y=685")
	check(last_y - 5.0 <= 685.0)
	check_eq(_count(w, "bullet_landed"), 1)
	var s := w.add_bullet(950.0, 300.0, 190.5255888, 110.0)
	var last_x := s.x
	while w.bullets.has(s):
		last_x = s.x
		w.run_steps(1)
		if w.bullets.has(s):
			check(s.x - 5.0 <= 960.0, "kept while partly on screen")
	check(last_x + 190.5255888 * STEP - 5.0 > 960.0, "removed right")
	var l := w.add_bullet(10.0, 300.0, -190.5255888, 110.0)
	w.run_steps(_steps(0.06))
	check(w.bullets.has(l), "partly visible at the left edge")
	w.run_steps(_steps(0.1))
	check(not w.bullets.has(l), "removed left")


func test_no_enemy_fire_in_level_13() -> void:
	var w := _fire_world(13)
	check(w.rank_timers.is_empty())
	var e := w.add_enemy(0, 300.0)
	var e2 := w.add_enemy(1, 600.0)
	check(not e.armed and not e2.armed)
	w.run_steps(_steps(15.0))
	check_eq(_count(w, "enemy_fire"), 0)


# --- Determinism / events ------------------------------------------------------------------------
func test_deterministic_with_seed() -> void:
	var a := GameWorld.new(17, 2, 3, 3, 1234)
	var b := GameWorld.new(17, 2, 3, 3, 1234)
	for i in 600:
		var axis := sin(float(i) * 0.05)
		a.update(1.0 / 60.0, axis, i % 3 != 0)
		b.update(1.0 / 60.0, axis, i % 3 != 0)
	check_eq(a.enemies.size(), b.enemies.size())
	for i in a.enemies.size():
		check_eq(a.enemies[i].x, b.enemies[i].x)
		check_eq(a.enemies[i].y, b.enemies[i].y)
	check_eq(a.bullets.size(), b.bullets.size())
	check_eq(a.lives, b.lives)
	check_eq(a.score_delta, b.score_delta)


func test_events_have_required_fields() -> void:
	var w := GameWorld.new(8, 1, 0, 3, 77)
	w.start_combat()
	var sp := _events(w, "enemy_spawned")
	check_eq(sp.size(), 3)
	for k in ["id", "x", "y", "scale"]:
		check(sp[0].has(k), "enemy_spawned." + k)
	w.apply_hit(w.enemies[0])
	var spl := _events(w, "enemy_split")
	check(spl[0].has("children") and spl[0].has("x") and spl[0].has("y") and spl[0].has("id"))
	w.apply_hit(w.enemies[0])
	var d := _events(w, "enemy_destroyed")
	for k in ["id", "x", "y", "scale", "points"]:
		check(d[0].has(k), "enemy_destroyed." + k)
	w.run_steps(1, 0.0, true)
	var s := _events(w, "shot_fired")
	check(s[0].has("ship_id") and s[0].has("count"))
	w.add_bullet(w.player_x, 659.0, 0.0, 0.0)
	w.run_steps(1)
	var ph := _events(w, "player_hit")
	check(ph[0].has("x") and ph[0].has("y") and ph[0].has("lives_left"))


func test_children_share_flap_phase_and_oscillation() -> void:
	var w := _world(9)
	w.osc_amplitude = 22.0
	var p := w.add_enemy(1, 480.0)
	p.flap_offset = 0.37
	w.run_steps(37)
	var phase := w.flap_phase(p)
	var y := p.y
	w.apply_hit(p)
	check_eq(w.enemies.size(), 2)
	for k in w.enemies:
		check_eq(k.flap_offset, 0.37, "child inherits the flap offset")
		check_near(w.flap_phase(k), phase, 1e-9, "children flap in sync with the parent")
		check_near(k.y, y, 1e-9, "children start at the parent's y")
		check_eq(k.group_id, p.group_id)
	w.run_steps(100)
	check_eq(w.enemies[0].y, w.enemies[1].y, "children oscillate together")
	check_near(w.flap_phase(w.enemies[0]), w.flap_phase(w.enemies[1]), 1e-12)


func test_fire_timers_frozen_during_respawn() -> void:
	var w := GameWorld.new(12, 1, 0, 3, 31)   # per-figure timers
	w.start_combat()
	w.run_steps(60)
	var timers := {}
	for e in w.enemies:
		timers[e.id] = e.fire_timer
	w.add_bullet(w.player_x, 659.0, 0.0, 0.0)
	w.run_steps(1)
	check_eq(w.state, GameWorld.State.RESPAWN)
	for e in w.enemies:
		timers[e.id] = e.fire_timer
	w.run_steps(200)
	for e in w.enemies:
		check_eq(e.fire_timer, timers[e.id], "per-figure timer frozen during respawn")
	check(w.bullets.is_empty())
	var r := GameWorld.new(3, 1, 0, 3, 32)
	r.start_combat()
	r.run_steps(60)
	r.add_bullet(r.player_x, 659.0, 0.0, 0.0)
	r.run_steps(1)
	var rt: Array[float] = r.rank_timers.duplicate()
	r.run_steps(200)
	check_eq(r.rank_timers, rt, "rank timers frozen during respawn")
	check_eq(r.events.filter(func(ev: Dictionary) -> bool: return ev["type"] == "enemy_fire").size(), 0)


# --- Fire rank ties (SPEC §7, §8) ------------------------------------------------------------------
## Collects enemy_fire events per figure id over `seconds` (events are drained step by step).
func _fires_by_id(w: GameWorld, seconds: float) -> Dictionary:
	var fired := {}
	for i in _steps(seconds):
		w.run_steps(1)
		for ev in w.events:
			if ev["type"] == "enemy_fire":
				fired[int(ev["id"])] = int(fired.get(int(ev["id"]), 0)) + 1
		w.events.clear()
	return fired


## Level 10 (RANK1): a bottom-lane pair is tied for "the overall lowest figure" (same lane, same phase).
## Both are armed, so both must get shots – but together only at the rate of the ONE rank-1 timer.
func test_fire_rank_tie_level10_armed_siblings_share_rank1() -> void:
	var w := _fire_world(10, 3)
	w.osc_amplitude = 22.0
	var p := w.add_enemy(2, 480.0)
	w.add_enemy(0, 200.0)
	w.apply_hit(p)
	var kids: Array[GameWorld.Enemy] = []
	for e in w.enemies:
		if e.is_child:
			kids.append(e)
	check_eq(kids.size(), 2)
	check_eq(kids[0].y, kids[1].y, "siblings have identical y")
	check(kids[0].armed and kids[1].armed)
	var fired := _fires_by_id(w, 60.0)
	var a := int(fired.get(kids[0].id, 0))
	var b := int(fired.get(kids[1].id, 0))
	check(a > 5 and b > 5, "both tied armed children fire (left=%d right=%d)" % [a, b])
	check_eq(fired.size(), 2, "nobody else fires (level 10: only the overall lowest)")
	# 60 s at F = 1.4: one timer with rand(1.8, 2.8)/1.4 → 30..47 salvos; a doubled rank would give ~70.
	check(a + b >= 28 and a + b <= 48, "one rank-1 timer for the pair (%d salvos)" % (a + b))


## Levels 7/8 (RANK2 + ONE_ARMED): a pair split on the middle lane is tied for rank 2 behind a bottom-lane
## original. Whichever child is armed takes rank 2 – for both possible picks.
func test_fire_rank_tie_prefers_the_armed_sibling() -> void:
	for armed_side in 2:
		var w := _fire_world(8, 40 + armed_side)
		w.osc_amplitude = 22.0
		var low := w.add_enemy(2, 150.0)
		var p := w.add_enemy(1, 600.0)
		w.apply_hit(p)
		var kids: Array[GameWorld.Enemy] = [w.enemies[1], w.enemies[2]]
		check(kids[0].is_child and kids[1].is_child and kids[0].x < kids[1].x, "left / right child")
		kids[armed_side].armed = true
		kids[1 - armed_side].armed = false
		var fired := _fires_by_id(w, 30.0)
		check(int(fired.get(kids[armed_side].id, 0)) >= 10, "armed child (side %d) holds rank 2 and fires" % armed_side)
		check_eq(int(fired.get(kids[1 - armed_side].id, 0)), 0, "defenceless sibling never fires")
		check(int(fired.get(low.id, 0)) >= 10, "rank 1 unaffected")


## A tie never lets a STRICTLY higher figure take over: a bottom-lane pair (one armed) holds ranks 1 and 2;
## the armed child fires on one rank timer, the defenceless child's rank is skipped, the middle original
## (rank 3) never fires.
func test_fire_rank_tie_no_passing_to_a_higher_figure() -> void:
	for s in 4:
		var w := _fire_world(7, 60 + s)
		w.osc_amplitude = 22.0
		var p := w.add_enemy(2, 480.0)
		var mid := w.add_enemy(1, 200.0)
		w.apply_hit(p)
		var armed: GameWorld.Enemy = null
		for e in w.enemies:
			if e.is_child and e.armed:
				armed = e
		check(armed != null)
		var fired := _fires_by_id(w, 40.0)
		check_eq(int(fired.get(mid.id, 0)), 0, "the higher original never gets the pair's rank")
		check_eq(fired.keys(), [armed.id], "only the armed child fires")
		# 40 s at F = 1.25: ONE timer → 17..27 salvos (both timers would give ~40).
		var n := int(fired.get(armed.id, 0))
		check(n >= 15 and n <= 28, "armed child fires at the rate of one rank timer (%d)" % n)


## Without a tie the order is strictly by y; rank_holder() does not draw random numbers then.
func test_rank_holder_without_ties_is_plain_order() -> void:
	var w := _fire_world(3)
	var a := w.add_enemy(0, 200.0)
	var b := w.add_enemy(1, 500.0)
	var c := w.add_enemy(2, 800.0)
	var st := w.rng.state
	check_eq(w.rank_holder(0), c)
	check_eq(w.rank_holder(1), b)
	check_eq(w.rank_holder(2), a)
	check(w.rank_holder(3) == null)
	check_eq(w.rng.state, st, "no random draw without a tie")


# --- Rolling window over a respawn (SPEC §1, §3, §8) -------------------------------------------------
## The 10 s window runs on GAME time, the respawn pause (1.3 game s) included: hits at 0 and 8, player dies
## at 8.5; a third hit at exactly 10.0 game s still counts the 0 s hit, one step later it has expired.
func test_rolling_window_counts_respawn_game_time() -> void:
	var w := _world(19)
	var a := w.add_enemy(0, 150.0)
	var b := w.add_enemy(1, 480.0)
	var t0 := w.step_count
	w.apply_hit(a)
	w.apply_hit(b)
	w.run_steps(_steps(8.0))
	w.apply_hit(a)
	w.apply_hit(b)
	w.run_steps(_steps(0.5))
	w.add_bullet(w.player_x, LevelData.PLAYER_Y, 0.0, 0.0)
	w.run_steps(1)
	check_eq(w.state, GameWorld.State.RESPAWN)
	var combat0 := w.combat_steps
	while w.state == GameWorld.State.RESPAWN:
		w.run_steps(1)
	check(w.combat_steps - combat0 <= 1, "combat (movement) paused during the respawn")
	while w.step_count - t0 < _steps(10.0):
		w.run_steps(1)
	w.apply_hit(a)
	check(not w.enemies.has(a), "0, 8, 10.0 (respawn in between) → destroyed")
	w.run_steps(1)
	w.apply_hit(b)
	check(w.enemies.has(b), "0, 8, 10.0+ → the 0 s hit expired during play + respawn game time")
	check_eq(b.hit_steps.size(), 2)


## Client decision (feedback round 1): the bass rises once per ORIGINAL enemy. enemy_destroyed carries
## group_cleared = true for single figures and only for the LAST child of a split pair.
func test_group_cleared_flag_for_bass() -> void:
	var w := _world(8, 0)
	var e := w.add_enemy(1, 480.0)
	w.apply_hit(e)   # split
	check_eq(_events(w, "enemy_destroyed").size(), 0, "split destroys nothing")
	check_eq(w.enemies.size(), 2)
	w.apply_hit(w.enemies[0])
	var d1 := _events(w, "enemy_destroyed")
	check_eq(d1.size(), 1)
	check_eq(bool(d1[0]["group_cleared"]), false, "first child: partner still alive")
	w.events.clear()
	w.apply_hit(w.enemies[0])
	var d2 := _events(w, "enemy_destroyed")
	check_eq(bool(d2[0]["group_cleared"]), true, "second child clears the pair")
	var w1 := _world(1, 0)
	w1.apply_hit(w1.add_enemy(2, 300.0))
	check_eq(bool(_events(w1, "enemy_destroyed")[0]["group_cleared"]), true, "single figure clears its group")
