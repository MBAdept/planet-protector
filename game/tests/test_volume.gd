extends TestBase
## MUSIC VOLUME / EFFECTS VOLUME (client request, feedback round 3; docs/SPEC.md §11, §12, §14):
## persistence + defaults + old settings files, the volume curve, OFF overriding the volume, buses updated at
## once, the arrival staying silent with a non-default volume, the title menu rows (left/right, clamping,
## controlled repeat, preview) and the pause overlay (adjusting neither resumes nor quits, is persisted, no
## input leaks in either direction).
## Like the other screen tests these run before the SceneTree is live: screens are driven by hand, the
## InputRouter is stepped manually and every key that is pressed is released again. Settings are redirected to
## a scratch file (Settings.settings_path) and restored afterwards, so the player's settings.cfg is never touched.

const AudioManagerScript := preload("res://scripts/autoload/audio_manager.gd")
const TitleScreen := preload("res://scripts/screens/title_screen.gd")
const ArrivalScreen := preload("res://scripts/screens/arrival_screen.gd")
const GameScreenScript := preload("res://scripts/game/game_screen.gd")

const STEP := 1.0 / 60.0
const SCRATCH_CFG := "user://test_volume_settings.cfg"


## Title screen that records its sounds together with the SFX bus gain at that moment.
class SpyTitle extends TitleScreen:
	var sfx_calls: Array[String] = []
	var sfx_bus_db: Array[float] = []

	func sfx(sfx_name: String) -> void:
		sfx_calls.append(sfx_name)
		sfx_bus_db.append(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(AudioManagerScript.BUS_SFX)))


## Sound output of the GameScreen: records effects (with the SFX bus gain at that moment), real bus handling.
class AudioSpy extends AudioManagerScript:
	var calls: Array[String] = []
	var sfx_bus_db: Array[float] = []

	func play_sfx(sfx_name: String, _volume_db: float = 0.0, _pitch: float = 1.0) -> void:
		calls.append("sfx:" + sfx_name)
		sfx_bus_db.append(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(BUS_SFX)))

	func set_game_music_suspended(suspended: bool) -> void:
		calls.append("suspend(%s)" % suspended)

	func play_game_music() -> void:
		calls.append("play_game_music")

	func stop_music() -> void:
		calls.append("stop_music")


## GameScreen without its view update (the view nodes never enter the tree here, see test_game_screen.gd).
class LogicOnlyScreen extends GameScreenScript:
	func _update_views(_dt: float, _game_dt: float) -> void:
		pass


## No joypad can be connected in the headless runner: like test_audit_flow.gd the InputRouter autoload gets a
## subclass for the controller tests that only reads a fake button table / fake left stick.
class FakePadRouter extends "res://scripts/autoload/input_router.gd":
	var pad := {}
	var stick := Vector2.ZERO

	func _joy(button: JoyButton) -> bool:
		return bool(pad.get(button, false))

	func _left_sticks() -> Dictionary:
		return {0: stick}

	## The ship's movement reads the fake stick too (same deadzone and rescaling as the real one).
	func move_axis() -> float:
		var a := super()
		if absf(stick.x) > MOVE_DEADZONE and absf(stick.x) > absf(a):
			a = signf(stick.x) * clampf((absf(stick.x) - MOVE_DEADZONE) / (0.9 - MOVE_DEADZONE), 0.0, 1.0)
		return a


# --- Helpers -------------------------------------------------------------------------------------
var _saved := {}


## Points Settings at the scratch file (removed first) and remembers every option to restore it later.
func _settings_begin() -> void:
	_saved = {"path": Settings.settings_path, "difficulty": Settings.difficulty, "music_on": Settings.music_on,
		"sfx_on": Settings.sfx_on, "fullscreen": Settings.fullscreen, "music_volume": Settings.music_volume,
		"sfx_volume": Settings.sfx_volume}
	Settings.settings_path = SCRATCH_CFG
	_remove_scratch()


func _settings_end() -> void:
	_remove_scratch()
	Settings.settings_path = _saved["path"]
	Settings.difficulty = _saved["difficulty"]
	Settings.music_on = _saved["music_on"]
	Settings.sfx_on = _saved["sfx_on"]
	Settings.fullscreen = _saved["fullscreen"]
	Settings.music_volume = _saved["music_volume"]
	Settings.sfx_volume = _saved["sfx_volume"]
	AudioManager.apply_settings()


func _remove_scratch() -> void:
	if FileAccess.file_exists(SCRATCH_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_CFG))


## Value stored in the scratch file (null if missing).
func _stored(key: String) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(SCRATCH_CFG) != OK:
		return null
	return cfg.get_value("audio", key, null)


func _bus_db(bus_name: String) -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus_name))


