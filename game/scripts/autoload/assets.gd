extends Node
## Autoload "Assets": loads textures, metadata and fonts (docs/SPEC.md §16).
## Every getter works even if the file does not exist yet (generated fallbacks), so code and art
## can be developed in parallel. Everything is cached; nothing is rebuilt per frame.

const SPRITES := "res://assets/sprites/"

var font_title: Font        ## Orbitron bold – titles, HUD numbers
var font_title_heavy: Font  ## Orbitron black – logo-like headings
var font_body: Font         ## Exo 2 medium – body text
var font_body_bold: Font    ## Exo 2 bold

var _cache := {}


func _ready() -> void:
	font_title = _variable_font("res://assets/fonts/Orbitron.ttf", 700)
	font_title_heavy = _variable_font("res://assets/fonts/Orbitron.ttf", 900)
	font_body = _variable_font("res://assets/fonts/Exo2.ttf", 500)
	font_body_bold = _variable_font("res://assets/fonts/Exo2.ttf", 700)
	# Orbitron lacks a few glyphs the texts use (e.g. "·" in "RANK 2 · NORMAL"): they come from the game's own Exo 2
	# instead of whatever system font the OS offers (or a missing-glyph box where there is none).
	if font_title is FontVariation and font_body_bold is FontVariation:
		font_title.fallbacks = [font_body_bold]
		font_title_heavy.fallbacks = [font_body_bold]


# --- Fonts ---------------------------------------------------------------------------------------
func _variable_font(path: String, weight: int) -> Font:
	if not ResourceLoader.exists(path):
		return ThemeDB.fallback_font
	var base: Font = load(path)
	var fv := FontVariation.new()
	fv.base_font = base
	var ts := TextServerManager.get_primary_interface()
	fv.variation_opentype = {ts.name_to_tag("wght"): weight}
	return fv


# --- Ships ---------------------------------------------------------------------------------------
func ship_texture(ship_id: int) -> Texture2D:
	var key: String = ShipData.ship(ship_id)["key"]
	return _cached("ship_" + key, func() -> Texture2D:
		var t := _load_tex(SPRITES + "ships/%s.png" % key)
		return t if t else _fallback_ship(ShipData.ship(ship_id)["accent"], int(ShipData.ship(ship_id)["count"])))


## Ship metadata from ships/<key>.json: {canvas, px_per_game_px, engines: [[x, y], ...] (game px relative to
## the ship centre, nozzle exit centres), engine_radius: [r, ...]}. Empty dictionary if the file is missing.
func ship_meta(ship_id: int) -> Dictionary:
	var key: String = ShipData.ship(ship_id)["key"]
	return _cached("shipmeta_" + key, func() -> Dictionary: return _load_json(SPRITES + "ships/%s.json" % key))


## Optional additive engine-glow overlay (may be null).
func ship_glow_texture(ship_id: int) -> Texture2D:
	var key: String = ShipData.ship(ship_id)["key"]
	return _cached("shipglow_" + key, func() -> Variant: return _load_tex(SPRITES + "ships/%s_glow.png" % key))


# --- Enemies -------------------------------------------------------------------------------------
## Returns {texture, frames, frame_w, frame_h, px_per_game_px, content_top, content_bottom, width_factor}.
## The texture is channel-packed (R diffuse, G specular, B emissive mask, A alpha) – see SPEC §16.2.
func enemy_sheet(planet: String) -> Dictionary:
	return _cached("enemy_" + planet, func() -> Dictionary:
		var tex := _load_tex(SPRITES + "enemies/%s.png" % planet)
		var meta := _load_json(SPRITES + "enemies/%s.json" % planet)
		if tex and not meta.is_empty():
			var d := {"texture": tex, "frames": 16, "frame_w": 256, "frame_h": 160, "px_per_game_px": 2.0,
				"content_top": 0.0, "content_bottom": 160.0,
				"width_factor": LevelData.PLANET_WIDTH_FACTOR.get(planet, 1.0)}
			d.merge(meta, true)
			d["texture"] = tex
			return d
		return _fallback_enemy_sheet(planet))


# --- Planets -------------------------------------------------------------------------------------
## Returns {texture, sphere_diameter_px, center: Vector2}.
func planet_info(planet: String) -> Dictionary:
	return _cached("planet_" + planet, func() -> Dictionary:
		var tex := _load_tex(SPRITES + "planets/%s.png" % planet)
		var meta := _load_json(SPRITES + "planets/%s.json" % planet)
		if tex and meta.has("sphere_diameter_px"):
			var c: Array = meta.get("center", [tex.get_width() * 0.5, tex.get_height() * 0.5])
			return {"texture": tex, "sphere_diameter_px": float(meta["sphere_diameter_px"]),
				"center": Vector2(float(c[0]), float(c[1]))}
		var fb := _fallback_planet(planet)
		return {"texture": fb, "sphere_diameter_px": 240.0, "center": Vector2(128, 128)})


## Draws a planet so that its SPHERE has the given diameter and center (rings extend outside).
func draw_planet(ci: CanvasItem, planet: String, center: Vector2, sphere_diameter: float,
		modulate: Color = Color.WHITE) -> void:
	var info := planet_info(planet)
	var tex: Texture2D = info["texture"]
	var k := sphere_diameter / float(info["sphere_diameter_px"])
	var origin: Vector2 = center - (info["center"] as Vector2) * k
	ci.draw_texture_rect(tex, Rect2(origin, Vector2(tex.get_width(), tex.get_height()) * k), false, modulate)


