extends TestBase
## Widescreen playfield (docs/SPEC.md §18.1): in the 16:9 display modes the logical canvas is 1280 px wide and
## the horizontal limits follow the screen edges with the classic margins (player [30, W − 30], start / respawn at
## W / 2, enemy centres [50, W − 50], bullets removed at 0 / W); everything else stays in px. The classic width
## 960 must stay bit-for-bit the game it was – the determinism tests compare against values recorded with the
## code before the widescreen change (git 5c62dec).

const GameScreenScript := preload("res://scripts/game/game_screen.gd")
const ProjectilesView := preload("res://scripts/game/projectiles_view.gd")
const Backdrop := preload("res://scripts/game/backdrop.gd")
const Autopilot := preload("res://scripts/game/autopilot.gd")

const W43 := 960.0
const W169 := 1280.0
const STEP := 1.0 / 60.0


## GameScreen without its view update (the view nodes never enter the tree here, see test_game_screen.gd).
class LogicOnlyScreen extends GameScreenScript:
	func _update_views(_dt: float, _game_dt: float) -> void:
		pass


# --- Helpers -------------------------------------------------------------------------------------
## A world in combat with no automatic spawns, no enemy fire and no oscillation.
func _world(level: int, width: float, rng_seed := 7) -> GameWorld:
	var w := GameWorld.new(level, 1, 0, 3, rng_seed, width)
	w.auto_slots = false
	w.osc_amplitude = 0.0
	w.allow_enemy_fire = false
	w.start_combat()
	w.events.clear()
	return w


## Forces a display mode for the test (Display.forced_mode = the --display override, never stored); returns the
## previous value for _restore_display().
func _force_display(m: int) -> Variant:
	var before: Variant = Display.get("forced_mode")
	Display.set("forced_mode", m)
	return before


func _restore_display(before: Variant) -> void:
	Display.set("forced_mode", before if before != null else -1)


# --- Limits (LevelData / GameWorld) ----------------------------------------------------------------
func test_limits_follow_the_right_edge() -> void:
	# Classic width: exactly the rule constants (the old code used them directly).
	check_eq(LevelData.player_max_x(W43), LevelData.PLAYER_MAX_X, "player max x at 960")
	check_eq(LevelData.player_start_x(W43), LevelData.PLAYER_START_X, "player start at 960")
	check_eq(LevelData.enemy_max_x(W43), LevelData.ENEMY_MAX_X, "enemy max x at 960")
	check_eq(LevelData.player_max_x(), 930.0, "default width is the classic one")
	check_eq(GameWorld.min_x(1.0), 50.0)
	check_eq(GameWorld.max_x(1.0), 910.0)
	# 16:9: same margins to the right edge, the left limits do not move.
	check_eq(LevelData.player_max_x(W169), 1250.0, "player max x at 1280")
	check_eq(LevelData.player_start_x(W169), 640.0, "player start at 1280")
	check_eq(LevelData.enemy_max_x(W169), 1230.0, "enemy max x at 1280")
	for s in [1.0, 0.45, 0.40]:
		check_eq(GameWorld.min_x(s, W169), 50.0, "enemy min x at 1280 (scale %.2f)" % s)
		check_eq(GameWorld.max_x(s, W169), 1230.0, "enemy max x at 1280 (scale %.2f)" % s)


func test_world_width_parameter() -> void:
	var classic := GameWorld.new(1, 1, 0, 3, 1)
	check_eq(classic.width, W43, "default width 960")
	check_eq(classic.player_x, 480.0, "classic start x")
	var wide := GameWorld.new(1, 1, 0, 3, 1, W169)
	check_eq(wide.width, W169)
	check_eq(wide.player_x, 640.0, "the ship starts at W / 2")
	check_eq(GameWorld.new(1, 1, 0, 3, 1, 500.0).width, W43, "never narrower than the classic playfield")


func test_player_clamp_and_respawn_wide() -> void:
	for width in [W43, W169]:
		var w := _world(1, width)
		w.run_game_seconds(5.0, 1.0)
		check_eq(w.player_x, width - 30.0, "W=%d: right clamp" % width)
		w.run_game_seconds(5.0, -1.0)
		check_eq(w.player_x, 30.0, "W=%d: left clamp" % width)
		# A hit far right: respawn at the centre of the playfield.
		w.run_game_seconds(5.0, 1.0)
		w.add_bullet(w.player_x, LevelData.PLAYER_Y, 0.0, 0.0)
		w.run_steps(1)
		check_eq(w.state, GameWorld.State.RESPAWN, "W=%d: hit" % width)
		var guard := 0
		while w.state == GameWorld.State.RESPAWN and guard < 2000:
			w.run_steps(1)
			guard += 1
		check_eq(w.state, GameWorld.State.PLAYING, "W=%d: respawned" % width)
		check_eq(w.player_x, width * 0.5, "W=%d: respawn at W / 2" % width)
		var ev: Dictionary = w.events.filter(func(e: Dictionary) -> bool: return e["type"] == "player_respawn")[0]
		check_eq(float(ev["x"]), width * 0.5, "W=%d: respawn event x" % width)


