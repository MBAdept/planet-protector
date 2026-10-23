class_name ProjectileArt
extends RefCounted
## Drawing of all projectiles (docs/SPEC.md §4, §7). Used by the game AND the ship-select previews.
## Everything is drawn with normal alpha blending from cached glow textures (looks luminous on the dark
## sky, works on any canvas item), never changes the caller's draw transform and allocates nothing
## per call except the small polygon arrays.

const FxTex := preload("res://scripts/game/fx_tex.gd")

const BLUE_GLOW := Color(0.16, 0.48, 1.0, 0.55)
const BLUE_BODY := Color(0.38, 0.74, 1.0, 0.95)
const BLUE_CORE := Color(0.88, 0.97, 1.0, 1.0)
const RED_GLOW := Color(1.0, 0.16, 0.10, 0.55)
const RED_BODY := Color(1.0, 0.24, 0.16, 0.95)
const RED_MID := Color(1.0, 0.55, 0.42, 1.0)
const RED_CORE := Color(1.0, 0.95, 0.9, 1.0)
const FLAME_OUTER := Color(1.0, 0.42, 0.10, 0.85)
const FLAME_INNER := Color(1.0, 0.86, 0.45, 0.95)
const FLAME_GLOW := Color(1.0, 0.5, 0.15, 0.45)


## Draws ONE logical player projectile of the given ship at `center` (game px, scaled by `scale`).
## `age` = seconds since launch (for flicker/flame animation). For double ships call it per bullet.
static func draw_player_shot(ci: CanvasItem, ship_id: int, center: Vector2, age: float, scale: float = 1.0) -> void:
	var look: int = ShipData.ship(ship_id)["look"]
	match look:
		ShipData.Look.LASER_BLUE:
			_laser(ci, center, age, scale, 36.0, 6.0, 2.6, BLUE_GLOW, BLUE_BODY, BLUE_CORE, BLUE_BODY)
		ShipData.Look.LASER_RED_THICK:
			_laser(ci, center, age, scale, 44.0, 12.0, 3.6, RED_GLOW, RED_BODY, RED_CORE, RED_MID)
		ShipData.Look.ROCKET:
			_rocket(ci, center, age, scale, false, 0.0)
		ShipData.Look.ROCKET_HEAVY_PAIR:
			# Hunter: ONE logical projectile drawn as two heavy rockets side by side (±6 px).
			_rocket(ci, center + Vector2(-6.0, 0.0) * scale, age, scale, true, 0.0)
			_rocket(ci, center + Vector2(6.0, 1.5) * scale, age, scale, true, 1.7)


## Draws one enemy fireball. `velocity` gives the tail direction. Caller is responsible for ground clipping.
## `alpha` fades the whole fireball (used while it sinks into the ground).
static func draw_enemy_bullet(ci: CanvasItem, pos: Vector2, velocity: Vector2, age: float, scale: float = 1.0,
		alpha: float = 1.0) -> void:
	if alpha <= 0.0:
		return
	var dir := velocity.normalized() if velocity.length_squared() > 1e-6 else Vector2.DOWN
	var back := -dir
	var sd := absf(pos.x * 0.37 + velocity.x * 0.013)
	var fl := 0.86 + 0.14 * sin(age * 41.0 + sd) * sin(age * 23.0 + sd * 1.7)
	var s := scale
	# Wide glow halo.
	FxTex.draw_centered(ci, FxTex.glow(), pos, Vector2(52, 52) * s * fl, _a(Color(1.0, 0.32, 0.06, 0.42), alpha))
	# Tail opposite to the velocity: a soft stretched glow plus two tapered gradient flames.
	var side := Vector2(-back.y, back.x)
	var tail_len := 40.0 * s * (0.82 + 0.28 * fl)
	FxTex.draw_oriented(ci, FxTex.glow(), pos + back * (tail_len * 0.42), back, Vector2(18.0 * s, tail_len * 1.25),
		_a(Color(1.0, 0.3, 0.05, 0.55), alpha))
	var wob := sin(age * 37.0 + sd) * 1.6 * s
	_tail(ci, pos, back, side, 6.0 * s, tail_len, wob, _a(Color(1.0, 0.36, 0.06, 0.9), alpha), _a(Color(0.9, 0.12, 0.02, 0.0), alpha))
	_tail(ci, pos, back, side, 3.2 * s, tail_len * 0.55, wob * 0.5, _a(Color(1.0, 0.86, 0.45, 0.95), alpha), _a(Color(1.0, 0.5, 0.1, 0.0), alpha))
	# Embers drifting behind.
	for i in 3:
		var ph := fposmod(age * 3.1 + float(i) * 0.33 + sd * 0.1, 1.0)
		var drift := side * sin(sd + float(i) * 2.3 + age * 9.0) * 4.0 * s
		var p := pos + back * (12.0 + ph * 26.0) * s + drift
		FxTex.draw_centered(ci, FxTex.core(), p, Vector2(4.0, 4.0) * s * (1.0 - ph * 0.6),
			_a(Color(1.0, 0.55, 0.15, 0.85 * (1.0 - ph)), alpha))
	# Burning body and white-hot core.
	FxTex.draw_centered(ci, FxTex.core(), pos, Vector2(17.0, 17.0) * s * fl, _a(Color(1.0, 0.42, 0.08, 1.0), alpha))
	FxTex.draw_centered(ci, FxTex.core(), pos, Vector2(12.5, 12.5) * s, _a(Color(1.0, 0.74, 0.28, 1.0), alpha))
	FxTex.draw_centered(ci, FxTex.core(), pos + dir * 1.0 * s, Vector2(7.5, 7.5) * s, _a(Color(1.0, 0.98, 0.88, 1.0), alpha))


