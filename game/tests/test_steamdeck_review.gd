extends TestBase
## Independent rules & regression review of the Steam Deck round (display modes 3 = 1280×800 16:10 with a 1152 px
## playfield, 4 = 1280×720 16:9 with the 1280 px playfield; docs/SPEC.md §11.2, §18.1).
## - Modes 0 / 1 / 2 bit-for-bit: full autopilot runs (invincible, to level end) and attract demos at W = 960 and
##   W = 1280, digests recorded by the reviewer with an untouched `git archive` of d1bd58e (before this change).
##   The digest covers every world event (JSON, frame-numbered) plus the final frame count / state / enemy count /
##   ship x / bullet count, so it is independent of tests/test_wide_playfield.gd's digest helper.
## - W = 1152: stack breaking near the right edge, demo guarantees on more seeds, mode/width table consistency.

const Autopilot := preload("res://scripts/game/autopilot.gd")
const W_DECK := 1152.0
const STEP := 1.0 / 60.0

## [width, level, difficulty, ship, seed] → "md5 frames state enemies player_x bullets" (recorded at d1bd58e).
const HEAD_RUNS := [
	[960.0, 1, 1, 0, 11, "c5b16de297ddef7524add97d0dedbc8d 1228 4 0 489.575857 0"],
	[960.0, 7, 0, 3, 202, "197c9c77b9598482ff2516235ae6ee38 2407 4 0 217.167886 0"],
	[960.0, 13, 2, 5, 9999, "c112b359d736ab57f137e55c1abbb8a4 3268 4 0 101.755036 0"],
	[960.0, 17, 1, 0, 11, "2234de3d59cfbdfc3f1351971d2ddd53 3644 4 0 199.363522 0"],
	[1280.0, 1, 1, 0, 11, "b7b5eb90737dd78be2b74f506092ee73 1786 4 0 489.693306 0"],
	[1280.0, 7, 0, 3, 202, "e2800b4d94c2aaeb696025e90c3c25f8 2521 4 0 784.182608 0"],
	[1280.0, 13, 2, 5, 9999, "2c9b8f739f3b78e00f7e1f9eb26a0668 4363 4 0 776.272783 0"],
	[1280.0, 17, 2, 5, 9999, "d197cc65939a3d1d870e405146ec994c 5120 4 0 79.899654 0"],
]
## [width, demo seed] → "md5 t=<time> x=<ship x>" (recorded at d1bd58e).
const HEAD_DEMOS := [
	[960.0, 77, "2e0ef759679ad0a1e0eaae290d4773f7 t=15.2653 x=622.4412"],
	[960.0, 4242, "395d3181f5a9ac174ea94c5239ee79c5 t=34.5833 x=302.5372"],
	[1280.0, 77, "cf3735a45190a542692ef76510839df5 t=15.2653 x=470.0277"],
	[1280.0, 4242, "acb6bda186811a1d69a3f31213fd1af1 t=33.2500 x=30.0000"],
]


static func run_digest(level: int, diff: int, ship: int, rng_seed: int, width: float) -> String:
	var w := GameWorld.new(level, diff, ship, 3, rng_seed, width)
	w.invincible = true
	var lines: PackedStringArray = []
	var guard := 0
	while not w.is_finished() and guard < 60 * 240:
		var d: Vector2 = Autopilot.decide(w)
		w.update(STEP, d.x, d.y > 0.5)
		for ev in w.events:
			lines.append("%d %s" % [guard, JSON.stringify(ev, "", true, true)])
		w.events.clear()
		guard += 1
	var st := "%d %s %d %.6f %d" % [guard, str(w.state), w.enemies.size(), w.player_x, w.bullets.size()]
	return "%s %s" % [("\n".join(lines) + st).md5_text(), st]


static func demo_digest(rng_seed: int, width: float) -> String:
	var d := AttractDirector.new(rng_seed)
	var w := d.make_world(width)
	var lines: PackedStringArray = []
	var i := 0
	while not d.is_over() and i < 60 * 45:
		w.events.clear()
		d.play(w, STEP)
		for ev in w.events:
			lines.append("%d %s" % [i, JSON.stringify(ev, "", true, true)])
		i += 1
	return "%s t=%.4f x=%.4f" % ["\n".join(lines).md5_text(), d.time, w.player_x]


func test_modes_0_1_2_match_head_runs() -> void:
	# The widths the modes hand to GameWorld (GameScreen: Display.logical_width()).
	check_eq([Display.logical_size_of(0), Display.logical_size_of(1), Display.logical_size_of(2)],
		[Vector2i(960, 720), Vector2i(1280, 720), Vector2i(1280, 720)], "logical canvas of modes 0–2")
	check_eq([Display.canvas_scale_of(0), Display.canvas_scale_of(1), Display.canvas_scale_of(2)], [1.0, 1.5, 2.0],
		"canvas scale of modes 0–2")
	for row: Array in HEAD_RUNS:
		check_eq(run_digest(row[1], row[2], row[3], row[4], row[0]), row[5],
			"W=%d level %d diff %d ship %d seed %d" % [row[0], row[1], row[2], row[3], row[4]])
	for row: Array in HEAD_DEMOS:
		check_eq(demo_digest(row[1], row[0]), row[2], "W=%d demo seed %d" % [row[0], row[1]])