# --- Enemies ---------------------------------------------------------------------------------------
func test_enemies_turn_at_the_wide_limits() -> void:
	for lvl in [1, 10, 17]:
		var w := _world(lvl, W169)
		var e := w.add_enemy(1, 640.0, 1.0)
		e.dir_timer = INF   # no random direction changes (levels ≥ 10): it flies wall to wall
		var lo := INF
		var hi := -INF
		for i in int(40.0 / LevelData.SIM_STEP):
			w.run_steps(1)
			lo = minf(lo, e.x)
			hi = maxf(hi, e.x)
		check_eq(hi, 1230.0, "level %d: rightmost centre at 1280" % lvl)
		check_eq(lo, 50.0, "level %d: leftmost centre at 1280" % lvl)
	# Children too (split level 7: 40 %).
	var c := _world(7, W169)
	var k := c.add_enemy(2, 1200.0, 1.0, LevelData.child_scale(7), true)
	k.dir_timer = INF
	var khi := -INF
	for i in int(5.0 / LevelData.SIM_STEP):
		c.run_steps(1)
		khi = maxf(khi, k.x)
	check_eq(khi, 1230.0, "child turns at 1230")


func test_child_clamping_at_the_wide_right_limit() -> void:
	for lvl in [7, 8, 12]:
		var w := _world(lvl, W169)
		var e := w.add_enemy(2, 1230.0)
		w.apply_hit(e)
		check_eq(w.enemies.size(), 2, "level %d: split" % lvl)
		check_eq(w.enemies[0].x, 1206.0, "level %d: left child at x − 24" % lvl)
		check_eq(w.enemies[1].x, 1230.0, "level %d: right child clamped to W − 50" % lvl)
		# At 960 the same right-edge figure would be clamped at 910 – a wide one far right of it is not.
		var m := _world(lvl, W169)
		var f := m.add_enemy(2, 1000.0)
		m.apply_hit(f)
		check_eq([m.enemies[0].x, m.enemies[1].x], [976.0, 1024.0], "level %d: no clamp at x = 1000 (wide)" % lvl)


## Spawn column search covers [50, W − 50]: with blockers on the other lanes everywhere left of 1150, the new
## original appears in the free column on the far right – a range that does not exist at 960.
func test_spawn_range_covers_the_wide_field() -> void:
	for s in [1, 2, 3, 4, 5, 6, 7, 8]:
		var w := GameWorld.new(1, 1, 0, 3, s, W169)
		for x in [160.0, 380.0, 600.0, 820.0, 1040.0]:
			w.add_enemy(1 if int(x) % 2 == 0 else 2, x)
		w.slots.resize(1)   # only the top-lane slot spawns
		w.start_combat()
		var spawned: Array = w.events.filter(func(e: Dictionary) -> bool: return e["type"] == "enemy_spawned")
		check_eq(spawned.size(), 1, "seed %d: one original" % s)
		var x := float(spawned[0]["x"])
		check(x >= 1150.0 and x <= 1230.0, "seed %d: spawn x %.1f in the free column [1150, 1230]" % [s, x])
	# Unblocked: spawns use the whole width (some beyond the classic limit 910), never beyond 1230.
	var beyond := 0
	for s in 60:
		var w := GameWorld.new(17, 1, 0, 3, 1000 + s, W169)
		w.start_combat()
		for e in w.enemies:
			check(e.x >= 50.0 and e.x <= 1230.0, "seed %d: spawn %.1f within [50, 1230]" % [s, e.x])
			if e.x > 910.0:
				beyond += 1
	check(beyond > 20, "spawns on the widened part of the field (%d)" % beyond)


