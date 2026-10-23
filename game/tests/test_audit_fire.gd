extends TestBase
## AUDIT – dimension "fire" (reference section F + the child fire rules of G 7–12).
## test_audit_fire_invariants_full_levels: regression – every salvo of naturally spawned, bot-played levels obeys
##   the table (count, permission/rank, child rule, 220 px/s, side chosen at fire time, rank-timer restarts).
## test_audit_fire_sideways_exit_*: regression for finding fire-1 – a fireball leaving sideways fades out
##   (view only) before it is removed, but never while it can still hit the player.

const STEP := LevelData.SIM_STEP
const Autopilot := preload("res://scripts/game/autopilot.gd")
const ProjectilesView := preload("res://scripts/game/projectiles_view.gd")


func _steps(seconds: float) -> int:
	return int(round(seconds / STEP))


func _ranks(lvl: int) -> int:
	var p := int(LevelData.fire(lvl)["perm"])
	if p == LevelData.Perm.RANK1:
		return 1
	if p == LevelData.Perm.RANK2:
		return 2
	return 0


## Runs a level with the bot (invincible) and checks every enemy salvo against the reference table.
func _check_level(lvl: int, rng_seed: int, seconds: float) -> Dictionary:
	var w := GameWorld.new(lvl, 1, 0, 3, rng_seed)
	w.invincible = true
	w.start_combat()
	var fd := LevelData.fire(lvl)
	var f := float(LevelData.level(lvl)["fire"])
	var stats := {"salvos": 0, "child_salvos": 0, "violations": []}
	var prev_rank: Array[float] = w.rank_timers.duplicate()
	for i in _steps(seconds):
		if w.is_finished():
			break
		var d: Vector2 = Autopilot.decide(w)
		w.run_steps(1, d.x, d.y > 0.5)
		# Rank timers (levels 1–10): every restart is rand(1.8, 2.8)/F.
		for r in w.rank_timers.size():
			if r < prev_rank.size() and w.rank_timers[r] > prev_rank[r] + 1e-9:
				var v := w.rank_timers[r]
				if v < 1.8 / f - 1e-9 or v > 2.8 / f + 1e-9:
					stats["violations"].append("L%d rank timer %d restarted at %f" % [lvl, r, v])
		prev_rank = w.rank_timers.duplicate()
		for ev in w.events:
			if ev["type"] != "enemy_fire":
				continue
			stats["salvos"] += 1
			var e := w.find_enemy(int(ev["id"]))
			if e == null:
				stats["violations"].append("L%d firing figure %d not alive" % [lvl, ev["id"]])
				continue
			if e.is_child:
				stats["child_salvos"] += 1
			if not e.armed:
				stats["violations"].append("L%d defenceless figure fired" % lvl)
			var exp_n := int(fd["child_count"]) if e.is_child else int(fd["count"])
			if int(ev["count"]) != exp_n:
				stats["violations"].append("L%d count %d != %d" % [lvl, ev["count"], exp_n])
			if lvl <= 10:
				# Never a figure with as many STRICTLY lower figures as there are rank timers (no passing upwards).
				var lower := 0
				for o in w.enemies:
					if o.y > e.y:
						lower += 1
				if lower >= _ranks(lvl):
					stats["violations"].append("L%d figure with %d strictly lower figures fired" % [lvl, lower])
			else:
				match int(fd["perm"]):
					LevelData.Perm.LANE_BOTTOM:
						if e.lane != LevelData.BOTTOM_LANE:
							stats["violations"].append("L%d lane %d fired" % [lvl, e.lane])
					LevelData.Perm.LANES_MID_BOTTOM:
						if e.lane < 1:
							stats["violations"].append("L%d lane %d fired" % [lvl, e.lane])
			if e.is_child and lvl >= 9 and e.lane != LevelData.BOTTOM_LANE:
				stats["violations"].append("L%d upper-lane child fired" % lvl)
			var v := Vector2(ev["vx"], ev["vy"])
			if absf(v.length() - 220.0) > 1e-3:
				stats["violations"].append("L%d speed %f" % [lvl, v.length()])
			if v.x != 0.0 and signf(v.x) != (1.0 if w.player_x >= e.x else -1.0):
				stats["violations"].append("L%d wrong side" % lvl)
		w.events.clear()
	return stats


