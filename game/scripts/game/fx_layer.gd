extends Node2D
## Procedural effects for the game screen (docs/SPEC.md §15). Drawn additively (Compatibility renderer:
## no HDR glow, so light is layered with an additive CanvasItemMaterial).
## - Explosions are rendered straight from GameWorld.explosions (age/duration live in the simulation, so
##   the level end waits for exactly what is shown). Every explosion is a pure function of (id, age):
##   no particle state, nothing allocated per frame.
## - Small impulses (split / colour stage / locked / rolling hits, muzzle flashes, materialize beams,
##   respawn) are spawned from world events and age in game time.
## - Power-ups (SPEC §19.3), in the power-up colour: a burst when one is triggered, a collapsing ring when it ends,
##   the TWIN's materialize beam / vanish burst, and a flash where the SHIELD absorbs a fireball.
## - Score popups are drawn by a normal-blend child node.

const FxTex := preload("res://scripts/game/fx_tex.gd")

const HOT := Color(1.0, 0.93, 0.75)
const FIRE := Color(1.0, 0.52, 0.16)
const EMBER := Color(0.75, 0.16, 0.05)
const SCAN := Color(0.45, 0.85, 1.0)

var world: GameWorld
var level := 1
var ship_accent := Color(0.4, 0.7, 1.0)

var _impulses: Array[Dictionary] = []
var _popups: Array[Dictionary] = []
var _text: Node2D
var _font: Font
var _debris_cols: Array[Color] = []


func _ready() -> void:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m
	_text = Node2D.new()
	_text.draw.connect(_draw_text)
	add_child(_text)
	_font = Assets.font_title
	for st in 3:
		var cols := LevelData.gradient_colors(level, st)
		var c: Color = cols[0].lerp(cols[cols.size() - 1], 0.35)
		if LevelData.is_black(level):
			c = Color(1.0, 0.45, 0.18)
		c = c.lerp(HOT, 0.25)
		_debris_cols.append(c)


## Advances impulses/popups by game seconds.
func advance(game_dt: float) -> void:
	var i := 0
	while i < _impulses.size():
		_impulses[i]["age"] += game_dt
		if _impulses[i]["age"] >= _impulses[i]["dur"]:
			_impulses.remove_at(i)
		else:
			i += 1
	i = 0
	while i < _popups.size():
		_popups[i]["age"] += game_dt
		if _popups[i]["age"] >= _popups[i]["dur"]:
			_popups.remove_at(i)
		else:
			i += 1
	queue_redraw()
	_text.queue_redraw()


## kind: "split", "stage", "locked", "rolling", "muzzle", "enemy_muzzle", "materialize", "respawn", "extra_life",
## power-ups: "powerup_on", "powerup_off", "twin_in", "twin_out", "shield_hit"
func impulse(kind: String, pos: Vector2, size: float = 1.0, color: Color = Color.WHITE) -> void:
	var dur: float = {"split": 0.42, "stage": 0.5, "locked": 0.28, "rolling": 0.34, "muzzle": 0.1,
		"enemy_muzzle": 0.14, "materialize": 0.55, "respawn": 0.6, "extra_life": 1.0, "powerup_on": 0.75,
		"powerup_off": 0.55, "twin_in": 0.5, "twin_out": 0.55, "shield_hit": 0.32}.get(kind, 0.3)
	_impulses.append({"kind": kind, "pos": pos, "scale": size, "color": color, "age": 0.0, "dur": dur,
		"seed": randf() * 100.0})


func popup(text: String, pos: Vector2, color: Color = Color(1.0, 0.92, 0.7), size: int = 14, dur: float = 0.9) -> void:
	_popups.append({"text": text, "pos": pos, "color": color, "size": size, "age": 0.0, "dur": dur})


func clear_impulses() -> void:
	_impulses.clear()


# --- Drawing -------------------------------------------------------------------------------------
func _draw() -> void:
	if world:
		for ex in world.explosions:
			_draw_explosion(ex)
	for im in _impulses:
		_draw_impulse(im)