# --- Enemy bullets ---------------------------------------------------------------------------------
func test_bullets_removed_at_the_wide_side_edges() -> void:
	for width in [W43, W169]:
		var w := _world(17, width)
		w.invincible = true
		var r := w.add_bullet(width - 60.0, 300.0, LevelData.ENEMY_BULLET_DIAG_B, LevelData.ENEMY_BULLET_DIAG_A)
		var last := r.x
		while w.bullets.has(r):
			last = r.x
			w.run_steps(1)
		check(last - GameWorld.BULLET_HALF <= width and last > width, "W=%d: removed once off-screen (last x %.2f)" % [width, last])
		var l := w.add_bullet(60.0, 300.0, -LevelData.ENEMY_BULLET_DIAG_B, LevelData.ENEMY_BULLET_DIAG_A)
		var last_l := l.x
		while w.bullets.has(l):
			last_l = l.x
			w.run_steps(1)
		check(last_l < 0.0 and last_l + GameWorld.BULLET_HALF >= 0.0, "W=%d: left edge (last x %.2f)" % [width, last_l])
	# A wide-field bullet at x = 1000 is still on screen (it would be gone at 960).
	var ww := _world(17, W169)
	var b := ww.add_bullet(1000.0, 300.0, 0.0, LevelData.ENEMY_BULLET_SPEED)
	ww.run_steps(1)
	check(ww.bullets.has(b), "x = 1000 is on the wide screen")


func test_side_fade_follows_the_width() -> void:
	var h := GameWorld.BULLET_HALF
	check_eq(ProjectilesView.side_fade(1271.0, 190.0, W169), 1.0, "still dangerous at 1250 + 21: fully visible")
	check(ProjectilesView.side_fade(1280.0 + h - 0.5, 190.0, W169) < 0.1, "faded out at the removal point")
	check_eq(ProjectilesView.side_fade(1000.0, 190.0, W169), 1.0, "no fade inside the wide field")
	check_eq(ProjectilesView.side_fade(951.0, 190.0, W43), 1.0, "classic band unchanged")
	check(ProjectilesView.side_fade(964.5, 190.0, W43) < 0.1, "classic removal point unchanged")
	check_eq(ProjectilesView.side_fade(9.0, -190.0, W169), 1.0, "left band is the same at every width")


## Review finding: the drawn fade must follow the width of the world being drawn (world.width), not the global
## display mode – e.g. dev/gallery.gd draws 960 worlds while a 16:9 mode may be stored. Both views below are drawn
## in a forced 16:9 session; the 960 world must still fade at its own right edge (965), the 1280 world at 1285.
func test_drawn_fade_uses_the_world_width_not_the_display_mode() -> void:
	var before: Variant = _force_display(1)
	check(Display.is_wide(), "display forced to 16:9")
	check(ProjectilesView.side_fade(964.5, 190.0) < 0.1, "default width is the classic 960, independent of Display")
	for wd in [W43, W169]:
		var w := _world(17, wd)
		var view := ProjectilesView.new()
		view.mode = ProjectilesView.Mode.BULLETS
		view.world = w
		var near_edge := w.add_bullet(wd + GameWorld.BULLET_HALF - 0.5, 300.0, 190.0, 110.0)
		var dangerous := w.add_bullet(wd - 9.0, 300.0, 190.0, 110.0)
		var inside := w.add_bullet(wd - 300.0, 300.0, 190.0, 110.0)
		check(view.fireball_alpha(near_edge) < 0.1, "W=%d: faded out just before its removal point" % wd)
		check_eq(view.fireball_alpha(dangerous), 1.0, "W=%d: still dangerous at W − 9: fully visible" % wd)
		check_eq(view.fireball_alpha(inside), 1.0, "W=%d: no fade inside the field" % wd)
		check_eq(view.fireball_alpha(near_edge), ProjectilesView.side_fade(near_edge.x, near_edge.vx, wd),
			"W=%d: drawn alpha = side_fade with the world's width" % wd)
		view.free()
	_restore_display(before)


# --- Scenery -------------------------------------------------------------------------------------
func test_planet_anchored_top_right() -> void:
	for lvl in range(1, 21):
		var c43 := Backdrop.planet_center(lvl)
		var c169 := Backdrop.planet_center(lvl, W169)
		check_eq(c169.x - c43.x, 320.0, "level %d: same distance to the right edge" % lvl)
		check_eq(c169.y, c43.y, "level %d: same height" % lvl)
		check(c169.x + LevelData.planet_diameter(lvl) * 0.5 <= W169 - Backdrop.PLANET_RIGHT_MARGIN + 1e-6,
			"level %d: sphere on screen" % lvl)


