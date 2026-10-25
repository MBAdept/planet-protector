extends TestBase
## Independent rules & regression review of the widescreen round (docs/SPEC.md §1, §5, §7, §11.2, §18).
## - Classic width (mode 0, W = 960) must be bit-for-bit the game of git 5c62dec: the hashes below were recorded by
##   running the same scenarios on a copy of that commit. Unlike test_wide_playfield's digests (event stream + final
##   state) they cover the COMPLETE world state after every update slice (player, every enemy incl. its timers,
##   shots, fireballs, explosions, slots, rank timers and the RNG state), raw float64 bytes, SHA-256.
## - W = 1280: an invariant sweep of the widened boundary rules (§18.1) over every level.
## - Settings back-compat of the display keys (§11.2).
## Failing tests mark bugs found by the review; the passing ones guard the verified behaviour.

const Autopilot := preload("res://scripts/game/autopilot.gd")
const STEP := 1.0 / 60.0


# --- Bit-for-bit classic width -------------------------------------------------------------------
static func _state_bytes(w: GameWorld) -> PackedByteArray:
	var a := PackedFloat64Array()
	a.append(w.player_x)
	a.append(float(w.state))
	a.append(float(w.lives))
	a.append(float(w.score_delta))
	a.append(float(w.spawned))
	a.append(float(w.destroyed))
	a.append(float(w.attempts))
	a.append(float(w.step_count))
	a.append(w.respawn_timer)
	a.append(float(w.rng.state & 0xFFFFFFFF))
	a.append(float((w.rng.state >> 32) & 0xFFFFFFFF))
	for t in w.rank_timers:
		a.append(t)
	for e in w.enemies:
		a.append_array([float(e.id), e.x, e.y, e.dir, e.scale, float(e.stage), 1.0 if e.armed else 0.0,
			e.fire_timer, e.dir_timer, e.turn_age, e.cover_time, e.age, float(e.lane)])
	for s in w.shots:
		a.append_array([float(s.id), s.x, s.y, s.offset])
	for b in w.bullets:
		a.append_array([float(b.id), b.x, b.y, b.vx, b.vy])
	for ex in w.explosions:
		a.append_array([float(ex.id), ex.x, ex.y, ex.age])
	for sl in w.slots:
		a.append_array([float(sl.alive), sl.refill])
	return a.to_byte_array()


static func _world(lvl: int, diff: int, ship: int, lives: int, rng_seed: int, width: float) -> GameWorld:
	if width < 0.0:
		return GameWorld.new(lvl, diff, ship, lives, rng_seed)
	return GameWorld.new(lvl, diff, ship, lives, rng_seed, width)


static func _hasher() -> HashingContext:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	return h


## Autoplay bot (Autopilot.decide), 1/60 s slices.
static func _bot_hash(lvl: int, diff: int, ship: int, rng_seed: int, lives: int, secs: float, width: float) -> Array:
	var w := _world(lvl, diff, ship, lives, rng_seed, width)
	var h := _hasher()
	var i := 0
	while i < int(secs * 60.0) and not w.is_finished():
		var d: Vector2 = Autopilot.decide(w)
		w.update(STEP, d.x, d.y > 0.5)
		h.update(_state_bytes(w))
		w.events.clear()
		i += 1
	return [i, h.finish().hex_encode()]


## Ship pinned to one wall with fire held (many lives: respawn at the start x, back to the wall).
static func _pin_hash(lvl: int, diff: int, ship: int, rng_seed: int, axis: float, secs: float, width: float) -> Array:
	var w := _world(lvl, diff, ship, 40, rng_seed, width)
	var h := _hasher()
	var i := 0
	while i < int(secs * 60.0) and not w.is_finished():
		w.update(STEP, axis, true)
		h.update(_state_bytes(w))
		w.events.clear()
		i += 1
	return [i, h.finish().hex_encode()]


