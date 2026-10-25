extends Node
## Autoload "InputRouter": keyboard + controller abstraction (docs/SPEC.md §12).
## Polls devices once per frame (runs before all screens because autoloads come first in the tree).
## - Edge-triggered logical buttons with a release guard: after require_release() every button that is
##   currently held is ignored until it has been released (no multi-confirm, no screen skipping).
## - Menu directions with controlled repeat; single axis only (stronger axis wins, tie → horizontal).
##   The left stick has hysteresis (stick_dir) so tremor at the threshold or the diagonal adds no steps.

signal text_char(ch: String)   ## printable key typed (uppercased), for name entry

enum B { UP, DOWN, LEFT, RIGHT, ENTER, ESCAPE, SPACE, P, Q, BACKSPACE, F11,
	JOY_A, JOY_B, JOY_X, JOY_Y, JOY_START, JOY_BACK }

const MOVE_DEADZONE := 0.25
const MENU_STICK_THRESHOLD := 0.5        # stick engages a menu direction at this deflection ...
const MENU_STICK_RELEASE := 0.35         # ... and keeps it until its axis drops below this
const MENU_STICK_SWITCH_MARGIN := 0.2    # the other axis takes over only when stronger by this margin
const REPEAT_DELAY := 0.35
const REPEAT_INTERVAL := 0.11

var _down := {}       # B -> bool (this frame)
var _prev := {}       # B -> bool (previous frame)
var _latched := {}    # B -> true while ignored until release
var _menu_dir := Vector2i.ZERO
var _menu_dir_latched := false
var _menu_hold := 0.0
var _menu_next := 0.0
var _menu_emit := Vector2i.ZERO
var _menu_emit_repeat := false   # true if this frame's _menu_emit comes from the auto-repeat
var _sticks := {}     # joypad id -> menu direction of its left stick (stick_dir), updated once per frame
## Text entry mode (name entry): the letter keys W/A/S/D are typed characters, not directions;
## only arrow keys, D-pad and stick navigate (SPEC §13 "arrow keys behave like the D-pad").
var text_mode := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100
	for b in B.values():
		_down[b] = false
		_prev[b] = false


func _process(delta: float) -> void:
	_update_sticks()
	for b in B.values():
		_prev[b] = _down[b]
		_down[b] = _poll(b)
		if _latched.has(b) and not _down[b]:
			_latched.erase(b)
	if just_pressed(B.F11):
		Display.toggle_fullscreen()   # mode 0: fullscreen on/off (persisted); 16:9 modes: fullscreen ↔ 16:9 window
	_update_menu_direction(delta)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var u: int = event.unicode
		if u >= 32 and u < 127:
			text_char.emit(String.chr(u).to_upper())


## Window mode of the current display mode (kept for callers of the old API; see Display.apply_window).
func apply_window_mode() -> void:
	Display.apply_window()


# --- Public API ----------------------------------------------------------------------------------
## Enables/disables text entry mode (see `text_mode`).
func set_text_mode(on: bool) -> void:
	text_mode = on


## Ignore every currently held button/direction until it is released. Main calls this on every screen change.
## Re-reads the devices instead of trusting this frame's cached state: the old screen may have left text
## mode meanwhile (name entry), so a held W/A/S/D only now counts as a direction and must be latched too.
func require_release() -> void:
	for b in B.values():
		if _down[b] or _poll(b):
			_latched[b] = true
	var d := _raw_dir()
	if d != Vector2i.ZERO:
		_menu_dir = d
	if _menu_dir != Vector2i.ZERO:
		_menu_dir_latched = true
	_menu_emit = Vector2i.ZERO
	_menu_emit_repeat = false


func is_down(b: int) -> bool:
	return _down[b] and not _latched.has(b)


func just_pressed(b: int) -> bool:
	return _down[b] and not _prev[b] and not _latched.has(b)