func test_mode_tables_agree() -> void:
	check_eq(Settings.DISPLAY_MODES, Display.MODE_COUNT, "Settings and Display know the same number of modes")
	for m in Display.MODE_COUNT:
		check(Display.LOGICAL_SIZE.has(m) and Display.RENDER_SIZE.has(m) and Display.MODE_NAMES.has(m)
			and Display.MODE_INFO.has(m) and Display.MODE_SHORT.has(m), "mode %d in every table" % m)
		check_eq(Display.logical_size_of(m).y, 720, "mode %d: logical height 720" % m)
		if Display.is_wide_mode(m):
			var r: Vector2i = Display.RENDER_SIZE[m]
			var l := Display.logical_size_of(m)
			check(absf(float(r.x) / float(l.x) - float(r.y) / float(l.y)) < 1e-9, "mode %d: uniform scale" % m)
	check_eq([Display.logical_size_of(3).x, Display.logical_size_of(4).x], [1152, 1280], "widths of modes 3 / 4")


## Stack breaking (levels ≥ 10) near the right edge of the 1152 field: the covered upper figure turns after
## STACK_COVER_TIME, nobody leaves [50, 1102].
func test_stack_breaking_at_1152_right_edge() -> void:
	var w := GameWorld.new(12, 1, 0, 3, 5, W_DECK)
	w.auto_slots = false
	w.osc_amplitude = 0.0
	w.allow_enemy_fire = false
	w.start_combat()
	w.enemies.clear()
	var upper := w.add_enemy(0, 1060.0, -1.0)
	var lower := w.add_enemy(2, 1070.0, -1.0)
	for e in [upper, lower]:
		e.dir_timer = INF
		e.turn_age = 10.0
	var flipped_at := -1.0
	var t := 0.0
	while t < 1.5:
		w.run_steps(1)
		t += LevelData.SIM_STEP
		for e in w.enemies:
			check(e.x >= 50.0 - 1e-6 and e.x <= 1102.0 + 1e-6, "enemy x %.2f in [50, 1102]" % e.x)
		if flipped_at < 0.0 and upper.dir > 0.0:
			flipped_at = t
	check(flipped_at > 0.0, "the covered upper figure turned")
	check(absf(flipped_at - LevelData.STACK_COVER_TIME) < 0.05, "after ≈ %.2f s (%.3f)" % [LevelData.STACK_COVER_TIME, flipped_at])
	check_eq(lower.dir, -1.0, "the lower figure keeps its direction")


## Attract demo guarantees (§11.1) on more seeds at W = 1152: 15 ≤ length ≤ D ≤ 40 s, ≥ HITS_MIN hits before the
## single player hit, never completes the level, ship and enemies inside the 1152 limits.
func test_attract_demo_guarantees_at_1152_more_seeds() -> void:
	for s in 24:
		var d := AttractDirector.new(70001 + s * 7919)
		var w := d.make_world(W_DECK)
		check_eq(w.width, W_DECK, "demo world width")
		var hits := 0
		var hits_at_hit := -1
		var guard := 0
		while not d.is_over() and guard < int(AttractDirector.DURATION_MAX * 60.0) + 120:
			guard += 1
			w.events.clear()
			d.play(w, STEP)
			check(w.state != GameWorld.State.CLEARING and w.state != GameWorld.State.COMPLETE and not w.goal_met,
				"seed %d: never completes" % s)
			for ev in w.events:
				var ty := String(ev["type"])
				if AttractDirector.HIT_EVENTS.has(ty):
					hits += 1
				elif ty == "player_hit":
					check(hits_at_hit < 0, "seed %d: one player hit" % s)
					hits_at_hit = hits
			check(w.player_x >= 30.0 and w.player_x <= 1122.0, "seed %d: ship x %.1f" % [s, w.player_x])
			for e in w.enemies:
				check(e.x >= 50.0 - 1e-6 and e.x <= 1102.0 + 1e-6, "seed %d: enemy x %.2f" % [s, e.x])
			if not failures.is_empty():
				return
		check(d.is_over(), "seed %d: over" % s)
		check(hits_at_hit >= AttractDirector.HITS_MIN, "seed %d: %d hits before the ship hit" % [s, hits_at_hit])
		check(d.time >= AttractDirector.DURATION_MIN - 1e-6 and d.time <= d.duration + 1e-6
			and d.duration <= AttractDirector.DURATION_MAX + 1e-6, "seed %d: length %.2f / D %.2f" % [s, d.time, d.duration])