## Tapered flame from the head (`pos`) along `back`: half width `hw` at the head, a tip at `length`.
static func _tail(ci: CanvasItem, pos: Vector2, back: Vector2, side: Vector2, hw: float, length: float, wob: float,
		head_col: Color, tip_col: Color) -> void:
	var mid := pos + back * (length * 0.45) + side * wob * 0.5
	var pts := PackedVector2Array([pos + side * hw, mid + side * hw * 0.62, pos + back * length + side * wob,
		mid - side * hw * 0.62, pos - side * hw])
	var mid_col := head_col.lerp(tip_col, 0.4)
	ci.draw_polygon(pts, PackedColorArray([head_col, mid_col, tip_col, mid_col, head_col]))


# --- Lasers --------------------------------------------------------------------------------------
static func _laser(ci: CanvasItem, c: Vector2, age: float, s: float, length: float, width: float, core_w: float,
		glow: Color, body: Color, core: Color, mid: Color) -> void:
	var fl := 0.9 + 0.1 * sin(age * 57.0)
	var half := length * 0.5
	# Wide soft glow around the bolt.
	FxTex.draw_centered(ci, FxTex.glow(), c + Vector2(0, 2) * s, Vector2(width * 5.0, length * 1.8) * s * fl, glow)
	FxTex.draw_centered(ci, FxTex.glow(), c, Vector2(width * 2.2, length * 1.25) * s, _a(glow, 1.2))
	# Outer body: pointed head, fading tail.
	_bolt(ci, c, half * s, width * 0.5 * s, _a(body, 1.0), _a(body, 0.0))
	if mid != body:
		_bolt(ci, c + Vector2(0, -1) * s, (half - 2.0) * s, width * 0.3 * s, mid, _a(mid, 0.0))
	# Hot core line.
	_bolt(ci, c + Vector2(0, -1.5) * s, (half - 3.0) * s, core_w * 0.5 * s, core, _a(core, 0.15))
	# Bright tip.
	FxTex.draw_centered(ci, FxTex.glow(), c + Vector2(0, -half + 3.0) * s, Vector2(width * 2.4, width * 2.8) * s, _a(core, 0.9 * fl))


## Elongated diamond: tip at the top (y − half), widest at 25 %, tapering into the tail.
static func _bolt(ci: CanvasItem, c: Vector2, half: float, hw: float, head_col: Color, tail_col: Color) -> void:
	var pts := PackedVector2Array([
		c + Vector2(0, -half),
		c + Vector2(hw, -half * 0.55),
		c + Vector2(hw * 0.75, half * 0.55),
		c + Vector2(0, half),
		c + Vector2(-hw * 0.75, half * 0.55),
		c + Vector2(-hw, -half * 0.55),
	])
	var mid_col := head_col.lerp(tail_col, 0.45)
	var cols := PackedColorArray([head_col, head_col, mid_col, tail_col, mid_col, head_col])
	ci.draw_polygon(pts, cols)


# --- Rockets -------------------------------------------------------------------------------------
static func _rocket(ci: CanvasItem, c: Vector2, age: float, s: float, heavy: bool, phase: float) -> void:
	var tex := Assets.projectile_texture("rocket_heavy" if heavy else "rocket")
	var nozzle_y := (15.5 if heavy else 12.5)
	# Flame first (behind the body).
	_flame(ci, c + Vector2(0, nozzle_y) * s, age + phase, s * (1.15 if heavy else 1.0))
	if tex:
		var size := Vector2(tex.get_width(), tex.get_height()) * 0.5 * s
		ci.draw_texture_rect(tex, Rect2(c - size * 0.5, size), false)
	elif heavy:
		_heavy_body(ci, c, s)
	else:
		_rocket_body(ci, c, s)


