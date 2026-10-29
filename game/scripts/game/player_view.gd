extends Node2D
## Player ship: Assets.ship_texture drawn at 0.5 scale centred on the node (x, 659), with an additive
## engine glow (the optional *_glow.png overlay plus procedural exhaust flames that flicker).
## Power-ups (SPEC §19.3), all additive light in the power-up colour `tint`: `heat` (RAPID FIRE: hotter, longer
## exhaust, glowing gun muzzles), `shield` (SHIELD: an energy bubble around the ship that touches the ground,
## `shield_flash` brightens it after an absorbed bullet) and `ghost` (the TWIN: the same ship, translucent, with a
## holographic sheen and engines in the tint colour).

const FxTex := preload("res://scripts/game/fx_tex.gd")
const GhostShader := preload("res://shaders/ghost.gdshader")

## Shield bubble: half extents around the ship (the ship ≈ 70 × 48) and its centre offset (a little above the ship
## centre, so the dome rests on the ground) – the same ellipse the world absorbs fireballs with (LevelData.SHIELD_R /
## SHIELD_CY), so what the player sees is what the shield stops.
const SHIELD_R := LevelData.SHIELD_R
const SHIELD_DY := LevelData.SHIELD_CY - LevelData.PLAYER_Y
const HEAT_COLOR := Color(1.0, 0.5, 0.14)

## Engine nozzle positions (game px, relative to the ship centre) per ship id: exact nozzle data from
## ships/<key>.json when available, otherwise derived once from the glow overlay (brightness centroids);
## last fallback: one engine at the bottom centre.
static var _engines := {}
static var _engine_widths := {}

var ship_id := 0
var alpha := 1.0          ## respawn fade-in
var bank := 0.0           ## -1..1 current horizontal movement (slight narrowing while strafing)
var anim := 0.0           ## seconds, drives the flicker
var ghost := false        ## TWIN look (set before entering the tree)
var tint := Color(0.4, 0.86, 1.0)   ## power-up colour
var heat := 0.0           ## 0…1 RAPID FIRE glow
var shield := 0.0         ## 0…1 SHIELD bubble
var shield_flash := 0.0   ## 0…1 bubble flash after an absorbed bullet

var _glow_node: Node2D
var _front: Node2D        ## additive light over the ship: shield bubble, ghost sheen, hot muzzles
var _accent := Color(0.4, 0.7, 1.0)


func _ready() -> void:
	_accent = tint if ghost else ShipData.ship(ship_id)["accent"]
	if ghost:
		# The TWIN's ship itself is drawn as a hologram (monochrome in the tint, scanlines, 55 % opacity).
		var gm := ShaderMaterial.new()
		gm.shader = GhostShader
		gm.set_shader_parameter("tint", tint)
		material = gm
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow_node = Node2D.new()
	_glow_node.material = m
	_glow_node.show_behind_parent = true
	_glow_node.draw.connect(_draw_glow)
	add_child(_glow_node)
	_front = Node2D.new()
	_front.material = m
	_front.draw.connect(_draw_front)
	add_child(_front)


func refresh() -> void:
	scale = Vector2(1.0 - 0.06 * absf(bank), 1.0)
	queue_redraw()
	_glow_node.queue_redraw()
	_front.queue_redraw()


func _draw() -> void:
	var tex := Assets.ship_texture(ship_id)
	var size := Vector2(tex.get_width(), tex.get_height()) * 0.5
	# The TWIN (ghost) gets its hologram look from its material (shaders/ghost.gdshader), the sheen in _draw_front.
	draw_texture_rect(tex, Rect2(-size * 0.5, size), false, Color(1, 1, 1, alpha))


