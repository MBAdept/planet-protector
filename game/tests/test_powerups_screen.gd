extends TestBase
## Power-ups on the game screen (docs/SPEC.md §19.3) and the two-player HUD labels (§19.2): GameScreen gives the
## world its power-up only with POWER-UPS ON (never in a demo), the power-up button (InputRouter.powerup_pressed)
## triggers it – not in the pause, not on a held button, silently refused when not possible –, the autoplay bot
## triggers it at once, the sounds; the HUD pill states, the blink and the captions in every display mode.
## Like tests/test_game_screen.gd the screen is driven by hand with its view update stubbed out.

const GameScreenScript := preload("res://scripts/game/game_screen.gd")
const AudioManagerScript := preload("res://scripts/autoload/audio_manager.gd")
const Hud := preload("res://scripts/game/hud.gd")
const PU := LevelData.PowerUp
const FRAME := 1.0 / 60.0


class LogicOnlyScreen extends GameScreenScript:
	func _update_views(_dt: float, _game_dt: float) -> void:
		pass


## Records the sound effects the GameScreen plays.
class AudioSpy extends AudioManagerScript:
	var sfx: Array[String] = []

	func play_title_music() -> void:
		pass

	func play_game_music() -> void:
		pass

	func stop_music() -> void:
		pass

	func set_game_music_suspended(_suspended: bool) -> void:
		pass

	func reset_bass(_level: int) -> void:
		pass

	func notify_enemy_destroyed() -> void:
		pass

	func play_sfx(sfx_name: String, _volume_db: float = 0.0, _pitch: float = 1.0) -> void:
		sfx.append(sfx_name)


# --- Helpers -------------------------------------------------------------------------------------
func _router_step() -> void:
	Input.flush_buffered_events()
	InputRouter._process(FRAME)


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


## A GameScreen of `level` with POWER-UPS on/off (one-player run), enemy fire off, invincible.
func _screen(level: int, powerups: bool, flags: Dictionary = {}) -> Node2D:
	if (InputRouter.get("_down") as Dictionary).is_empty():
		InputRouter._ready()
	InputRouter.set_text_mode(false)
	_router_step()
	Run.start_new(1, 0, level, powerups)
	var f := {"invincible": true}
	f.merge(flags, true)
	Run.dev_flags = f
	var gs: Node2D = LogicOnlyScreen.new()
	gs.set("audio", AudioSpy.new())
	gs.setup({"level": level})
	gs._ready()
	(gs.get("world") as GameWorld).allow_enemy_fire = false
	return gs


func _frames(gs: Node2D, n: int) -> void:
	for i in n:
		_router_step()
		gs._process(FRAME)


func _past_intro(gs: Node2D) -> void:
	var w: GameWorld = gs.get("world")
	var guard := 0
	while w.state == GameWorld.State.INTRO and guard < 400:
		_frames(gs, 1)
		guard += 1


func _cleanup(gs: Node2D, keys: Array = []) -> void:
	for k in keys:
		_key(k, false)
	_router_step()
	(gs.get("audio") as Node).free()
	gs.free()
	Run.dev_flags = {}
	Run.start_new(1, 0, 1)
	AudioManager.stop_music()


func _spy(gs: Node2D) -> AudioSpy:
	return gs.get("audio")


# --- Wiring ----------------------------------------------------------------------------------------
func test_world_gets_the_level_powerup_only_with_powerups_on() -> void:
	for level in range(1, 21):
		var on := _screen(level, true)
		check_eq((on.get("world") as GameWorld).powerup, LevelData.powerup_of(level), "level %d with POWER-UPS ON" % level)
		_cleanup(on)
		var off := _screen(level, false)
		check_eq((off.get("world") as GameWorld).powerup, PU.NONE, "level %d with POWER-UPS OFF" % level)
		_cleanup(off)
	check_eq(LevelData.powerup_of(13), PU.NONE, "no power-up on the bonus level")
	check_eq(LevelData.powerup_of(17), PU.NONE, "Earth must be protected by skill")