static func _h(a: float, b: float) -> float:
	return fposmod(sin(a * 12.9898 + b * 78.233) * 43758.5453, 1.0)


func _draw_explosion(ex: GameWorld.Explosion) -> void:
	var player := ex.kind == "player"
	var age := ex.age
	var dur := ex.duration
	var k := age / dur
	var s := ex.scale * (1.65 if player else 1.0)
	if ex.is_child:
		s = maxf(s, 0.55)
	var c := Vector2(ex.x, ex.y)
	var id := float(ex.id)
	var hot := HOT if not player else Color(0.85, 0.95, 1.0)
	var debris: Color = ship_accent.lerp(Color.WHITE, 0.3) if player else _debris_cols[clampi(ex.stage, 0, 2)]

	# 1) Wide light bloom + bright core flash (first ≈ 0.2 s).
	var fa := clampf(1.0 - age / (0.32 if player else 0.24), 0.0, 1.0)
	if fa > 0.0:
		FxTex.draw_centered(self, FxTex.glow(), c, Vector2.ONE * (150.0 * s), _ca(FIRE, 0.42 * fa * fa))
		var r := (22.0 + 46.0 * _ease_out(clampf(age / 0.16, 0.0, 1.0))) * s
		FxTex.draw_centered(self, FxTex.glow(), c, Vector2.ONE * r * 2.0, _ca(hot, fa * fa))
		FxTex.draw_centered(self, FxTex.core(), c, Vector2.ONE * r * 0.7, _ca(Color.WHITE, fa * fa * fa))

	# 2) Expanding shock ring.
	var ring_t := age / (0.55 if player else 0.42)
	if ring_t < 1.0:
		var rr := (10.0 + (150.0 if player else 82.0) * _ease_out(ring_t)) * s / (1.65 if player else 1.0)
		var ring_col := Color(0.65, 0.85, 1.0) if player else Color(1.0, 0.82, 0.55)
		FxTex.draw_centered(self, FxTex.ring(), c, Vector2.ONE * rr * 2.0, _ca(ring_col, 0.75 * pow(1.0 - ring_t, 1.4)))
		if player:
			var r2 := rr * 0.7
			FxTex.draw_centered(self, FxTex.ring(), c + Vector2(0, 14), Vector2(r2 * 2.6, r2 * 0.55), _ca(ring_col, 0.35 * pow(1.0 - ring_t, 2.0)))

	# 3) Glowing fire clouds drifting outwards, over a central fireball that cools down.
	var core_a := pow(clampf(1.0 - k * 1.25, 0.0, 1.0), 1.6)
	if core_a > 0.0:
		var cr := (20.0 + 26.0 * _ease_out(k * 2.0)) * s
		FxTex.draw_centered(self, FxTex.glow(), c, Vector2.ONE * cr * 2.4, _ca(hot.lerp(FIRE, clampf(k * 3.0, 0.0, 1.0)), 0.95 * core_a))
	var n_clouds := 18 if player else 12
	for i in n_clouds:
		var fi := float(i)
		var delay := _h(id, fi * 3.1) * 0.1
		var life := (0.55 + 0.45 * _h(id, fi * 5.7)) * dur
		var a := (age - delay) / life
		if a <= 0.0 or a >= 1.0:
			continue
		var ang := TAU * _h(id, fi * 1.3)
		var dist := (8.0 + 30.0 * _h(id, fi * 2.9)) * s * (1.0 - pow(1.0 - a, 3.0))
		var p := c + Vector2(cos(ang), sin(ang) * 0.85) * dist + Vector2(0, -10.0 * a * s)
		var rad := (11.0 + 15.0 * _h(id, fi * 7.3)) * s * (0.65 + 0.85 * a)
		var col: Color
		if a < 0.22:
			col = hot.lerp(FIRE, a / 0.22)
		else:
			col = FIRE.lerp(EMBER, clampf((a - 0.22) / 0.6, 0.0, 1.0))
		FxTex.draw_centered(self, FxTex.glow(), p, Vector2.ONE * rad * 2.0, _ca(col, 0.95 * pow(1.0 - a, 1.05)))

	# 4) Sparks: fast streaks with drag and a little gravity.
	var n_sparks := 30 if player else 16
	for j in n_sparks:
		var fj := float(j) + 40.0
		var life2 := (0.3 + 0.55 * _h(id, fj * 1.7)) * dur
		if age >= life2:
			continue
		var ang2 := TAU * _h(id, fj * 2.3)
		var v0 := (170.0 + 330.0 * _h(id, fj * 3.7)) * s
		var drag := 4.2
		var e := exp(-drag * age)
		var dist2 := v0 * (1.0 - e) / drag
		var dirv := Vector2(cos(ang2), sin(ang2))
		var p2 := c + dirv * dist2 + Vector2(0, 55.0 * age * age)
		var vel := dirv * v0 * e + Vector2(0, 110.0 * age)
		var spd := vel.length()
		var ln := clampf(spd * 0.06, 3.0, 24.0 * s + 4.0)
		var fade := 1.0 - age / life2
		var scol := Color(1.0, 0.95, 0.8).lerp(FIRE, clampf(age / life2 * 1.3, 0.0, 1.0))
		if spd > 1.0:
			FxTex.draw_oriented(self, FxTex.streak(), p2 - vel / spd * ln * 0.5, (vel / spd).orthogonal(), Vector2(ln * 2.0, 3.2),
				_ca(scol, fade))

	# 5) Debris chunks in the enemy colour (glowing hot), tumbling.
	var n_deb := 12 if player else 7
	for d in n_deb:
		var fd := float(d) + 90.0
		var life3 := (0.55 + 0.4 * _h(id, fd * 1.1)) * dur
		if age >= life3:
			continue
		var ang3 := TAU * _h(id, fd * 4.1)
		var v3 := (70.0 + 120.0 * _h(id, fd * 2.2)) * s
		var e3 := exp(-2.4 * age)
		var p3 := c + Vector2(cos(ang3), sin(ang3)) * v3 * (1.0 - e3) / 2.4 + Vector2(0, 40.0 * age * age)
		var rot := age * (6.0 + 10.0 * _h(id, fd * 6.6)) + fd
		var sz := Vector2(2.6, 5.5) * (0.7 + 0.6 * _h(id, fd * 8.8)) * maxf(s, 0.6)
		var dcol := debris.lerp(EMBER, clampf(age / life3, 0.0, 1.0))
		FxTex.draw_oriented(self, FxTex.core(), p3, Vector2(cos(rot), sin(rot)), sz, _ca(dcol, 1.0 - age / life3))

	# 6) Lingering ember glow.
	FxTex.draw_centered(self, FxTex.glow(), c, Vector2.ONE * 70.0 * s, _ca(EMBER, 0.35 * pow(1.0 - k, 2.0)))


