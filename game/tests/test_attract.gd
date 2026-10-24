extends TestBase
## Attract mode / demo run (docs/SPEC.md §11.1): title idle timer, the AttractDirector choreography (level,
## duration and hit bounds over many seeds, simulated headless with a real GameWorld), the GameScreen in attract
## mode (Run / Settings / audio untouched, any input exits) and the hand-over back to the title.
## Like the other screen tests these run before the SceneTree is live: screens are driven by hand, the
## InputRouter is stepped manually and every key that is pressed is released again.

const GameScreenScript := preload("res://scripts/game/game_screen.gd")
const TitleScreen := preload("res://scripts/screens/title_screen.gd")
const Hud := preload("res://scripts/game/hud.gd")
const MainScript := preload("res://scripts/main.gd")
const AudioManagerScript := preload("res://scripts/autoload/audio_manager.gd")
const Autopilot := preload("res://scripts/game/autopilot.gd")

const STEP := 1.0 / 60.0


## GameScreen without its view update (the view nodes never enter the tree here, see test_game_screen.gd).
class LogicOnlyScreen extends GameScreenScript:
	func _update_views(_dt: float, _game_dt: float) -> void:
		pass


## Records every call the GameScreen makes on its sound output.
class AudioSpy extends AudioManagerScript:
	var calls: Array[String] = []

	func play_title_music() -> void:
		calls.append("play_title_music")

	func play_game_music() -> void:
		calls.append("play_game_music")

	func stop_music() -> void:
		calls.append("stop_music")

	func set_game_music_suspended(suspended: bool) -> void:
		calls.append("set_game_music_suspended(%s)" % suspended)

	func reset_bass(level: int) -> void:
		calls.append("reset_bass(%d)" % level)

	func notify_enemy_destroyed() -> void:
		calls.append("notify_enemy_destroyed")

	func play_sfx(sfx_name: String, _volume_db: float = 0.0, _pitch: float = 1.0) -> void:
		calls.append("sfx:" + sfx_name)


# --- Helpers -------------------------------------------------------------------------------------
func _router_init() -> void:
	if (InputRouter.get("_down") as Dictionary).is_empty():
		InputRouter._ready()
	InputRouter.set_text_mode(false)
	_router_step()


func _router_step(dt: float = STEP) -> void:
	Input.flush_buffered_events()
	InputRouter._process(dt)


