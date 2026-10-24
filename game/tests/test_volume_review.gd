extends TestBase
## Review of the volume package (feedback round 3; docs/SPEC.md §12, §14): defects found by the reviewer.
## Each test pins the behaviour the spec / the previous version require and FAILS on the reviewed code.
## Same harness as tests/test_volume.gd: the screen is driven by hand before the SceneTree is live, the
## InputRouter is stepped manually, every key pressed is released again, and Settings are redirected to a
## scratch file and restored afterwards (the player's settings.cfg is never touched).

const AudioManagerScript := preload("res://scripts/autoload/audio_manager.gd")
const GameScreenScript := preload("res://scripts/game/game_screen.gd")

const STEP := 1.0 / 60.0
const SCRATCH_CFG := "user://test_volume_review_settings.cfg"


## Sound output of the GameScreen: records effects; no real playback, no music.
class AudioSpy extends AudioManagerScript:
	var calls: Array[String] = []

	func play_sfx(sfx_name: String, _volume_db: float = 0.0, _pitch: float = 1.0) -> void:
		calls.append("sfx:" + sfx_name)

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


# --- Helpers -------------------------------------------------------------------------------------
var _saved := {}


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


func _run(screen: Node, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 1e-6:
		_router_step()
		screen._process(STEP)
		t += STEP


func _tap(screen: Node, code: Key) -> void:
	_key(code, true)
	_run(screen, STEP)
	_key(code, false)
	_run(screen, STEP * 2)


## Level 1 with the INTERCEPTOR (ship 0), invincible, run until the combat has started.
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


func _shots_fired(spy: AudioSpy) -> int:
	var n := 0
	for c in spy.calls:
		if c.begins_with("sfx:shot_"):
			n += 1
	return n


# --- Findings ------------------------------------------------------------------------------------
## Finding: the pause's resume release guard latches EVERY held button, the fire buttons included, so a fire
## button held through pause → resume no longer fires until it is released and pressed again. The task only
## asked for a MOVEMENT release guard on resume ("Movement keys must not leak into the game after resuming");
## holding fire is explicitly allowed (REFERENCE_DE A/B "Gedrückthalten der Feuertaste ist erlaubt"), A/B do
## nothing in the pause, and before this change holding fire kept firing after a resume. docs/SPEC.md §12
## (as written by the package) also only promises the guard for a movement direction.
func test_fire_held_through_pause_keeps_firing_after_resume() -> void:
	_settings_begin()
	var spy := AudioSpy.new()
	var gs := _game(spy)
	var w: GameWorld = gs.get("world")
	check_eq(w.state, GameWorld.State.PLAYING, "combat running")
	# Hold fire: the ship fires (hold-to-fire is allowed).
	_key(KEY_SPACE, true)
	_run(gs, 0.5)
	check(_shots_fired(spy) >= 1, "holding Space fires")
	# Pause and resume with P while Space stays held the whole time.
	_tap(gs, KEY_P)
	check(gs.get("paused"), "P pauses")
	_run(gs, 0.5)
	spy.calls.clear()
	var shots_before := w.shots.size()
	_tap(gs, KEY_P)
	check(not gs.get("paused"), "P resumes")
	# 2.5 s is enough for any salvo still in flight from before the pause to leave the field (500 px/s).
	_run(gs, 2.5)
	check(_shots_fired(spy) >= 1,
		"Space held through pause/resume keeps firing after the resume (fired %d salvos, %d shots in flight before)"
		% [_shots_fired(spy), shots_before])
	_key(KEY_SPACE, false)
	_run(gs, STEP * 2)
	gs.free()
	spy.free()
	Run.dev_flags = {}
	AudioManager.stop_music()
	_settings_end()


## Same root cause: fire pressed DURING the pause (A/B/Space do nothing there) and held into the resume – the
## player resumes with the trigger already down, ready to shoot – does not fire until released and re-pressed.
func test_fire_pressed_in_pause_and_held_fires_after_resume() -> void:
	_settings_begin()
	var spy := AudioSpy.new()
	var gs := _game(spy)
	_run(gs, 2.0)   # no salvo of ours in flight
	_tap(gs, KEY_P)
	check(gs.get("paused"), "P pauses")
	_key(KEY_SPACE, true)
	_run(gs, 0.3)
	check(gs.get("paused"), "Space does nothing in the pause")
	check_eq(_shots_fired(spy), 0, "no shot while paused")
	_tap(gs, KEY_P)
	check(not gs.get("paused"), "P resumes")
	_run(gs, 1.0)
	check(_shots_fired(spy) >= 1, "Space held when resuming fires (fired %d salvos)" % _shots_fired(spy))
	_key(KEY_SPACE, false)
	_run(gs, STEP * 2)
	gs.free()
	spy.free()
	Run.dev_flags = {}
	AudioManager.stop_music()
	_settings_end()