## Enter, X/Y (Square/Triangle), Start. allow_fire_buttons adds Space and A (title + ship select).
func confirm_pressed(allow_fire_buttons: bool = false) -> bool:
	var r := just_pressed(B.ENTER) or just_pressed(B.JOY_X) or just_pressed(B.JOY_Y) or just_pressed(B.JOY_START)
	if allow_fire_buttons:
		r = r or just_pressed(B.SPACE) or just_pressed(B.JOY_A)
	return r


## Escape or controller B (sub-menus).
func back_pressed() -> bool:
	return just_pressed(B.ESCAPE) or just_pressed(B.JOY_B)


## In game: P, Escape, Start.
func pause_pressed() -> bool:
	return just_pressed(B.P) or just_pressed(B.ESCAPE) or just_pressed(B.JOY_START)


## In pause: Q or Select/Back → title.
func quit_pressed() -> bool:
	return just_pressed(B.Q) or just_pressed(B.JOY_BACK)


## Title screen: Select/Back opens highscores.
func highscores_pressed() -> bool:
	return just_pressed(B.JOY_BACK)


## Name entry: Backspace or controller B.
func delete_pressed() -> bool:
	return just_pressed(B.BACKSPACE) or just_pressed(B.JOY_B)


## Space, A or B held (Cross/Circle).
func fire_held() -> bool:
	return is_down(B.SPACE) or is_down(B.JOY_A) or is_down(B.JOY_B)


## Horizontal movement −1…1 from arrows/A/D, D-pad or left stick (deadzone, rescaled).
func move_axis() -> float:
	var k := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A):
		k -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D):
		k += 1.0
	var best := k
	for id in Input.get_connected_joypads():
		var d := 0.0
		if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_LEFT):
			d -= 1.0
		if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_RIGHT):
			d += 1.0
		if absf(d) > absf(best):
			best = d
		var ax := Input.get_joy_axis(id, JOY_AXIS_LEFT_X)
		var a := 0.0
		if absf(ax) > MOVE_DEADZONE:
			a = signf(ax) * clampf((absf(ax) - MOVE_DEADZONE) / (0.9 - MOVE_DEADZONE), 0.0, 1.0)
		if absf(a) > absf(best):
			best = a
	return clampf(best, -1.0, 1.0)


## Menu navigation step for this frame (with repeat). Exactly one axis or ZERO.
func menu_direction() -> Vector2i:
	return _menu_emit


## True if this frame's menu_direction() step was produced by the auto-repeat of a held direction
## (false for the first step of a fresh press). Binary options (ON/OFF) use it to react once per press.
func menu_direction_is_repeat() -> bool:
	return _menu_emit_repeat


# --- Internals -----------------------------------------------------------------------------------
func _poll(b: int) -> bool:
	match b:
		B.UP:
			return _raw_dir().y < 0
		B.DOWN:
			return _raw_dir().y > 0
		B.LEFT:
			return _raw_dir().x < 0
		B.RIGHT:
			return _raw_dir().x > 0
		B.ENTER:
			return Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_KP_ENTER)
		B.ESCAPE:
			return Input.is_key_pressed(KEY_ESCAPE)
		B.SPACE:
			return Input.is_key_pressed(KEY_SPACE)
		B.P:
			return Input.is_physical_key_pressed(KEY_P)
		B.Q:
			return Input.is_physical_key_pressed(KEY_Q)
		B.BACKSPACE:
			return Input.is_key_pressed(KEY_BACKSPACE)
		B.F11:
			return Input.is_key_pressed(KEY_F11)
		B.JOY_A:
			return _joy(JOY_BUTTON_A)
		B.JOY_B:
			return _joy(JOY_BUTTON_B)
		B.JOY_X:
			return _joy(JOY_BUTTON_X)
		B.JOY_Y:
			return _joy(JOY_BUTTON_Y)
		B.JOY_START:
			return _joy(JOY_BUTTON_START)
		B.JOY_BACK:
			return _joy(JOY_BUTTON_BACK)
	return false


func _joy(button: JoyButton) -> bool:
	for id in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(id, button):
			return true
	return false


