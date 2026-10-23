class_name Starfield
extends Node2D
## Layered star background (docs/SPEC.md §15).
##
## Binding API: `velocity` (px/s of the NEAREST layer; deeper layers move slower) and `density`.
## Look: thousands of faint points on three pre-rendered depth layers, a few dozen medium stars and
## a handful of bright stars with soft halos (drawn as cached sprites so they stay crisp and can
## twinkle gently), subtle white / bluish / warm tints, clustered distribution that follows a faint
## nebula haze. Nothing is rebuilt per frame: all textures are generated once and cached statically
## (shared by every Starfield instance with the same density). The scroll position is shared too, so
## the sky continues seamlessly from one screen to the next.
## Fast horizontal motion (arrival sequence, e.g. velocity = Vector2(-900, 0)) cross-fades the dot
## layers into pre-rendered streak layers and stretches the sprite stars into streaks.

## Velocity of the nearest layer in px/s. Gameplay: slow drift down; arrival: fast right → left.
var velocity := Vector2(0, 6)
## Multiplies the number of stars (rebuilds the cached textures for that density on change).
var density := 1.0:
	set(value):
		density = maxf(value, 0.05)
		if is_inside_tree():
			_build()
## Intensity of the faint nebula haze (0 = off, 1 = default subtle look).
var nebula := 1.0
## Area covered (stars wrap around inside it).
var size := Vector2(960, 720)

## Depth (speed factor) of the three pre-rendered layers: far, middle, near-ish.
const LAYER_DEPTH: Array[float] = [0.14, 0.3, 0.55]
const LAYER_COUNT: Array[int] = [1150, 430, 150]
const NEBULA_DEPTH := 0.06
const NEAR_COUNT := 46
const BRIGHT_COUNT := 13
const TEX_W := 960
const TEX_H := 720
## Streak length (px) baked into the streak version of layer 1 and 2.
const STREAK_LEN: Array[int] = [0, 13, 26]

const TINTS: Array[Color] = [
	Color(1.0, 1.0, 1.0), Color(0.80, 0.88, 1.0), Color(0.70, 0.82, 1.0),
	Color(1.0, 0.92, 0.80), Color(1.0, 0.82, 0.66),
]
const TINT_WEIGHTS: Array[float] = [0.42, 0.26, 0.12, 0.14, 0.06]

static var _cache := {}        # density key → built data (textures + star tables)
static var _shared := {}       # density key → scroll state, so the sky continues across screens
static var _stamps := {}       # stamp key → Image

var _data: Dictionary = {}
var _key := ""
var _offsets: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var _nebula_offset := Vector2.ZERO
var _near_pos := PackedVector2Array()
var _bright_pos := PackedVector2Array()
var _time := 0.0
var _nebula_node: Node2D


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_nebula_node = Node2D.new()
	_nebula_node.show_behind_parent = true
	_nebula_node.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_nebula_node.material = mat
	_nebula_node.draw.connect(_draw_nebula)
	add_child(_nebula_node)
	_build()


func _exit_tree() -> void:
	_store_state()


func _process(delta: float) -> void:
	_time += delta
	for i in LAYER_DEPTH.size():
		_offsets[i] = _wrap(_offsets[i] + velocity * LAYER_DEPTH[i] * delta)
	_nebula_offset = _wrap(_nebula_offset + velocity * NEBULA_DEPTH * delta)
	var near: Array = _data.get("near", [])
	for i in near.size():
		_near_pos[i] = _wrap(_near_pos[i] + velocity * float(near[i]["depth"]) * delta)
	var bright: Array = _data.get("bright", [])
	for i in bright.size():
		_bright_pos[i] = _wrap(_bright_pos[i] + velocity * float(bright[i]["depth"]) * delta)
	_store_state()
	queue_redraw()
	if _nebula_node:
		_nebula_node.queue_redraw()