# --- Bots ------------------------------------------------------------------------------------------
## The dev autoplay bot plays the wide field: it completes levels, uses the widened part and stays in range.
func test_autoplay_bot_plays_the_wide_field() -> void:
	for lvl in [1, 7, 14]:
		var w := GameWorld.new(lvl, 1, lvl % 6, 3, 31 + lvl, W169)
		w.invincible = true
		var right := -INF
		var guard := 0
		while not w.is_finished() and guard < 60 * 300:
			var d: Vector2 = Autopilot.decide(w)
			w.update(STEP, d.x, d.y > 0.5)
			right = maxf(right, w.player_x)
			check(w.player_x >= 30.0 and w.player_x <= 1250.0, "level %d: ship x %.1f in range" % [lvl, w.player_x])
			guard += 1
			if not failures.is_empty():
				return
		check_eq(w.state, GameWorld.State.COMPLETE, "level %d completed by the bot at 1280" % lvl)
		check(right > 930.0, "level %d: the bot uses the widened field (max x %.1f)" % [lvl, right])


func test_escape_set_spans_the_wide_range() -> void:
	var w := _world(17, W169)
	check_eq(Autopilot._escape_set(w), PackedFloat64Array([30.0, 1250.0]), "no fireball: the whole wide range")
	check(Autopilot.can_escape(w))
	# A salvo coming down at the right wall: positions there can no longer escape; the ship must go left.
	w.player_x = 1240.0
	for i in 12:
		w.add_bullet(1150.0 + i * 9.0, 560.0)
	var s := Autopilot._escape_set(w)
	check(s.size() == 2 and s[0] == 30.0 and s[1] < 1250.0 and s[1] > 930.0,
		"escape set within the wide range, its right end blocked: %s" % str(s))
	var to := Autopilot.demo(w, false, false)
	check(to.x < 0.0, "the demo bot dodges to the left (axis %.2f)" % to.x)


## Attract mode at 1280 (SPEC §11.1 / §18.1): the same choreography guarantees as at 960.
func _simulate_demo(d: AttractDirector, tag: String) -> void:
	var w := d.make_world(W169)
	check_eq(w.width, W169, "%s: demo world is wide" % tag)
	var guard := 0
	var hits := 0
	var hits_at_hit := -1
	var fired_after_hits := 0
	var through := {}
	var right := -INF
	while not d.is_over() and guard < int(AttractDirector.DURATION_MAX * 60.0) + 120:
		guard += 1
		w.events.clear()
		d.play(w, STEP)
		right = maxf(right, w.player_x)
		check(w.state != GameWorld.State.CLEARING and w.state != GameWorld.State.COMPLETE and not w.goal_met,
			"%s: the level is never completed" % tag)
		for ev in w.events:
			var ty := String(ev["type"])
			if AttractDirector.HIT_EVENTS.has(ty):
				hits += 1
			elif ty == "shot_fired" and hits >= d.hits_wanted:
				fired_after_hits += 1
			elif ty == "player_hit":
				check(hits_at_hit < 0, "%s: the ship is hit only once" % tag)
				hits_at_hit = hits
		if w.player_alive and w.invincible:
			for b in w.bullets:
				if absf(b.x - w.player_x) < LevelData.PLAYER_HIT_DX and absf(b.y - LevelData.PLAYER_Y) < LevelData.PLAYER_HIT_DY:
					through[b.id] = true
		check(w.player_x >= 30.0 and w.player_x <= 1250.0, "%s: ship in range" % tag)
		if not failures.is_empty():
			return
	check(d.is_over(), "%s: the demo ends" % tag)
	check_eq(fired_after_hits, 0, "%s: no salvo after %d hits" % [tag, d.hits_wanted])
	check(hits_at_hit >= AttractDirector.HITS_MIN, "%s: %d hits landed before the ship was hit" % [tag, hits_at_hit])
	check_eq(through.size(), 0, "%s: fireballs through the invincible ship" % tag)
	check(d.hit_time >= d.t_vulnerable - 1e-6, "%s: hit not before the window" % tag)
	check(d.hit_time <= d.t_die + AttractDirector.BOT_SLICE + 1e-6, "%s: hit %.3f by t_die %.3f" % [tag, d.hit_time, d.t_die])
	check(d.time >= AttractDirector.DURATION_MIN - 1e-6 and d.time <= d.duration + 1e-6,
		"%s: total %.3f s within [15, D = %.3f]" % [tag, d.time, d.duration])
	check_eq(w.state, GameWorld.State.GAME_OVER, "%s: the player explosion has finished at the end" % tag)