## Raw single-axis direction: digital sources (keys, D-pad) and the left stick (this frame's _sticks).
## Stronger axis wins; a tie (also D-pad / key diagonals) counts as horizontal.
func _raw_dir() -> Vector2i:
	var h := 0.0
	var v := 0.0
	var letters := not text_mode
	if Input.is_key_pressed(KEY_LEFT) or (letters and Input.is_physical_key_pressed(KEY_A)):
		h -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or (letters and Input.is_physical_key_pressed(KEY_D)):
		h += 1.0
	if Input.is_key_pressed(KEY_UP) or (letters and Input.is_physical_key_pressed(KEY_W)):
		v -= 1.0
	if Input.is_key_pressed(KEY_DOWN) or (letters and Input.is_physical_key_pressed(KEY_S)):
		v += 1.0
	for id in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_LEFT):
			h -= 1.0
		if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_RIGHT):
			h += 1.0
		if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_UP):
			v -= 1.0
		if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_DOWN):
			v += 1.0
	for sd: Vector2i in _sticks.values():
		h += sd.x
		v += sd.y
	h = clampf(h, -1.0, 1.0)
	v = clampf(v, -1.0, 1.0)
	if h != 0.0:
		return Vector2i(int(h), 0)
	if v != 0.0:
		return Vector2i(0, int(v))
	return Vector2i.ZERO


## Menu direction of ONE analog stick with hysteresis (pure; `prev` is this stick's result of the previous
## frame). From rest it engages at MENU_STICK_THRESHOLD on the stronger axis (tie → horizontal). An engaged
## direction is kept while its axis stays ≥ MENU_STICK_RELEASE in the same sign; it switches to the other
## axis only when that one reaches the threshold AND is stronger by MENU_STICK_SWITCH_MARGIN. So a reading
## wobbling around 0.5 or around the 45° diagonal stays one held direction (controlled repeat, no extra steps).
static func stick_dir(sx: float, sy: float, prev: Vector2i) -> Vector2i:
	if prev != Vector2i.ZERO:
		var on := sx * prev.x if prev.x != 0 else sy * prev.y   # deflection along the engaged direction
		var other := absf(sy) if prev.x != 0 else absf(sx)
		if on >= MENU_STICK_RELEASE and (other < MENU_STICK_THRESHOLD or other < on + MENU_STICK_SWITCH_MARGIN):
			return prev
	if maxf(absf(sx), absf(sy)) < MENU_STICK_THRESHOLD:
		return Vector2i.ZERO
	if absf(sx) >= absf(sy):
		return Vector2i(int(signf(sx)), 0)
	return Vector2i(0, int(signf(sy)))


## Left-stick deflection of every connected pad (id -> Vector2).
func _left_sticks() -> Dictionary:
	var r := {}
	for id in Input.get_connected_joypads():
		r[id] = Vector2(Input.get_joy_axis(id, JOY_AXIS_LEFT_X), Input.get_joy_axis(id, JOY_AXIS_LEFT_Y))
	return r


## Once per frame (before the buttons are polled), so _raw_dir() stays the same within a frame.
func _update_sticks() -> void:
	var now := {}
	var sticks := _left_sticks()
	for id in sticks:
		var s: Vector2 = sticks[id]
		now[id] = stick_dir(s.x, s.y, _sticks.get(id, Vector2i.ZERO))
	_sticks = now


func _update_menu_direction(delta: float) -> void:
	_menu_emit = Vector2i.ZERO
	_menu_emit_repeat = false
	var d := _raw_dir()
	if d == Vector2i.ZERO:
		_menu_dir = Vector2i.ZERO
		_menu_dir_latched = false
		return
	if _menu_dir_latched:
		if d != _menu_dir:
			_menu_dir_latched = false
		else:
			return
	if d != _menu_dir:
		_menu_dir = d
		_menu_hold = 0.0
		_menu_next = REPEAT_DELAY
		_menu_emit = d
		return
	_menu_hold += delta
	if _menu_hold >= _menu_next:
		_menu_next += REPEAT_INTERVAL
		_menu_emit = d
		_menu_emit_repeat = true
