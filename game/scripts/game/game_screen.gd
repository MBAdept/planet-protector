extends Node2D
## Gameplay screen (docs/SPEC.md §1, §3–§10, §15, §17.1).
## Owns the pure GameWorld simulation, feeds it with input (or the autoplay bot), renders it, turns its
## events into audio + effects, syncs score/lives/play time into Run and reports the result.
## Protocol: setup({"level": n}) before entering the tree; emits finished("completed"|"game_over"|"quit", {}).

signal finished(result: String, data: Dictionary)

const Backdrop := preload("res://scripts/game/backdrop.gd")
const PlayerView := preload("res://scripts/game/player_view.gd")
const ProjectilesView := preload("res://scripts/game/projectiles_view.gd")
const FxLayer := preload("res://scripts/game/fx_layer.gd")
const Hud := preload("res://scripts/game/hud.gd")
const Autopilot := preload("res://scripts/game/autopilot.gd")

## Real seconds. Frames up to this length are simulated and counted IN FULL (the world sub-steps them), so
## hitches and slow machines keep real-time speed and exact real play time (SPEC §1, §9). Only a longer
## stall (system suspend, debugger break, blocked window system) is an interruption, not play: just this
## much of it is simulated and counted.
const MAX_FRAME_DT := 0.5
## Real seconds. The autoplay bot re-decides at least this often inside a long frame (dev only).
const AUTOPLAY_SLICE := 1.0 / 60.0
const OUTRO_DELAY := 0.7           ## real seconds after COMPLETE before the screen changes
const GAME_OVER_DELAY := 0.6

var level := 1
var world: GameWorld
var paused := false

var _base_score := 0
var _base_time := 0.0
var _done := false
var _end_wait := 0.0
var _clear_time := -1.0
var _respawn_time := -1.0
var _since_respawn := 10.0
var _shake := 0.0
var _shake_t := 0.0
var _last_axis := 0.0
var _anim := 0.0
var _sfx_this_frame := {}
var _enemy_nodes := {}             # enemy id → EnemyArt

var _stars: Starfield
var _root: Node2D
var _enemy_layer: Node2D
var _fx: Node2D
var _shots: Node2D
var _player: Node2D
var _bullets: Node2D
var _hud: Node2D


func setup(args: Dictionary) -> void:
	level = clampi(int(args.get("level", Run.level)), LevelData.FIRST_LEVEL, LevelData.LAST_LEVEL)


func _ready() -> void:
	world = GameWorld.new(level, Run.difficulty, Run.ship_id, Run.lives, randi())
	world.invincible = Run.dev("invincible")
	_base_score = Run.score
	_base_time = Run.active_time
	Run.level = level
	_build()
	# Title music (ship select) stops for gameplay (SPEC §14) – the intro banner is silent; the game music
	# starts with the combat.
	AudioManager.stop_music()
	AudioManager.reset_bass(level)


func _build() -> void:
	var sky := Backdrop.new()
	sky.setup(Backdrop.Mode.SKY, level)
	add_child(sky)
	_stars = Starfield.new()
	_stars.velocity = Vector2(0, 6)
	add_child(_stars)
	var planet := Backdrop.new()
	planet.setup(Backdrop.Mode.PLANET, level)
	add_child(planet)
	var vignette := Backdrop.new()
	vignette.setup(Backdrop.Mode.VIGNETTE, level)
	add_child(vignette)

	_root = Node2D.new()
	add_child(_root)
	var ground := Backdrop.new()
	ground.setup(Backdrop.Mode.GROUND, level)
	_root.add_child(ground)
	_enemy_layer = Node2D.new()
	_root.add_child(_enemy_layer)
	_fx = FxLayer.new()
	_fx.world = world
	_fx.level = level
	_fx.ship_accent = ShipData.ship(Run.ship_id)["accent"]
	_root.add_child(_fx)
	_shots = ProjectilesView.new()
	_shots.mode = ProjectilesView.Mode.SHOTS
	_shots.world = world
	_root.add_child(_shots)
	_player = PlayerView.new()
	_player.ship_id = world.ship_id
	_player.position = Vector2(world.player_x, LevelData.PLAYER_Y)
	_root.add_child(_player)
	# Enemy fireballs: clipped at the ground line – nothing (not even glow or tail) below y = 685.
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.position = Vector2.ZERO
	clip.size = Vector2(LevelData.SCREEN_W, LevelData.GROUND_Y)
	_root.add_child(clip)
	_bullets = ProjectilesView.new()
	_bullets.mode = ProjectilesView.Mode.BULLETS
	_bullets.world = world
	clip.add_child(_bullets)

	_hud = Hud.new()
	_hud.world = world
	_hud.level = level
	add_child(_hud)


