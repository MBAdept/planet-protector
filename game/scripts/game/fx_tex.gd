extends RefCounted
## Procedural glow / ring / streak textures for projectiles and effects.
## Built once on first use and cached statically – never rebuilt per frame.
## Usage: const FxTex := preload("res://scripts/game/fx_tex.gd"); FxTex.glow()

static var _cache := {}


## Soft round glow, white with a smooth (gaussian-like) alpha falloff to 0 at the edge.
static func glow() -> Texture2D:
	return _cached_tex("glow", func() -> Texture2D:
		return _radial(128, func(r: float) -> float:
			return clampf(exp(-r * r * 4.2) - exp(-4.2), 0.0, 1.0) / (1.0 - exp(-4.2))))


## Hot core: a tighter, brighter disc with a short soft edge.
static func core() -> Texture2D:
	return _cached_tex("core", func() -> Texture2D:
		return _radial(64, func(r: float) -> float:
			return clampf(1.0 - smoothstep(0.35, 1.0, r), 0.0, 1.0)))


## Thin ring (shock waves). The bright band sits at ~88 % of the radius.
static func ring() -> Texture2D:
	return _cached_tex("ring", func() -> Texture2D:
		return _radial(256, func(r: float) -> float:
			var d := (r - 0.88) / 0.07
			var inner := clampf(1.0 - r, 0.0, 1.0) * 0.18
			return clampf(exp(-d * d) + inner * smoothstep(0.3, 0.88, r), 0.0, 1.0)))


## Horizontal streak: gaussian across, long soft fade along (sparks, beams). Draw it rotated.
static func streak() -> Texture2D:
	return _cached_tex("streak", func() -> Texture2D:
		var w := 128
		var h := 32
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			var v := (float(y) + 0.5) / float(h) * 2.0 - 1.0
			var across := exp(-v * v * 6.0) * (1.0 - absf(v))
			for x in w:
				var u := (float(x) + 0.5) / float(w)
				var along := smoothstep(0.0, 0.25, u) * smoothstep(1.0, 0.6, u)
				img.set_pixel(x, y, Color(1, 1, 1, clampf(across * along, 0.0, 1.0)))
		return ImageTexture.create_from_image(img))


## Vertical teardrop flame: bright round head at the top, long fading tail downwards.
static func flame() -> Texture2D:
	return _cached_tex("flame", func() -> Texture2D:
		var w := 32
		var h := 96
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			var v := (float(y) + 0.5) / float(h)          # 0 top … 1 bottom
			var width := lerpf(1.0, 0.08, pow(v, 0.7))
			var along := (1.0 - smoothstep(0.55, 1.0, v)) * smoothstep(0.0, 0.08, v)
			for x in w:
				var u := ((float(x) + 0.5) / float(w) * 2.0 - 1.0) / maxf(width, 0.01)
				var across := exp(-u * u * 2.5) * clampf(1.0 - absf(u), 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, clampf(across * along, 0.0, 1.0)))
		return ImageTexture.create_from_image(img))


## Horizontal soft band, 1 at the centre line (horizon glows, scan bars).
static func band() -> Texture2D:
	return _cached_tex("band", func() -> Texture2D:
		var img := Image.create(4, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			var v := (float(y) + 0.5) / 64.0 * 2.0 - 1.0
			var a := clampf(exp(-v * v * 5.0) * (1.0 - absf(v)), 0.0, 1.0)
			for x in 4:
				img.set_pixel(x, y, Color(1, 1, 1, a))
		return ImageTexture.create_from_image(img))


static var _uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
static var _pts := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
static var _cols := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])


## Draws a texture centred at `center` with `size` (axis aligned). Respects any draw transform of `ci`.
static func draw_centered(ci: CanvasItem, tex: Texture2D, center: Vector2, size: Vector2, color: Color) -> void:
	ci.draw_texture_rect(tex, Rect2(center - size * 0.5, size), false, color)


## Draws a texture as a rotated quad: `ax` = half extent along the texture's x axis, `ay` = along y.
## Uses draw_primitive, so it never touches the caller's draw transform.
static func draw_quad(ci: CanvasItem, tex: Texture2D, center: Vector2, ax: Vector2, ay: Vector2, color: Color) -> void:
	_pts[0] = center - ax - ay
	_pts[1] = center + ax - ay
	_pts[2] = center + ax + ay
	_pts[3] = center - ax + ay
	for i in 4:
		_cols[i] = color
	ci.draw_primitive(_pts, _cols, _uvs, tex)


## Same as draw_quad but oriented by a unit direction `dir` that the texture's +y axis points to.
static func draw_oriented(ci: CanvasItem, tex: Texture2D, center: Vector2, dir: Vector2, size: Vector2, color: Color) -> void:
	var ay := dir * (size.y * 0.5)
	var ax := Vector2(-dir.y, dir.x) * (size.x * 0.5)
	draw_quad(ci, tex, center, ax, ay, color)


# --- Internals -----------------------------------------------------------------------------------
static func _cached_tex(key: String, maker: Callable) -> Texture2D:
	if not _cache.has(key):
		_cache[key] = maker.call()
	return _cache[key]


static func _radial(n: int, falloff: Callable) -> Texture2D:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := float(n) * 0.5
	for y in n:
		for x in n:
			var dx := (float(x) + 0.5 - c) / c
			var dy := (float(y) + 0.5 - c) / c
			var r := sqrt(dx * dx + dy * dy)
			var a := 0.0 if r >= 1.0 else float(falloff.call(r))
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