## Irregular real-time slices (0.001–0.05 s) and irregular input.
static func _irregular_hash(lvl: int, diff: int, ship: int, rng_seed: int, secs: float, width: float) -> Array:
	var w := _world(lvl, diff, ship, 6, rng_seed, width)
	var r := RandomNumberGenerator.new()
	r.seed = rng_seed * 3 + 1
	var h := _hasher()
	var t := 0.0
	var i := 0
	var axis := 0.0
	while t < secs and not w.is_finished():
		var dt := r.randf_range(0.001, 0.05)
		if r.randf() < 0.08:
			axis = [-1.0, -0.5, 0.0, 0.35, 1.0][r.randi_range(0, 4)]
		w.update(dt, axis, r.randf() < 0.85)
		h.update(_state_bytes(w))
		w.events.clear()
		t += dt
		i += 1
	return [i, h.finish().hex_encode()]


## Hand-placed figures at the classic right limit: turning at 910, split children clamped, fireballs leaving at
## both sides (removal at x > 965 / x < −5).
static func _edges_hash(lvl: int, width: float) -> Array:
	var w := _world(lvl, 1, 4, 3, 77 + lvl, width)
	w.auto_slots = false
	w.invincible = true
	w.start_combat()
	var h := _hasher()
	var a := w.add_enemy(2, 905.0, 1.0)
	var b := w.add_enemy(1, 60.0, -1.0)
	w.add_enemy(0, 890.0, 1.0)
	w.run_steps(60)
	h.update(_state_bytes(w))
	w.events.clear()
	w.apply_hit(a)
	w.apply_hit(b)
	h.update(_state_bytes(w))
	w.events.clear()
	for k in 6:
		w.add_bullet(950.0 + k, 600.0, 190.5255888, 110.0)
		w.add_bullet(10.0 - k, 600.0, -190.5255888, 110.0)
	var i := 2
	for k in 600:
		w.update(STEP, 1.0 if (k / 90) % 2 == 0 else -1.0, false)
		h.update(_state_bytes(w))
		w.events.clear()
		i += 1
	return [i, h.finish().hex_encode()]


## A whole attract demo (director + world).
static func _demo_hash(rng_seed: int, width: float) -> Array:
	var d := AttractDirector.new(rng_seed)
	var w: GameWorld = d.make_world() if width < 0.0 else d.make_world(width)
	var h := _hasher()
	var i := 0
	while not d.is_over() and i < 60 * 45:
		d.play(w, STEP)
		h.update(_state_bytes(w))
		w.events.clear()
		i += 1
	return [i, h.finish().hex_encode()]


## Recorded on git 5c62dec (scratch copy of that commit, same scenario code): [slices, sha256 of all slice states].
const HEAD_HASHES := {
	"bot L12 d2 s0 seed4242": [7542, "f52f83157458019d0e8d2674886afc084ab5dda95340a9ca1db5ddca820fec7c"],
	"bot L20 d2 s2 seed4242": [2272, "9196612ed4c79ced28f1f475b78aa411eb9b0e97e579e79c3dda6a4bf700b12f"],
	"pin L10 left": [5400, "c8aeba6de2826fbd0d07399728ce352c53409988c0577559eddf80df15e4492e"],
	"pin L17 right": [5400, "e8a9f794951f30a2d07da9898c5334ae32e8a4aae3aca1951084c6a5cdfd722b"],
	"irregular L19": [1954, "59b017b2bc2a1e6777a5ee2a6c0743105ff9e777201c0c485d0c1ca682c40996"],
	"edges L7": [602, "2f84395434a79b92a221cfd6607ddcc76730d4c6a25dbf47633507ff291d3cda"],
	"demo 104729017": [1290, "111c86951b050bc7fd1f1ab225641a02288b1c4be34fbb4c4c2540516ccf0fb3"],
}


func _classic_hashes(width: float) -> Dictionary:
	return {
		"bot L12 d2 s0 seed4242": _bot_hash(12, 2, 0, 4242, 3, 150.0, width),
		"bot L20 d2 s2 seed4242": _bot_hash(20, 2, 2, 4242, 3, 150.0, width),
		"pin L10 left": _pin_hash(10, 2, 0, 510, -1.0, 90.0, width),
		"pin L17 right": _pin_hash(17, 1, 1, 517, 1.0, 90.0, width),
		"irregular L19": _irregular_hash(19, 1, 5, 1147, 80.0, width),
		"edges L7": _edges_hash(7, width),
		"demo 104729017": _demo_hash(104729017, width),
	}