func test_attract_worlds_have_none() -> void:
	Run.start_new(1, 0, 11, true)
	for lvl in [8, 11, 15]:
		var gs: Node2D = LogicOnlyScreen.new()
		gs.set("audio", AudioSpy.new())
		gs.setup({"attract": {"seed": 31, "level": lvl}})
		gs._ready()
		check_eq((gs.get("world") as GameWorld).powerup, PU.NONE, "demo on level %d: no power-up" % lvl)
		(gs.get("audio") as Node).free()
		gs.free()
	Run.start_new(1, 0, 1)


func test_powerup_press_activates() -> void:
	for code: Key in [KEY_SHIFT, KEY_CTRL]:
		var gs := _screen(8, true)
		var w: GameWorld = gs.get("world")
		_past_intro(gs)
		_frames(gs, 5)
		check_eq(w.powerup_state, GameWorld.PowerState.READY, "nothing without a press")
		_key(code, true)
		_frames(gs, 1)
		check_eq(w.powerup_state, GameWorld.PowerState.ACTIVE, "%s triggers it" % OS.get_keycode_string(code))
		check(_spy(gs).sfx.has("powerup_on"), "power-up sound")
		_cleanup(gs, [code])


func test_controller_buttons_are_powerup_buttons() -> void:
	if (InputRouter.get("_down") as Dictionary).is_empty():
		InputRouter._ready()
	_router_step()
	var down: Dictionary = InputRouter.get("_down")
	var prev: Dictionary = InputRouter.get("_prev")
	var B: Dictionary = InputRouter.B
	for name: String in ["SHIFT", "CTRL", "JOY_X", "JOY_Y", "JOY_LB", "JOY_RB"]:
		down[B[name]] = true
		prev[B[name]] = false
		check(InputRouter.powerup_pressed(), name + " is a power-up button")
		prev[B[name]] = true
		check(not InputRouter.powerup_pressed(), name + ": only a fresh press counts")
		down[B[name]] = false
		prev[B[name]] = false
	for name: String in ["SPACE", "JOY_A", "JOY_B", "ENTER", "JOY_START", "P"]:
		down[B[name]] = true
		check(not InputRouter.powerup_pressed(), name + " is not a power-up button")
		down[B[name]] = false
	_router_step()


func test_refused_presses_are_silent_and_need_a_new_press() -> void:
	var gs := _screen(15, true)
	var w: GameWorld = gs.get("world")
	_frames(gs, 10)
	check_eq(w.state, GameWorld.State.INTRO)
	_key(KEY_SHIFT, true)
	_frames(gs, 2)
	check_eq(w.powerup_state, GameWorld.PowerState.READY, "not during the intro banner")
	check(not _spy(gs).sfx.has("powerup_on"), "a refused press makes no sound")
	_past_intro(gs)
	_frames(gs, 5)
	check_eq(w.powerup_state, GameWorld.PowerState.READY, "a held button does not trigger it later")
	_key(KEY_SHIFT, false)
	_frames(gs, 1)
	_key(KEY_SHIFT, true)
	_frames(gs, 1)
	check_eq(w.powerup_state, GameWorld.PowerState.ACTIVE, "a fresh press does")
	_cleanup(gs, [KEY_SHIFT])


func test_no_activation_in_the_pause() -> void:
	var gs := _screen(11, true)
	var w: GameWorld = gs.get("world")
	_past_intro(gs)
	_key(KEY_P, true)
	_frames(gs, 1)
	_key(KEY_P, false)
	check(gs.get("paused"), "paused")
	_key(KEY_SHIFT, true)
	_frames(gs, 3)
	check_eq(w.powerup_state, GameWorld.PowerState.READY, "not in the pause")
	_key(KEY_P, true)
	_frames(gs, 1)
	_key(KEY_P, false)
	check(not gs.get("paused"), "resumed")
	_frames(gs, 3)
	check_eq(w.powerup_state, GameWorld.PowerState.READY, "the press in the pause does not act afterwards")
	_cleanup(gs, [KEY_SHIFT])


func test_release_guard_of_a_screen_change() -> void:
	var gs := _screen(8, true)
	var w: GameWorld = gs.get("world")
	_past_intro(gs)
	# A confirm / X press that changed the screen is latched by Main's require_release().
	_key(KEY_CTRL, true)
	_router_step()
	InputRouter.require_release()
	gs._process(FRAME)
	_frames(gs, 3)
	check_eq(w.powerup_state, GameWorld.PowerState.READY, "latched until released")
	_cleanup(gs, [KEY_CTRL])


