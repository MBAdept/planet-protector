extends TestBase
## Review tests for the ui package (docs/SPEC.md §11, §12, §13, §17).
## Tests run inside run_tests.gd's _initialize, i.e. before the SceneTree is live: autoloads exist but their
## _ready has not run and nothing is inside the tree. Screens are therefore driven by hand
## (_ready / _process), and InputRouter is initialised and stepped manually. Every test releases the keys
## it pressed so no state leaks into later tests.

const InterlevelScreen := preload("res://scripts/screens/interlevel_screen.gd")
const ArrivalScreen := preload("res://scripts/screens/arrival_screen.gd")
const TitleScreen := preload("res://scripts/screens/title_screen.gd")

const STEP := 1.0 / 60.0


## Interlevel that records every sound it starts instead of playing it.
class SpyInterlevel extends InterlevelScreen:
	var sfx_calls: Array[String] = []

	func sfx(sfx_name: String) -> void:
		sfx_calls.append(sfx_name)


# --- helpers -------------------------------------------------------------------------------------
func _router_init() -> void:
	if (InputRouter.get("_down") as Dictionary).is_empty():
		InputRouter._ready()
	InputRouter.set_text_mode(false)
	_router_step()


func _router_step(dt: float = STEP) -> void:
	Input.flush_buffered_events()
	InputRouter._process(dt)


func _key(code: Key, pressed: bool, unicode: int = 0) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	ev.unicode = unicode if pressed else 0
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	return ev


func _release_all(codes: Array) -> void:
	for c in codes:
		_key(c, false)
	_router_step()
	_router_step()