func _draw_glow() -> void:
	var f := 0.82 + 0.1 * sin(anim * 37.0) + 0.08 * sin(anim * 91.0 + 1.1)
	var g := Assets.ship_glow_texture(ship_id)
	var gk := 0.7 if ghost else 1.0
	if g:
		var size := Vector2(g.get_width(), g.get_height()) * 0.5
		var gc := Color(1, 1, 1).lerp(_accent, 0.6) if ghost else Color(1, 1, 1)
		_glow_node.draw_texture_rect(g, Rect2(-size * 0.5, size), false, Color(gc.r, gc.g, gc.b, alpha * gk * (0.75 + 0.35 * f)))
	# RAPID FIRE: the engines run hot – longer flames shifting to orange-white.
	var acc := _accent.lerp(HEAT_COLOR, heat)
	# Engine light spilling onto the ground surface right below the ship.
	FxTex.draw_centered(_glow_node, FxTex.glow(), Vector2(0, LevelData.GROUND_Y - LevelData.PLAYER_Y + 2.0),
		Vector2(96.0, 16.0) * (0.9 + 0.1 * f) * (1.0 + 0.25 * heat), Color(acc.r, acc.g, acc.b, (0.22 + 0.12 * heat) * alpha * gk))
	var hot := Color(0.75, 0.9, 1.0).lerp(acc, 0.25).lerp(Color(1.0, 0.9, 0.62), heat)
	var list := engines(ship_id)
	var widths: Array = _engine_widths.get(ship_id, [])
	for i in list.size():
		var p: Vector2 = list[i]
		var wk: float = widths[i] if i < widths.size() else 1.0
		var ln := (12.0 + 6.0 * f) * (0.75 + 0.25 * wk) * (1.0 + 0.55 * heat)
		FxTex.draw_centered(_glow_node, FxTex.glow(), p + Vector2(0, 3), Vector2(22, 22) * f * wk * (1.0 + 0.3 * heat), Color(acc.r, acc.g, acc.b, 0.55 * alpha * gk))
		FxTex.draw_oriented(_glow_node, FxTex.flame(), p + Vector2(0, ln * 0.42), Vector2.DOWN, Vector2(8.0 * wk, ln),
			Color(acc.r, acc.g, acc.b, 0.8 * alpha * gk))
		FxTex.draw_oriented(_glow_node, FxTex.flame(), p + Vector2(0, ln * 0.25), Vector2.DOWN, Vector2(4.0 * wk, ln * 0.6),
			Color(hot.r, hot.g, hot.b, 0.95 * alpha * gk))


func _draw_front() -> void:
	if ghost and alpha > 0.0:
		_draw_ghost_sheen()
	if heat > 0.0:
		_draw_heat()
	if shield > 0.0:
		_draw_shield()


## TWIN: an additive pass of the ship in the tint colour with a slow shimmer – a luminous, holographic double.
func _draw_ghost_sheen() -> void:
	var tex := Assets.ship_texture(ship_id)
	var size := Vector2(tex.get_width(), tex.get_height()) * 0.5
	var sh := 0.85 + 0.15 * sin(anim * 5.3) * sin(anim * 2.1 + 0.7)
	_front.draw_texture_rect(tex, Rect2(-size * 0.5, size), false, Color(tint.r, tint.g, tint.b, 0.2 * alpha * sh))
	FxTex.draw_centered(_front, FxTex.glow(), Vector2(0, 2), Vector2(120, 78), Color(tint.r, tint.g, tint.b, 0.16 * alpha))


## RAPID FIRE: the hull glows red-hot (an additive orange pass of the ship, throbbing), hot gun muzzles (one per
## projectile of the salvo) and a heat aura.
func _draw_heat() -> void:
	var a := heat * alpha
	var throb := 0.75 + 0.25 * sin(anim * 17.0)
	FxTex.draw_centered(_front, FxTex.glow(), Vector2(0, -2), Vector2(124, 80), Color(HEAT_COLOR.r, HEAT_COLOR.g, HEAT_COLOR.b, 0.2 * a))
	var tex := Assets.ship_texture(ship_id)
	var size := Vector2(tex.get_width(), tex.get_height()) * 0.5
	_front.draw_texture_rect(tex, Rect2(-size * 0.5, size), false, Color(HEAT_COLOR.r, HEAT_COLOR.g * 0.8, HEAT_COLOR.b, 0.32 * a * throb))
	var muzzle_y := LevelData.SALVO_Y - LevelData.PLAYER_Y + 4.0
	for off in ShipData.shot_offsets(ship_id):
		var pulse := 0.8 + 0.2 * sin(anim * 31.0 + off)
		var p := Vector2(off, muzzle_y)
		FxTex.draw_centered(_front, FxTex.glow(), p, Vector2(30, 38) * pulse, Color(HEAT_COLOR.r, HEAT_COLOR.g, HEAT_COLOR.b, 0.85 * a))
		FxTex.draw_centered(_front, FxTex.core(), p, Vector2(7, 9) * pulse, Color(1.0, 0.92, 0.75, 0.95 * a))


