extends Node2D
## Draws the world's projectiles via ProjectileArt.
## Mode SHOTS: own salvos. Mode BULLETS: enemy fireballs + ground splashes – this node lives inside a
## clipping Control (0,0)-(W,685) (W = playfield width, 960, 1280 or 1152), so nothing of a fireball is ever drawn below
## the ground.
## TWIN power-up (SPEC §19.3): the twin's shots look like the ship's own but are drawn on a child layer tinted in the
## twin colour, so the player can tell them apart.

const FxTex := preload("res://scripts/game/fx_tex.gd")

enum Mode { SHOTS, BULLETS }

var mode: Mode = Mode.SHOTS
var world: GameWorld
var twin_color := Color(0.74, 0.58, 1.0)
var _splashes: Array[Dictionary] = []
var _twin_layer: Node2D          ## SHOTS on a TWIN level only


func _ready() -> void:
	if mode == Mode.SHOTS and world != null and world.powerup == LevelData.PowerUp.TWIN:
		_twin_layer = Node2D.new()
		var c := Color(1, 1, 1).lerp(twin_color, 0.55)
		_twin_layer.modulate = Color(c.r, c.g, c.b, 0.9)
		_twin_layer.draw.connect(_draw_twin_shots)
		add_child(_twin_layer)
	set_process(_twin_layer != null)


func _process(_delta: float) -> void:
	if _twin_layer != null:
		_twin_layer.queue_redraw()


## Bullet reached the ground surface: small splash of light on the horizon (clipped like the bullets).
func splash(x: float) -> void:
	_splashes.append({"x": x, "age": 0.0, "seed": randf() * 10.0})


func advance(game_dt: float) -> void:
	var i := 0
	while i < _splashes.size():
		_splashes[i]["age"] += game_dt
		if _splashes[i]["age"] > 0.32:
			_splashes.remove_at(i)
		else:
			i += 1
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	if mode == Mode.SHOTS:
		for s in world.shots:
			if not s.twin:
				ProjectileArt.draw_player_shot(self, world.ship_id, Vector2(s.x, s.y), s.age)
		return
	var gy := LevelData.GROUND_Y
	for sp in _splashes:
		var t: float = sp["age"] / 0.32
		var x: float = sp["x"]
		var a := pow(1.0 - t, 1.5)
		FxTex.draw_centered(self, FxTex.glow(), Vector2(x, gy), Vector2(46.0 + 30.0 * t, 22.0), Color(1.0, 0.45, 0.12, 0.6 * a))
		FxTex.draw_centered(self, FxTex.core(), Vector2(x, gy), Vector2(14.0 * (1.0 - t) + 4.0, 6.0), Color(1.0, 0.9, 0.6, a))
		for k in 3:
			var ang := -PI * (0.2 + 0.6 * fposmod(sin(sp["seed"] + k * 2.1) * 43.7, 1.0))
			var q := Vector2(x, gy) + Vector2(cos(ang), sin(ang)) * 22.0 * t
			FxTex.draw_centered(self, FxTex.core(), q, Vector2(3, 3), Color(1.0, 0.7, 0.3, a))
	for b in world.bullets:
		ProjectileArt.draw_enemy_bullet(self, Vector2(b.x, b.y), Vector2(b.vx, b.vy), b.age, 1.0, fireball_alpha(b))


func _draw_twin_shots() -> void:
	for s in world.shots:
		if s.twin:
			ProjectileArt.draw_player_shot(_twin_layer, world.ship_id, Vector2(s.x, s.y), s.age)


## Drawn alpha of an enemy fireball of `world`: it fades while it sinks into the ground (it is removed once
## entirely below y = 685) and while it leaves sideways. The side fade uses the width of the world being drawn
## (world.width), never the global display mode, so a 960 world stays classic even in a 16:9 session.
func fireball_alpha(b: GameWorld.Bullet) -> float:
	var alpha := clampf((LevelData.GROUND_Y + GameWorld.BULLET_HALF - b.y) / (2.0 * GameWorld.BULLET_HALF), 0.0, 1.0)
	alpha *= side_fade(b.x, b.vx, world.width)
	return alpha


## Alpha of a fireball leaving the screen sideways. It is removed once its body is entirely off-screen
## (head x < -5 / > W + 5) while its tail is still visible, so it fades out before – but only in the band
## where it can no longer hit any player position (x ≤ 30 − 21 = 9 / x ≥ (W − 30) + 21 = W − 9).
## `w` = playfield width W of the world the bullet belongs to; the default is the classic 960 (like the
## LevelData limit helpers), so the result never depends on the global display mode.
static func side_fade(x: float, vx: float, w: float = LevelData.SCREEN_W) -> float:
	var h := GameWorld.BULLET_HALF
	if vx < 0.0:
		var safe_l := LevelData.PLAYER_MIN_X - LevelData.PLAYER_HIT_DX
		return clampf((x + h) / (safe_l + h), 0.0, 1.0)
	if vx > 0.0:
		var safe_r := LevelData.player_max_x(w) + LevelData.PLAYER_HIT_DX
		return clampf((w + h - x) / (w + h - safe_r), 0.0, 1.0)
	return 1.0