## Mode 0 is the classic game bit for bit (SPEC §18): default width and an explicit width of 960 give exactly the
## per-slice world states of the code before the widescreen change.
func test_review_classic_width_matches_head_state_by_state() -> void:
	var got_default := _classic_hashes(-1.0)
	var got_960 := _classic_hashes(960.0)
	for k: String in HEAD_HASHES:
		check_eq(got_default[k], HEAD_HASHES[k], "%s (default width) vs git 5c62dec" % k)
		check_eq(got_960[k], HEAD_HASHES[k], "%s (width 960) vs git 5c62dec" % k)


# --- W = 1280 boundary rules (SPEC §18.1) ---------------------------------------------------------------
## Bot and wall-to-wall sweeps on every level at W = 1280; after every slice: ship x ∈ [30, 1250], start / respawn
## x = 640, every figure's centre (children included) ∈ [50, 1230], spawns within [50, 1230] and also beyond the
## classic 910, no fireball alive once its body is entirely off-screen (x − 5 > 1280 / x + 5 < 0) – and the field
## is really used (ship beyond 930, figures beyond 910, fireballs beyond 965).
func test_review_wide_boundary_invariants_all_levels() -> void:
	var seen := {"ship_right": -INF, "enemy_right": -INF, "bullet_right": -INF, "respawns": 0, "spawns_wide": 0}
	for lvl in range(1, 21):
		for policy in ["bot", "sweep"]:
			var w := GameWorld.new(lvl, lvl % 4, (lvl + 3) % 6, 30, 900 + lvl, 1280.0)
			check_eq(w.player_x, 640.0, "L%d: start x = W / 2" % lvl)
			for i in 60 * 30:
				var axis := 0.0
				var fire := true
				if policy == "bot":
					var d: Vector2 = Autopilot.decide(w)
					axis = d.x
					fire = d.y > 0.5
				else:
					axis = 1.0 if fposmod(float(i) / 60.0, 9.0) < 4.5 else -1.0
				w.update(STEP, axis, fire)
				seen["ship_right"] = maxf(seen["ship_right"], w.player_x)
				if w.player_x < 30.0 or w.player_x > 1250.0:
					check(false, "L%d %s: ship x %.3f outside [30, 1250]" % [lvl, policy, w.player_x])
				for e in w.enemies:
					seen["enemy_right"] = maxf(seen["enemy_right"], e.x)
					if e.x < 50.0 or e.x > 1230.0:
						check(false, "L%d %s: figure %d at x %.3f outside [50, 1230]" % [lvl, policy, e.id, e.x])
				for b in w.bullets:
					seen["bullet_right"] = maxf(seen["bullet_right"], b.x)
					if b.x - GameWorld.BULLET_HALF > 1280.0 or b.x + GameWorld.BULLET_HALF < 0.0:
						check(false, "L%d %s: fireball alive at x %.3f" % [lvl, policy, b.x])
				for ev in w.events:
					match String(ev["type"]):
						"player_respawn":
							seen["respawns"] += 1
							check_eq(float(ev["x"]), 640.0, "L%d %s: respawn x" % [lvl, policy])
						"enemy_spawned":
							var x := float(ev["x"])
							check(x >= 50.0 and x <= 1230.0, "L%d %s: spawn x %.3f" % [lvl, policy, x])
							if x > 910.0:
								seen["spawns_wide"] += 1
				w.events.clear()
				if not failures.is_empty() or w.is_finished():
					break
			if not failures.is_empty():
				return
	check(seen["ship_right"] == 1250.0, "the ship reaches the wide right limit (%s)" % str(seen["ship_right"]))
	check(seen["enemy_right"] == 1230.0, "figures reach the wide right limit (%s)" % str(seen["enemy_right"]))
	check(seen["bullet_right"] > 1271.0, "fireballs cross the wide fade band (%s)" % str(seen["bullet_right"]))
	check(seen["respawns"] > 0, "respawns happened")
	check(seen["spawns_wide"] > 0, "spawns beyond the classic limit")