func _draw_impulse(im: Dictionary) -> void:
	var kind: String = im["kind"]
	var t: float = im["age"] / im["dur"]
	var p: Vector2 = im["pos"]
	var s: float = im["scale"]
	var col: Color = im["color"]
	var sd: float = im["seed"]
	match kind:
		"split", "rolling":
			var base := Color(1.0, 0.85, 0.5) if kind == "split" else Color(1.0, 0.5, 0.12)
			var fa := pow(1.0 - t, 2.0)
			FxTex.draw_centered(self, FxTex.glow(), p, Vector2.ONE * (34.0 + 30.0 * t) * s * 2.0, _ca(base, 0.75 * fa))
			FxTex.draw_centered(self, FxTex.core(), p, Vector2.ONE * 22.0 * s * (1.0 - t), _ca(Color.WHITE, fa))
			FxTex.draw_centered(self, FxTex.ring(), p, Vector2.ONE * (12.0 + 64.0 * _ease_out(t)) * s * 2.0, _ca(base, 0.65 * (1.0 - t)))
			_sparks(p, sd, t, im["dur"], 9, 260.0 * s, base)
		"stage":
			var fa2 := 1.0 - t
			FxTex.draw_centered(self, FxTex.glow(), p, Vector2.ONE * 90.0 * s, _ca(col, 0.6 * fa2 * fa2))
			FxTex.draw_centered(self, FxTex.ring(), p, Vector2.ONE * (16.0 + 58.0 * _ease_out(t)) * 2.0 * s, _ca(col, 0.85 * fa2))
			for i in 8:
				var ang := TAU * float(i) / 8.0 + sd + t * 1.5
				var q := p + Vector2(cos(ang), sin(ang) * 0.6) * (20.0 + 34.0 * _ease_out(t)) * s
				FxTex.draw_centered(self, FxTex.core(), q, Vector2.ONE * 5.0 * s * fa2, _ca(col.lerp(Color.WHITE, 0.5), fa2))
		"locked":
			var fa3 := pow(1.0 - t, 1.5)
			var cyan := Color(0.55, 0.85, 1.0)
			FxTex.draw_centered(self, FxTex.core(), p, Vector2.ONE * 16.0 * s * fa3, _ca(Color.WHITE, fa3))
			FxTex.draw_centered(self, FxTex.glow(), p, Vector2.ONE * 46.0 * s, _ca(cyan, 0.6 * fa3))
			# hexagonal "shield" outline flashing around the hit point
			var r := (16.0 + 14.0 * _ease_out(t)) * s
			var pts := PackedVector2Array()
			for i in 7:
				var a := TAU * float(i) / 6.0 + PI / 6.0
				pts.append(p + Vector2(cos(a), sin(a)) * r)
			draw_polyline(pts, _ca(cyan, 0.9 * fa3), 2.0, true)
			_sparks(p, sd, t, im["dur"], 4, 160.0 * s, cyan)
		"muzzle":
			var fa4 := 1.0 - t
			FxTex.draw_centered(self, FxTex.glow(), p, Vector2(26, 30) * s * (0.6 + 0.4 * fa4), _ca(col, 0.9 * fa4))
			FxTex.draw_centered(self, FxTex.core(), p, Vector2(8, 10) * s * fa4, _ca(Color.WHITE, fa4))
		"enemy_muzzle":
			var fa5 := 1.0 - t
			FxTex.draw_centered(self, FxTex.glow(), p, Vector2.ONE * 26.0 * s, _ca(Color(1.0, 0.45, 0.12), 0.7 * fa5))
		"materialize":
			var fa6 := sin(t * PI)
			var w := (8.0 + 70.0 * _ease_out(t)) * s
			FxTex.draw_quad(self, FxTex.glow(), p, Vector2(w * 0.5, 0), Vector2(0, 95.0 * s), _ca(SCAN, 0.35 * fa6))
			FxTex.draw_centered(self, FxTex.ring(), p, Vector2(150.0, 80.0) * s * (1.0 - 0.7 * t), _ca(SCAN, 0.5 * fa6))
			for i in 10:
				var ang := TAU * _h(sd, float(i))
				var dist := (70.0 + 30.0 * _h(sd, float(i) + 9.0)) * (1.0 - _ease_out(t)) * s
				var q := p + Vector2(cos(ang), sin(ang) * 0.55) * dist
				FxTex.draw_centered(self, FxTex.core(), q, Vector2.ONE * 4.0 * s, _ca(SCAN.lerp(Color.WHITE, 0.4), fa6))
		"respawn":
			var fa7 := 1.0 - t
			FxTex.draw_quad(self, FxTex.glow(), p + Vector2(0, -40), Vector2(26.0 * fa7 + 6.0, 0), Vector2(0, 110.0), _ca(col, 0.45 * fa7))
			FxTex.draw_centered(self, FxTex.ring(), p, Vector2(120.0, 60.0) * (0.3 + 0.9 * _ease_out(t)), _ca(col, 0.8 * fa7))
			FxTex.draw_centered(self, FxTex.glow(), p, Vector2(90, 70), _ca(col, 0.5 * fa7 * fa7))
		"extra_life":
			var fa8 := sin(t * PI)
			FxTex.draw_centered(self, FxTex.ring(), p, Vector2.ONE * (30.0 + 120.0 * _ease_out(t)) * 2.0, _ca(Color(0.5, 1.0, 0.6), 0.7 * (1.0 - t)))
			FxTex.draw_centered(self, FxTex.glow(), p, Vector2(140, 100), _ca(Color(0.45, 1.0, 0.55), 0.4 * fa8))
		"powerup_on":
			# Burst around the ship: flash, two flat shock rings racing outwards, a light pillar, sparks.
			var fa9 := 1.0 - t
			var hi := col.lerp(Color.WHITE, 0.5)
			FxTex.draw_centered(self, FxTex.glow(), p, Vector2(170, 120) * (0.7 + 0.3 * t), _ca(col, 0.6 * fa9 * fa9))
			FxTex.draw_centered(self, FxTex.core(), p, Vector2(40, 30) * fa9, _ca(Color.WHITE, fa9 * fa9))
			for k in 2:
				var tk := clampf((t - 0.12 * k) / (1.0 - 0.12 * k), 0.0, 1.0)
				if tk > 0.0:
					var rr := (24.0 + 170.0 * _ease_out(tk)) * (1.0 - 0.3 * k)
					FxTex.draw_centered(self, FxTex.ring(), p, Vector2(rr * 2.0, rr * 0.9), _ca(hi if k == 0 else col, 0.85 * pow(1.0 - tk, 1.3)))
			FxTex.draw_quad(self, FxTex.glow(), p + Vector2(0, -70), Vector2(22.0 * fa9 + 6.0, 0), Vector2(0, 130.0), _ca(col, 0.45 * fa9))
			_sparks(p, sd, t, im["dur"], 14, 340.0, col)
		"powerup_off":
			# The effect fades: a ring collapsing onto the ship, a last soft glow, a few falling embers.
			var fa10 := 1.0 - t
			FxTex.draw_centered(self, FxTex.ring(), p, Vector2(150.0, 100.0) * (1.0 - 0.75 * _ease_out(t)), _ca(col, 0.7 * fa10))
			FxTex.draw_centered(self, FxTex.glow(), p, Vector2(110, 80), _ca(col, 0.35 * fa10 * fa10))
			for i in 8:
				var ang := -PI * (0.15 + 0.7 * _h(sd, float(i)))
				var q := p + Vector2(cos(ang), sin(ang)) * (36.0 + 10.0 * _h(sd, float(i) + 4.0)) + Vector2(0, 46.0 * t * t)
				FxTex.draw_centered(self, FxTex.core(), q, Vector2.ONE * 4.0 * fa10, _ca(col.lerp(Color.WHITE, 0.4), fa10))
		"twin_in":
			# The twin materializes: a scan beam narrowing onto it, a ring closing in, particles converging.
			var fa11 := sin(t * PI)
			var w2 := (70.0 - 50.0 * _ease_out(t))
			FxTex.draw_quad(self, FxTex.glow(), p + Vector2(0, -50), Vector2(w2 * 0.5, 0), Vector2(0, 120.0), _ca(col, 0.5 * fa11))
			FxTex.draw_centered(self, FxTex.ring(), p, Vector2(170.0, 96.0) * (1.0 - 0.6 * _ease_out(t)), _ca(col, 0.65 * fa11))
			for i in 12:
				var ang := TAU * _h(sd, float(i))
				var dist := (80.0 + 30.0 * _h(sd, float(i) + 9.0)) * (1.0 - _ease_out(t))
				var q := p + Vector2(cos(ang), sin(ang) * 0.5) * dist
				FxTex.draw_centered(self, FxTex.core(), q, Vector2.ONE * 4.5, _ca(col.lerp(Color.WHITE, 0.45), fa11))
		"twin_out":
			# The twin dissolves: a flash, a ring bursting outwards, its particles flying apart and the beam fading.
			var fa12 := 1.0 - t
			FxTex.draw_centered(self, FxTex.glow(), p, Vector2(130, 96), _ca(col, 0.6 * fa12 * fa12))
			FxTex.draw_centered(self, FxTex.ring(), p, Vector2(1.0, 0.6) * (30.0 + 130.0 * _ease_out(t)) * 2.0, _ca(col, 0.7 * fa12))
			FxTex.draw_quad(self, FxTex.glow(), p + Vector2(0, -50), Vector2(16.0 * fa12 + 4.0, 0), Vector2(0, 120.0), _ca(col, 0.35 * fa12))
			for i in 12:
				var ang := TAU * _h(sd, float(i))
				var q := p + Vector2(cos(ang), sin(ang) * 0.5) * (10.0 + 90.0 * _ease_out(t)) * (0.6 + 0.4 * _h(sd, float(i) + 3.0))
				FxTex.draw_centered(self, FxTex.core(), q, Vector2.ONE * 4.5 * fa12, _ca(col.lerp(Color.WHITE, 0.45), fa12))
		"shield_hit":
			# A fireball dies on the shield: white-hot flash, a hexagonal ripple in the shield colour, deflected sparks.
			var fa13 := pow(1.0 - t, 1.5)
			FxTex.draw_centered(self, FxTex.core(), p, Vector2.ONE * 20.0 * fa13, _ca(Color.WHITE, fa13))
			FxTex.draw_centered(self, FxTex.glow(), p, Vector2.ONE * 64.0, _ca(col, 0.75 * fa13))
			FxTex.draw_centered(self, FxTex.glow(), p, Vector2.ONE * 30.0, _ca(Color(1.0, 0.55, 0.2), 0.6 * fa13))
			var r2 := 10.0 + 18.0 * _ease_out(t)
			var hex := PackedVector2Array()
			for i in 7:
				var a := TAU * float(i) / 6.0
				hex.append(p + Vector2(cos(a), sin(a) * 0.8) * r2)
			draw_polyline(hex, _ca(col.lerp(Color.WHITE, 0.3), 0.9 * fa13), 1.6, true)
			_sparks(p, sd, t, im["dur"], 5, 200.0, col)