func test_autoplay_triggers_it_at_once() -> void:
	var gs := _screen(10, true, {"autoplay": true})
	var w: GameWorld = gs.get("world")
	_past_intro(gs)
	_frames(gs, 1)
	check_eq(w.powerup_state, GameWorld.PowerState.ACTIVE, "the bot triggers it as soon as the combat starts")
	check_near(w.powerup_left, 15.0, 2.0 * FRAME, "in its first frame of combat")
	_cleanup(gs)
	var gs2 := _screen(10, true, {"autoplay": true, "manual_powerup": true})
	var w2: GameWorld = gs2.get("world")
	_past_intro(gs2)
	_frames(gs2, 30)
	check_eq(w2.powerup_state, GameWorld.PowerState.READY, "dev flag manual_powerup: only on a press")
	_cleanup(gs2)


func test_sounds_of_the_powerup_events() -> void:
	var gs := _screen(15, true)
	var w: GameWorld = gs.get("world")
	_past_intro(gs)
	check(w.activate_powerup())
	w.add_bullet(w.player_x + 10.0, LevelData.PLAYER_Y - 20.0, 0.0, 0.0)
	_frames(gs, 1)
	var spy := _spy(gs)
	check(spy.sfx.has("powerup_on"), "powerup_on")
	check(spy.sfx.has("shield_hit"), "shield_hit on an absorbed fireball")
	check_eq(w.lives, 3)
	var guard := 0
	while w.powerup_state == GameWorld.PowerState.ACTIVE and guard < 1000:
		_frames(gs, 1)
		guard += 1
	check(spy.sfx.has("powerup_off"), "powerup_off when it ends")
	check(float(gs.get("_powerup_end")) >= 0.0, "the HUD's USED fade starts")
	_cleanup(gs)


func test_powerup_sfx_are_registered() -> void:
	for n in ["powerup_on", "powerup_off", "shield_hit"]:
		check(AudioManagerScript.SFX_NAMES.has(n), n + " registered")
		check(AudioManagerScript.SFX_TUNING.has(n), n + " tuned")
		check(ResourceLoader.exists("res://assets/audio/sfx/%s.wav" % n), n + ".wav")
	check_eq(AudioManagerScript.SFX_NAMES.size(), 19)


func test_twin_shots_get_a_muzzle_at_the_twin() -> void:
	var gs := _screen(11, true)
	var w: GameWorld = gs.get("world")
	_past_intro(gs)
	w.player_x = 200.0
	check(w.activate_powerup())
	_frames(gs, 1)
	check(_spy(gs).sfx.has(String(ShipData.ship(0)["sfx"])), "the twin's salvo uses the ship's shot sound")
	var muzzles := 0
	var twin_in := 0
	for im: Dictionary in (gs.get("_fx") as Node).get("_impulses"):
		if im["kind"] == "muzzle":
			muzzles += 1
			check_near((im["pos"] as Vector2).x, w.twin_x, 350.0 / 60.0 + 1.0, "muzzle flash at the twin")
		elif im["kind"] == "twin_in":
			twin_in += 1
	check_eq(muzzles, 1, "one muzzle flash (the ship did not fire)")
	check_eq(twin_in, 1, "materialize effect")
	_cleanup(gs)


# --- HUD -------------------------------------------------------------------------------------------
func _hud(w: GameWorld) -> Node2D:
	if Assets.font_title == null:
		Assets._ready()
	var hud: Node2D = Hud.new()
	hud.set("world", w)
	hud.set("level", w.level)
	hud.set("_f_label", hud.call("_spaced", Assets.font_body_bold, 2))
	hud.set("_f_value", Assets.font_title)
	hud.set("_planet", LevelData.planet_of(w.level))
	return hud


func _combat_world(level: int, kind: int) -> GameWorld:
	var w := GameWorld.new(level, 1, 0, 3, 3)
	w.powerup = kind
	w.auto_slots = false
	w.allow_enemy_fire = false
	w.start_combat()
	return w


