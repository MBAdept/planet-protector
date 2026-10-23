class_name EnemyArt
extends Node2D
## A colourised enemy sprite (docs/SPEC.md §16.2). Used by the game and by menu screens (e.g. Mars rules).
## Draws the current flap frame of the channel-packed sheet Assets.enemy_sheet(planet) through
## shaders/enemy.gdshader. The colour gradient is a GradientTexture1D cached per colour list.
## Draw size = frame size / px_per_game_px * scale_factor, centred on the node origin (logical centre).
## Every property setter triggers a redraw, so callers can simply assign values each frame.

const SHADER := preload("res://shaders/enemy.gdshader")

## Shared colour gradients: key (colour list) → GradientTexture1D.
static var _gradients := {}

var planet := "neptune":                ## which enemy design
	set(v):
		if v != planet:
			planet = v
			_sheet = {}
			queue_redraw()
var colors: Array[Color] = [Color(0.2, 0.4, 1.0), Color(0.6, 1.0, 1.0)]:  ## gradient top → bottom
	set(v):
		colors = v
		_grad_dirty = true
		queue_redraw()
var eye_color := Color(1.0, 0.95, 0.7):
	set(v):
		eye_color = v
		queue_redraw()
var black := false:                     ## very dark enemies get an outline
	set(v):
		black = v
		queue_redraw()
var scale_factor := 1.0:                ## 1.0 original, 0.40/0.45 children
	set(v):
		if v != scale_factor:
			scale_factor = v
			queue_redraw()
var flap_phase := 0.0:                  ## 0..1 position in the wing-flap cycle
	set(v):
		if v != flap_phase:
			flap_phase = v
			queue_redraw()
var flash := 0.0:                       ## 0..1 orange hit flash amount
	set(v):
		if v != flash:
			flash = v
			queue_redraw()
var materialize := 1.0:                 ## 0..1 fade/scan-in amount
	set(v):
		if v != materialize:
			materialize = v
			queue_redraw()
## Optional: when > 0 the node animates its own wing flap at this rate (cycles per second), for menus.
var auto_flap_hz := 0.0:
	set(v):
		auto_flap_hz = v
		set_process(v > 0.0)

var _sheet := {}
var _mat: ShaderMaterial
var _grad_dirty := true


func _ready() -> void:
	# The strips ship with mipmaps; children (scale 0.40/0.45) would shimmer with plain linear filtering.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_process(auto_flap_hz > 0.0)


func _process(delta: float) -> void:
	if auto_flap_hz > 0.0:
		flap_phase = fposmod(flap_phase + delta * auto_flap_hz, 1.0)


## Convenience used by menus: configure from a level number (and colour stage for levels 14–16).
func configure(level: int, stage: int = LevelData.Stage.VIOLET) -> void:
	planet = LevelData.planet_of(level)
	colors = LevelData.gradient_colors(level, stage)
	eye_color = LevelData.eye_color(level)
	black = LevelData.is_black(level)
	queue_redraw()


## Visual size of the drawn frame in game px (including transparent margins).
func draw_size() -> Vector2:
	var sh := _get_sheet()
	return Vector2(float(sh["frame_w"]), float(sh["frame_h"])) / float(sh["px_per_game_px"]) * scale_factor


## Cached GradientTexture1D for a colour list (top → bottom).
static func gradient_texture(cols: Array[Color]) -> GradientTexture1D:
	var key := ""
	for c in cols:
		key += c.to_html() + ","
	if _gradients.has(key):
		return _gradients[key]
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var pc := PackedColorArray()
	var n := maxi(cols.size(), 1)
	for i in n:
		offs.append(0.0 if n == 1 else float(i) / float(n - 1))
		pc.append(cols[i] if cols.size() > 0 else Color.WHITE)
	g.offsets = offs
	g.colors = pc
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC if n > 2 else Gradient.GRADIENT_INTERPOLATE_LINEAR
	g.interpolation_color_space = Gradient.GRADIENT_COLOR_SPACE_OKLAB
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	t.use_hdr = false
	_gradients[key] = t
	return t


## Emissive area of a black enemy in local frame UV (x0, y0, x1, y1): the sheet's optional "eye_rect"
## (frame px, inclusive), else the whole frame. Only the eyes may glow on black enemies (SPEC §15).
static func eye_rect_uv(sh: Dictionary) -> Vector4:
	var fw := float(sh["frame_w"])
	var fh := float(sh["frame_h"])
	var r: Array = sh.get("eye_rect", [0, 0, fw - 1.0, fh - 1.0])
	return Vector4(float(r[0]) / fw, float(r[1]) / fh, (float(r[2]) + 1.0) / fw, (float(r[3]) + 1.0) / fh)


func _get_sheet() -> Dictionary:
	if _sheet.is_empty():
		_sheet = Assets.enemy_sheet(planet)
	return _sheet


func _draw() -> void:
	var sh := _get_sheet()
	var tex: Texture2D = sh["texture"]
	if tex == null:
		return
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
		_mat.set_shader_parameter("seed", float(get_instance_id() % 997))
		material = _mat
	if _grad_dirty:
		_mat.set_shader_parameter("gradient_tex", gradient_texture(colors))
		_grad_dirty = false
	var frames := maxi(int(sh["frames"]), 1)
	var fw := float(sh["frame_w"])
	var fh := float(sh["frame_h"])
	var frame := clampi(int(floor(fposmod(flap_phase, 1.0) * frames)), 0, frames - 1)
	var src := Rect2(fw * frame, 0.0, fw, fh)
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	_mat.set_shader_parameter("frame_uv", Vector4(src.position.x / tw, src.position.y / th, fw / tw, fh / th))
	_mat.set_shader_parameter("content_top", float(sh["content_top"]) / fh)
	_mat.set_shader_parameter("content_bottom", float(sh["content_bottom"]) / fh)
	_mat.set_shader_parameter("eye_color", eye_color)
	_mat.set_shader_parameter("eye_glow", 0.9 if black else 0.55)
	_mat.set_shader_parameter("eye_rect", eye_rect_uv(sh) if black else Vector4(0.0, 0.0, 1.0, 1.0))
	_mat.set_shader_parameter("outline", 1.0 if black else 0.0)
	_mat.set_shader_parameter("flash", flash)
	_mat.set_shader_parameter("flash_color", LevelData.HIT_FLASH_COLOR)
	_mat.set_shader_parameter("materialize", materialize)
	var size := Vector2(fw, fh) / float(sh["px_per_game_px"]) * scale_factor
	draw_texture_rect_region(tex, Rect2(-size * 0.5, size), src)
