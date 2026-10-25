extends Node2D
## Static scenery of the game screen: sky gradient, background planet, ground strip (docs/SPEC.md §15).
## One script, four modes (separate nodes so the Starfield can sit between sky and planet).
## Everything is drawn once (no per-frame redraw); textures are cached statically.
## Playfield width (SPEC §18.1): `width` (960 or 1280) – sky, vignette and haze span it, the ground strip is tiled
## to it and the planet stays anchored to the top-right corner (same distance to the right edge as at 960).

const FxTex := preload("res://scripts/game/fx_tex.gd")

enum Mode { SKY, PLANET, GROUND, VIGNETTE }

const ATMOSPHERE := {
	"neptune": Color(0.30, 0.50, 1.00), "uranus": Color(0.50, 0.92, 0.92), "saturn": Color(1.00, 0.80, 0.52),
	"jupiter": Color(1.00, 0.68, 0.45), "mars": Color(1.00, 0.48, 0.28), "earth": Color(0.42, 0.68, 1.00),
}
## Sphere centre (SPEC: around (850, 140) at width 960, i.e. 110 px from the right edge); moved down for bigger
## zoom stages so it stays clear of the HUD and moved left so the whole sphere stays on screen (rings may still
## extend past the edge).
const PLANET_X := 850.0
const PLANET_Y := 140.0
const PLANET_MIN_TOP := 56.0
const PLANET_RIGHT_MARGIN := 14.0

static var _sky_cache := {}
static var _vignette: Texture2D

var mode: Mode = Mode.SKY
var level := 1
var planet := "neptune"
var width := LevelData.SCREEN_W     ## playfield width (960 or 1280)


func setup(p_mode: Mode, p_level: int, p_width: float = LevelData.SCREEN_W) -> void:
	mode = p_mode
	level = p_level
	width = p_width
	planet = LevelData.planet_of(level)
	queue_redraw()


## Sphere centre of the level's planet on a playfield `w` px wide: anchored to the top-right corner.
static func planet_center(lvl: int, w: float = LevelData.SCREEN_W) -> Vector2:
	var r := LevelData.planet_diameter(lvl) * 0.5
	var dx := w - LevelData.SCREEN_W
	return Vector2(minf(PLANET_X + dx, w - PLANET_RIGHT_MARGIN - r), maxf(PLANET_Y, PLANET_MIN_TOP + r))


static func atmosphere(p: String) -> Color:
	return ATMOSPHERE.get(p, Color(0.5, 0.7, 1.0))


func _draw() -> void:
	match mode:
		Mode.SKY:
			draw_texture_rect(_sky_texture(planet), Rect2(0, 0, width, LevelData.SCREEN_H), false)
		Mode.PLANET:
			_draw_planet()
		Mode.GROUND:
			_draw_ground()
		Mode.VIGNETTE:
			draw_texture_rect(_vignette_texture(), Rect2(-40, -40, width + 80, LevelData.SCREEN_H + 80), false)


func _draw_planet() -> void:
	var d := LevelData.planet_diameter(level)
	var c := planet_center(level, width)
	var atm := atmosphere(planet)
	# Soft atmospheric halo behind the sphere.
	FxTex.draw_centered(self, FxTex.glow(), c, Vector2.ONE * d * 1.75, Color(atm.r, atm.g, atm.b, 0.16))
	FxTex.draw_centered(self, FxTex.glow(), c, Vector2.ONE * d * 1.22, Color(atm.r, atm.g, atm.b, 0.22))
	Assets.draw_planet(self, planet, c, d, Color(0.92, 0.92, 0.95))


func _draw_ground() -> void:
	var gy := LevelData.GROUND_Y
	var atm := atmosphere(planet)
	# Faint haze above the horizon (kept very subtle so fireballs stay readable).
	draw_texture_rect(FxTex.band(), Rect2(0, gy - 26.0, width, 52.0), false, Color(atm.r, atm.g, atm.b, 0.10))
	_draw_ground_strip(Assets.ground_texture(planet), gy)
	# Rim light along the surface line.
	draw_texture_rect(FxTex.band(), Rect2(0, gy - 3.0, width, 6.0), false, Color(atm.r, atm.g, atm.b, 0.55))
	draw_line(Vector2(0, gy + 0.5), Vector2(width, gy + 0.5), Color(atm.lerp(Color.WHITE, 0.4), 0.35), 1.0)


## The ground texture covers 960 px (SPEC §16.4, horizontally tileable): tiled from x = 0 to the playfield width,
## the last tile cut to fit (exactly one tile at 960).
func _draw_ground_strip(tex: Texture2D, gy: float) -> void:
	var h := LevelData.SCREEN_H - gy
	var x := 0.0
	while x < width - 0.01:
		var part := minf(LevelData.SCREEN_W, width - x)
		if part >= LevelData.SCREEN_W:
			draw_texture_rect(tex, Rect2(x, gy, part, h), false)
		else:
			var k := part / LevelData.SCREEN_W
			draw_texture_rect_region(tex, Rect2(x, gy, part, h), Rect2(0, 0, tex.get_width() * k, tex.get_height()))
		x += part


static func _sky_texture(p: String) -> Texture2D:
	if _sky_cache.has(p):
		return _sky_cache[p]
	var atm := atmosphere(p)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 0.78, 1.0])
	g.colors = PackedColorArray([
		Color(0.004, 0.006, 0.018),
		Color(0.010, 0.013, 0.036),
		Color(0.018, 0.022, 0.050).lerp(atm * 0.12, 0.35),
		(atm * 0.20).lerp(Color(0.03, 0.03, 0.05), 0.35),
	])
	g.interpolation_color_space = Gradient.GRADIENT_COLOR_SPACE_OKLAB
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	t.width = 8
	t.height = 256
	for i in 4:
		var c: Color = g.colors[i]
		c.a = 1.0
		g.set_color(i, c)
	_sky_cache[p] = t
	return t


## Soft dark corners over the background layers (stars / planet), never over gameplay elements.
static func _vignette_texture() -> Texture2D:
	if _vignette:
		return _vignette
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 0.8, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.0), Color(0, 0, 0.01, 0.28), Color(0, 0, 0.02, 0.6)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.05, 0.5)
	t.width = 256
	t.height = 192
	_vignette = t
	return t