# --- Frame ---------------------------------------------------------------------------------------
func _process(delta: float) -> void:
	_sfx_this_frame.clear()
	if _done:
		return
	if paused:
		if InputRouter.pause_pressed():
			_set_paused(false)
		elif InputRouter.quit_pressed():
			_finish("quit")
		_hud.queue_redraw()
		return
	if not world.is_finished() and InputRouter.pause_pressed():
		_set_paused(true)
		return

	var dt := minf(delta, MAX_FRAME_DT)
	var prev_x := world.player_x
	if Run.dev("autoplay"):
		var left := dt
		while left > 1e-9:
			var slice := minf(left, AUTOPLAY_SLICE)
			var d: Vector2 = Autopilot.decide(world)
			world.update(slice, d.x, d.y > 0.5)
			left -= slice
	else:
		world.update(dt, InputRouter.move_axis(), InputRouter.fire_held())
	var game_dt := dt * world.speed_factor if world.state != GameWorld.State.INTRO else 0.0
	_last_axis = clampf((world.player_x - prev_x) / maxf(LevelData.PLAYER_SPEED * game_dt, 1e-6), -1.0, 1.0) if game_dt > 0.0 else 0.0
	_anim += dt
	_handle_events()
	_sync_run()
	_update_views(dt, game_dt)
	_check_end(dt)


func _set_paused(p: bool) -> void:
	paused = p
	_hud.paused = p
	_stars.velocity = Vector2.ZERO if p else Vector2(0, 6)
	if p:
		AudioManager.set_game_music_suspended(true)
	elif world.state == GameWorld.State.PLAYING:
		AudioManager.set_game_music_suspended(false)
	_hud.queue_redraw()


func _sync_run() -> void:
	Run.score = _base_score + world.score_delta
	Run.lives = world.lives
	Run.active_time = _base_time + world.active_time


func _check_end(dt: float) -> void:
	if world.state == GameWorld.State.COMPLETE:
		_end_wait += dt
		if _end_wait >= OUTRO_DELAY:
			_finish("completed")
	elif world.state == GameWorld.State.GAME_OVER:
		_end_wait += dt
		if _end_wait >= GAME_OVER_DELAY:
			_finish("game_over")


func _finish(result: String) -> void:
	if _done:
		return
	_done = true
	_sync_run()
	if result == "completed":
		Run.last_level_result = world.result.duplicate()
		if world.is_bonus():
			Run.last_bonus_result = world.bonus_result.duplicate()
	AudioManager.stop_music()
	finished.emit(result, {})