# --- Settings back-compat (SPEC §11.2) ------------------------------------------------------------
const SCRATCH_CFG := "user://test_wide_review_settings.cfg"


## Exactly what version 1.3 (git 5c62dec) writes: no display keys.
const RELEASE_1_3_FILE := "[game]\n\ndifficulty=2\n\n[audio]\n\nmusic_on=false\nsfx_on=true\nmusic_volume=70\nsfx_volume=40\n\n[video]\n\nfullscreen=true\n"


func _with_scratch_settings(body: Callable) -> void:
	var saved := {"path": Settings.settings_path, "difficulty": Settings.difficulty, "music_on": Settings.music_on,
		"sfx_on": Settings.sfx_on, "fullscreen": Settings.fullscreen, "music_volume": Settings.music_volume,
		"sfx_volume": Settings.sfx_volume, "display_mode": Settings.display_mode,
		"display_chosen": Settings.display_chosen}
	Settings.settings_path = SCRATCH_CFG
	body.call()
	if FileAccess.file_exists(SCRATCH_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_CFG))
	Settings.settings_path = saved["path"]
	for k: String in saved:
		if k != "path":
			Settings.set(k, saved[k])


## A settings file of the previous release loads unchanged plus "classic, not chosen" (first-start screen once);
## the first save afterwards keeps every old value and adds the two display keys.
func test_review_release_1_3_settings_file_round_trip() -> void:
	_with_scratch_settings(func() -> void:
		var f := FileAccess.open(SCRATCH_CFG, FileAccess.WRITE)
		f.store_string(RELEASE_1_3_FILE)
		f.close()
		Settings.display_mode = 2
		Settings.display_chosen = true
		Settings.load_settings()
		check_eq([Settings.difficulty, Settings.music_on, Settings.sfx_on, Settings.music_volume, Settings.sfx_volume,
			Settings.fullscreen], [2, false, true, 70, 40, true], "1.3 options load unchanged")
		check_eq([Settings.display_mode, Settings.display_chosen], [0, false], "no display keys: classic, not chosen")
		check_eq(RunFlow.first_screen(Settings.display_chosen, false, false), "display_select",
			"an existing player sees the first-start choice once")
		Settings.set_display_mode(1)
		Settings.set_display_chosen(true)
		var cfg := ConfigFile.new()
		check_eq(cfg.load(SCRATCH_CFG), OK, "file written")
		check_eq([cfg.get_value("game", "difficulty"), cfg.get_value("audio", "music_on"),
			cfg.get_value("audio", "music_volume"), cfg.get_value("audio", "sfx_volume"),
			cfg.get_value("video", "fullscreen"), cfg.get_value("video", "display_mode"),
			cfg.get_value("video", "display_chosen")], [2, false, 70, 40, true, 1, true],
			"old values kept, display keys added")
		check_eq(RunFlow.first_screen(Settings.display_chosen, false, false), "title", "asked only once"))


## BUG (minor): SPEC §11.2 – `[video] display_mode` is "0–2, default 0; anything else reads as 0". A non-integer
## number in a damaged / hand-edited file is "anything else", but clean_display_mode() truncates it to a valid mode
## (1.5 → 1, 2.9 → 2, 0.5 → 0 by accident), so a damaged file can switch a player into a fullscreen 16:9 mode.
func test_review_fractional_display_mode_reads_as_classic() -> void:
	for v in [1.5, 2.9, 1.0001, 0.5]:
		check_eq(Settings.clean_display_mode(v), 0, "display_mode=%s is not one of 0, 1, 2 → classic (0)" % str(v))
	# Whole numbers stored as floats are still the mode they name.
	check_eq(Settings.clean_display_mode(1.0), 1, "1.0 → 1")
	check_eq(Settings.clean_display_mode(2), 2, "2 → 2")
	_with_scratch_settings(func() -> void:
		var cfg := ConfigFile.new()
		cfg.set_value("video", "display_mode", 1.5)
		cfg.set_value("video", "display_chosen", true)
		cfg.save(SCRATCH_CFG)
		Settings.load_settings()
		check_eq(Settings.display_mode, 0, "a damaged display_mode=1.5 loads as the classic mode"))