## Steps a (not-in-tree) screen and the router together for `seconds`.
func _run(screen: Node, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 1e-6:
		_router_step()
		screen._process(STEP)
		t += STEP


# --- §11 exact texts / progress lines ------------------------------------------------------------
func test_all_arrival_texts_and_targets_exact() -> void:
	var expected := {
		3: ["Neptun has been secured - approaching Uranus", "uranus"],
		6: ["Uranus has been secured - approaching Saturn", "saturn"],
		9: ["Saturn has been secured - approaching Jupiter", "jupiter"],
		12: ["Jupiter has been secured - approaching Mars", "mars"],
		16: ["Mars has been secured - protect EARTH!", "earth"],
	}
	check_eq(LevelData.ARRIVAL_AFTER.keys().size(), 5, "exactly five arrival sequences")
	for n: int in expected:
		check(LevelData.ARRIVAL_AFTER.has(n), "arrival after %d" % n)
		check_eq(LevelData.ARRIVAL_AFTER[n]["text"], expected[n][0], "arrival text after %d" % n)
		check_eq(LevelData.ARRIVAL_AFTER[n]["target"], expected[n][1], "arrival target after %d" % n)


func test_victory_text_exact() -> void:
	var exact := "You are a real champion on the trigger. You moved smoothly through enemy lines, you destroyed them all! Everlasting love to You, oh great PLANET PROTECTOR!"
	check_eq(LevelData.VICTORY_TEXT, exact, "victory text")


func test_interlevel_progress_text_for_every_level() -> void:
	var expected := {
		1: "2 more battles until Uranus", 2: "1 more battle until Uranus", 3: "Neptune secured!",
		4: "2 more battles until Saturn", 5: "1 more battle until Saturn", 6: "Uranus secured!",
		7: "2 more battles until Jupiter", 8: "1 more battle until Jupiter", 9: "Saturn secured!",
		10: "2 more battles until Mars", 11: "1 more battle until Mars", 12: "Jupiter secured!",
		14: "2 more battles until Earth", 15: "1 more battle until Earth", 16: "Mars secured!",
		17: "3 more battles to defend Earth", 18: "2 more battles to defend Earth",
		19: "1 more battle to defend Earth",
	}
	for n: int in expected:
		check_eq(LevelData.progress_text(n), expected[n], "interlevel %d" % n)


# --- §11 run flow branches -----------------------------------------------------------------------
func test_run_flow_every_branch() -> void:
	check_eq(RunFlow.next("title", "quit", 0)["screen"], "quit")
	check_eq(RunFlow.next("title", "highscores", 0)["screen"], "highscores")
	check_eq(RunFlow.next("highscores", "back", 0)["screen"], "title")
	check_eq(RunFlow.next("ship_select", "back", 0)["screen"], "title")
	check_eq(RunFlow.next("level", "quit", 13)["screen"], "title", "quit from pause in the bonus level")
	check_eq(RunFlow.next("level", "completed", 13)["screen"], "bonus_result")
	check_eq(RunFlow.next("bonus_result", "continue", 13)["screen"], "mars_rules")
	var st := RunFlow.next("mars_rules", "continue", 13)
	check_eq([st["screen"], st["level"]], ["level", 14])
	check_eq(RunFlow.next("interlevel", "continue", 13)["screen"], "level", "no arrival after 13")
	for n in range(1, 21):
		var nx := RunFlow.next("interlevel", "continue", n)
		var want := "arrival" if n in [3, 6, 9, 12, 16] else ("victory" if n == 20 else "level")
		check_eq(nx["screen"], want, "after interlevel %d" % n)


# --- §12 release guard ---------------------------------------------------------------------------
func test_release_guard_blocks_held_enter_after_screen_change() -> void:
	_router_init()
	_key(KEY_ENTER, true)
	_router_step()
	check(InputRouter.confirm_pressed(), "fresh press confirms")
	InputRouter.require_release()   # Main does this on every screen change
	for i in 30:
		_router_step()
		check(not InputRouter.confirm_pressed(), "held Enter must not confirm the next screen (frame %d)" % i)
	_key(KEY_ENTER, false)
	_router_step()
	_key(KEY_ENTER, true)
	_router_step()
	check(InputRouter.confirm_pressed(), "a new press after the release confirms")
	_release_all([KEY_ENTER])


func test_release_guard_blocks_held_fire_after_screen_change() -> void:
	_router_init()
	_key(KEY_SPACE, true)
	_router_step()
	InputRouter.require_release()
	_router_step()
	check(not InputRouter.fire_held(), "Space held from ship select must not fire before a release")
	_release_all([KEY_SPACE])


# --- §13 name entry: text mode -------------------------------------------------------------------
func test_text_mode_letters_are_not_directions_but_arrows_are() -> void:
	_router_init()
	InputRouter.set_text_mode(true)
	for code in [KEY_W, KEY_A, KEY_S, KEY_D]:
		_key(code, true)
		_router_step()
		check_eq(InputRouter.menu_direction(), Vector2i.ZERO, "letter %s in text mode" % OS.get_keycode_string(code))
		_key(code, false)
		_router_step()
	_key(KEY_UP, true)
	_router_step()
	check_eq(InputRouter.menu_direction(), Vector2i(0, -1), "arrow keys still navigate in text mode")
	_key(KEY_UP, false)
	InputRouter.set_text_mode(false)
	_release_all([KEY_UP])


# --- §13 sorting ---------------------------------------------------------------------------------
func test_highscore_sort_score_desc_then_time_asc() -> void:
	var list: Array = [
		{"name": "C", "score": 100, "time": 50.0}, {"name": "A", "score": 300, "time": 90.0},
		{"name": "B", "score": 100, "time": 49.95}, {"name": "D", "score": 300, "time": 89.99},
	]
	Settings.sort_entries(list)
	var names: Array[String] = []
	for e in list:
		names.append(String(e["name"]))
	check_eq(names, ["D", "A", "B", "C"] as Array[String], "score desc, then time asc (full precision)")


# --- §11 / §14 arrival must be completely silent ---------------------------------------------------
## BUG (review): confirming the interlevel after levels 3/6/9/12/16 starts the 0.55 s "menu_confirm"
## sound in the same frame the silent arrival begins, and the arrival only calls stop_music(), so the
## sound (plus the tail of the 3 s level_complete jingle) plays into the arrival. Recorded with Movie
## Maker: audible for ~1.5 s after the arrival appeared (peak -5.4 dBFS on its first frame).
## Passes when either no sound is started at that hand-over, or the arrival silences effects (SFX bus
## muted while it runs).
func test_hand_over_into_arrival_starts_no_sound() -> void:
	_router_init()
	for n in LevelData.ARRIVAL_AFTER:
		var spy := SpyInterlevel.new()
		spy.setup({"level": n})
		spy._ready()
		_run(spy, InterlevelScreen.CONFIRM_DELAY + 0.1)
		_key(KEY_ENTER, true)
		_run(spy, STEP)
		check(spy.is_finished(), "interlevel %d continues on Enter" % n)
		InputRouter.require_release()
		var arrival := ArrivalScreen.new()
		arrival.setup({"level": n})
		arrival._ready()
		_run(arrival, 0.2)
		var bus := AudioServer.get_bus_index("SFX")
		var silenced := bus >= 0 and AudioServer.is_bus_mute(bus)
		check(spy.sfx_calls.is_empty() or silenced,
			"after level %d the arrival starts while %s plays (arrival must be completely silent)" % [n, spy.sfx_calls])
		_release_all([KEY_ENTER])
		spy.free()
		arrival.free()
	AudioManager.apply_settings()


# --- §11 title options ---------------------------------------------------------------------------
## BUG (review, polish): the menu auto-repeat (0.35 s / 0.11 s) also drives the ON/OFF toggles, so holding
## Left/Right on MUSIC (or SOUND EFFECTS) flickers the setting ~8x per second (16 flips in 2 s measured
## through main.tscn), muting/unmuting the bus and rewriting settings.cfg every time. A held direction
## should flip an ON/OFF option once. The user's settings file and values are restored afterwards.
func test_title_onoff_toggle_does_not_autorepeat() -> void:
	var path := Settings.SETTINGS_PATH
	var had_file := FileAccess.file_exists(path)
	var backup := FileAccess.get_file_as_string(path) if had_file else ""
	var music0 := Settings.music_on
	var sfx0 := Settings.sfx_on
	_router_init()
	var title := TitleScreen.new()
	title.setup({"select": "music"})
	title._ready()
	_run(title, 0.1)
	var flips := 0
	var last := Settings.music_on
	_key(KEY_RIGHT, true)
	var t := 0.0
	while t < 1.0:
		_router_step()
		title._process(STEP)
		t += STEP
		if Settings.music_on != last:
			flips += 1
			last = Settings.music_on
	_release_all([KEY_RIGHT])
	title.free()
	# restore the user's settings (values + file)
	Settings.music_on = music0
	Settings.sfx_on = sfx0
	AudioManager.apply_settings()
	if had_file:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(flips >= 1, "pressing Right on MUSIC toggles it")
	check(flips <= 1, "holding Right for 1 s on MUSIC must flip it once, flipped %d times" % flips)