## SHIELD: a glowing energy bubble – soft inner light, a bright rim, energy arcs running round it, and its light
## on the ground where the dome rests. shield_flash (an absorbed bullet) brightens the rim.
func _draw_shield() -> void:
	var s := shield * alpha
	var c := tint
	var hi := tint.lerp(Color.WHITE, 0.55)
	var ctr := Vector2(0, SHIELD_DY)
	var fl := 0.92 + 0.08 * sin(anim * 23.0) * sin(anim * 7.0 + 1.3)
	FxTex.draw_centered(_front, FxTex.glow(), ctr, SHIELD_R * 2.3, Color(c.r, c.g, c.b, (0.13 + 0.12 * shield_flash) * s))
	FxTex.draw_centered(_front, FxTex.ring(), ctr, SHIELD_R * 2.0 * (1.0 + 0.03 * shield_flash),
		Color(c.r, c.g, c.b, (0.6 + 0.4 * shield_flash) * s * fl))
	# Energy arcs running round the rim (circle arcs squashed to the bubble's ellipse).
	_front.draw_set_transform(ctr, 0.0, Vector2(1.0, SHIELD_R.y / SHIELD_R.x))
	for k in 3:
		var a0 := anim * (1.6 + 0.45 * k) * (1.0 if k % 2 == 0 else -1.0) + TAU * float(k) / 3.0
		_front.draw_arc(Vector2.ZERO, SHIELD_R.x * 0.9, a0, a0 + 0.85, 20, Color(hi.r, hi.g, hi.b, 0.5 * s), 1.6, true)
	_front.draw_set_transform(Vector2.ZERO)
	# Light where the dome meets the ground.
	var gy := LevelData.GROUND_Y - LevelData.PLAYER_Y
	FxTex.draw_centered(_front, FxTex.glow(), Vector2(0, gy), Vector2(SHIELD_R.x * 2.6, 12.0), Color(c.r, c.g, c.b, 0.35 * s))
	FxTex.draw_centered(_front, FxTex.core(), Vector2(0, gy), Vector2(SHIELD_R.x * 1.5, 3.0), Color(hi.r, hi.g, hi.b, 0.3 * s))


## Engine positions for a ship (cached). Looks for one or two bright blobs in the glow overlay.
static func engines(id: int) -> Array:
	if _engines.has(id):
		return _engines[id]
	var out: Array = []
	var meta := Assets.ship_meta(id)
	if meta.get("engines", []) is Array and not (meta.get("engines", []) as Array).is_empty():
		var radii: Array = meta.get("engine_radius", [])
		var widths: Array = []
		for i in (meta["engines"] as Array).size():
			var e: Array = meta["engines"][i]
			out.append(Vector2(float(e[0]), float(e[1])))
			widths.append(clampf(float(radii[i]) / 2.0, 0.55, 1.1) if i < radii.size() else 1.0)
		_engines[id] = out
		_engine_widths[id] = widths
		return out
	var g := Assets.ship_glow_texture(id)
	if g:
		var img := g.get_image()
		if img and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			var halves: Array = [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
			var w := img.get_width()
			var h := img.get_height()
			for y in range(0, h, 2):
				for x in range(0, w, 2):
					var c := img.get_pixel(x, y)
					var lum := (c.r + c.g + c.b) * c.a
					if lum > 0.15:
						var hi := 0 if x * 2 < w else 1
						halves[hi][0] += lum
						halves[hi][1] += lum * float(x)
						halves[hi][2] += lum * float(y)
			var tot: float = halves[0][0] + halves[1][0]
			if tot > 0.0:
				var cl := Vector2(halves[0][1], halves[0][2]) / maxf(halves[0][0], 1e-6)
				var cr := Vector2(halves[1][1], halves[1][2]) / maxf(halves[1][0], 1e-6)
				var balanced := minf(halves[0][0], halves[1][0]) > 0.25 * maxf(halves[0][0], halves[1][0])
				var center := Vector2(w, h) * 0.5
				if balanced and absf(cl.x - cr.x) > 14.0:
					out = [(cl - center) * 0.5, (cr - center) * 0.5]
				else:
					var cc := (Vector2(halves[0][1], halves[0][2]) + Vector2(halves[1][1], halves[1][2])) / tot
					out = [(cc - center) * 0.5]
	if out.is_empty():
		out = [Vector2(0, 22)]
	_engines[id] = out
	return out
