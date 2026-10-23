extends Node2D
## Player ship: Assets.ship_texture drawn at 0.5 scale centred on the node (x, 659), with an additive
## engine glow (the optional *_glow.png overlay plus procedural exhaust flames that flicker).

const FxTex := preload("res://scripts/game/fx_tex.gd")

## Engine nozzle positions (game px, relative to the ship centre) per ship id: exact nozzle data from
## ships/<key>.json when available, otherwise derived once from the glow overlay (brightness centroids);
## last fallback: one engine at the bottom centre.
static var _engines := {}
static var _engine_widths := {}

var ship_id := 0
var alpha := 1.0          ## respawn fade-in
var bank := 0.0           ## -1..1 current horizontal movement (slight narrowing while strafing)
var anim := 0.0           ## seconds, drives the flicker

var _glow_node: Node2D
var _accent := Color(0.4, 0.7, 1.0)


func _ready() -> void:
	_accent = ShipData.ship(ship_id)["accent"]
	_glow_node = Node2D.new()
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow_node.material = m
	_glow_node.show_behind_parent = true
	_glow_node.draw.connect(_draw_glow)
	add_child(_glow_node)


func refresh() -> void:
	scale = Vector2(1.0 - 0.06 * absf(bank), 1.0)
	queue_redraw()
	_glow_node.queue_redraw()


func _draw() -> void:
	var tex := Assets.ship_texture(ship_id)
	var size := Vector2(tex.get_width(), tex.get_height()) * 0.5
	draw_texture_rect(tex, Rect2(-size * 0.5, size), false, Color(1, 1, 1, alpha))


func _draw_glow() -> void:
	var f := 0.82 + 0.1 * sin(anim * 37.0) + 0.08 * sin(anim * 91.0 + 1.1)
	var g := Assets.ship_glow_texture(ship_id)
	if g:
		var size := Vector2(g.get_width(), g.get_height()) * 0.5
		_glow_node.draw_texture_rect(g, Rect2(-size * 0.5, size), false, Color(1, 1, 1, alpha * (0.75 + 0.35 * f)))
	# Engine light spilling onto the ground surface right below the ship.
	FxTex.draw_centered(_glow_node, FxTex.glow(), Vector2(0, LevelData.GROUND_Y - LevelData.PLAYER_Y + 2.0),
		Vector2(96.0, 16.0) * (0.9 + 0.1 * f), Color(_accent.r, _accent.g, _accent.b, 0.22 * alpha))
	var hot := Color(0.75, 0.9, 1.0).lerp(_accent, 0.25)
	var list := engines(ship_id)
	var widths: Array = _engine_widths.get(ship_id, [])
	for i in list.size():
		var p: Vector2 = list[i]
		var wk: float = widths[i] if i < widths.size() else 1.0
		var ln := (12.0 + 6.0 * f) * (0.75 + 0.25 * wk)
		FxTex.draw_centered(_glow_node, FxTex.glow(), p + Vector2(0, 3), Vector2(22, 22) * f * wk, Color(_accent.r, _accent.g, _accent.b, 0.55 * alpha))
		FxTex.draw_oriented(_glow_node, FxTex.flame(), p + Vector2(0, ln * 0.42), Vector2.DOWN, Vector2(8.0 * wk, ln),
			Color(_accent.r, _accent.g, _accent.b, 0.8 * alpha))
		FxTex.draw_oriented(_glow_node, FxTex.flame(), p + Vector2(0, ln * 0.25), Vector2.DOWN, Vector2(4.0 * wk, ln * 0.6),
			Color(hot.r, hot.g, hot.b, 0.95 * alpha))


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