func test_attract_demos_on_the_wide_field() -> void:
	for s in range(1, 13):
		_simulate_demo(AttractDirector.new(s * 7919), "W=1280 seed %d" % (s * 7919))
		if not failures.is_empty():
			return
	for lvl in [1, 14, 20]:
		for dur in [AttractDirector.DURATION_MIN, AttractDirector.DURATION_MAX]:
			var d := AttractDirector.new(1234 + lvl, lvl)
			d.set_duration(dur)
			_simulate_demo(d, "W=1280 level %d D=%.0f" % [lvl, dur])


# --- GameScreen ------------------------------------------------------------------------------------
func test_game_screen_takes_the_display_width() -> void:
	if (InputRouter.get("_down") as Dictionary).is_empty():
		InputRouter._ready()
	var before: Variant = _force_display(1)
	check(Display.is_wide(), "Display.forced_mode = 1 makes the display wide")
	check_eq(Display.logical_width(), W169)
	Run.start_new(1, 0, 3)
	Run.dev_flags = {"invincible": true, "autoplay": true}
	var gs: Node2D = LogicOnlyScreen.new()
	gs.setup({"level": 3})
	gs._ready()
	var w: GameWorld = gs.get("world")
	check_eq(gs.get("width"), W169, "screen width")
	check_eq(w.width, W169, "world width")
	check_eq(w.player_x, 640.0, "ship starts at W / 2")
	var hud: Node2D = gs.get("_hud")
	check_eq(hud.get("width"), W169, "HUD width")
	var clip: Control = (gs.get("_bullets") as Node).get_parent()
	check_eq(clip.size, Vector2(W169, LevelData.GROUND_Y), "fireball clip spans the wide field")
	var guard := 0
	while not w.is_finished() and guard < 1200:
		gs._process(0.25)
		guard += 1
	check_eq(w.state, GameWorld.State.COMPLETE, "autoplay completes level 3 on the wide screen")
	gs.free()
	# Attract mode builds its demo world with the same width.
	var ds: Node2D = LogicOnlyScreen.new()
	ds.setup({"attract": {"seed": 4242, "level": 5}})
	ds._ready()
	check_eq((ds.get("world") as GameWorld).width, W169, "demo world width")
	ds.free()
	_restore_display(before)
	Run.dev_flags = {}
	AudioManager.stop_music()
	# Back in the classic mode: 960 as before.
	check(not Display.is_wide(), "restored")
	var cs: Node2D = LogicOnlyScreen.new()
	cs.setup({"level": 1})
	cs._ready()
	check_eq((cs.get("world") as GameWorld).width, W43, "classic world width")
	cs.free()
	AudioManager.stop_music()


# --- Determinism of the classic width (compared with the code before the widescreen change) -----------
## Plays a scenario and returns a digest: md5 of the full event stream (full float precision) and the final state.
## policy: "bot" = Autopilot.decide, "sweep" = scripted input (full sweeps into both walls, fire 3 of 4 s).
static func digest(level: int, diff: int, ship: int, rng_seed: int, lives: int, invincible: bool, policy: String,
		seconds: float, width: float = -1.0) -> Dictionary:
	var w: GameWorld
	if width < 0.0:
		w = GameWorld.new(level, diff, ship, lives, rng_seed)
	else:
		w = GameWorld.new(level, diff, ship, lives, rng_seed, width)
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


## A whole attract demo (director + world at the default width): md5 of its event stream and its outcome.
static func demo_digest(rng_seed: int) -> Dictionary:
	var d := AttractDirector.new(rng_seed)
	var w := d.make_world()
	var lines := PackedStringArray()
	var i := 0
	while not d.is_over() and i < 60 * 45:
		w.events.clear()
		d.play(w, 1.0 / 60.0)
		for ev in w.events:
			lines.append("%d %s" % [i, JSON.stringify(ev, "", true, true)])
		i += 1
	return {"events": lines.size(), "md5": "\n".join(lines).md5_text(), "hits": d.hits, "hit_time": d.hit_time,
		"withdrawn": d.salvos_withdrawn, "time": d.time, "player_x": w.player_x}