func _send(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _key_event(code: Key, pressed: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	return ev


func _key(code: Key, pressed: bool) -> void:
	_send(_key_event(code, pressed))


func _joy_button(button: JoyButton, pressed: bool) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = button
	ev.pressed = pressed
	return ev


func _joy_motion(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.device = 0
	ev.axis = axis
	ev.axis_value = value
	return ev


## Runs a title screen for `seconds` (router stepped every frame); returns the finished result ("" = none).
func _run_title(title: Node, seconds: float, got: Array[String]) -> void:
	var t := 0.0
	while t < seconds - 1e-9 and got.is_empty():
		_router_step()
		title._process(STEP)
		t += STEP


func _attract_screen(seed_value: int, lvl: int = 0) -> Node2D:
	if (InputRouter.get("_down") as Dictionary).is_empty():
		InputRouter._ready()
	var gs: Node2D = LogicOnlyScreen.new()
	gs.setup({"attract": {"seed": seed_value, "level": lvl}})
	return gs


## Simulates a whole demo headless (director + GameWorld, 60 fps frames) and checks the choreography. The world
## events are followed in EVENT order (a salvo in the same sub-step as the N-th hit counts as after it).
## Returns the director (finished) for further checks.
func _simulate(d: AttractDirector, tag: String) -> AttractDirector:
	var w := d.make_world()
	var guard := 0
	var hits := 0
	var hits_at_hit := -1
	var fired_after_hits := 0
	var through := {}
	while not d.is_over() and guard < int(AttractDirector.DURATION_MAX * 60.0) + 120:
		guard += 1
		w.events.clear()
		d.play(w, STEP)
		if d.time < d.t_vulnerable - 1e-6:
			check(w.invincible, "%s: invincible before t_vulnerable (t=%.3f)" % [tag, d.time])
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
		# No fireball may pass through the ship while it is invincible (it would look like a bug).
		if w.player_alive and w.invincible:
			for b in w.bullets:
				if absf(b.x - w.player_x) < LevelData.PLAYER_HIT_DX and absf(b.y - LevelData.PLAYER_Y) < LevelData.PLAYER_HIT_DY:
					through[b.id] = true
	check(d.is_over(), "%s: the demo ends" % tag)
	check_eq(hits, d.hits, "%s: the director counts the hits" % tag)
	check_eq(fired_after_hits, 0, "%s: no salvo after %d hits" % [tag, d.hits_wanted])
	check(hits_at_hit >= AttractDirector.HITS_MIN, "%s: %d hits landed before the ship was hit" % [tag, hits_at_hit])
	check_eq(through.size(), 0, "%s: fireballs through the invincible ship" % tag)
	check(d.hit_time >= d.t_vulnerable - 1e-6, "%s: hit %.3f not before the window %.3f" % [tag, d.hit_time, d.t_vulnerable])
	check(d.hit_time >= AttractDirector.DURATION_MIN - AttractDirector.HIT_TO_END - 1e-6, "%s: hit not before 13.1 s" % tag)
	check(d.hit_time <= d.t_die + AttractDirector.BOT_SLICE + 1e-6, "%s: hit %.3f by t_die %.3f" % [tag, d.hit_time, d.t_die])
	check(d.time >= AttractDirector.DURATION_MIN - 1e-6 and d.time <= AttractDirector.DURATION_MAX + 1e-6,
		"%s: total %.3f s within [15, 40]" % [tag, d.time])
	check(d.time <= d.duration + 1e-6, "%s: total %.3f s within D = %.3f" % [tag, d.time, d.duration])
	check_eq(w.state, GameWorld.State.GAME_OVER, "%s: the player explosion has finished at the end" % tag)
	check_eq(w.lives, 0, "%s: the one life is gone" % tag)
	check(w.destroyed < w.total, "%s: not all enemies destroyed" % tag)
	return d


# --- §11.1 input classification -----------------------------------------------------------------
func test_player_input_events() -> void:
	check(AttractDirector.is_player_input(_key_event(KEY_K, true)), "key press")
	var echo := _key_event(KEY_K, true)
	echo.echo = true
	check(AttractDirector.is_player_input(echo), "held key (auto-repeat)")
	check(not AttractDirector.is_player_input(_key_event(KEY_K, false)), "key release")
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	check(AttractDirector.is_player_input(mb), "mouse button")
	check(not AttractDirector.is_player_input(InputEventMouseMotion.new()), "mouse motion does not count")
	check(AttractDirector.is_player_input(_joy_button(JOY_BUTTON_A, true)), "joypad button")
	check(AttractDirector.is_player_input(_joy_button(JOY_BUTTON_DPAD_LEFT, true)), "D-pad")
	check(not AttractDirector.is_player_input(_joy_button(JOY_BUTTON_A, false)), "joypad button release")
	check(AttractDirector.is_player_input(_joy_motion(JOY_AXIS_LEFT_X, 0.7)), "left stick 0.7")
	check(AttractDirector.is_player_input(_joy_motion(JOY_AXIS_LEFT_Y, -0.8)), "left stick up")
	check(AttractDirector.is_player_input(_joy_motion(JOY_AXIS_RIGHT_X, -0.6)), "right stick")
	check(not AttractDirector.is_player_input(_joy_motion(JOY_AXIS_LEFT_X, 0.45)), "stick 0.45 is within the threshold")
	check(not AttractDirector.is_player_input(_joy_motion(JOY_AXIS_TRIGGER_LEFT, 1.0)), "triggers do not count")


# --- §11.1 title idle timer ---------------------------------------------------------------------
func test_title_idle_timer_triggers_attract_and_input_resets_it() -> void:
	_router_init()
	check_eq(AttractDirector.IDLE_TIME, 90.0, "default idle time")
	var title := TitleScreen.new()
	title.setup({"attract_after": 2.0})
	var got: Array[String] = []
	title.finished.connect(func(r: String, _d: Dictionary) -> void: got.append(r))
	title._ready()
	_run_title(title, 1.5, got)
	check(got.is_empty(), "no demo before the idle time")
	# A held key (polled) resets the timer.
	_key(KEY_K, true)
	_run_title(title, 0.2, got)
	check(title.idle < 1e-6, "held key keeps the timer at 0")
	_key(KEY_K, false)
	_run_title(title, 1.8, got)
	check(got.is_empty(), "the key press restarted the 2 s timer")
	# An input EVENT (here a stick nudge delivered through _input) resets it as well.
	title._input(_joy_motion(JOY_AXIS_RIGHT_Y, 0.9))
	check(title.idle < 1e-6, "stick event resets the timer")
	_run_title(title, 1.9, got)
	check(got.is_empty(), "still idle for less than 2 s")
	# Mouse motion is no player input.
	title._input(InputEventMouseMotion.new())
	_run_title(title, 0.3, got)
	check_eq(got, ["attract"] as Array[String], "after 2 s without input the title hands over to the demo")
	title.free()


func test_title_idle_default_and_held_joypad_button() -> void:
	_router_init()
	var title := TitleScreen.new()
	title.setup({})
	var got: Array[String] = []
	title.finished.connect(func(r: String, _d: Dictionary) -> void: got.append(r))
	title._ready()
	_send(_joy_button(JOY_BUTTON_X, true))
	_run_title(title, 0.5, got)
	check(title.idle < 1e-6, "held joypad button keeps the timer at 0")
	_send(_joy_button(JOY_BUTTON_X, false))
	_run_title(title, 1.0, got)
	check_near(title.idle, 1.0, 0.03, "timer runs once released")
	check(got.is_empty(), "default idle time is 90 s")
	title.free()


# --- §11.1 director: level, ship, hits, duration --------------------------------------------------
func test_demo_choices_never_bonus_level_and_bounded() -> void:
	var seen := {}
	for s in 3000:
		var d := AttractDirector.new(s)
		seen[d.level] = true
		check(AttractDirector.is_demo_level(d.level) and d.level != LevelData.BONUS_LEVEL, "seed %d: level %d" % [s, d.level])
		check(d.ship_id >= 0 and d.ship_id < ShipData.SHIPS.size(), "seed %d: ship" % s)
		check(d.hits_wanted >= 3 and d.hits_wanted <= 6, "seed %d: hits %d" % [s, d.hits_wanted])
		check(d.duration >= 15.0 and d.duration <= 40.0, "seed %d: D %.3f" % [s, d.duration])
		check_near(d.t_die, d.duration - 1.9, 1e-9, "seed %d: t_die" % s)
		check_near(d.t_vulnerable, maxf(13.1, d.t_die - 3.0), 1e-9, "seed %d: window start" % s)
		if not failures.is_empty():
			return
	check_eq(seen.size(), 19, "all 19 demo levels occur")
	check(not seen.has(LevelData.BONUS_LEVEL), "never the bonus level")
	# Dev override (--attract-level): valid levels win, 13 and nonsense are ignored; the rest stays the same.
	var a := AttractDirector.new(42)
	var b := AttractDirector.new(42, 7)
	check_eq(b.level, 7, "level override")
	check_eq([b.ship_id, b.hits_wanted, b.duration, b.world_seed], [a.ship_id, a.hits_wanted, a.duration, a.world_seed],
		"the override does not change the other choices")
	check(AttractDirector.new(42, 13).level != 13, "level 13 is never shown")
	check_eq(AttractDirector.new(42, 99).level, a.level, "invalid level → random")
	check_eq(AttractDirector.new(42).level, a.level, "same seed, same demo")
	var w := b.make_world()
	check_eq(w.difficulty, 1, "NORMAL")
	check_eq(w.speed_factor, 1.0, "speed factor 1.0")
	check_eq(w.lives, 1, "one life")
	check(w.invincible, "invincible at the start")


# --- §11.1 choreography over many seeds -----------------------------------------------------------
func test_demo_runs_hit_and_end_within_bounds() -> void:
	for s in range(1, 17):
		_simulate(AttractDirector.new(s * 7919), "seed %d" % (s * 7919))
		if not failures.is_empty():
			return


func test_demo_bounds_at_extreme_durations() -> void:
	# Shortest (window = the single instant 13.1 s) and longest demo, on a calm and on the busiest level.
	for lvl in [1, 14, 20]:
		for dur in [AttractDirector.DURATION_MIN, AttractDirector.DURATION_MAX]:
			var d := AttractDirector.new(1234 + lvl, lvl)
			d.set_duration(dur)
			_simulate(d, "level %d D=%.0f" % [lvl, dur])
	var d15 := AttractDirector.new(5, 1)
	d15.set_duration(15.0)
	check_near(d15.t_vulnerable, 13.1, 1e-9, "D=15: window starts at 13.1")
	check_near(d15.t_die, 13.1, 1e-9, "D=15: and ends there")


## Without any enemy fire the rescue fireball takes the ship at t_die: the demo lasts exactly D.
func test_rescue_fireball_hits_at_t_die() -> void:
	for dur in [15.0, 27.3, 40.0]:
		var d := AttractDirector.new(77, 2)
		d.set_duration(dur)
		var w := d.make_world()
		w.allow_enemy_fire = false
		var guard := 0
		while not d.is_over() and guard < 3000:
			d.play(w, STEP)
			w.events.clear()
			guard += 1
		check(d.rescue_placed, "D=%.1f: rescue fireball placed" % dur)
		check(not d.failsafe_placed, "D=%.1f: the failsafe fireball is not needed" % dur)
		# It enters the hit box right after t_die (the ship is vulnerable by then, also for D = 15): the hit lands in
		# the first sub-step after t_die (+ the slice it ends in).
		check(d.hit_time > d.t_die and d.hit_time <= d.t_die + AttractDirector.BOT_SLICE + 1e-6,
			"D=%.1f: hit %.4f at t_die %.4f" % [dur, d.hit_time, d.t_die])
		check_near(d.time, dur, 1e-6, "D=%.1f: total = D" % dur)
		check_eq(w.state, GameWorld.State.GAME_OVER, "D=%.1f: explosion over" % dur)


## The salvo withdrawal: a salvo that would close the last way out of a fireball wall is removed with its event
## (before anything is drawn); a harmless one stays. Only salvos of the last slice (ids above `last_bullet`) count.
func test_salvo_that_traps_the_invincible_ship_is_withdrawn() -> void:
	var d := AttractDirector.new(21, 3)
	var w := d.make_world()
	w.allow_enemy_fire = false
	w.update(LevelData.INTRO_TIME + STEP, 0.0, false)
	w.enemies.clear()
	w.player_x = 480.0
	check(Autopilot.can_escape(w), "no fireball: the ship can escape")
	# A wall of fireballs 0.5 s above the ship from the left edge to x = 420 and from x = 560 to the right edge: the
	# gap 420…560 is the way out.
	var y := LevelData.PLAYER_Y - LevelData.ENEMY_BULLET_SPEED * 0.5
	var x := 0.0
	while x <= 960.0:
		if x <= 420.0 or x >= 560.0:
			w.add_bullet(x, y)
		x += 20.0
	check(Autopilot.can_escape(w), "the gap is a way out")
	var last := w.bullets[w.bullets.size() - 1].id
	var first := w.events.size()
	# Two salvos "fired in the last slice": one closes the gap, one is far up on the left.
	for bx in [440.0, 460.0, 480.0, 500.0, 520.0, 540.0]:
		w.add_bullet(bx, y).owner_id = 901
	w.events.append({"type": "enemy_fire", "id": 901, "x": 490.0, "y": y, "count": 6, "vx": 0.0, "vy": 220.0})
	for bx in [100.0, 120.0]:
		w.add_bullet(bx, 300.0).owner_id = 902
	w.events.append({"type": "enemy_fire", "id": 902, "x": 110.0, "y": 300.0, "count": 2, "vx": 0.0, "vy": 220.0})
	check(not Autopilot.can_escape(w), "with the closing salvo there is no way out")
	d._withdraw_hopeless_salvos(w, first, last)
	check_eq(d.salvos_withdrawn, 1, "one salvo withdrawn")
	var owners := {}
	for b in w.bullets:
		owners[b.owner_id] = int(owners.get(b.owner_id, 0)) + 1
	check(not owners.has(901), "the closing salvo is gone")
	check_eq(int(owners.get(902, 0)), 2, "the harmless salvo stays")
	check_eq(w.events.size(), first + 1, "only the harmless salvo's event is left")
	check_eq(int(w.events[first]["id"]), 902, "the harmless salvo's event")
	check(Autopilot.can_escape(w), "the way out is open again")
	# The ship takes it: a few seconds of the demo's dodging never let a fireball touch it.
	var touched := false
	for i in 150:
		var input: Vector2 = Autopilot.demo(w, false, false)
		w.update(STEP, input.x, false)
		for b in w.bullets:
			if absf(b.x - w.player_x) < LevelData.PLAYER_HIT_DX and absf(b.y - LevelData.PLAYER_Y) < LevelData.PLAYER_HIT_DY:
				touched = true
	check(not touched, "the ship escapes through the gap")


func test_hit_counting_follows_world_events() -> void:
	var d := AttractDirector.new(3)
	var w := d.make_world()
	w.events.append({"type": "enemy_split"})
	w.events.append({"type": "locked_hit"})
	w.events.append({"type": "enemy_hit_nonlethal", "kind": "color_stage"})
	w.events.append({"type": "enemy_hit_nonlethal", "kind": "rolling"})
	w.events.append({"type": "enemy_destroyed"})
	w.events.append({"type": "shot_fired"})
	d.advance(0.0, w, 1)
	check_eq(d.hits, 3, "split / stage / rolling / destroyed count, locked hits do not (first event skipped)")


# --- §11.1 GameScreen in attract mode -------------------------------------------------------------
func test_attract_screen_leaves_run_settings_and_audio_alone() -> void:
	AudioManager.play_title_music()
	AudioManager.reset_bass(5)
	for i in 3:
		AudioManager.notify_enemy_destroyed()
	var bass0 := AudioManager.bass_semitone()
	Run.start_new(3, 4, 7)
	Run.score = 4321
	Run.lives = 2
	Run.active_time = 12.5
	Run.active = false
	Run.last_level_result = {"level": 6, "completion_bonus": 250, "extra_life": false, "flawless": true}
	Run.dev_flags = {"autoplay": false, "invincible": true}
	var run0 := [Run.difficulty, Run.ship_id, Run.speed_factor, Run.score, Run.lives, Run.level, Run.active_time,
		Run.active, Run.last_level_result.duplicate(), Run.last_bonus_result.duplicate()]
	var settings0 := [Settings.difficulty, Settings.music_on, Settings.sfx_on, Settings.fullscreen]
	var hs0: Array = []
	for diff in 4:
		hs0.append(Settings.get_highscores(diff).duplicate(true))
	var files0 := [_file(Settings.SETTINGS_PATH), _file(Settings.HIGHSCORE_PATH)]

	var gs := _attract_screen(2024)
	var spy := AudioSpy.new()
	gs.set("audio", spy)
	var got: Array[String] = []
	gs.finished.connect(func(r: String, _d: Dictionary) -> void: got.append(r))
	gs._ready()
	var w: GameWorld = gs.get("world")
	var dir: AttractDirector = gs.get("director")
	check(gs.get("attract"), "attract mode")
	check_eq(w.level, dir.level, "the director's level")
	check(w.level != LevelData.BONUS_LEVEL, "never level 13")
	var frames := 0
	var events := 0
	while got.is_empty() and frames < 41 * 60:
		events += w.events.size()
		gs._process(STEP)
		frames += 1
	check_eq(got, ["end"] as Array[String], "the demo ends by itself")
	check(frames >= 15 * 60 - 1 and frames <= 40 * 60 + 1, "demo length %d frames" % frames)
	check(dir.hits >= 1, "the demo landed hits (%d)" % dir.hits)
	check(spy.calls.is_empty(), "no sound calls during the demo: %s" % [spy.calls])
	check(AudioManager.is_title_music_playing(), "the title music keeps playing")
	check(not AudioManager.is_game_music_active(), "no game music")
	check_eq(AudioManager.bass_semitone(), bass0, "bass untouched")
	var run1 := [Run.difficulty, Run.ship_id, Run.speed_factor, Run.score, Run.lives, Run.level, Run.active_time,
		Run.active, Run.last_level_result, Run.last_bonus_result]
	check_eq(run1, run0, "Run untouched")
	check_eq([Settings.difficulty, Settings.music_on, Settings.sfx_on, Settings.fullscreen], settings0, "Settings untouched")
	for diff in 4:
		check_eq(Settings.get_highscores(diff), hs0[diff], "highscores %d untouched" % diff)
	check_eq([_file(Settings.SETTINGS_PATH), _file(Settings.HIGHSCORE_PATH)], files0, "no settings / highscore files written")
	gs.free()
	# Sanity check of the spy: a normal level screen does reach it.
	var normal: Node2D = LogicOnlyScreen.new()
	var spy2 := AudioSpy.new()
	normal.set("audio", spy2)
	Run.start_new(1, 0, 1)
	normal.setup({"level": 1})
	normal._ready()
	for i in 150:
		normal._process(STEP)
	check(spy2.calls.has("stop_music") and spy2.calls.has("reset_bass(1)") and spy2.calls.has("play_game_music"),
		"a normal level uses the sound output: %s" % [spy2.calls])
	normal.free()
	spy.free()
	spy2.free()
	Run.dev_flags = {}
	AudioManager.stop_music()


func _file(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "<none>"


func test_any_input_ends_the_demo_and_never_pauses() -> void:
	_router_init()
	var cases: Array = [
		["key", _key_event(KEY_K, true), _key_event(KEY_K, false)],
		["escape", _key_event(KEY_ESCAPE, true), _key_event(KEY_ESCAPE, false)],
		["p", _key_event(KEY_P, true), _key_event(KEY_P, false)],
		["joy start", _joy_button(JOY_BUTTON_START, true), _joy_button(JOY_BUTTON_START, false)],
		["d-pad", _joy_button(JOY_BUTTON_DPAD_RIGHT, true), _joy_button(JOY_BUTTON_DPAD_RIGHT, false)],
		["left stick", _joy_motion(JOY_AXIS_LEFT_X, 0.8), _joy_motion(JOY_AXIS_LEFT_X, 0.0)],
	]
	for c: Array in cases:
		var gs := _attract_screen(11)
		var got: Array[String] = []
		gs.finished.connect(func(r: String, _d: Dictionary) -> void: got.append(r))
		gs._ready()
		for i in 180:   # 3 s: the intro is over, the demo is playing
			_router_step()
			gs._process(STEP)
		check(got.is_empty(), "%s: still running before the input" % c[0])
		_send(c[1])
		_router_step()
		gs._process(STEP)
		check_eq(got, ["exit"] as Array[String], "%s ends the demo at once" % c[0])
		check(not gs.get("paused"), "%s does not pause the demo" % c[0])
		_send(c[2])
		_router_step()
		_router_step()
		gs.free()
	# A press shorter than a frame only arrives as an event (_input) – it ends the demo as well.
	var gs2 := _attract_screen(12)
	var log2: Array[String] = []
	gs2.finished.connect(func(r: String, _d: Dictionary) -> void: log2.append(r))
	gs2._ready()
	gs2._process(STEP)
	gs2._input(_joy_motion(JOY_AXIS_RIGHT_X, -0.9))
	gs2._process(STEP)
	check_eq(log2, ["exit"] as Array[String], "stick event ends the demo")
	gs2.free()


## The press that ends the demo is latched by Main's require_release(): it does not act on the title
## (Enter would start a game, Escape would quit), the menu stands on START GAME and the idle timer restarts.
func test_exit_press_does_not_act_on_the_title() -> void:
	_router_init()
	for code: Key in [KEY_ENTER, KEY_ESCAPE, KEY_SPACE, KEY_DOWN]:
		var gs := _attract_screen(5)
		var got: Array[String] = []
		gs.finished.connect(func(r: String, _d: Dictionary) -> void: got.append(r))
		gs._ready()
		for i in 60:
			_router_step()
			gs._process(STEP)
		_key(code, true)
		_router_step()
		gs._process(STEP)
		check_eq(got, ["exit"] as Array[String], "key %d ends the demo" % code)
		gs.free()
		# Main: RunFlow → title, _show() → require_release(); the key is still held.
		check_eq(RunFlow.next("attract", "exit", 0)["screen"], "title", "demo → title")
		InputRouter.require_release()
		var title := TitleScreen.new()
		title.setup({"attract_after": 5.0})
		var tlog: Array[String] = []
		title.finished.connect(func(r: String, _d: Dictionary) -> void: tlog.append(r))
		title._ready()
		_run_title(title, 0.5, tlog)
		_key(code, false)
		_run_title(title, 0.5, tlog)
		check(tlog.is_empty(), "key %d does not act on the title: %s" % [code, tlog])
		check_eq(title.get("_sel"), 0, "key %d: the menu stands on START GAME" % code)
		check_near(title.idle, 0.5, 0.05, "key %d: the idle timer restarted after the release" % code)
		title.free()


func test_run_flow_and_main_wiring() -> void:
	check_eq(RunFlow.next("title", "attract", 0)["screen"], "attract", "idle title → demo")
	check_eq(RunFlow.next("attract", "end", 0)["screen"], "title", "demo over → title")
	check_eq(RunFlow.next("attract", "exit", 0)["screen"], "title", "input → title")
	if (InputRouter.get("_down") as Dictionary).is_empty():
		InputRouter._ready()
	Run.active = false
	Run.score = 777
	var main: Node = MainScript.new()
	main.set("_args", {"attract-after": "4.5", "attract-seed": "99", "attract-level": "9"})
	main._go(RunFlow.step("title"))
	var title: Node = main.get("_screen")
	check_eq(main.get("_screen_name"), "title")
	check_eq(float((title.get("args") as Dictionary).get("attract_after", -1.0)), 4.5, "--attract-after reaches the title")
	main._handle_finished("attract", {}, "title", title)
	var demo: Node = main.get("_screen")
	check_eq(main.get("_screen_name"), "attract", "title → demo")
	check(demo.get("attract"), "GameScreen in attract mode")
	check_eq(demo.get("level"), 9, "--attract-level")
	check_eq((demo.get("director") as AttractDirector).level, AttractDirector.new(99, 9).level, "--attract-seed")
	check_eq((demo.get("director") as AttractDirector).duration, AttractDirector.new(99, 9).duration, "seeded duration")
	check(not Run.active, "Run.active stays false")
	check_eq(Run.score, 777, "Run untouched")
	main._handle_finished("end", {}, "attract", demo)
	var back: Node = main.get("_screen")
	check_eq(main.get("_screen_name"), "title", "demo → title")
	check_eq(String((back.get("args") as Dictionary).get("select", "start")), "start", "menu on START GAME")
	check_eq(float((back.get("args") as Dictionary).get("attract_after", -1.0)), 4.5, "idle time again")
	main.free()
	title.free()
	demo.free()
	Run.score = 0


func test_hud_shows_the_demo_world_not_run() -> void:
	Run.start_new(3, 5, 12)
	Run.score = 98765
	Run.lives = 4
	Run.active_time = 321.0
	var d := AttractDirector.new(8)
	var w := d.make_world()
	w.score_delta = 120
	var hud: Node2D = Hud.new()
	hud.set("world", w)
	hud.set("attract", true)
	check_eq(hud.call("_score"), 120, "demo score")
	check_eq(hud.call("_lives"), 1, "demo lives")
	check_eq(hud.call("_difficulty_name"), "NORMAL", "demo difficulty")
	check_eq(hud.call("_ship_id"), d.ship_id, "demo ship")
	check_eq(hud.call("_play_time"), w.active_time, "demo time")
	hud.set("attract", false)
	check_eq(hud.call("_score"), 98765, "normal play shows Run")
	check_eq(hud.call("_difficulty_name"), "EXPERT", "normal play difficulty")
	hud.free()
	Run.start_new(1, 0, 1)