static func _flame(ci: CanvasItem, nozzle: Vector2, age: float, s: float) -> void:
	var f1 := 0.78 + 0.22 * sin(age * 71.0) * sin(age * 29.0 + 1.3)
	var f2 := 0.85 + 0.15 * sin(age * 97.0 + 0.7)
	var ln := (16.0 + 7.0 * f1) * s
	FxTex.draw_centered(ci, FxTex.glow(), nozzle + Vector2(0, 3) * s, Vector2(16, 18) * s * f2, FLAME_GLOW)
	FxTex.draw_oriented(ci, FxTex.flame(), nozzle + Vector2(0, ln * 0.4), Vector2.DOWN, Vector2(7.5 * s, ln), FLAME_OUTER)
	FxTex.draw_oriented(ci, FxTex.flame(), nozzle + Vector2(0, ln * 0.22), Vector2.DOWN, Vector2(3.6 * s, ln * 0.55), FLAME_INNER)
	FxTex.draw_centered(ci, FxTex.core(), nozzle + Vector2(0, 1) * s, Vector2(4.5, 4.5) * s, Color(1.0, 0.97, 0.85, 0.95))


## Procedural fallback for rocket.png (≈ 6 × 26 game px, nose up).
static func _rocket_body(ci: CanvasItem, c: Vector2, s: float) -> void:
	var metal := Color(0.80, 0.83, 0.88)
	var dark := Color(0.42, 0.45, 0.52)
	var nose := Color(0.95, 0.30, 0.22)
	# fins
	for sx in [-1.0, 1.0]:
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(sx * 2.5, 5) * s, c + Vector2(sx * 6.0, 11.5) * s,
			c + Vector2(sx * 6.0, 13.0) * s, c + Vector2(sx * 2.5, 11.0) * s]), dark)
	# body with a lit left side
	ci.draw_polygon(PackedVector2Array([c + Vector2(-3, -6) * s, c + Vector2(3, -6) * s, c + Vector2(3, 12) * s,
		c + Vector2(-3, 12) * s]), PackedColorArray([metal.lightened(0.25), metal.darkened(0.25), metal.darkened(0.35),
		metal.lightened(0.1)]))
	ci.draw_rect(Rect2(c + Vector2(-3, 4) * s, Vector2(6, 1.6) * s), nose.darkened(0.2))
	# nose cone
	ci.draw_polygon(PackedVector2Array([c + Vector2(0, -13) * s, c + Vector2(3, -6) * s, c + Vector2(-3, -6) * s]),
		PackedColorArray([nose.lightened(0.3), nose.darkened(0.25), nose]))
	ci.draw_rect(Rect2(c + Vector2(-2.2, 11.5) * s, Vector2(4.4, 1.6) * s), Color(0.25, 0.26, 0.3))


## Procedural fallback for rocket_heavy.png (thick warhead).
static func _heavy_body(ci: CanvasItem, c: Vector2, s: float) -> void:
	var metal := Color(0.74, 0.76, 0.82)
	var dark := Color(0.36, 0.36, 0.44)
	var war := Color(0.66, 0.40, 0.98)
	for sx in [-1.0, 1.0]:
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(sx * 3.0, 6) * s, c + Vector2(sx * 7.0, 13) * s,
			c + Vector2(sx * 7.0, 15.5) * s, c + Vector2(sx * 3.0, 13.5) * s]), dark)
	ci.draw_polygon(PackedVector2Array([c + Vector2(-3.2, -5) * s, c + Vector2(3.2, -5) * s, c + Vector2(3.2, 14.5) * s,
		c + Vector2(-3.2, 14.5) * s]), PackedColorArray([metal.lightened(0.2), metal.darkened(0.3), metal.darkened(0.4),
		metal.lightened(0.05)]))
	# bulbous warhead (wider than the body)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in 13:
		var a := PI + PI * float(i) / 12.0
		var p := Vector2(cos(a) * 4.8, sin(a) * 9.0 - 4.0)
		pts.append(c + p * s)
		cols.append(war.lightened(0.35) if p.x < 0.0 else war.darkened(0.15))
	pts.append(c + Vector2(4.8, -1.0) * s)
	cols.append(war.darkened(0.3))
	pts.append(c + Vector2(-4.8, -1.0) * s)
	cols.append(war)
	ci.draw_polygon(pts, cols)
	ci.draw_rect(Rect2(c + Vector2(-3.2, -1.0) * s, Vector2(6.4, 1.4) * s), Color(0.95, 0.85, 0.3))
	ci.draw_rect(Rect2(c + Vector2(-2.6, 14.0) * s, Vector2(5.2, 1.6) * s), Color(0.22, 0.22, 0.27))


static func _a(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * alpha)
