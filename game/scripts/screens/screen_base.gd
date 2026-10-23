class_name ScreenBase
extends Node2D
## Common base of all menu / sequence screens (protocol docs/SPEC.md §17.1):
## created with `new()`, configured with `setup(args)` BEFORE entering the tree, emits `finished` once.
## Provides a Starfield background (drawn behind everything), a running clock and small helpers.
## Subclasses override `_enter()` (called from _ready) and `_tick(delta)` (per frame, until finished)
## and draw in `_draw()` as usual; the screen redraws every frame.

signal finished(result: String, data: Dictionary)

const W := 960.0
const H := 720.0
const CX := 480.0
## Duration of the fade-in when a screen appears (real seconds).
const FADE_IN := 0.22
## Vertical centre and size of the standard continue hint.
const CONTINUE_HINT_Y := 688.0
const CONTINUE_HINT_SIZE := 15

var args: Dictionary = {}
## Seconds since the screen entered the tree (real time).
var time := 0.0
var starfield: Starfield
var _done := false


func setup(p_args: Dictionary) -> void:
	args = p_args


func _ready() -> void:
	starfield = Starfield.new()
	starfield.z_index = -10
	starfield.velocity = _star_velocity()
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
func sfx(sfx_name: String) -> void:
	AudioManager.play_sfx(sfx_name)


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