# --- Drawing -------------------------------------------------------------------------------------
func _draw() -> void:
	if _data.is_empty():
		return
	var layers: Array = _data["layers"]
	var horizontal := absf(velocity.x) >= absf(velocity.y)
	for i in layers.size():
		var layer_speed := absf(velocity.x) * LAYER_DEPTH[i]
		var k := 0.0
		if STREAK_LEN[i] > 0 and horizontal:
			k = smoothstep(140.0, 460.0, layer_speed)
		if k < 0.999:
			_draw_tiled(self, layers[i], _offsets[i], Color(1, 1, 1, 1.0 - 0.85 * k))
		if k > 0.001:
			_draw_streak_layer(i, k)
	_draw_sprites()


func _draw_tiled(ci: CanvasItem, tex: Texture2D, offset: Vector2, mod: Color) -> void:
	# Texture repeat is enabled, so a shifted source region wraps around seamlessly.
	var src := Rect2(Vector2(-offset.x, -offset.y) * Vector2(tex.get_width() / size.x, tex.get_height() / size.y),
		Vector2(tex.get_width(), tex.get_height()))
	ci.draw_texture_rect_region(tex, Rect2(Vector2.ZERO, size), src, mod)


func _draw_streak_layer(i: int, k: float) -> void:
	# Baked tails point away from the motion: +x for motion to the left, −x for motion to the right.
	var tex := _streak_texture(i, 1 if velocity.x <= 0.0 else -1)
	if tex != null:
		_draw_tiled(self, tex, _offsets[i], Color(1, 1, 1, k))


func _draw_sprites() -> void:
	var dot: Texture2D = _data["dot"]
	var streak: Texture2D = _data["streak"]
	var halo := Assets.soft_circle()
	var spike: Texture2D = _data["spike"]
	var speed := velocity.length()
	var tail_angle := (-velocity).angle()
	var near: Array = _data["near"]
	for i in near.size():
		var s: Dictionary = near[i]
		var tw := 1.0 - 0.10 * (0.5 + 0.5 * sin(_time * float(s["freq"]) + float(s["phase"])))
		var col: Color = s["color"]
		col.a = float(s["alpha"]) * tw
		_draw_star_core(dot, streak, _near_pos[i], float(s["size"]), col, speed * float(s["depth"]), tail_angle)
	var bright: Array = _data["bright"]
	for i in bright.size():
		var b: Dictionary = bright[i]
		var p := _bright_pos[i]
		var tw := 1.0 - 0.12 * (0.5 + 0.5 * sin(_time * float(b["freq"]) + float(b["phase"])))
		var col: Color = b["color"]
		var hs := float(b["halo"]) * (0.96 + 0.04 * tw)
		var star_speed := speed * float(b["depth"])
		var streak_k := smoothstep(60.0, 300.0, star_speed)
		var hc := col
		hc.a = float(b["halo_alpha"]) * tw * (1.0 - 0.7 * streak_k)
		draw_texture_rect(halo, Rect2(p - Vector2(hs, hs) * 0.5, Vector2(hs, hs)), false, hc)
		if float(b["spikes"]) > 0.0 and streak_k < 0.99:
			var sc := col
			sc.a = float(b["spikes"]) * tw * (1.0 - streak_k)
			var sl := hs * 1.25
			draw_texture_rect(spike, Rect2(p - Vector2(sl * 0.5, 1.5), Vector2(sl, 3.0)), false, sc)
			draw_set_transform(p, PI * 0.5, Vector2.ONE)
			draw_texture_rect(spike, Rect2(Vector2(-sl * 0.5, -1.5), Vector2(sl, 3.0)), false, sc)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var cc := col.lerp(Color.WHITE, 0.55)
		cc.a = minf(1.0, 0.95 * tw + 0.05)
		_draw_star_core(dot, streak, p, float(b["size"]), cc, star_speed, tail_angle)


