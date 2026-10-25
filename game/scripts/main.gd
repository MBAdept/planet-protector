extends Node
## Screen manager and run flow (docs/SPEC.md §11, §17.1, §17.3).
## Every screen is created with `new()`, configured with `setup(args)` before entering the tree and
## reports back through `finished(result, data)`. The flow decisions live in RunFlow (pure, tested).
##
## Dev / test command line (user args after `--`):
##   --level=N --ship=K --difficulty=D       start a run directly at level N (skips menus)
##   --dev [--invincible] [--autoplay]       dev flags for GameScreen (Run.dev_flags)
##   --screen=<name> [--arrival=N] [--name=ABC]  open one screen with fake run data (see RunFlow.SCREENS);
##                                           --name: initial name (name_entry), highlighted row of the fake
##                                           list (highscores), fake BEST line (title) – only without stored scores
##   --select=<item> [--pending-display=<m>] (with --screen=title) initial menu row / a pending DISPLAY choice
##   --screen=attract                        start a demo run (attract mode) directly
##   --attract-after=<s>                     idle time on the title before the demo starts (default 90)
##   --attract-level=N --attract-seed=S      fixed demo level (1–20 except 13) / random seed (deterministic captures)
##   --screenshot=<abs path.png> [--screenshot-delay=<s>]   save a viewport PNG, then quit (16:9 modes: exactly the
##                                           render size 1920×1080 / 2560×1440; mode 0: the window, 1280×960)
##   --quit-after=<s>                        quit after s seconds
##   --display=<0|1|2>                       display mode for this run (Display; not stored, no first-start screen)
##   --first-start                           show the first-start display choice even if one is stored

const GameScreenScript := preload("res://scripts/game/game_screen.gd")
const SCREEN_SCRIPTS := {
	"title": preload("res://scripts/screens/title_screen.gd"),
	"ship_select": preload("res://scripts/screens/ship_select_screen.gd"),
	"interlevel": preload("res://scripts/screens/interlevel_screen.gd"),
	"arrival": preload("res://scripts/screens/arrival_screen.gd"),
	"mars_rules": preload("res://scripts/screens/mars_rules_screen.gd"),
	"bonus_result": preload("res://scripts/screens/bonus_result_screen.gd"),
	"victory": preload("res://scripts/screens/victory_screen.gd"),
	"game_over": preload("res://scripts/screens/game_over_screen.gd"),
	"name_entry": preload("res://scripts/screens/name_entry_screen.gd"),
	"highscores": preload("res://scripts/screens/highscores_screen.gd"),
	"display_select": preload("res://scripts/screens/display_select_screen.gd"),
}

var _screen: Node = null
var _screen_name := ""
var _args := {}
## Level the run is at (for "level": the level currently played / just finished).
var _level := 1
var _shot_path := ""
var _shot_delay := 0.0
var _shot_busy := false
var _clock := 0.0
## The highscore list was opened from the title menu (return there with HIGHSCORES selected).
var _hs_from_title := false


func _ready() -> void:
	_args = RunFlow.parse_args(OS.get_cmdline_user_args())
	var dev := _args.has("dev")
	Run.dev_flags = {
		"dev": dev,
		"invincible": dev and _args.has("invincible"),
		"autoplay": dev and _args.has("autoplay"),
	}
	# Display mode (--display is read by the Display autoload itself, so dev scenes get it too): the canvas is
	# set up already; the window follows here (not in screenshot runs – their image is the render size anyway).
	Display.apply_canvas()
	if not _args.has("screenshot"):
		Display.apply_window()
	AudioManager.apply_settings()
	if _args.has("screenshot"):
		_take_screenshot_later(String(_args["screenshot"]), RunFlow.arg_float(_args, "screenshot-delay", 1.0))
	if _args.has("quit-after"):
		_quit_later(RunFlow.arg_float(_args, "quit-after", 5.0))
	if _args.has("screen"):
		_open_dev_screen(String(_args["screen"]))
	elif _args.has("level"):
		var lvl := RunFlow.arg_int(_args, "level", 1, LevelData.FIRST_LEVEL, LevelData.LAST_LEVEL)
		Run.start_new(_arg_difficulty(), _arg_ship(), lvl)
		_go(RunFlow.step("level", lvl))
	else:
		_go(RunFlow.step(RunFlow.first_screen(Settings.display_chosen, Display.forced_mode >= 0,
			_args.has("first-start"))))


