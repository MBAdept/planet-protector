extends Node
## DEV ONLY (excluded from export). Drives the REAL main scene through a whole run: the game screens are
## played by the autopilot (pass --dev --autoplay [--invincible]), every other screen is confirmed by
## injected Enter presses. Logs every screen change with the run state and optionally saves screenshots.
##   godot --headless --path game res://dev/playthrough.tscn -- --dev --autoplay --invincible --level=1 \
##       [--timescale=4] [--shots=/abs/dir] [--limit=1800] [--display=<0|1|2>]
## --display: display mode (SPEC §18), read by the Display autoload / Main; the log states the mode and the
## playfield width every level is played with.
## Ends (exit code 0) when the title screen is reached again after the run, or exit code 1 on timeout.

var _main: Node
var _args := {}
var _last_screen := ""
var _t := 0.0
var _screen_t := 0.0
var _press_t := 0.0
var _pressed := false
var _shots := ""
var _shot_taken := {}
var _limit := 1800.0
var _started_run := false
var _log: Array[String] = []


func _ready() -> void:
	_args = RunFlow.parse_args(OS.get_cmdline_user_args())
	Engine.time_scale = float(_args.get("timescale", 1.0))
	_shots = String(_args.get("shots", ""))
	_limit = float(_args.get("limit", 1800.0))
	if _shots != "":
		DirAccess.make_dir_recursive_absolute(_shots)
	_main = load("res://main.tscn").instantiate()
	add_child(_main)
	_note("display mode %d (%s): logical %s" % [Display.mode(), Display.MODE_NAMES[Display.mode()], Display.logical_size()])


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.001)
	_t += real
	_screen_t += real
	var scr: String = String(_main.get("_screen_name"))
	if scr != _last_screen:
		var screen: Node = _main.get("_screen")
		var world: Variant = screen.get("world") if screen != null and scr == "level" else null
		_note("%7.1fs  %-12s level=%d score=%d lives=%d time=%s%s" % [_t, scr, Run.level, Run.score, Run.lives,
			Fmt.time(Run.active_time), "  width=%d" % (world as GameWorld).width if world != null else ""])
		if scr == "title" and _started_run:
			_finish(0)
			return
		if scr == "level":
			_started_run = true   # a screen before the run (e.g. the first-start display choice) does not count
		_last_screen = scr
		_screen_t = 0.0
	if _t > _limit:
		_note("TIMEOUT")
		_finish(1)
		return
	if _shots != "" and DisplayServer.get_name() != "headless":
		var key := "%s_%d" % [scr, Run.level]
		var when := 6.0 if scr == "level" else (12.5 if scr == "arrival" else 1.2)
		if not _shot_taken.has(key) and _screen_t >= when:
			_shot_taken[key] = true
			get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [_shots, Run.level, scr])
	if scr != "level":
		_drive_menu(real)


func _drive_menu(real: float) -> void:
	_press_t += real
	if not _pressed and _press_t > 0.7:
		_key(true)
	elif _pressed and _press_t > 0.85:
		_key(false)


func _key(down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ENTER
	ev.physical_keycode = KEY_ENTER
	ev.pressed = down
	Input.parse_input_event(ev)
	_pressed = down
	if not down:
		_press_t = 0.0


func _note(s: String) -> void:
	print(s)
	_log.append(s)


func _finish(code: int) -> void:
	_note("RESULT score=%d lives=%d time=%s" % [Run.score, Run.lives, Fmt.time(Run.active_time)])
	Engine.time_scale = 1.0
	get_tree().quit(code)
