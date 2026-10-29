class_name ScreenBase
extends Node2D
## Common base of all menu / sequence screens (protocol docs/SPEC.md §17.1):
## created with `new()`, configured with `setup(args)` BEFORE entering the tree, emits `finished` once.
## Provides a Starfield background (drawn behind everything), a running clock and small helpers.
## Subclasses override `_enter()` (called from _ready) and `_tick(delta)` (per frame, until finished)
## and draw in `_draw()` as usual; the screen redraws every frame.
## Display modes (Display, SPEC §1): every screen is laid out on the classic 960 × 720 canvas (W, H, CX are its
## content coordinates). On the wider canvases (1280 × 720 in 16:9, 1152 × 720 in 16:10) the screen node is moved
## right by `ox` (Display.center_offset() = 160 / 96), so that layout is centred; full-width elements (starfield, darkening
## overlays, planets anchored to a side, corner captions) use left_x() / right_x() / full_rect(), the canvas edges
## in content coordinates (−160 … 1120 in 16:9, −96 … 1056 in 16:10, 0 … 960 in 4:3). The mode never changes while a screen is shown
## (Main re-creates the title after a display change).

signal finished(result: String, data: Dictionary)

## Classic layout canvas (content coordinates). The real canvas is `sw` wide, see ox.
const W := 960.0
const H := 720.0
const CX := 480.0
## Duration of the fade-in when a screen appears (real seconds).
const FADE_IN := 0.22
## Hand-over guard of the two-player screens (guarded_confirm): a confirm press only counts after the screen's delay AND
## this many quiet seconds without a refused press, so the outgoing player's tapping cannot pass a hand-over.
const HANDOVER_QUIET := 0.4
## Vertical centre and size of the standard continue hint.
const CONTINUE_HINT_Y := 688.0
const CONTINUE_HINT_SIZE := 15

var args: Dictionary = {}
## Seconds since the screen entered the tree (real time).
var time := 0.0
var starfield: Starfield
## Width of the logical canvas (Display.logical_width(): 960, 1280 or 1152) when the screen was created.
var sw := W
## Offset of the 960-wide content layout on the canvas (0 in 4:3, 160 in 16:9); also the node's position.x.
var ox := 0.0
var _done := false
var _guard_open := false
var _guard_press := -INF


func setup(p_args: Dictionary) -> void:
	args = p_args


func _ready() -> void:
	sw = Display.logical_width()
	ox = Display.center_offset()
	position.x = ox
	starfield = Starfield.new()
	starfield.z_index = -10
	starfield.velocity = _star_velocity()
	starfield.size = Vector2(sw, H)
	starfield.position.x = -ox      # the sky spans the whole canvas
	add_child(starfield)
	_enter()
	modulate = Color(1, 1, 1, 0) if _use_fade() else Color.WHITE


func _process(delta: float) -> void:
	time += delta
	if _use_fade():
		modulate.a = clampf(time / FADE_IN, 0.0, 1.0)
	if not _done:
		_tick(delta)
	queue_redraw()


## Emits `finished` exactly once; afterwards `_tick` is no longer called.
func finish(result: String, data: Dictionary = {}) -> void:
	if _done:
		return
	_done = true
	finished.emit(result, data)


func is_finished() -> bool:
	return _done


# --- Overridables --------------------------------------------------------------------------------
func _enter() -> void:
	pass


func _tick(_delta: float) -> void:
	pass


func _star_velocity() -> Vector2:
	return Vector2(-7, 3)


func _use_fade() -> bool:
	return true


# --- Helpers -------------------------------------------------------------------------------------
## Left / right edge of the canvas in content coordinates (−ox / W + ox).
func left_x() -> float:
	return -ox


func right_x() -> float:
	return W + ox


## The whole canvas in content coordinates.
func full_rect() -> Rect2:
	return Rect2(-ox, 0.0, sw, H)


func sfx(sfx_name: String) -> void:
	AudioManager.play_sfx(sfx_name)


## Confirm of a two-player hand-over point (SPEC §19.3): true for a fresh confirm press once the screen has run `delay`
## seconds and no confirm press came in the last HANDOVER_QUIET seconds. Every refused press restarts that quiet window,
## so continuous tapping (the previous player mashing through) never confirms, while the incoming player's first press
## after taking the controller does. Once a press was accepted the guard stays open (further presses count at once).
func guarded_confirm(allow_fire_buttons: bool, delay: float) -> bool:
	if not InputRouter.confirm_pressed(allow_fire_buttons):
		return false
	if _guard_open or (time >= delay and time - _guard_press >= HANDOVER_QUIET):
		_guard_open = true
		return true
	_guard_press = time
	return false


## 0 → 1 between `start` and `start + duration` seconds of screen time, smoothstepped.
func ramp(start: float, duration: float) -> float:
	return smoothstep(0.0, 1.0, clampf((time - start) / maxf(duration, 0.0001), 0.0, 1.0))


## Standard "continue" hint at the bottom of the screen (fades in after `delay`). It sits on a dark
## backing because several screens show a planet (clouds, rings) behind the bottom area.
func draw_continue_hint(label: String = "Continue", delay: float = 0.6, y: float = CONTINUE_HINT_Y) -> void:
	var a := ramp(delay, 0.35)
	if a <= 0.0:
		return
	var col := UiKit.COLOR_DIM.lerp(UiKit.COLOR_TEXT, 0.25)
	col.a = a * (0.78 + 0.22 * sin(time * 3.0))
	UiKit.hint_bar(self, Vector2(CX, y), continue_hint_items(label), CONTINUE_HINT_SIZE, col, a)


## Items of the standard continue hint (for UiKit.hint_bar / hint_bar_rect).
static func continue_hint_items(label: String = "Continue") -> Array:
	return [[["ENTER", "pad:X", "pad:START"], label]]


## Big screen title with glow, centred.
func draw_title(s: String, baseline: float, size: int = 40, color: Color = UiKit.COLOR_TEXT,
		glow: Color = UiKit.COLOR_HILITE) -> void:
	UiKit.text_glow(self, Assets.font_title_heavy, Vector2(CX, baseline), s, size, color, glow,
		HORIZONTAL_ALIGNMENT_CENTER)