func _bus_muted(bus_name: String) -> bool:
	return AudioServer.is_bus_mute(AudioServer.get_bus_index(bus_name))


func _router_init() -> void:
	if (InputRouter.get("_down") as Dictionary).is_empty():
		InputRouter._ready()
	InputRouter.set_text_mode(false)
	_router_step()


func _router_step(dt: float = STEP) -> void:
	Input.flush_buffered_events()
	InputRouter._process(dt)


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


var _orig_router: Script


func _swap_in() -> void:
	_orig_router = InputRouter.get_script()
	InputRouter.set_script(FakePadRouter)
	InputRouter._ready()
	InputRouter.set_text_mode(false)
	InputRouter._process(STEP)


func _swap_out() -> void:
	InputRouter.set_script(_orig_router)
	InputRouter._ready()
	InputRouter._process(STEP)


## Fake controller input (only while swapped in).
func _pad(button: JoyButton, down: bool) -> void:
	InputRouter.pad[button] = down


func _stick(v: Vector2) -> void:
	InputRouter.stick = v


## Press (one frame) and release (two frames) of a fake pad button / stick direction while the screen runs.
func _pad_tap(screen: Node, button: JoyButton) -> void:
	_pad(button, true)
	_run(screen, STEP)
	_pad(button, false)
	_run(screen, STEP * 2)


func _stick_tap(screen: Node, v: Vector2) -> void:
	_stick(v)
	_run(screen, STEP)
	_stick(Vector2.ZERO)
	_run(screen, STEP * 2)


