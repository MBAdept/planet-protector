extends TestBase
## Independent review tests for GameWorld (docs/SPEC.md §1, §3–§10).
## Tests prefixed "test_review_defect_" document a deviation and FAIL on the reviewed code;
## all other tests are additional evidence that a rule holds (they pass).

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


# --- Sub-stepping / speed factor (SPEC §1) -------------------------------------------------------
## EXPERT (×1.44) with 0.1 s real frames (≈ 35 sub-steps per update): a 500 px/s laser must still
## hit the smallest target (level-7 child, |dy| < 8.4 px).
func test_expert_large_frames_shot_does_not_tunnel_through_child() -> void:
	var w := _world(7, 0, 3)
	var kid := w.add_enemy(2, 480.0, 1.0, 0.40, true)
	w.player_x = 480.0
	var guard := 0
	while w.enemies.has(kid) and guard < 40:
		w.update(0.1, 0.0, guard == 0)
		guard += 1
	check(not w.enemies.has(kid), "child destroyed despite large frames at EXPERT")
	check_eq(_count(w, "enemy_destroyed"), 1)


## EXPERT with 0.1 s real frames: a falling enemy bullet must hit the player exactly once.
func test_expert_large_frames_bullet_does_not_tunnel_through_player() -> void:
	var w := _world(1, 0, 3, 2)
	w.add_enemy(0, 100.0)
	w.add_bullet(480.0, 520.0, 0.0, LevelData.ENEMY_BULLET_SPEED)
	w.add_bullet(486.0, 520.0, 0.0, LevelData.ENEMY_BULLET_SPEED)   # same step → still one life
	for i in 20:
		w.update(0.1, 0.0, false)
	check_eq(w.lives, 1, "exactly one life lost")
	check_eq(_count(w, "player_hit"), 1)


## Game timers run on game time, play time on real time (EXPERT): refill 2.0 game s, respawn 1.3 game s.
func test_expert_refill_and_respawn_in_game_time_play_time_real() -> void:
	var w := GameWorld.new(1, 3, 0, 3, 5)
	w.allow_enemy_fire = false
	w.update(LevelData.INTRO_TIME, 0.0, false)
	check_eq(w.state, GameWorld.State.PLAYING)
	var victim: GameWorld.Enemy = w.enemies[0]
	var sl := victim.slot
	w.apply_hit(victim)
	var real := 0.0
	var frame := 1.0 / 120.0
	while w.slots[sl].alive == 0 and real < 5.0:
		w.update(frame, 0.0, false)
		real += frame
	check_near(real, 2.0 / 1.44, 0.02, "refill after 2.0 GAME seconds")
	var t_before := w.active_time
	check_near(t_before, real, 0.01, "play time = real seconds while playing")
	w.add_bullet(w.player_x, LevelData.PLAYER_Y, 0.0, 0.0)
	w.update(frame, 0.0, false)
	check_eq(w.state, GameWorld.State.RESPAWN)
	var resp := 0.0
	while w.state == GameWorld.State.RESPAWN and resp < 5.0:
		w.update(frame, 0.0, false)
		resp += frame
	check_near(resp, 1.3 / 1.44, 0.02, "respawn after 1.3 GAME seconds")
	check(w.active_time - t_before < frame + 0.01, "respawn time not counted")