# --- Ground, projectiles, UI ---------------------------------------------------------------------
func ground_texture(planet: String) -> Texture2D:
	return _cached("ground_" + planet, func() -> Texture2D:
		var t := _load_tex(SPRITES + "ground/%s.png" % planet)
		return t if t else _fallback_ground(LevelData.GROUND_COLORS.get(planet, Color(0.3, 0.3, 0.3))))


## tex_name: "rocket" or "rocket_heavy". May return null (callers draw procedurally then).
func projectile_texture(tex_name: String) -> Texture2D:
	return _cached("proj_" + tex_name, func() -> Variant: return _load_tex(SPRITES + "projectiles/%s.png" % tex_name))


func logo_texture() -> Texture2D:
	return _cached("logo", func() -> Variant: return _load_tex(SPRITES + "ui/logo.png"))


func ui_texture(tex_name: String) -> Texture2D:
	return _cached("ui_" + tex_name, func() -> Variant: return _load_tex(SPRITES + "ui/%s.png" % tex_name))


## 128×128 white radial falloff (alpha) for glows/halos.
func soft_circle() -> Texture2D:
	return _cached("soft_circle", func() -> Texture2D:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 128
		t.height = 128
		return t)


# --- Internals -----------------------------------------------------------------------------------
func _cached(key: String, maker: Callable) -> Variant:
	if not _cache.has(key):
		_cache[key] = maker.call()
	return _cache[key]


func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


func _fallback_ship(accent: Color, count: int) -> Texture2D:
	var img := Image.create(160, 112, false, Image.FORMAT_RGBA8)
	for y in 112:
		for x in 160:
			var dx := absf(x - 80.0)
			var top := 12.0 + dx * 1.4
			if y >= top and y <= 96 and dx <= 66:
				var shade := 0.55 + 0.45 * (1.0 - float(y - 12) / 84.0)
				var c := Color(0.62, 0.66, 0.74).lerp(accent, 0.35 if dx < 14 else 0.1) * shade
				c.a = 1.0
				img.set_pixel(x, y, c)
	if count == 2:
		for side in [-1, 1]:
			for y in range(18, 60):
				for x in range(80 + side * 24 - 3, 80 + side * 24 + 4):
					img.set_pixel(x, y, accent.lightened(0.3))
	return ImageTexture.create_from_image(img)


func _fallback_enemy_sheet(planet: String) -> Dictionary:
	# 4-frame, 1 px per game px channel-packed placeholder: R diffuse, G spec, B eyes, A alpha.
	var fw := 128
	var fh := 80
	var frames := 4
	var wf: float = LevelData.PLANET_WIDTH_FACTOR.get(planet, 1.0)
	var img := Image.create(fw * frames, fh, false, Image.FORMAT_RGBA8)
	for f in frames:
		var flap := sin(TAU * float(f) / frames) * 14.0
		for y in fh:
			for x in fw:
				var px := float(x) - fw * 0.5
				var py := float(y) - fh * 0.5
				var body := (px * px) / 144.0 + (py * py) / 400.0 <= 1.0
				var ax := absf(px)
				var wing_y := -ax * 0.25 + flap * (ax / 45.0)
				var wing := ax <= 45.0 * wf and ax > 6.0 and py > wing_y - 7.0 and py < wing_y + 6.0 - ax * 0.06
				if body or wing:
					var r := clampf(0.85 - (py + 20.0) / 70.0, 0.15, 1.0)
					var eye := body and absf(absf(px) - 5.0) < 2.5 and absf(py + 8.0) < 2.0
					img.set_pixel(f * fw + x, y, Color(r, 0.15 if body else 0.05, 1.0 if eye else 0.0, 1.0))
	return {"texture": ImageTexture.create_from_image(img), "frames": frames, "frame_w": fw, "frame_h": fh,
		"px_per_game_px": 1.0, "content_top": 12.0, "content_bottom": 68.0, "width_factor": wf}


func _fallback_planet(planet: String) -> Texture2D:
	var base: Color = {"neptune": Color(0.2, 0.35, 0.9), "uranus": Color(0.55, 0.85, 0.88),
		"saturn": Color(0.82, 0.68, 0.45), "jupiter": Color(0.7, 0.5, 0.33), "mars": Color(0.8, 0.35, 0.18),
		"earth": Color(0.2, 0.45, 0.85)}.get(planet, Color(0.6, 0.6, 0.6))
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var light := Vector3(-0.6, -0.6, 0.55).normalized()
	for y in 256:
		for x in 256:
			var nx := (x - 128.0) / 120.0
			var ny := (y - 128.0) / 120.0
			var r2 := nx * nx + ny * ny
			if r2 <= 1.0:
				var n := Vector3(nx, ny, sqrt(1.0 - r2))
				var l := clampf(n.dot(light), 0.0, 1.0) * 0.9 + 0.08
				var c := base * l
				c.a = clampf((1.0 - r2) * 60.0, 0.0, 1.0)
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _fallback_ground(color: Color) -> Texture2D:
	var img := Image.create(960, 35, false, Image.FORMAT_RGBA8)
	for y in 35:
		var c := color.lerp(Color(0, 0, 0), float(y) / 45.0)
		if y < 2:
			c = color.lightened(0.35)
		c.a = 1.0
		for x in 960:
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
