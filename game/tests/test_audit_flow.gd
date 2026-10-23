extends TestBase
## Audit (flow): controller semantics per context (REFERENCE_DE.md §L), driven through the REAL screens.
## No joypad can be connected in the headless runner, so the InputRouter autoload temporarily gets a
## subclass whose only changes are `_joy()` / `_left_sticks()` reading a fake button table / fake left
## stick (all mapping logic stays the production code). The original script is restored after every test.

const TitleScreen := preload("res://scripts/screens/title_screen.gd")
const ShipSelectScreen := preload("res://scripts/screens/ship_select_screen.gd")
const HighscoresScreen := preload("res://scripts/screens/highscores_screen.gd")
const NameEntryScreen := preload("res://scripts/screens/name_entry_screen.gd")
const InterlevelScreen := preload("res://scripts/screens/interlevel_screen.gd")

const STEP := 1.0 / 60.0


class FakePadRouter extends "res://scripts/autoload/input_router.gd":
	var pad := {}
	var stick := Vector2.ZERO

	func _joy(button: JoyButton) -> bool:
		return bool(pad.get(button, false))

	func _left_sticks() -> Dictionary:
		return {0: stick}


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


func _pad(button: JoyButton, down: bool) -> void:
	InputRouter.pad[button] = down


func _run(screen: Node, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 1e-6:
		InputRouter._process(STEP)
		screen._process(STEP)
		t += STEP


## Presses and releases a pad button while stepping the screen; returns [finished?, result].
func _tap(screen: Node, button: JoyButton) -> Array:
	var res := [false, ""]
	var cb := func(r: String, _d: Dictionary) -> void:
		res[0] = true
		res[1] = r
	screen.finished.connect(cb)
	_pad(button, true)
	_run(screen, STEP * 3)
	_pad(button, false)
	_run(screen, STEP * 3)
	screen.finished.disconnect(cb)
	return res


# --- L: title ------------------------------------------------------------------------------------
func test_title_controller_a_x_y_start_confirm_b_ignored_back_highscores() -> void:
	_swap_in()
	for b: JoyButton in [JOY_BUTTON_B]:
		var t := TitleScreen.new()
		t.setup({"select": "start"})
		t._ready()
		_run(t, 0.1)
		var r := _tap(t, b)
		check(not r[0], "B must be ignored on the title, got finished(%s)" % r[1])
		t.free()
	for b: JoyButton in [JOY_BUTTON_A, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_START]:
		var t := TitleScreen.new()
		t.setup({"select": "start"})
		t._ready()
		_run(t, 0.1)
		var r := _tap(t, b)
		check(r[0] and r[1] == "start", "pad button %d confirms START GAME on the title (got %s)" % [b, r])
		t.free()
	var t2 := TitleScreen.new()
	t2.setup({"select": "start"})
	t2._ready()
	_run(t2, 0.1)
	var r2 := _tap(t2, JOY_BUTTON_BACK)
	check(r2[0] and r2[1] == "highscores", "Select/Back opens the highscores from the title (got %s)" % [r2])
	t2.free()
	_swap_out()


# --- L: ship select ------------------------------------------------------------------------------
func test_ship_select_controller_a_confirms_b_goes_back() -> void:
	_swap_in()
	for b: JoyButton in [JOY_BUTTON_A, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_START]:
		var s := ShipSelectScreen.new()
		s.setup({"ship": 2})
		s._ready()
		_run(s, 0.1)
		var r := _tap(s, b)
		check(r[0] and r[1] == "confirm", "pad button %d confirms the ship (got %s)" % [b, r])
		s.free()
	var s2 := ShipSelectScreen.new()
	s2.setup({"ship": 2})
	s2._ready()
	_run(s2, 0.1)
	var r2 := _tap(s2, JOY_BUTTON_B)
	check(r2[0] and r2[1] == "back", "B goes back from the ship select (got %s)" % [r2])
	s2.free()
	_swap_out()


# --- L: highscores (sub-menu) --------------------------------------------------------------------
func test_highscores_controller_b_goes_back() -> void:
	_swap_in()
	for b: JoyButton in [JOY_BUTTON_B, JOY_BUTTON_START, JOY_BUTTON_X]:
		var h := HighscoresScreen.new()
		h.setup({"difficulty": 1})
		h._ready()
		_run(h, 0.1)
		var r := _tap(h, b)
		check(r[0] and r[1] == "back", "pad button %d leaves the highscores (got %s)" % [b, r])
		h.free()
	_swap_out()


# --- L: name editor with controller --------------------------------------------------------------
func test_name_entry_controller_b_deletes_x_y_start_confirm_a_ignored() -> void:
	_swap_in()
	for b: JoyButton in [JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_START]:
		var n := NameEntryScreen.new()
		n.setup({"difficulty": 1, "score": 0, "time": 1.0, "level": 1, "ship": 0, "initial_name": "AB"})
		n._ready()
		_run(n, 0.1)
		# A is a fire button: it must not confirm or delete here.
		var ra := _tap(n, JOY_BUTTON_A)
		check(not ra[0], "A does not confirm the name entry")
		check_eq(n.editor.text, "AB", "A leaves the name unchanged")
		var rb := _tap(n, JOY_BUTTON_B)
		check(not rb[0], "B does not leave the name entry")
		check_eq(n.editor.text, "A", "B deletes the last character")
		# X / Y / Start are the confirm the screen polls (the screen itself is not stepped here, so the
		# highscore file is never written by this test).
		_pad(b, true)
		InputRouter._process(STEP)
		check(InputRouter.confirm_pressed(), "pad button %d is a name-entry confirm" % b)
		_pad(b, false)
		InputRouter._process(STEP)
		n._exit_tree()
		n.free()
	_swap_out()


# --- L: sequence screens: A is not a confirm outside title / ship select -------------------------
func test_interlevel_confirm_x_not_a() -> void:
	_swap_in()
	Run.last_level_result = {"level": 4, "completion_bonus": 250, "extra_life": false}
	var il := InterlevelScreen.new()
	il.setup({"level": 4})
	il._ready()
	_run(il, InterlevelScreen.CONFIRM_DELAY + 0.1)
	var ra := _tap(il, JOY_BUTTON_A)
	check(not ra[0], "A (fire) does not confirm the interlevel")
	var rx := _tap(il, JOY_BUTTON_X)
	check(rx[0] and rx[1] == "continue", "X (Square) confirms the interlevel (got %s)" % [rx])
	il.free()
	_swap_out()


# --- L: in-game mapping (router level) -----------------------------------------------------------
func test_in_game_pad_mapping_start_pauses_back_quits_a_b_fire() -> void:
	_swap_in()
	_pad(JOY_BUTTON_START, true)
	InputRouter._process(STEP)
	check(InputRouter.pause_pressed(), "Start (Options) pauses in game")
	_pad(JOY_BUTTON_START, false)
	_pad(JOY_BUTTON_BACK, true)
	InputRouter._process(STEP)
	check(InputRouter.quit_pressed(), "Select/Back leaves the pause")
	_pad(JOY_BUTTON_BACK, false)
	for b: JoyButton in [JOY_BUTTON_A, JOY_BUTTON_B]:
		_pad(b, true)
		InputRouter._process(STEP)
		check(InputRouter.fire_held(), "pad button %d (Cross/Circle) fires" % b)
		_pad(b, false)
		InputRouter._process(STEP)
	for b: JoyButton in [JOY_BUTTON_X, JOY_BUTTON_Y]:
		_pad(b, true)
		InputRouter._process(STEP)
		check(not InputRouter.fire_held(), "pad button %d (Square/Triangle) does not fire" % b)
		_pad(b, false)
		InputRouter._process(STEP)
	_swap_out()


## Regression (audit flow-1): a letter typed as the LAST name character (A or D) that is still down when
## Enter confirms (ordinary key rollover) must not act as LEFT/RIGHT on the highscores screen and switch
## the difficulty tab away from the list that holds the new entry. NameEntry._exit_tree() turns text mode
## off before Main calls InputRouter.require_release(), so require_release() must latch the direction that
## is held NOW (letters included), not only the one computed earlier in the frame with letters ignored.
func test_letter_held_from_name_entry_does_not_switch_highscore_tab() -> void:
	for letter: Key in [KEY_A, KEY_D]:
		InputRouter.set_text_mode(false)
		InputRouter._process(STEP)
		var n := NameEntryScreen.new()
		n.setup({"difficulty": 1, "score": 5, "time": 1.0, "level": 1, "ship": 0})
		n._ready()                                   # text mode on
		_key(letter, true)                           # the last letter is typed ...
		n._on_text_char(OS.get_keycode_string(letter))
		_run(n, STEP * 3)
		_key(KEY_ENTER, true)                        # ... and Enter is pressed while it is still down
		InputRouter._process(STEP)
		check(InputRouter.confirm_pressed(), "Enter confirms the name")
		# Main._show(): the old screen leaves the tree, the new one enters, then require_release().
		n._exit_tree()
		n.free()
		var h := HighscoresScreen.new()
		h.setup({"difficulty": 1, "rank": 0})
		h._ready()
		InputRouter.require_release()
		_run(h, 0.3)
		check_eq(int(h.get("_diff")), 1,
			"%s held from the name entry must not switch the highscore tab (NORMAL list with the new entry)" %
			OS.get_keycode_string(letter))
		_key(KEY_ENTER, false)
		_key(letter, false)
		_run(h, STEP * 3)
		h.free()
	InputRouter.set_text_mode(false)


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


## Select/Back held from "quit to title" in the pause must not also open the highscores on the title.
func test_held_back_from_pause_does_not_chain_into_title_highscores() -> void:
	_swap_in()
	_pad(JOY_BUTTON_BACK, true)
	InputRouter._process(STEP)
	check(InputRouter.quit_pressed(), "Back quits from the pause")
	InputRouter.require_release()   # Main: screen change to the title
	var t := TitleScreen.new()
	t.setup({})
	t._ready()
	var fin := [false]
	t.finished.connect(func(_r: String, _d: Dictionary) -> void: fin[0] = true)
	_run(t, 0.5)
	check(not fin[0], "held Back must not open the highscores on the title")
	_pad(JOY_BUTTON_BACK, false)
	_run(t, STEP * 2)
	t.free()
	_swap_out()


# --- L: menu stick hysteresis (audit flow-2) -----------------------------------------------------
func test_stick_dir_engages_on_stronger_axis_with_hysteresis() -> void:
	var Z := Vector2i.ZERO
	var R := Vector2i(1, 0)
	var L := Vector2i(-1, 0)
	var U := Vector2i(0, -1)
	var D := Vector2i(0, 1)
	var sd := func(sx: float, sy: float, prev: Vector2i) -> Vector2i: return InputRouter.stick_dir(sx, sy, prev)
	# From rest: threshold 0.5, stronger axis, tie -> horizontal.
	check_eq(sd.call(0.49, 0.0, Z), Z, "below the threshold from rest")
	check_eq(sd.call(0.5, 0.0, Z), R, "engages at 0.5")
	check_eq(sd.call(-0.6, 0.2, Z), L, "left")
	check_eq(sd.call(0.1, 0.6, Z), D, "down")
	check_eq(sd.call(0.1, -0.6, Z), U, "up")
	check_eq(sd.call(0.6, -0.6, Z), R, "tie counts as horizontal")
	check_eq(sd.call(-0.6, 0.6, Z), L, "tie counts as horizontal (left)")
	# Engaged: kept until the axis drops below 0.35 (no flapping around 0.5).
	check_eq(sd.call(0.48, 0.0, R), R, "0.48 keeps an engaged RIGHT")
	check_eq(sd.call(0.36, 0.0, R), R, "0.36 keeps an engaged RIGHT")
	check_eq(sd.call(0.34, 0.0, R), Z, "below 0.35 releases")
	check_eq(sd.call(0.0, -0.4, U), U, "0.4 keeps an engaged UP")
	check_eq(sd.call(-0.6, 0.0, R), L, "flipping to the other side is a new direction")
	# Diagonal wobble keeps the first axis; a clearly stronger other axis takes over.
	check_eq(sd.call(0.70, -0.71, R), R, "near-diagonal wobble keeps RIGHT")
	check_eq(sd.call(0.71, -0.70, U), U, "near-diagonal wobble keeps UP")
	check_eq(sd.call(0.6, -0.75, R), R, "other axis stronger by < 0.2 does not switch")
	check_eq(sd.call(0.6, -0.85, R), U, "other axis stronger by >= 0.2 switches")
	check_eq(sd.call(0.3, -0.6, R), U, "released axis + engaged other axis switches")
	check_eq(sd.call(0.3, -0.45, R), Z, "released axis, other axis below the threshold -> nothing")


## Counts the menu steps (and their directions) while the fake stick follows `samples` (one per frame).
func _stick_steps(samples: Array) -> Array:
	var dirs := []
	for s: Vector2 in samples:
		InputRouter.stick = s
		InputRouter._process(STEP)
		if InputRouter.menu_direction() != Vector2i.ZERO:
			dirs.append(InputRouter.menu_direction())
	InputRouter.stick = Vector2.ZERO
	for i in 3:
		InputRouter._process(STEP)
	return dirs


func test_stick_tremor_steps_like_a_steady_hold() -> void:
	_swap_in()
	var frames := 60   # 1 s: first step + repeats at 0.35 s, 0.46 s, ...
	var steady := []
	var tremor := []
	var diag := []
	for i in frames:
		var flip := (i / 3) % 2 == 1   # 10 Hz wobble
		steady.append(Vector2(0.6, 0.0))
		tremor.append(Vector2(0.48 if flip else 0.52, 0.0))
		diag.append(Vector2(0.70, -0.71) if flip else Vector2(0.71, -0.70))
	var n_steady := _stick_steps(steady)
	check(n_steady.size() >= 3, "a steady stick hold repeats (got %d steps)" % n_steady.size())
	var n_tremor := _stick_steps(tremor)
	check_eq(n_tremor.size(), n_steady.size(), "stick wobbling around 0.5 steps like a steady hold")
	var n_diag := _stick_steps(diag)
	check_eq(n_diag.size(), n_steady.size(), "near-diagonal stick wobble steps like a steady hold")
	for d: Vector2i in n_diag:
		check_eq(d, Vector2i(1, 0), "near-diagonal wobble keeps the first axis")
	_swap_out()