func _draw_star_core(dot: Texture2D, streak: Texture2D, p: Vector2, sz: float, col: Color, star_speed: float,
		tail_angle: float) -> void:
	var length := clampf(star_speed * 0.05, 0.0, 80.0)
	if length > 2.0:
		var thick := sz * 0.9
		var sc := col
		sc.a *= clampf(1.6 / sqrt(maxf(length / sz, 1.0)), 0.35, 1.0)
		draw_set_transform(p, tail_angle, Vector2.ONE)
		draw_texture_rect(streak, Rect2(Vector2(-sz * 0.5, -thick * 0.5), Vector2(length + sz * 0.5, thick)), false, sc)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_texture_rect(dot, Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, col)


func _draw_nebula() -> void:
	if _data.is_empty() or nebula <= 0.0:
		return
	var neb: Array = _data["nebula"]
	var tints: Array[Color] = [Color(0.045, 0.08, 0.19), Color(0.11, 0.035, 0.15)]
	for i in neb.size():
		var off := _nebula_offset * (1.0 + 0.6 * i) + Vector2(173.0, 91.0) * i
		var c: Color = tints[i] * nebula
		c.a = 1.0
		_draw_tiled(_nebula_node, neb[i], _wrap(off), c)


# --- State ---------------------------------------------------------------------------------------
func _wrap(p: Vector2) -> Vector2:
	return Vector2(fposmod(p.x, size.x), fposmod(p.y, size.y))


func _store_state() -> void:
	if _key == "":
		return
	_shared[_key] = {"offsets": _offsets.duplicate(), "nebula": _nebula_offset,
		"near": _near_pos.duplicate(), "bright": _bright_pos.duplicate(), "time": _time}


func _build() -> void:
	_key = "%.3f" % density
	if not _cache.has(_key):
		_cache[_key] = _generate(density)
	_data = _cache[_key]
	var near: Array = _data["near"]
	var bright: Array = _data["bright"]
	if _shared.has(_key):
		var st: Dictionary = _shared[_key]
		_offsets.assign(st["offsets"])
		_nebula_offset = st["nebula"]
		_near_pos = (st["near"] as PackedVector2Array).duplicate()
		_bright_pos = (st["bright"] as PackedVector2Array).duplicate()
		_time = float(st["time"])
	else:
		_near_pos.resize(near.size())
		for i in near.size():
			_near_pos[i] = near[i]["pos"]
		_bright_pos.resize(bright.size())
		for i in bright.size():
			_bright_pos[i] = bright[i]["pos"]
	queue_redraw()