# --- Bonus level time (SPEC §9, §10) -------------------------------------------------------------
## Zero attempts left with a DOUBLE salvo: one projectile hits, the other flies on – play time runs
## until the second one has left the field, then the level ends.
func test_bonus_last_double_salvo_time_runs_until_both_projectiles_gone() -> void:
	var w := _world(13, 2)   # Double Dart
	w.attempts = 1
	var e := w.add_enemy(1, 480.0 - 12.0)   # only the left projectile (x = 468) overlaps
	w.player_x = 480.0
	w.run_steps(1, 0.0, true)
	check_eq(w.attempts, 0)
	check_eq(w.shots.size(), 2)
	var guard := 0
	while w.enemies.has(e) and guard < 2000:
		w.run_steps(1)
		guard += 1
	check_eq(w.shots.size(), 1, "the right projectile flies on")
	check_eq(w.state, GameWorld.State.PLAYING, "goal not met while the last salvo is still flying")
	var t := w.active_time
	while not w.shots.is_empty() and guard < 4000:
		w.run_steps(1)
		guard += 1
	check(w.active_time > t + 0.7, "flight time of the remaining projectile counts (≈ 340 px at 430 px/s)")
	check(w.goal_met, "goal met once the last projectile is gone")
	w.run_steps(_steps(1.0))
	check_eq(w.state, GameWorld.State.COMPLETE)
	check_eq(w.bonus_result.get("remaining", -1), 0)
	check_eq(w.score_delta, 0, "no kill score, bonus 0")


# --- Final phase (SPEC §3, §9) -------------------------------------------------------------------
## Level 10 (flawless level): life lost in the final phase → completion bonus yes, extra life no,
## and the respawn pause is not counted as play time.
func test_final_phase_life_loss_level10() -> void:
	var w := _world(10)
	w.spawned = w.total
	var e := w.add_enemy(0, 200.0)
	var b := w.add_bullet(480.0, 560.0, 0.0, LevelData.ENEMY_BULLET_SPEED)
	w.apply_hit(e)   # original splits
	for k in w.enemies.duplicate():
		w.apply_hit(k)
	check(w.enemies.is_empty())
	var guard := 0
	while w.state == GameWorld.State.PLAYING and guard < 2000:
		w.run_steps(1)
		guard += 1
	check_eq(w.state, GameWorld.State.RESPAWN, "bullet still dangerous after the last kill")
	var t := w.active_time
	w.run_steps(_steps(3.0))
	check_eq(w.state, GameWorld.State.COMPLETE)
	check_near(w.active_time, t, 1e-9, "respawn + explosion wait not counted")
	check_eq(w.result.get("flawless"), false)
	check_eq(w.result.get("extra_life"), false)
	check_eq(w.result.get("completion_bonus"), 750)
	check_eq(w.lives, 2)
	check(b != null)


## Last life lost in the final phase → game over, no completion.
func test_final_phase_last_life_is_game_over() -> void:
	var w := _world(1, 0, 3, 1)
	w.spawned = w.total
	var e := w.add_enemy(0, 200.0)
	w.add_bullet(480.0, 600.0, 0.0, LevelData.ENEMY_BULLET_SPEED)
	w.apply_hit(e)
	w.run_steps(_steps(3.0))
	check_eq(w.state, GameWorld.State.GAME_OVER)
	check_eq(_count(w, "level_complete"), 0)


# --- Colour lock with the real slot system (SPEC §5, §8) ------------------------------------------
func test_color_lock_relocked_by_refilled_violet() -> void:
	var w := GameWorld.new(14, 1, 0, 3, 11)
	w.allow_enemy_fire = false
	w.start_combat()
	check_eq(w.enemies.size(), 3)
	for e in w.enemies:
		w.apply_hit(e)   # violet → yellow
	for e in w.enemies:
		w.apply_hit(e)   # yellow → green (no violet left)
	for e in w.enemies:
		check_eq(e.stage, LevelData.Stage.GREEN)
	var first: GameWorld.Enemy = w.enemies[0]
	w.apply_hit(first)   # all green → destroyed
	check(not w.enemies.has(first))
	w.run_game_seconds(2.0)
	check_eq(w.enemies.size(), 3, "slot refilled after 2.0 s")
	var fresh: GameWorld.Enemy = w.enemies[w.enemies.size() - 1]
	check_eq(fresh.stage, LevelData.Stage.VIOLET)
	var green: GameWorld.Enemy = w.enemies[0]
	w.events.clear()
	w.apply_hit(green)
	check(w.enemies.has(green), "new violet re-establishes the lock")
	check_eq(_count(w, "locked_hit"), 1)