func _sparks(p: Vector2, sd: float, t: float, dur: float, n: int, speed: float, col: Color) -> void:
	var age := t * dur
	for i in n:
		var ang := TAU * _h(sd, float(i) * 1.7)
		var v0 := speed * (0.5 + 0.5 * _h(sd, float(i) * 3.3))
		var e := exp(-5.0 * age)
		var dirv := Vector2(cos(ang), sin(ang))
		var q := p + dirv * v0 * (1.0 - e) / 5.0
		var ln := clampf(v0 * e * 0.05, 2.0, 14.0)
		FxTex.draw_oriented(self, FxTex.streak(), q - dirv * ln * 0.5, dirv.orthogonal(), Vector2(ln * 2.0, 2.6), _ca(col.lerp(Color.WHITE, 0.4), 1.0 - t))


func _draw_text() -> void:
	for p in _popups:
		var t: float = p["age"] / p["dur"]
		var a := clampf(1.0 - pow(t, 3.0), 0.0, 1.0) * clampf(t * 12.0, 0.0, 1.0)
		var pos: Vector2 = p["pos"] + Vector2(0, -28.0 * _ease_out(t))
		var size: int = p["size"]
		var txt: String = p["text"]
		var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var col: Color = p["color"]
		_text.draw_string_outline(_font, pos - Vector2(w * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4,
			Color(0.0, 0.0, 0.0, 0.6 * a))
		_text.draw_string(_font, pos - Vector2(w * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, _ca(col, a))


static func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)


static func _ca(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * clampf(a, 0.0, 1.0))