# --- Flow ----------------------------------------------------------------------------------------
func _go(st: Dictionary, extra: Dictionary = {}) -> void:
	var screen_name: String = st["screen"]
	var lvl := int(st.get("level", 0))
	if lvl > 0:
		_level = lvl
	match screen_name:
		"quit":
			Run.active = false
			get_tree().quit()
		"level":
			_start_level(_level)
		"display_select":
			Run.active = false
			_open("display_select", extra)
		"title":
			Run.active = false
			if _args.has("attract-after"):
				extra = _merge({"attract_after": RunFlow.arg_float(_args, "attract-after", AttractDirector.IDLE_TIME)}, extra)
			_open("title", extra)
		"attract":
			_start_attract()
		"ship_select":
			_open("ship_select", {"ship": Run.ship_id})
		"interlevel", "arrival", "bonus_result", "mars_rules":
			_open(screen_name, _merge({"level": _level}, extra))
		"victory", "game_over":
			Run.active = false
			_open(screen_name, _merge({"level": _level,
				"qualifies": _run_qualifies()}, extra))
		"name_entry":
			_open("name_entry", _merge({"difficulty": Run.difficulty, "score": Run.score, "time": Run.active_time,
				"level": Run.level, "ship": Run.ship_id}, extra))
		"highscores":
			_open("highscores", _merge({"difficulty": Settings.difficulty}, extra))
		_:
			push_warning("Main: unknown screen '%s'" % screen_name)
			_open("title")


func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	out.merge(b, true)
	return out


func _run_qualifies() -> bool:
	return RunFlow.entry_qualifies(Run.score, Settings.qualifies(Run.difficulty, Run.score, Run.active_time))


func _open(screen_name: String, screen_args: Dictionary = {}) -> void:
	var script: GDScript = SCREEN_SCRIPTS[screen_name]
	var s: Node = script.new()
	s.setup(screen_args)
	s.finished.connect(_on_screen_finished.bind(screen_name, s))
	_show(s, screen_name)


func _start_level(n: int) -> void:
	Run.level = n
	Run.active = true
	var gs: Node = GameScreenScript.new()
	gs.setup({"level": n})
	gs.finished.connect(_on_screen_finished.bind("level", gs))
	_show(gs, "level")


## Attract mode (SPEC §11.1): a demo run of the GameScreen. It never touches Run – Run.active stays false.
func _start_attract() -> void:
	var gs: Node = GameScreenScript.new()
	gs.setup({"attract": {"seed": RunFlow.arg_int(_args, "attract-seed", randi() & 0x7fffffff, 0, 0x7fffffff),
		"level": RunFlow.arg_int(_args, "attract-level", 0, 0, LevelData.LAST_LEVEL)}})
	gs.finished.connect(_on_screen_finished.bind("attract", gs))
	_show(gs, "attract")


func _show(screen: Node, screen_name: String) -> void:
	if _screen:
		if _screen.get_parent() == self:
			remove_child(_screen)
		_screen.queue_free()
	_screen = screen
	_screen_name = screen_name
	add_child(screen)
	InputRouter.require_release()


func _on_screen_finished(result: String, data: Dictionary, from: String, emitter: Node) -> void:
	# Switch screens at the end of the frame, never in the middle of the emitting screen's callback.
	_handle_finished.call_deferred(result, data, from, emitter)


func _handle_finished(result: String, data: Dictionary, from: String, emitter: Node) -> void:
	if emitter != _screen:
		return   # stale signal from a screen that has already been replaced
	var end_of_run := from == "victory" or from == "game_over"
	var nxt := RunFlow.next(from, result, _level, _run_qualifies() if end_of_run else false)
	match from:
		"title":
			_hs_from_title = result == "highscores"
			if _hs_from_title:
				_go(nxt, {"difficulty": Settings.difficulty})
				return
			if result == "display":
				_go(nxt, {"select": "display"})   # the title again, on the new canvas
				return
		"ship_select":
			if result == "confirm":
				Run.start_new(Settings.difficulty, int(data.get("ship", 0)))
				_level = LevelData.FIRST_LEVEL
				nxt = RunFlow.next(from, result, _level)
		"victory", "game_over":
			_hs_from_title = false
			_go(nxt, {"difficulty": Run.difficulty})
			return
		"name_entry":
			_go(nxt, {"difficulty": int(data.get("difficulty", Run.difficulty)), "rank": int(data.get("rank", -1))})
			return
		"highscores":
			_go(nxt, {"select": "highscores" if _hs_from_title else "start"})
			_hs_from_title = false
			return
	_go(nxt)


# --- Dev helpers ---------------------------------------------------------------------------------
func _arg_difficulty() -> int:
	return RunFlow.arg_int(_args, "difficulty", Settings.difficulty, 0, 3)


func _arg_ship() -> int:
	return RunFlow.arg_int(_args, "ship", 0, 0, ShipData.SHIPS.size() - 1)