# --- Documented deviations (these FAIL on the reviewed code) --------------------------------------
## SPEC §7/§8 level 10: bottom-lane children are armed, "only the overall lowest figure may fire".
## Siblings have IDENTICAL y (same lane, inherited oscillation phase), so both are "the lowest".
## ranked_enemies() breaks the tie by id, so the RIGHT child (higher id) never holds rank 1 while
## its left sibling lives – it can never fire, although the rule arms both bottom-lane children.
func test_review_defect_level10_tied_siblings_right_child_never_fires() -> void:
	var w := GameWorld.new(10, 1, 0, 3, 3)
	w.auto_slots = false
	w.invincible = true
	w.start_combat()
	var p := w.add_enemy(2, 480.0)
	w.apply_hit(p)
	var left: GameWorld.Enemy = w.enemies[0]
	var right: GameWorld.Enemy = w.enemies[1]
	check(left.armed and right.armed, "both bottom-lane children armed")
	var fired := {left.id: 0, right.id: 0}
	for i in _steps(60.0):
		w.run_steps(1)
		for ev in w.events:
			if ev["type"] == "enemy_fire" and fired.has(int(ev["id"])):
				fired[int(ev["id"])] += 1
		w.events.clear()
	check(fired[left.id] > 0, "left child fires")
	check(fired[right.id] > 0, "right child never fired in 60 s (left=%d right=%d)" % [fired[left.id], fired[right.id]])


## SPEC §7/§8 levels 7–8 (RANK2 + ONE_ARMED): siblings on the MIDDLE lane share rank 2 by y; if the
## random pick armed the RIGHT child, the unarmed left sibling always holds rank 2 (tie → lower id)
## and does not pass its right, so the armed child is silent for its whole life.
func test_review_defect_level8_armed_right_sibling_silenced_by_tie_break() -> void:
	var silent_cases := 0
	var cases := 0
	for s in 40:
		var w := GameWorld.new(8, 1, 0, 3, 500 + s)
		w.auto_slots = false
		w.invincible = true
		w.enemy_speed = 0.0
		w.start_combat()
		w.add_enemy(2, 150.0)            # rank 1: the bottom-lane original
		var p := w.add_enemy(1, 600.0)
		w.apply_hit(p)
		var right: GameWorld.Enemy = w.enemies[2]
		if not right.armed:
			continue
		cases += 1
		var shots := 0
		for i in _steps(30.0):
			w.run_steps(1)
			for ev in w.events:
				if ev["type"] == "enemy_fire" and int(ev["id"]) == right.id:
					shots += 1
			w.events.clear()
		if shots == 0:
			silent_cases += 1
	check(cases > 0, "some seeds arm the right child")
	check_eq(silent_cases, 0, "armed right child never fired in %d of %d cases;" % [silent_cases, cases])


## SPEC §1 lists "the 10 s rolling window" as GAME time and the respawn delay (1.3 game s) as game time;
## §3 pauses movement, fire and refill during respawn but not the rolling window. The implementation
## measures the window with combat_steps, which are frozen during RESPAWN, so a hit that is > 10 game s
## old still counts. Hits at game time 0 and 8, player dies at 8.5, third hit at 10.5 game s
## (respawn included) → the 0 s hit must have expired → the enemy must survive.
## NOTE: interpretation issue (the engineer documented "combat clock frozen" as a choice).
func test_review_defect_rolling_window_ignores_respawn_game_time() -> void:
	var w := _world(19)
	var e := w.add_enemy(0, 150.0)
	var t0 := w.step_count
	w.apply_hit(e)
	w.run_steps(_steps(8.0))
	w.apply_hit(e)
	w.run_steps(_steps(0.5))
	w.add_bullet(w.player_x, LevelData.PLAYER_Y, 0.0, 0.0)
	w.run_steps(1)
	check_eq(w.state, GameWorld.State.RESPAWN)
	while w.state == GameWorld.State.RESPAWN:
		w.run_steps(1)
	while (w.step_count - t0) * STEP < 10.5:
		w.run_steps(1)
	w.apply_hit(e)
	check(w.enemies.has(e), "hit from 10.5 game s ago still counted (window frozen during respawn)")