# --- Generation (once per density, cached) -------------------------------------------------------
static func _generate(dens: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260423
	var data := {}
	# Nebula haze: two seamless noise layers, high contrast so most of the sky stays black.
	var neb_tex: Array[Texture2D] = []
	var neb_img: Array[Image] = []
	for i in 2:
		var n := FastNoiseLite.new()
		n.seed = 77 + i * 31
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.0075 if i == 0 else 0.013
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 3
		n.fractal_gain = 0.5
		var img := n.get_seamless_image(320, 240, false, false, 0.2, true)
		img.convert(Image.FORMAT_RGBA8)
		img.adjust_bcs(0.80 if i == 0 else 0.74, 2.5 if i == 0 else 3.4, 1.0)
		neb_img.append(img)
		neb_tex.append(ImageTexture.create_from_image(img))
	data["nebula"] = neb_tex
	# Density map: nebula brightness + a few compact clusters (uneven, natural distribution).
	var clusters: Array[Vector3] = []
	for i in 6:
		clusters.append(Vector3(rng.randf() * TEX_W, rng.randf() * TEX_H, rng.randf_range(22.0, 60.0)))
	var layers: Array[Texture2D] = []
	var layer_stars: Array = []
	for li in LAYER_DEPTH.size():
		var img := Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGBA8)
		var stars: Array[Vector4i] = []   # x, y, alpha level, tint
		var count := int(LAYER_COUNT[li] * dens)
		for s in count:
			var p := _sample_position(rng, neb_img[0], clusters)
			var a: float
			var sigma_idx: int
			match li:
				0:
					a = rng.randf_range(0.12, 0.42)
					sigma_idx = 0
				1:
					a = rng.randf_range(0.22, 0.6)
					sigma_idx = 0 if rng.randf() < 0.6 else 1
				_:
					a = rng.randf_range(0.32, 0.78)
					sigma_idx = 1 if rng.randf() < 0.65 else 2
			var ai := clampi(int(round(a * 16.0)) - 1, 0, 15)
			var ti := _pick_tint(rng)
			var stamp := _dot_stamp(sigma_idx, ai, ti)
			_blend_wrapped(img, stamp, Vector2i(int(p.x), int(p.y)))
			stars.append(Vector4i(int(p.x), int(p.y), ai, ti))
		layers.append(ImageTexture.create_from_image(img))
		layer_stars.append(stars)
	data["layers"] = layers
	data["layer_stars"] = layer_stars
	data["streak_tex"] = {}
	# Medium stars (sprites, near depths) and bright stars with halos.
	var near: Array = []
	for i in int(NEAR_COUNT * dens):
		var ti := _pick_tint(rng)
		near.append({"pos": _sample_position(rng, neb_img[0], clusters), "depth": rng.randf_range(0.7, 1.0),
			"size": rng.randf_range(2.0, 3.3), "alpha": rng.randf_range(0.45, 0.85), "color": TINTS[ti],
			"phase": rng.randf() * TAU, "freq": rng.randf_range(0.5, 1.6)})
	data["near"] = near
	var bright: Array = []
	for i in maxi(int(BRIGHT_COUNT * dens), 3):
		var ti := _pick_tint(rng)
		var big := i < 3
		bright.append({"pos": _sample_position(rng, neb_img[0], clusters), "depth": rng.randf_range(0.6, 1.0),
			"size": rng.randf_range(3.6, 4.6) if big else rng.randf_range(2.8, 3.8),
			"halo": rng.randf_range(30.0, 44.0) if big else rng.randf_range(14.0, 24.0),
			"halo_alpha": rng.randf_range(0.20, 0.30) if big else rng.randf_range(0.12, 0.2),
			"spikes": 0.32 if big else 0.0, "color": TINTS[ti].lerp(Color.WHITE, 0.2),
			"phase": rng.randf() * TAU, "freq": rng.randf_range(0.4, 1.1)})
	data["bright"] = bright
	data["dot"] = _make_dot_texture()
	data["streak"] = _make_streak_texture()
	data["spike"] = _make_spike_texture()
	return data


static func _sample_position(rng: RandomNumberGenerator, neb: Image, clusters: Array[Vector3]) -> Vector2:
	# 18 % of the stars belong to compact clusters, the rest follow the nebula density.
	if rng.randf() < 0.18:
		var c: Vector3 = clusters[rng.randi() % clusters.size()]
		var r := absf(rng.randfn(0.0, c.z))
		var ang := rng.randf() * TAU
		return Vector2(fposmod(c.x + cos(ang) * r, TEX_W), fposmod(c.y + sin(ang) * r, TEX_H))
	for attempt in 12:
		var p := Vector2(rng.randf() * TEX_W, rng.randf() * TEX_H)
		var n := neb.get_pixel(int(p.x / TEX_W * neb.get_width()) % neb.get_width(),
			int(p.y / TEX_H * neb.get_height()) % neb.get_height()).r
		if rng.randf() < 0.22 + 0.78 * n:
			return p
	return Vector2(rng.randf() * TEX_W, rng.randf() * TEX_H)


static func _pick_tint(rng: RandomNumberGenerator) -> int:
	var r := rng.randf()
	for i in TINT_WEIGHTS.size():
		r -= TINT_WEIGHTS[i]
		if r <= 0.0:
			return i
	return 0


static func _blend_wrapped(img: Image, stamp: Image, center: Vector2i) -> void:
	var w := stamp.get_width()
	var h := stamp.get_height()
	var tl := center - Vector2i(w >> 1, h >> 1)
	var src := Rect2i(0, 0, w, h)
	for dx in [0, -TEX_W, TEX_W]:
		for dy in [0, -TEX_H, TEX_H]:
			var p: Vector2i = tl + Vector2i(dx, dy)
			if p.x + w <= 0 or p.y + h <= 0 or p.x >= TEX_W or p.y >= TEX_H:
				continue
			img.blend_rect(stamp, src, p)