# --- Events → audio + FX -------------------------------------------------------------------------
func _sfx(sfx_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if _sfx_this_frame.has(sfx_name):
		return
	_sfx_this_frame[sfx_name] = true
	AudioManager.play_sfx(sfx_name, volume_db, pitch)


func _handle_events() -> void:
	for ev in world.events:
		match String(ev["type"]):
			"combat_start":
				AudioManager.play_game_music()
			"shot_fired":
				_sfx(String(ShipData.ship(int(ev["ship_id"]))["sfx"]))
				var col := _muzzle_color()
				for off in ShipData.shot_offsets(world.ship_id):
					_fx.impulse("muzzle", Vector2(world.player_x + off, LevelData.SALVO_Y), 1.0, col)
			"enemy_fire":
				_sfx("enemy_fire", -2.0, randf_range(0.95, 1.05))
				_fx.impulse("enemy_muzzle", Vector2(ev["x"], ev["y"]), 1.0)
			"enemy_spawned":
				_sfx("materialize", -4.0)
				_fx.impulse("materialize", Vector2(ev["x"], ev["y"]), float(ev["scale"]))
			"enemy_split":
				_sfx("enemy_hit")
				_fx.impulse("split", Vector2(ev["x"], ev["y"]), 1.0)
				_kick(1.5, 0.12)
			"enemy_hit_nonlethal":
				_sfx("enemy_hit")
				if ev["kind"] == "rolling":
					_fx.impulse("rolling", Vector2(ev["x"], ev["y"]), float(ev.get("scale", 1.0)))
				else:
					var cols := LevelData.gradient_colors(level, int(ev.get("stage", 1)))
					_fx.impulse("stage", Vector2(ev["x"], ev["y"]), float(ev.get("scale", 1.0)), cols[0])
			"locked_hit":
				_sfx("locked_hit")
				_fx.impulse("locked", Vector2(ev["x"], ev["y"]), float(ev.get("scale", 1.0)))
			"enemy_destroyed":
				_sfx("enemy_explode", 0.0, randf_range(0.93, 1.07))
				# Client decision: the bass rises once per ORIGINAL enemy, i.e. for split enemies only when
				# the last child of the pair is gone.
				if bool(ev.get("group_cleared", true)):
					AudioManager.notify_enemy_destroyed()
				var pts := int(ev["points"])
				if pts > 0:
					_fx.popup("+%d" % pts, Vector2(ev["x"], float(ev["y"]) - 22.0))
				_kick(2.5 if not bool(ev.get("is_child", false)) else 1.5, 0.18)
			"player_hit":
				_sfx("player_explode")
				AudioManager.set_game_music_suspended(true)
				_respawn_time = 0.0
				_kick(9.0, 0.55)
			"player_respawn":
				_respawn_time = -1.0
				_since_respawn = 0.0
				if not paused and world.state == GameWorld.State.PLAYING:
					AudioManager.set_game_music_suspended(false)
				_fx.impulse("respawn", Vector2(ev["x"], LevelData.PLAYER_Y), 1.0, ShipData.ship(world.ship_id)["accent"])
			"bullet_landed":
				_bullets.splash(float(ev["x"]))
			"extra_life":
				_sfx("extra_life")
				var p := Vector2(world.player_x, LevelData.PLAYER_Y - 40.0)
				_fx.impulse("extra_life", Vector2(480, 330), 1.0)
				_fx.popup("+1 LIFE", p, Color(0.55, 1.0, 0.6), 20, 1.6)
			"clearing":
				_clear_time = 0.0
				_sfx("level_complete")
				AudioManager.stop_music()
			"level_goal_met", "level_complete", "game_over":
				pass
	world.events.clear()


func _muzzle_color() -> Color:
	match int(world.ship()["look"]):
		ShipData.Look.LASER_BLUE:
			return Color(0.35, 0.7, 1.0)
		ShipData.Look.LASER_RED_THICK:
			return Color(1.0, 0.3, 0.2)
	return Color(1.0, 0.6, 0.25)


func _kick(amount: float, dur: float) -> void:
	if amount >= _shake:
		_shake = amount
		_shake_t = dur


# --- Views ---------------------------------------------------------------------------------------
func _update_views(dt: float, game_dt: float) -> void:
	# Screen shake (world layers only, never the HUD).
	if _shake_t > 0.0:
		_shake_t = maxf(_shake_t - dt, 0.0)
		var k := _shake * (_shake_t / 0.55)
		_root.position = Vector2(randf_range(-k, k), randf_range(-k, k) * 0.6)
		if _shake_t <= 0.0:
			_shake = 0.0
			_root.position = Vector2.ZERO
	_sync_enemies()
	_player.visible = world.player_alive
	if world.player_alive:
		_player.position = Vector2(world.player_x, LevelData.PLAYER_Y)
		_player.anim = _anim
		_player.bank = lerpf(_player.bank, _last_axis, clampf(dt * 12.0, 0.0, 1.0))
		_player.alpha = clampf(_since_respawn / 0.35, 0.0, 1.0)
		_player.refresh()
	_since_respawn += dt
	_fx.advance(game_dt)
	_shots.queue_redraw()
	_bullets.advance(game_dt)
	if _clear_time >= 0.0:
		_clear_time += dt
	if _respawn_time >= 0.0:
		_respawn_time += game_dt
	_hud.anim = _anim
	_hud.clear_time = _clear_time
	_hud.respawn_time = _respawn_time
	_hud.queue_redraw()


func _sync_enemies() -> void:
	var seen := {}
	for e in world.enemies:
		seen[e.id] = true
		var art: EnemyArt = _enemy_nodes.get(e.id)
		if art == null:
			art = EnemyArt.new()
			art.configure(level, e.stage)
			art.set_meta("stage", e.stage)
			_enemy_layer.add_child(art)
			_enemy_nodes[e.id] = art
		if int(art.get_meta("stage")) != e.stage:
			art.colors = LevelData.gradient_colors(level, e.stage)
			art.set_meta("stage", e.stage)
		art.position = Vector2(e.x, e.y)
		art.scale_factor = e.scale
		art.flap_phase = world.flap_phase(e)
		art.flash = clampf(e.flash / LevelData.HIT_FLASH_TIME, 0.0, 1.0)
		art.materialize = e.materialize()
	for id in _enemy_nodes.keys():
		if not seen.has(id):
			(_enemy_nodes[id] as Node).queue_free()
			_enemy_nodes.erase(id)