## Opens a single screen with plausible fake run data (for screenshots / visual checks).
func _open_dev_screen(screen_name: String) -> void:
	if screen_name == "attract":
		AudioManager.play_title_music()   # a demo runs on the title music (normally it is already playing)
		_go(RunFlow.step("attract"))
		return
	if not SCREEN_SCRIPTS.has(screen_name):
		push_warning("Main: unknown --screen=%s, valid: %s, attract" % [screen_name, ", ".join(RunFlow.SCREENS)])
		_go(RunFlow.step("title"))
		return
	var diff := _arg_difficulty()
	var ship := _arg_ship()
	var lvl := RunFlow.arg_int(_args, "level", 5, LevelData.FIRST_LEVEL, LevelData.LAST_LEVEL)
	match screen_name:
		"arrival":
			lvl = RunFlow.arg_int(_args, "arrival", 3, 1, LevelData.LAST_LEVEL)
			if not LevelData.ARRIVAL_AFTER.has(lvl):
				lvl = 3
		"bonus_result":
			lvl = LevelData.BONUS_LEVEL
		"mars_rules":
			lvl = LevelData.BONUS_LEVEL
		"victory":
			lvl = LevelData.LAST_LEVEL
	Run.start_new(diff, ship, lvl)
	Run.score = 1000 + lvl * 1234
	Run.active_time = 41.7 * lvl + 12.3
	Run.lives = 2
	var lr: Dictionary = LevelData.level(lvl)
	Run.last_level_result = {"level": lvl, "completion_bonus": int(lr["bonus"]),
		"extra_life": LevelData.flawless_extra_life(lvl), "flawless": true}
	var remaining := 37
	var factor := int(ShipData.ship(ship)["bonus_factor"])
	var bonus := LevelData.bonus_value(remaining, ship)
	Run.last_bonus_result = {"remaining": remaining, "factor": factor, "bonus": bonus,
		"extra_life": LevelData.bonus_gives_extra_life(bonus)}
	_level = lvl
	match screen_name:
		"display_select":
			Run.active = false
			_go(RunFlow.step(screen_name))
			return
		"title", "ship_select":
			Run.active = false
			Run.score = 0
			var extra := {}
			if screen_name == "title" and _args.has("name") and Settings.get_highscores(Settings.difficulty).is_empty():
				extra["preview_best"] = {"name": _arg_name(), "score": 48000}
			if screen_name == "title" and _args.has("select"):
				extra["select"] = String(_args["select"])
			if screen_name == "title" and _args.has("pending-display"):
				extra["display_pending"] = RunFlow.arg_int(_args, "pending-display", 0, 0, Display.MODE_COUNT - 1)
			_go(RunFlow.step(screen_name), extra)
		"highscores":
			var extra := {"difficulty": diff}
			if Settings.get_highscores(diff).is_empty():
				extra["preview_entries"] = _fake_highscores()
				extra["rank"] = 2
			_go(RunFlow.step("highscores"), extra)
		"name_entry":
			_go(RunFlow.step(screen_name, lvl), {"initial_name": String(_args.get("name", ""))})
		_:
			_go(RunFlow.step(screen_name, lvl))


## --name as it would be stored (upper case, valid characters, max Settings.NAME_MAX).
func _arg_name() -> String:
	return Settings.sanitize_name(String(_args.get("name", "")))


## Fake top 10 with names of 2–8 characters; --name replaces the highlighted row (index 2).
func _fake_highscores() -> Array:
	var names := ["STARDUST", "ACE", "ZED-9", "PILOT", "KIRA", "MAX_", "COMET-42", "IO", "VEGA", "B0B"]
	if _args.has("name"):
		names[2] = _arg_name()
	var out: Array = []
	for i in 10:
		out.append({"name": names[i], "score": 48000 - i * 3870 - (i * i) * 113,
			"time": 1500.0 - i * 61.3, "level": 20 - i * 2, "ship": i % 6})
	return out


func _take_screenshot_later(path: String, delay: float) -> void:
	_shot_path = path
	_shot_delay = maxf(delay, 0.0)


## Screenshot delay is measured with the same process deltas the screens see (so a delay of 5 s
## shows a screen at its own time 5 s even if the first frames were slow, e.g. under llvmpipe).
func _process(delta: float) -> void:
	if _shot_path == "":
		return
	_clock += delta
	if _clock >= _shot_delay and not _shot_busy:
		_shot_busy = true
		_capture.call_deferred()


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		DirAccess.make_dir_recursive_absolute(_shot_path.get_base_dir())
		var err := img.save_png(_shot_path)
		var st: Variant = _screen.get("time") if _screen else null
		print("Screenshot saved: %s (%s)%s" % [_shot_path, error_string(err),
			"" if st == null else " at screen time %.2f s" % float(st)])
	get_tree().quit()


func _quit_later(seconds: float) -> void:
	await get_tree().create_timer(maxf(seconds, 0.0), true, false, true).timeout
	get_tree().quit()