## Steps a (not-in-tree) screen and the router together for `seconds`.
func _run(screen: Node, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 1e-6:
		_router_step()
		screen._process(STEP)
		t += STEP


## Press (one frame) and release (two frames) of a key while the screen runs.
func _tap(screen: Node, code: Key) -> void:
	_key(code, true)
	_run(screen, STEP)
	_key(code, false)
	_run(screen, STEP * 2)


func _title(select: String) -> SpyTitle:
	var t := SpyTitle.new()
	t.setup({"select": select})
	t._ready()
	_run(t, 0.1)
	return t


# --- §14 settings: defaults, persistence, old files ------------------------------------------------
func test_defaults_and_settings_files_without_volume_keys() -> void:
	_settings_begin()
	check_eq(Settings.DEFAULT_VOLUME, 100, "default 100 % = the original mix")
	# A settings.cfg from before this option: only the old keys.
	var old := ConfigFile.new()
	old.set_value("game", "difficulty", 2)
	old.set_value("audio", "music_on", false)
	old.set_value("audio", "sfx_on", true)
	old.set_value("video", "fullscreen", false)
	old.save(SCRATCH_CFG)
	Settings.music_volume = 30
	Settings.sfx_volume = 0
	Settings.load_settings()
	check_eq(Settings.music_volume, 100, "missing MUSIC VOLUME key → 100 %")
	check_eq(Settings.sfx_volume, 100, "missing EFFECTS VOLUME key → 100 %")
	check_eq(Settings.difficulty, 2, "old keys still read (difficulty)")
	check_eq(Settings.music_on, false, "old keys still read (music_on)")
	check_eq(Settings.sfx_on, true, "old keys still read (sfx_on)")
	# Saving adds the keys and keeps the old ones; a round trip gives the same values.
	check(Settings.set_music_volume(60), "60 % is a change")
	check_eq(_stored("music_volume"), 60, "MUSIC VOLUME written")
	check_eq(_stored("sfx_volume"), 100, "EFFECTS VOLUME written")
	check_eq(_stored("music_on"), false, "MUSIC ON/OFF kept in the file")
	Settings.music_volume = 0
	Settings.difficulty = 0
	Settings.load_settings()
	check_eq(Settings.music_volume, 60, "round trip")
	check_eq(Settings.difficulty, 2, "round trip keeps the other options")
	# Damaged / hand-edited values: snapped to 10 %, clamped, non-numbers → default.
	var odd := ConfigFile.new()
	odd.set_value("audio", "music_volume", 55)
	odd.set_value("audio", "sfx_volume", "loud")
	odd.save(SCRATCH_CFG)
	Settings.load_settings()
	check_eq(Settings.music_volume, 60, "55 → 60 (10 % steps)")
	check_eq(Settings.sfx_volume, 100, "a string falls back to the default")
	for c: Array in [[130, 100], [-20, 0], [0, 0], [100, 100], [44, 40], [72.4, 70], [true, 100], [null, 100]]:
		check_eq(Settings.clean_volume(c[0]), c[1], "clean_volume(%s)" % [c[0]])
	_settings_end()


func test_setters_clamp_snap_persist_and_signal() -> void:
	_settings_begin()
	Settings.music_volume = 100
	Settings.sfx_volume = 100
	var emitted := [0]
	var cb := func() -> void: emitted[0] += 1
	Settings.changed.connect(cb)
	check(not Settings.set_music_volume(100), "same value: no change")
	check(not FileAccess.file_exists(SCRATCH_CFG), "no change, no write")
	check(not Settings.step_volume("music_volume", 1), "step beyond 100 % does nothing")
	check_eq(emitted[0], 0, "no signal without a change")
	check(Settings.step_volume("music_volume", -1), "step down")
	check_eq(Settings.music_volume, 90, "−10 %")
	check_eq(_stored("music_volume"), 90, "persisted at once")
	check_eq(emitted[0], 1, "changed emitted once")
	check(Settings.set_sfx_volume(37), "37 is snapped")
	check_eq(Settings.sfx_volume, 40, "snapped to 40")
	check(Settings.set_sfx_volume(-50), "clamped")
	check_eq(Settings.sfx_volume, 0, "clamped to 0")
	check(not Settings.step_volume("sfx_volume", -1), "step below 0 % does nothing")
	check_eq(Settings.volume("sfx_volume"), 0)
	check_eq(Settings.volume("music_volume"), 90)
	check_eq(_stored("sfx_volume"), 0, "0 % persisted")
	Settings.changed.disconnect(cb)
	_settings_end()


# --- §14 curve, OFF, buses --------------------------------------------------------------------------
func test_volume_curve() -> void:
	check_near(AudioManagerScript.volume_db(100), 0.0, 1e-6, "100 % = 0 dB (the original mix)")
	check_eq(AudioManagerScript.volume_db(0), AudioManagerScript.VOLUME_MUTE_DB, "0 % → mute gain")
	check_near(AudioManagerScript.volume_db(50), -12.0412, 1e-3, "50 % = amplitude 0.25")
	check_near(AudioManagerScript.volume_db(10), -40.0, 1e-3, "10 % = −40 dB")
	check_near(db_to_linear(AudioManagerScript.volume_db(70)), 0.49, 1e-4, "amplitude = v²")
	var prev := -INF
	for p in range(0, 101, 10):
		var db := AudioManagerScript.volume_db(p)
		check(db > prev, "rising at %d %%" % p)
		check(db <= 0.0, "never above 0 dB at %d %% (no extra gain, the limiter guarantee holds)" % p)
		prev = db
	# Every 10 % step is audible (≥ 1.5 dB) and none is a jump (≤ 12 dB except into silence).
	for p in range(20, 101, 10):
		var d := AudioManagerScript.volume_db(p) - AudioManagerScript.volume_db(p - 10)
		check(d >= 1.5 and d <= 12.1, "step %d → %d %% is %.1f dB" % [p - 10, p, d])
	check(AudioManagerScript.bus_muted(true, 0), "0 % mutes")
	check(AudioManagerScript.bus_muted(false, 100), "OFF mutes at 100 %")
	check(AudioManagerScript.bus_muted(false, 50), "OFF mutes at 50 %")
	check(not AudioManagerScript.bus_muted(true, 10), "10 % with ON is audible")


func test_apply_settings_sets_both_buses_and_off_overrides() -> void:
	_settings_begin()
	Settings.music_on = true
	Settings.sfx_on = true
	Settings.music_volume = 50
	Settings.sfx_volume = 80
	AudioManager.apply_settings()
	check_near(_bus_db("Music"), AudioManagerScript.volume_db(50), 1e-3, "Music bus gain")
	check_near(_bus_db("SFX"), AudioManagerScript.volume_db(80), 1e-3, "SFX bus gain")
	check(not _bus_muted("Music") and not _bus_muted("SFX"), "both audible")
	Settings.music_on = false
	Settings.sfx_volume = 0
	AudioManager.apply_settings()
	check(_bus_muted("Music"), "MUSIC OFF mutes regardless of the volume")
	check(_bus_muted("SFX"), "EFFECTS VOLUME 0 % mutes")
	Settings.music_on = true
	Settings.sfx_volume = 100
	Settings.sfx_on = false
	AudioManager.apply_settings()
	check(not _bus_muted("Music"), "MUSIC ON again")
	check(_bus_muted("SFX"), "SOUND EFFECTS OFF mutes at 100 %")
	check_near(_bus_db("SFX"), 0.0, 1e-3, "the gain follows the volume while OFF (heard once ON)")
	# Limiter on Master is still there.
	var has_limiter := false
	for i in AudioServer.get_bus_effect_count(0):
		has_limiter = has_limiter or AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter
	check(has_limiter, "limiter on Master")
	_settings_end()


## In the game AudioManager listens to Settings.changed: a setter alone updates the bus in the same call.
func test_changes_act_immediately_through_the_signal() -> void:
	_settings_begin()
	Settings.music_on = true
	Settings.sfx_on = true
	var am: Node = AudioManagerScript.new()
	am._ready()   # connects Settings.changed → apply_settings (not in the tree: no player is started)
	Settings.set_music_volume(30)
	check_near(_bus_db("Music"), AudioManagerScript.volume_db(30), 1e-3, "music gain changed by the setter alone")
	Settings.set_sfx_volume(0)
	check(_bus_muted("SFX"), "0 % muted by the setter alone")
	Settings.set_sfx_volume(20)
	check(not _bus_muted("SFX"), "20 % audible again")
	check_near(_bus_db("SFX"), AudioManagerScript.volume_db(20), 1e-3, "sfx gain changed by the setter alone")
	if Settings.changed.is_connected(am.apply_settings):
		Settings.changed.disconnect(am.apply_settings)
	am.free()
	_settings_end()


# --- §11/§14 arrival stays completely silent with any volume ---------------------------------------
func test_arrival_silent_and_volume_restored_with_custom_volume() -> void:
	_settings_begin()
	Settings.sfx_on = true
	Settings.music_on = true
	for vol in [40, 0, 100]:
		Settings.sfx_volume = vol
		Settings.music_volume = 70
		AudioManager.apply_settings()
		var want := AudioManagerScript.volume_db(vol)
		var arrival := ArrivalScreen.new()
		arrival.setup({"level": 9})
		arrival._ready()
		arrival._process(STEP)
		if vol > 0:
			check(_bus_db("SFX") < want - 0.5, "%d %%: ringing effects fade out from the player's volume" % vol)
		var t := STEP
		while t < 0.2:
			arrival._process(STEP)
			t += STEP
		check(_bus_muted("SFX"), "%d %%: SFX bus muted during the arrival" % vol)
		check(not AudioManager.is_title_music_playing() and not AudioManager.is_game_music_active(),
			"%d %%: no music in the arrival" % vol)
		# Settings.changed (F11) re-applies the settings with the custom volume: the arrival keeps it muted.
		AudioManager.apply_settings()
		arrival._process(STEP)
		check(_bus_muted("SFX"), "%d %%: stays muted after apply_settings" % vol)
		arrival._exit_tree()
		check_eq(_bus_muted("SFX"), vol == 0, "%d %%: effects back on exit (0 %% stays muted)" % vol)
		check_near(_bus_db("SFX"), want, 1e-3, "%d %%: the player's volume restored" % vol)
		check_near(_bus_db("Music"), AudioManagerScript.volume_db(70), 1e-3, "%d %%: music volume untouched" % vol)
		arrival.free()
	_settings_end()


# --- §11 title menu ---------------------------------------------------------------------------------
func test_title_items_order_and_existing_items_unchanged() -> void:
	check_eq(TitleScreen.ITEMS, ["start", "difficulty", "players", "powerups", "music", "music_volume", "sfx",
		"sfx_volume", "display", "highscores", "quit"] as Array[String],
		"11 items: PLAYERS / POWER-UPS under DIFFICULTY, volumes directly under MUSIC / SOUND EFFECTS, then DISPLAY")
	check_eq(TitleScreen.LABELS["music_volume"], "MUSIC VOLUME")
	check_eq(TitleScreen.LABELS["sfx_volume"], "EFFECTS VOLUME")
	for item in ["music_volume", "sfx_volume", "difficulty"]:
		check(TitleScreen.accepts_step(item, true), "%s steps with the controlled repeat" % item)
	for item in ["music", "sfx"]:
		check(not TitleScreen.accepts_step(item, true), "%s still flips once per press" % item)
	_settings_begin()
	_router_init()
	# Up/down walks through all 11 rows (wrapping) – the volume rows are ordinary stops.
	var t := _title("start")
	var seen: Array[String] = []
	for i in TitleScreen.ITEMS.size():
		seen.append(TitleScreen.ITEMS[int(t.get("_sel"))])
		_tap(t, KEY_DOWN)
	check_eq(seen, TitleScreen.ITEMS, "down visits every row in order")
	check_eq(int(t.get("_sel")), 0, "wraps to START GAME")
	_tap(t, KEY_UP)
	check_eq(TitleScreen.ITEMS[int(t.get("_sel"))], "quit", "up wraps to QUIT")
	t.free()
	# "select" from Main (back from the highscores) still lands on the right row.
	var t2 := _title("highscores")
	check_eq(TitleScreen.ITEMS[int(t2.get("_sel"))], "highscores", "select arg")
	t2.free()
	# Escape still quits from any row, a volume row included.
	var t3 := _title("sfx_volume")
	var got: Array[String] = []
	t3.finished.connect(func(r: String, _d: Dictionary) -> void: got.append(r))
	_tap(t3, KEY_ESCAPE)
	check_eq(got, ["quit"] as Array[String], "Escape quits on EFFECTS VOLUME")
	t3.free()
	_settings_end()


func test_title_volume_left_right_clamp_repeat_and_preview() -> void:
	_settings_begin()
	_router_init()
	Settings.music_on = true
	Settings.sfx_on = true
	Settings.music_volume = 70
	Settings.sfx_volume = 100
	AudioManager.apply_settings()
	var t := _title("music_volume")
	check(AudioManager.is_title_music_playing(), "title music on")
	var fin: Array[String] = []
	t.finished.connect(func(r: String, _d: Dictionary) -> void: fin.append(r))
	# One press = one step, heard live: the Music bus follows at once, the title music is not restarted.
	_tap(t, KEY_LEFT)
	check_eq(Settings.music_volume, 60, "Left: −10 %")
	check_near(_bus_db("Music"), AudioManagerScript.volume_db(60), 1e-3, "music bus follows at once")
	check(AudioManager.is_title_music_playing(), "the title music keeps playing")
	check_eq(_stored("music_volume"), 60, "persisted")
	check_eq(t.sfx_calls, ["menu_move"] as Array[String], "menu blip for MUSIC VOLUME")
	# Holding Right: controlled repeat (0.35 s delay, 0.11 s interval) up to 100 %, then clamped.
	_key(KEY_RIGHT, true)
	_run(t, STEP)
	check_eq(Settings.music_volume, 70, "first step at once")
	_run(t, 0.3)
	check_eq(Settings.music_volume, 70, "no repeat before 0.35 s")
	_run(t, 0.5)
	check_eq(Settings.music_volume, 100, "repeat steps every 0.11 s, then clamps at 100 %")
	var calls := t.sfx_calls.size()
	_run(t, 0.5)
	check_eq(Settings.music_volume, 100, "stays at 100 %")
	check_eq(t.sfx_calls.size(), calls, "no sound while clamped")
	_key(KEY_RIGHT, false)
	_run(t, STEP * 2)
	# Holding Left from 100 %: reaches 0 % (mute) and stays there.
	_key(KEY_LEFT, true)
	_run(t, 2.0)
	_key(KEY_LEFT, false)
	_run(t, STEP * 2)
	check_eq(Settings.music_volume, 0, "held Left reaches 0 %")
	check(_bus_muted("Music"), "0 % mutes the music")
	check(AudioManager.is_title_music_playing(), "muting by volume does not stop the title music")
	_tap(t, KEY_RIGHT)
	check_eq(Settings.music_volume, 10, "back to 10 %")
	check(not _bus_muted("Music"), "10 % audible again (title music still running)")
	# EFFECTS VOLUME: the preview plays at the NEW gain.
	_tap(t, KEY_DOWN)
	_tap(t, KEY_DOWN)
	check_eq(TitleScreen.ITEMS[int(t.get("_sel"))], "sfx_volume", "on EFFECTS VOLUME")
	t.sfx_calls.clear()
	t.sfx_bus_db.clear()
	_tap(t, KEY_LEFT)
	check_eq(Settings.sfx_volume, 90, "Left: −10 %")
	check_eq(t.sfx_calls, [AudioManagerScript.VOLUME_PREVIEW_SFX] as Array[String], "preview effect")
	if t.sfx_bus_db.size() == 1:
		check_near(t.sfx_bus_db[0], AudioManagerScript.volume_db(90), 1e-3, "preview at the new gain")
	_tap(t, KEY_RIGHT)
	_tap(t, KEY_RIGHT)
	check_eq(Settings.sfx_volume, 100, "clamped at 100 %")
	check_eq(t.sfx_calls.size(), 2, "no preview for the clamped step")
	# Confirm on a volume row only previews: no change, no wrap, no screen change.
	_tap(t, KEY_ENTER)
	check_eq(Settings.sfx_volume, 100, "Enter does not change the volume")
	check_eq(t.sfx_calls.size(), 3, "Enter previews")
	check(fin.is_empty(), "the title never finished: %s" % [fin])
	check_eq(_stored("sfx_volume"), 100, "persisted")
	t.free()
	_settings_end()


## Controller on the title volume rows: stick left/right steps; A/X/Y/Start only preview (no change, no start),
## B is ignored, Select/Back still opens the highscores.
func test_title_volume_with_controller() -> void:
	_settings_begin()
	_swap_in()
	Settings.sfx_volume = 50
	Settings.music_volume = 50
	var t := _title("sfx_volume")
	var fin: Array[String] = []
	t.finished.connect(func(r: String, _d: Dictionary) -> void: fin.append(r))
	_stick_tap(t, Vector2(-0.8, 0.1))
	check_eq(Settings.sfx_volume, 40, "stick left: −10 %")
	_stick_tap(t, Vector2(0.9, 0.0))
	_stick_tap(t, Vector2(0.9, 0.0))
	check_eq(Settings.sfx_volume, 60, "stick right twice: +20 %")
	for b: JoyButton in [JOY_BUTTON_A, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_START, JOY_BUTTON_B]:
		_pad_tap(t, b)
	check_eq(Settings.sfx_volume, 60, "face buttons / Start do not change the volume")
	check(fin.is_empty(), "A/X/Y/Start/B on EFFECTS VOLUME do not leave the title: %s" % [fin])
	check_eq(t.sfx_calls.count(AudioManagerScript.VOLUME_PREVIEW_SFX), 3 + 4, "3 steps + 4 confirms preview, B is silent")
	_stick_tap(t, Vector2(0.0, -0.8))
	_stick_tap(t, Vector2(0.0, -0.8))
	check_eq(TitleScreen.ITEMS[int(t.get("_sel"))], "music_volume", "stick up twice → MUSIC VOLUME")
	_stick_tap(t, Vector2(-0.8, 0.0))
	check_eq(Settings.music_volume, 40, "stick left on MUSIC VOLUME")
	_pad_tap(t, JOY_BUTTON_BACK)
	check_eq(fin, ["highscores"] as Array[String], "Select/Back opens the highscores")
	t.free()
	_swap_out()
	_settings_end()


## Layout at 960 × 720 with 11 rows (two-player round): tagline above the panel, panel above the hints, labels clear of
## the bars.
func test_title_layout_fits() -> void:
	if Assets.font_title == null:
		Assets._ready()
	var panel := TitleScreen.menu_panel_rect()
	var logo := Assets.logo_texture()
	var logo_h := TitleScreen.LOGO_W * float(logo.get_height()) / float(logo.get_width()) if logo else 120.0
	var tagline := TitleScreen.LOGO_Y + 3.0 + logo_h * 0.5 + 22.0   # baseline at the lowest float position
	check(tagline + 8.0 < panel.position.y, "tagline (%.0f) above the menu panel (%.0f)" % [tagline, panel.position.y])
	var hint_top := TitleScreen.HINT_Y - 14 * 1.55 * 0.5
	check(panel.end.y + 16.0 < hint_top, "panel bottom %.0f clear of the hints (%.0f)" % [panel.end.y, hint_top])
	check(panel.position.x > 150.0 and panel.end.x < 810.0, "panel leaves room for the side demons")
	for item in ["music_volume", "sfx_volume"]:
		var c := Vector2(TitleScreen.CX, 300.0)
		var row := UiKit.menu_row_rect(c, TitleScreen.MENU_W, TitleScreen.MENU_FONT)
		var font := Assets.font_title
		var label_end := row.position.x + 30.0 + UiKit.text_width(font, TitleScreen.LABELS[item], TitleScreen.MENU_FONT)
		var vx := row.end.x - 30.0 - 18.0   # selected: value column moved left by the pointer
		var bar := UiKit.volume_bar_rect(Vector2(vx - UiKit.text_width(font, "100%", TitleScreen.MENU_FONT)
			- TitleScreen.MENU_FONT * 0.6, c.y), TitleScreen.MENU_FONT)
		var pointer_left := bar.position.x - 14.0 - 6.0
		check(label_end + 8.0 < pointer_left, "%s: label (to %.0f) clear of the bar pointer (%.0f)" % [item,
			label_end, pointer_left])


# --- §12 pause overlay ------------------------------------------------------------------------------
func _game(spy: AudioSpy) -> Node2D:
	_router_init()
	Run.start_new(1, 0, 1)
	Run.dev_flags = {"invincible": true}
	var gs: Node2D = LogicOnlyScreen.new()
	gs.set("audio", spy)
	gs.setup({"level": 1})
	gs._ready()
	var w: GameWorld = gs.get("world")
	var guard := 0
	while w.state == GameWorld.State.INTRO and guard < 400:
		_router_step()
		gs._process(STEP)
		guard += 1
	return gs


func test_pause_volume_adjust_does_not_resume_or_quit_and_persists() -> void:
	_settings_begin()
	Settings.music_on = true
	Settings.sfx_on = true
	Settings.music_volume = 100
	Settings.sfx_volume = 50
	AudioManager.apply_settings()
	var spy := AudioSpy.new()
	var gs := _game(spy)
	var w: GameWorld = gs.get("world")
	check_eq(w.state, GameWorld.State.PLAYING, "combat running")
	var fin: Array[String] = []
	gs.finished.connect(func(r: String, _d: Dictionary) -> void: fin.append(r))
	# Move left, then pause WHILE Left is still held: the held direction must not step a volume.
	_key(KEY_LEFT, true)
	_run(gs, 0.2)
	check(w.player_x < 480.0, "ship moved left")
	_key(KEY_P, true)
	_run(gs, STEP)
	check(gs.get("paused"), "P pauses")
	check(spy.calls.has("suspend(true)"), "game music silent in the pause")
	_key(KEY_P, false)
	_run(gs, 1.0)
	check_eq([Settings.music_volume, Settings.sfx_volume], [100, 50], "Left held from the game does not step a volume")
	_key(KEY_LEFT, false)
	_run(gs, STEP * 2)
	check_eq(int(gs.get("pause_sel")), 0, "MUSIC VOLUME selected")
	# Left/right on MUSIC VOLUME.
	_tap(gs, KEY_LEFT)
	check_eq(Settings.music_volume, 90, "Left: −10 %")
	check_near(_bus_db("Music"), AudioManagerScript.volume_db(90), 1e-3, "applied at once")
	check_eq(_stored("music_volume"), 90, "persisted")
	check(spy.calls.has("sfx:menu_move"), "menu blip")
	_tap(gs, KEY_RIGHT)
	_tap(gs, KEY_RIGHT)
	check_eq(Settings.music_volume, 100, "Right: back to 100 % and clamped")
	# Down → EFFECTS VOLUME; Right plays the preview at the new gain.
	_tap(gs, KEY_DOWN)
	check_eq(int(gs.get("pause_sel")), 1, "EFFECTS VOLUME selected")
	spy.calls.clear()
	spy.sfx_bus_db.clear()
	_tap(gs, KEY_RIGHT)
	check_eq(Settings.sfx_volume, 60, "Right: +10 %")
	check_eq(spy.calls, ["sfx:" + AudioManagerScript.VOLUME_PREVIEW_SFX] as Array[String], "preview effect")
	if spy.sfx_bus_db.size() == 1:
		check_near(spy.sfx_bus_db[0], AudioManagerScript.volume_db(60), 1e-3, "preview at the new gain")
	check_eq(_stored("sfx_volume"), 60, "persisted")
	# Holding Left: controlled repeat down to 0 % (mute), clamped there.
	_key(KEY_LEFT, true)
	_run(gs, 1.5)
	check_eq(Settings.sfx_volume, 0, "held Left reaches 0 %")
	check(_bus_muted("SFX"), "0 % mutes the effects")
	check(gs.get("paused"), "still paused after all the adjusting")
	check(fin.is_empty(), "neither resumed nor quit: %s" % [fin])
	check(not spy.calls.has("suspend(false)"), "game music stays silent while paused")
	# Resume with Left still held: the ship must not move until Left is released.
	var x0 := w.player_x
	_key(KEY_P, true)
	_run(gs, STEP)
	check(not gs.get("paused"), "P resumes")
	check(spy.calls.has("suspend(false)"), "game music back on resume")
	_key(KEY_P, false)
	_run(gs, 0.5)
	check_eq(w.player_x, x0, "Left held from the pause does not move the ship")
	_key(KEY_LEFT, false)
	_run(gs, STEP * 2)
	_key(KEY_RIGHT, true)
	_run(gs, 0.2)
	_key(KEY_RIGHT, false)
	_run(gs, STEP * 2)
	check(w.player_x > x0 + 20.0, "a fresh press moves the ship again")
	check_eq(Settings.sfx_volume, 0, "game input does not touch the volume")
	# Escape pauses, a volume step, Q still quits to the title.
	_tap(gs, KEY_ESCAPE)
	check(gs.get("paused"), "Escape pauses")
	_tap(gs, KEY_RIGHT)
	check_eq(Settings.sfx_volume, 10, "EFFECTS VOLUME still selected in the next pause")
	check(gs.get("paused") and fin.is_empty(), "still paused")
	_tap(gs, KEY_Q)
	check_eq(fin, ["quit"] as Array[String], "Q quits to the title")
	gs.free()
	spy.free()
	Run.dev_flags = {}
	AudioManager.stop_music()
	_settings_end()


## Controller: Start pauses / resumes, the stick selects and steps, A/B (fire) do nothing in the pause, Back
## quits to the title.
func test_pause_volume_with_controller() -> void:
	_settings_begin()
	Settings.music_volume = 50
	Settings.sfx_volume = 50
	var spy := AudioSpy.new()
	_swap_in()
	var gs := _game(spy)
	var fin: Array[String] = []
	gs.finished.connect(func(r: String, _d: Dictionary) -> void: fin.append(r))
	_pad_tap(gs, JOY_BUTTON_START)
	check(gs.get("paused"), "Start pauses")
	_stick_tap(gs, Vector2(0.0, 0.8))
	_stick_tap(gs, Vector2(0.8, 0.0))
	_pad_tap(gs, JOY_BUTTON_B)
	_pad_tap(gs, JOY_BUTTON_A)
	check(gs.get("paused"), "still paused")
	check_eq([Settings.music_volume, Settings.sfx_volume], [50, 60], "stick down + right: EFFECTS VOLUME 60 %")
	check(fin.is_empty(), "nothing finished")
	_pad_tap(gs, JOY_BUTTON_START)
	check(not gs.get("paused"), "Start resumes")
	_pad_tap(gs, JOY_BUTTON_START)
	check(gs.get("paused"), "Start pauses again")
	_pad_tap(gs, JOY_BUTTON_BACK)
	check_eq(fin, ["quit"] as Array[String], "Back quits to the title")
	gs.free()
	spy.free()
	_swap_out()
	Run.dev_flags = {}
	AudioManager.stop_music()
	_settings_end()


## Controller: the pause guards only the directions. The stick held from the game into the pause steps nothing
## until it was released and pushed again; fire (A) is not latched, so A held through pause → resume keeps firing
## (hold-to-fire, REFERENCE_DE); the stick still held when resuming does not move the ship until released.
func test_pause_guards_directions_not_fire_with_controller() -> void:
	_settings_begin()
	Settings.music_volume = 50
	Settings.sfx_volume = 50
	var spy := AudioSpy.new()
	_swap_in()
	var gs := _game(spy)
	var w: GameWorld = gs.get("world")
	# Stick left + A held in the game: the ship moves and fires.
	_stick(Vector2(-0.8, 0.0))
	_pad(JOY_BUTTON_A, true)
	_run(gs, 0.5)
	check(w.player_x < 480.0, "stick moves the ship")
	check(_shots_fired(spy) >= 1, "holding A fires")
	_pad_tap(gs, JOY_BUTTON_START)
	check(gs.get("paused"), "Start pauses")
	_run(gs, 1.0)
	check_eq([Settings.music_volume, Settings.sfx_volume], [50, 50], "stick held from the game steps no volume")
	check_eq(int(gs.get("pause_sel")), 0, "selection unchanged")
	_stick(Vector2.ZERO)
	_run(gs, STEP * 2)
	_stick_tap(gs, Vector2(0.8, 0.0))
	check_eq(Settings.music_volume, 60, "a fresh push steps at once")
	# Resume with the stick held left and A still held.
	_stick(Vector2(-0.8, 0.0))
	_run(gs, 0.2)
	check_eq(Settings.music_volume, 50, "the guard is gone after the fresh push: held left steps")
	spy.calls.clear()
	var x0 := w.player_x
	_pad_tap(gs, JOY_BUTTON_START)
	check(not gs.get("paused"), "Start resumes")
	_run(gs, 2.5)
	check_eq(w.player_x, x0, "stick held from the pause does not move the ship")
	check(_shots_fired(spy) >= 1, "A held through pause → resume keeps firing (%d salvos)" % _shots_fired(spy))
	_stick(Vector2.ZERO)
	_pad(JOY_BUTTON_A, false)
	_run(gs, STEP * 2)
	gs.free()
	spy.free()
	_swap_out()
	Run.dev_flags = {}
	AudioManager.stop_music()
	_settings_end()


func _shots_fired(spy: AudioSpy) -> int:
	var n := 0
	for c in spy.calls:
		if c.begins_with("sfx:shot_"):
			n += 1
	return n


## Attract mode has no pause: a direction ends the demo and changes no volume (SPEC §11.1).
func test_attract_mode_has_no_volume_menu() -> void:
	_settings_begin()
	_router_init()
	Settings.music_volume = 80
	Settings.sfx_volume = 80
	var gs: Node2D = LogicOnlyScreen.new()
	gs.setup({"attract": {"seed": 3, "level": 2}})
	var got: Array[String] = []
	gs.finished.connect(func(r: String, _d: Dictionary) -> void: got.append(r))
	gs._ready()
	_run(gs, 2.5)
	_key(KEY_LEFT, true)
	_run(gs, 0.5)
	_key(KEY_LEFT, false)
	_run(gs, STEP * 2)
	check_eq(got, ["exit"] as Array[String], "Left ends the demo")
	check(not gs.get("paused"), "no pause in a demo")
	check_eq([Settings.music_volume, Settings.sfx_volume], [80, 80], "volumes untouched")
	check(not FileAccess.file_exists(SCRATCH_CFG), "nothing saved")
	gs.free()
	_settings_end()