## Expected digests recorded with the code BEFORE the widescreen change (git 5c62dec, the same digest functions
## run on a copy of that tree). The md5 covers every event with full float precision.
## [level, difficulty, ship, seed, lives, invincible, policy, game seconds] → digest
const EXPECTED := [
	[[3, 1, 2, 4242, 3, true, "bot", 40.0], {"destroyed": 12,"enemies_md5": "d751713988987e9331980363e24189ce","events": 192,"lives": 3,"md5": "9adf6e744291f0ccbc4386f98959f9d2","player_x": 478.9676834012277,"score": 220,"state": 4,"steps": 7471}],
	[[11, 2, 4, 777, 3, true, "sweep", 30.0], {"destroyed": 3,"enemies_md5": "7a5d007274f49645c137455f63c187ed","events": 449,"lives": 3,"md5": "3b4a50bbb4489205d1f6d6752510668a","player_x": 870.0000000000066,"score": 120,"state": 1,"steps": 8121}],
	[[17, 3, 1, 99, 3, false, "bot", 40.0], {"destroyed": 34,"enemies_md5": "c8e9ea4ce2c0e76a613fb71f9b2c2745","events": 652,"lives": 1,"md5": "f7baa1119ae347b659fcdc41ecebb0ec","player_x": 210.61863940277357,"score": 4080,"state": 1,"steps": 13201}],
	[[8, 0, 3, 1234, 5, true, "sweep", 30.0], {"destroyed": 4,"enemies_md5": "1adce3f28c6c397a142e81aae2208570","events": 100,"lives": 5,"md5": "31678983718e56565223bc5ba911069d","player_x": 730.000000000003,"score": 100,"state": 1,"steps": 6768}],
	[[20, 1, 5, 31337, 3, false, "sweep", 30.0], {"destroyed": 0,"enemies_md5": "0a8137f2f55fbf5eb6d678c271856ea2","events": 218,"lives": 0,"md5": "63207e2460a6fcece3af1165fbe3d123","player_x": 849.7916666666646,"score": 0,"state": 6,"steps": 4159}],
	[[13, 1, 0, 55, 3, true, "bot", 40.0], {"destroyed": 19,"enemies_md5": "d751713988987e9331980363e24189ce","events": 59,"lives": 3,"md5": "30ddaf0f51cfc92d4402d10b1ff5e34d","player_x": 863.5809702679705,"score": 0,"state": 1,"steps": 9168}],
	[[15, 1, 2, 2024, 3, true, "bot", 40.0], {"destroyed": 4,"enemies_md5": "4b212c6933bf9290012d03dde677adb7","events": 404,"lives": 3,"md5": "5761a62cda971746ad764cf2e06bc457","player_x": 196.98819833460425,"score": 400,"state": 1,"steps": 9168}],
]
## attract seed → demo digest
const EXPECTED_DEMOS := [
	[7919, {"events": 106,"hit_time": 16.683333333333668,"hits": 5,"md5": "cd9005899cf488afcde158931d2f20a3","player_x": 777.0087512192671,"time": 18.58333333333356,"withdrawn": 0}],
	[39595, {"events": 198,"hit_time": 26.649999999999768,"hits": 3,"md5": "68103f7ff5783b9582713340f265cf53","player_x": 461.45676435938896,"time": 28.54999999999966,"withdrawn": 0}],
	[451383, {"events": 553,"hit_time": 22.483333333333338,"hits": 4,"md5": "cd9155f7da9d37a9a14fdf354776fc66","player_x": 638.0685301303935,"time": 24.38333333333323,"withdrawn": 0}],
]


func _check_digest(got: Dictionary, want: Dictionary, tag: String) -> void:
	check_eq(got.keys().size(), want.keys().size(), "%s: digest keys" % tag)
	for k: String in want:
		if want[k] is float:
			check_near(float(got.get(k, NAN)), want[k], 1e-9, "%s: %s" % [tag, k])
		else:
			check_eq(got.get(k), want[k], "%s: %s" % [tag, k])


func test_classic_width_is_bit_for_bit_the_old_game() -> void:
	for row: Array in EXPECTED:
		var a: Array = row[0]
		_check_digest(digest(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7]), row[1], "%s default width" % str(a))
		_check_digest(digest(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], W43), row[1], "%s width 960" % str(a))
		if not failures.is_empty():
			return


func test_classic_attract_demos_are_the_old_ones() -> void:
	for row: Array in EXPECTED_DEMOS:
		_check_digest(demo_digest(row[0]), row[1], "demo seed %d" % row[0])


## The wide field changes the game only where the limits matter: a 1280 world with the same seed differs.
func test_wide_width_is_a_different_field() -> void:
	var a := digest(17, 1, 2, 4242, 3, true, "sweep", 20.0)
	var b := digest(17, 1, 2, 4242, 3, true, "sweep", 20.0, W169)
	check(a["md5"] != b["md5"], "different event stream at 1280")