func test_hud_pill_states() -> void:
	var none := _hud(_combat_world(8, PU.NONE))
	check_eq(String(none.call("powerup_pill")["mode"]), "", "nothing on a level without a power-up")
	none.free()
	var w := _combat_world(8, PU.RAPID_FIRE)
	var hud := _hud(w)
	var p: Dictionary = hud.call("powerup_pill")
	check_eq(String(p["mode"]), "ready")
	check_eq(float(p["alpha"]), 1.0)
	check(w.activate_powerup())
	p = hud.call("powerup_pill")
	check_eq(String(p["mode"]), "active")
	check_eq(String(p["seconds"]), "10.0", "full time")
	check_eq(float(p["fill"]), 1.0)
	w.run_game_seconds(3.75)
	p = hud.call("powerup_pill")
	check_eq(String(p["seconds"]), "6.3", "one decimal, rounded up")
	check_near(float(p["fill"]), 0.625, 1e-6, "draining bar")
	check_eq(float(p["blink"]), 1.0, "no blinking yet")
	w.run_game_seconds(4.5)
	var blinks: Array[float] = []
	for i in 400:
		w.run_steps(1)
		blinks.append(float(hud.call("powerup_pill")["blink"]))
	check(blinks.min() < 0.5 and blinks.max() > 0.95, "blinks in the last 2 s")
	w.run_game_seconds(0.5)
	check_eq(w.powerup_state, GameWorld.PowerState.USED)
	hud.set("powerup_end", 0.0)
	p = hud.call("powerup_pill")
	check_eq(String(p["mode"]), "used")
	check_eq(float(p["alpha"]), 1.0)
	hud.set("powerup_end", Hud.POWERUP_USED_SHOW + Hud.POWERUP_USED_FADE * 0.5)
	check_near(float(hud.call("powerup_pill")["alpha"]), 0.5, 1e-6, "fading")
	hud.set("powerup_end", Hud.POWERUP_USED_SHOW + Hud.POWERUP_USED_FADE + 0.01)
	check_eq(String(hud.call("powerup_pill")["mode"]), "", "then nothing")
	hud.free()
	# READY dims once the goal is met (it can no longer be used).
	var g := _combat_world(15, PU.SHIELD)
	var gh := _hud(g)
	g.spawned = g.total
	g.add_bullet(5.0, 200.0, 0.0, 0.0)
	g.run_steps(1)
	check(g.goal_met)
	check(float(gh.call("powerup_pill")["alpha"]) < 1.0, "dim after the goal")
	gh.free()
	# READY is only at full strength while the button works: dim in the intro banner and during a respawn.
	var iw := GameWorld.new(8, 1, 0, 3, 3)
	iw.powerup = PU.RAPID_FIRE
	var ih := _hud(iw)
	check_eq(iw.state, GameWorld.State.INTRO)
	check(float(ih.call("powerup_pill")["alpha"]) < 1.0, "dim in the intro banner")
	iw.auto_slots = false
	iw.allow_enemy_fire = false
	iw.start_combat()
	check_eq(float(ih.call("powerup_pill")["alpha"]), 1.0, "full once the combat runs")
	iw.add_bullet(iw.player_x, LevelData.PLAYER_Y, 0.0, 0.0)
	iw.run_steps(1)
	check_eq(iw.state, GameWorld.State.RESPAWN)
	check(float(ih.call("powerup_pill")["alpha"]) < 1.0, "dim during a respawn")
	iw.run_game_seconds(LevelData.RESPAWN_DELAY + 0.1)
	check_eq(iw.state, GameWorld.State.PLAYING)
	check_eq(float(ih.call("powerup_pill")["alpha"]), 1.0, "full again after the respawn")
	ih.free()
	# An ACTIVE pill dims once the last life is lost (the timer is frozen over the game-over moment).
	var ow := _combat_world(11, PU.TWIN)
	ow.lives = 1
	var oh := _hud(ow)
	check(ow.activate_powerup())
	ow.add_bullet(ow.player_x, LevelData.PLAYER_Y, 0.0, 0.0)
	ow.run_steps(1)
	check_eq(ow.state, GameWorld.State.GAME_OVER_WAIT)
	check_eq(String(oh.call("powerup_pill")["mode"]), "active")
	check(float(oh.call("powerup_pill")["alpha"]) < 1.0, "dim after the last life")
	oh.free()