func test_audit_fire_invariants_full_levels() -> void:
	for lvl in range(1, 21):
		if lvl == LevelData.BONUS_LEVEL:
			continue
		var st := _check_level(lvl, 900 + lvl, 30.0)
		var vio: Array = st["violations"]
		check(vio.is_empty(), "L%d: %d violations, first: %s" % [lvl, vio.size(), str(vio.slice(0, 3))])
		check(int(st["salvos"]) > 0, "L%d fired" % lvl)
		if lvl >= 7 and lvl <= 12:
			check(int(st["child_salvos"]) > 0, "L%d children fired" % lvl)


## fire-1: a bullet leaving sideways is removed (simulation: once its 10 px body is off-screen) while its
## drawn tail is still on screen. ProjectilesView fades it out first, only inside the band where no player
## position can be hit any more, so the tail does not pop away. Simulation and timing stay unchanged.
func _check_side_exit(start_x: float, v: Vector2, edge: String) -> void:
	var w := GameWorld.new(17, 1, 0, 3, 1)
	w.auto_slots = false
	w.invincible = true
	w.start_combat()
	var b := w.add_bullet(start_x, 400.0, v.x, v.y)
	var last_x := b.x
	var lethal_dim := 0
	while w.bullets.has(b):
		last_x = b.x
		var a := ProjectilesView.side_fade(b.x, b.vx)
		var reachable := b.x > LevelData.PLAYER_MIN_X - LevelData.PLAYER_HIT_DX \
			and b.x < LevelData.PLAYER_MAX_X + LevelData.PLAYER_HIT_DX
		if reachable and a < 1.0:
			lethal_dim += 1
		w.run_steps(1)
	check(last_x < 0.0 or last_x > LevelData.SCREEN_W, "%s: removed only once the head is off-screen (%.2f)" % [edge, last_x])
	check(ProjectilesView.side_fade(last_x, v.x) <= 0.1,
		"%s: last drawn alpha before removal %.2f (head x=%.2f) – the tail must not pop away" % [
			edge, ProjectilesView.side_fade(last_x, v.x), last_x])
	check_eq(lethal_dim, 0, "%s: steps where a still dangerous fireball was drawn faded" % edge)


## Left edge: an 8 o'clock bullet (−190.53, 110) – its tail points back to the right/up.
func test_audit_fire_sideways_exit_fades_left_edge() -> void:
	_check_side_exit(60.0, Vector2(-LevelData.ENEMY_BULLET_DIAG_B, LevelData.ENEMY_BULLET_DIAG_A), "left 8 o'clock")
	_check_side_exit(60.0, Vector2(-LevelData.ENEMY_BULLET_DIAG_A, LevelData.ENEMY_BULLET_DIAG_B), "left 7 o'clock")


## Same at the right edge: a 4 o'clock bullet (+190.53, 110).
func test_audit_fire_sideways_exit_fades_right_edge() -> void:
	_check_side_exit(900.0, Vector2(LevelData.ENEMY_BULLET_DIAG_B, LevelData.ENEMY_BULLET_DIAG_A), "right 4 o'clock")
	_check_side_exit(900.0, Vector2(LevelData.ENEMY_BULLET_DIAG_A, LevelData.ENEMY_BULLET_DIAG_B), "right 5 o'clock")
	check_near(ProjectilesView.side_fade(480.0, 0.0), 1.0, 0.0, "straight-down bullets never fade sideways")
	var src := (ProjectilesView as GDScript).source_code
	check(src.contains("alpha *= side_fade(b.x, b.vx)"), "ProjectilesView._draw applies the side fade to every fireball")