## Gaussian dot stamp; sigma index 0..2, alpha level 0..15, tint index.
static func _dot_stamp(sigma_idx: int, alpha_idx: int, tint_idx: int) -> Image:
	var key := "d%d_%d_%d" % [sigma_idx, alpha_idx, tint_idx]
	if _stamps.has(key):
		return _stamps[key]
	var sigma: float = [0.42, 0.58, 0.78][sigma_idx]
	var a := float(alpha_idx + 1) / 16.0
	var r := maxi(1, ceili(sigma * 2.6))
	var img := Image.create(2 * r + 1, 2 * r + 1, false, Image.FORMAT_RGBA8)
	var tint: Color = TINTS[tint_idx]
	for y in 2 * r + 1:
		for x in 2 * r + 1:
			var d2 := float((x - r) * (x - r) + (y - r) * (y - r))
			var c := tint
			c.a = a * exp(-d2 / (2.0 * sigma * sigma))
			img.set_pixel(x, y, c)
	_stamps[key] = img
	return img


## Horizontal streak stamp centred on the star head; tail_dir +1 = tail to the right (motion to the left).
static func _streak_stamp(length: int, alpha_idx: int, tint_idx: int, tail_dir: int) -> Image:
	var key := "s%d_%d_%d_%d" % [length, alpha_idx, tint_idx, tail_dir]
	if _stamps.has(key):
		return _stamps[key]
	var a := float(alpha_idx + 1) / 16.0
	var w := length + 3
	var img := Image.create(w * 2 + 1, 5, false, Image.FORMAT_RGBA8)
	var tint: Color = TINTS[tint_idx]
	for y in 5:
		var vy := exp(-float((y - 2) * (y - 2)) / (2.0 * 0.55 * 0.55))
		for x in w * 2 + 1:
			var dx := float(x - w) * float(tail_dir)
			var along := 0.0
			if dx < 0.0:
				along = exp(-dx * dx / (2.0 * 0.6 * 0.6))
			else:
				along = pow(clampf(1.0 - dx / float(length), 0.0, 1.0), 1.4)
			var c := tint
			c.a = clampf(a * vy * along * 1.15, 0.0, 1.0)
			img.set_pixel(x, y, c)
	_stamps[key] = img
	return img


func _streak_texture(i: int, tail_dir: int) -> Texture2D:
	if STREAK_LEN[i] <= 0:
		return null
	var cache: Dictionary = _data["streak_tex"]
	var key := i * 10 + (1 if tail_dir > 0 else 0)
	if not cache.has(key):
		var img := Image.create(TEX_W, TEX_H, false, Image.FORMAT_RGBA8)
		for s: Vector4i in _data["layer_stars"][i]:
			_blend_wrapped(img, _streak_stamp(STREAK_LEN[i], s.z, s.w, tail_dir), Vector2i(s.x, s.y))
		cache[key] = ImageTexture.create_from_image(img)
	return cache[key]


static func _make_dot_texture() -> Texture2D:
	var n := 16
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(exp(-d * d * 4.5) * 1.05 - 0.02, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


static func _make_streak_texture() -> Texture2D:
	var w := 64
	var h := 8
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var vy := exp(-pow((y + 0.5 - h * 0.5) / (h * 0.22), 2.0))
		for x in w:
			var u := (x + 0.5) / float(w)
			img.set_pixel(x, y, Color(1, 1, 1, vy * pow(1.0 - u, 1.3)))
	return ImageTexture.create_from_image(img)


static func _make_spike_texture() -> Texture2D:
	var w := 64
	var h := 4
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var vy := exp(-pow((y + 0.5 - h * 0.5) / 0.9, 2.0))
		for x in w:
			var u := absf((x + 0.5) / float(w) * 2.0 - 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, vy * pow(1.0 - u, 2.2)))
	return ImageTexture.create_from_image(img)