func test_blink_curve() -> void:
	check_eq(Hud.powerup_blink(5.0), 1.0)
	check_eq(Hud.powerup_blink(2.0), 1.0)
	check_eq(Hud.powerup_blink(0.0), 1.0)
	var lo := 1.0
	for i in 200:
		var v := Hud.powerup_blink(2.0 * float(i) / 200.0)
		check(v >= 0.25 - 1e-6 and v <= 1.0 + 1e-6, "0.25 … 1")
		lo = minf(lo, v)
	check_near(lo, 0.25, 1e-6, "dips to 0.25")


## The pill fits the ground strip (685…720) and stays well inside the playfield in every display mode (modes 3/4
## lift the caption size), in each of its states and for each power-up.
func test_hud_pill_fits_in_every_mode() -> void:
	var saved := Display.forced_mode
	for m in [0, 1, 2, 3, 4]:
		Display.forced_mode = m
		for kind: int in [PU.RAPID_FIRE, PU.TWIN, PU.SHIELD]:
			var w := _combat_world(8, kind)
			var hud := _hud(w)
			hud.set("width", float(Display.logical_size_of(m).x))
			for mode: String in ["ready", "active", "used"]:
				var r: Rect2 = hud.call("powerup_pill_rect", mode)
				check(r.position.y >= LevelData.GROUND_Y + 2.0 and r.end.y <= LevelData.SCREEN_H - 2.0,
					"mode %d %s %s: inside the ground strip" % [m, Hud.powerup_name(kind), mode])
				check(r.size.x <= 420.0, "mode %d %s %s: compact (%.0f px)" % [m, Hud.powerup_name(kind), mode, r.size.x])
				check(r.position.x > 240.0 and r.end.x < float(hud.get("width")) - 240.0,
					"mode %d: centred, clear of the screen sides" % m)
			# The key hint's caps (1.55 × size) fit the pill.
			check(Hud.PILL_HINT_SIZE * 1.55 <= Hud.PILL_H - 4.0, "key caps inside the pill")
			hud.free()
	Display.forced_mode = saved


func test_hud_two_player_captions() -> void:
	var w := _combat_world(10, PU.TWIN)
	var hud := _hud(w)
	Run.start_new(1, 0, 10, true)
	check_eq(hud.call("score_caption"), ["SCORE", Hud.C_LABEL], "one player: as before")
	check_eq(hud.call("intro_caption"), [["JUPITER  ·  NORMAL", Hud.C_ACCENT]], "one player: as before")
	Run.start_match(2, [0, 4], [[], []], 10, true)
	check_eq(hud.call("score_caption"), ["P1 SCORE", UiKit.COLOR_P1])
	var ic: Array = hud.call("intro_caption")
	check_eq(ic, [["PLAYER 1", UiKit.COLOR_P1], ["  ·  JUPITER  ·  HARD", Hud.C_ACCENT]])
	Run.switch_to(1)
	check_eq(hud.call("score_caption"), ["P2 SCORE", UiKit.COLOR_P2])
	check_eq((hud.call("intro_caption") as Array)[0], ["PLAYER 2", UiKit.COLOR_P2])
	hud.set("attract", true)
	check_eq(hud.call("score_caption"), ["SCORE", Hud.C_LABEL], "a demo is never a match")
	hud.free()
	var b := _combat_world(13, PU.NONE)
	var bh := _hud(b)
	check_eq(bh.call("intro_caption"), [["PLAYER 2", UiKit.COLOR_P2], ["  ·  LEVEL 13  ·  BONUS ROUND", Hud.C_ACCENT]])
	# "P2 SCORE" stays clear of LIVES (x 160) in every mode.
	var saved := Display.forced_mode
	var f: Font = bh.get("_f_label")
	bh.free()
	for m in [0, 1, 2, 3, 4]:
		Display.forced_mode = m
		var wcap := f.get_string_size("P2 SCORE", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.label_size(Hud.LABEL_SIZE)).x
		check(18.0 + wcap + 12.0 <= 160.0, "mode %d: P2 SCORE clear of LIVES (%.0f px)" % [m, wcap])
	Display.forced_mode = saved
	Run.start_new(1, 0, 1)
