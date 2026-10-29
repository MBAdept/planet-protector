class_name GameWorld
extends RefCounted
## PURE, deterministic simulation of one level (docs/SPEC.md §1, §3–§10, §17.2).
## No nodes, no autoloads – only the static data classes LevelData / ShipData.
## Time base: update() receives REAL seconds; the world converts them into game time
## (game_dt = real_dt * speed_factor) and advances in fixed sub-steps of LevelData.SIM_STEP.
## Everything is driven by one seeded RandomNumberGenerator, so a run is reproducible.
## Playfield width (SPEC §18.1): `width` is 960 (classic 4:3), 1280 (16:9) or 1152 (16:10, Steam Deck) and fixed
## for the world's life. Only the horizontal limits follow it (player clamp / start, enemy turning and spawn
## limits, sideways bullet removal); every speed, distance, hit box, timing and lane y stays the same. With width
## 960 the world is bit-for-bit the classic one.

enum State { INTRO, PLAYING, RESPAWN, CLEARING, COMPLETE, GAME_OVER_WAIT, GAME_OVER }

const EPS := 1e-6
const BULLET_HALF := LevelData.ENEMY_BULLET_W * 0.5
## Rolling window (10 game-s) expressed in sub-steps, so "now − t ≤ 10.0" is evaluated exactly.
const ROLLING_WINDOW_STEPS := 2400


# --- Entities ------------------------------------------------------------------------------------
class Enemy:
	var id := 0
	var slot := -1               ## original slot index (children keep the parent's slot), -1 = none
	var lane := 0
	var x := 0.0
	var y := 0.0
	var dir := 1.0               ## +1 right, -1 left
	var scale := 1.0             ## 1.0 original, 0.40 / 0.45 child
	var is_child := false
	var parent_id := -1
	var group_id := 0            ## id of the original; children share it (shared flap phase)
	var osc_phase := 0.0         ## vertical oscillation phase (children inherit it)
	var flap_offset := 0.0       ## 0..1 wing-flap offset (children inherit it)
	var age := 0.0               ## game seconds since spawn (materialize)
	var stage: int = LevelData.Stage.VIOLET
	var hit_steps: Array[int] = []   ## rolling-window hit times (game sub-step indices = step_count)
	var flash := 0.0             ## remaining orange hit-flash time (game s)
	var armed := true            ## may fire at all (child rules / lane permissions)
	var fire_timer := INF        ## per-figure timer (levels ≥ 11)
	var dir_timer := INF         ## random direction change timer (levels ≥ 10)
	var turn_age := 0.0          ## game seconds since its last direction change (spawn / split counts as one)
	var cover_time := 0.0        ## game seconds it has been covered by a lower figure in a row (levels ≥ 10)

	func materialize() -> float:
		return clampf(age / LevelData.MATERIALIZE_TIME, 0.0, 1.0)


class Shot:
	var id := 0
	var x := 0.0
	var y := 0.0
	var offset := 0.0            ## lateral offset relative to the ship (guided shots keep it)
	var speed := 0.0
	var guided := false
	var piercing := false
	var age := 0.0
	var hit_ids := {}            ## enemy ids this projectile already touched


class Bullet:
	var id := 0
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var age := 0.0
	var owner_id := -1
	var landed := false          ## head reached the ground surface (FX only)


class Explosion:
	var id := 0
	var kind := "enemy"          ## "enemy" | "player"
	var x := 0.0
	var y := 0.0
	var scale := 1.0
	var age := 0.0
	var duration := LevelData.ENEMY_EXPLOSION_TIME
	var stage := 0               ## colour stage of the destroyed enemy (levels 14–16)
	var is_child := false


class Slot:
	var lane := 0
	var alive := 0               ## alive figures belonging to this slot (original or its children)
	var refill := -1.0           ## game seconds until refill, < 0 = not pending


# --- Configuration -------------------------------------------------------------------------------
var level := 1
var difficulty := 1
var ship_id := 0
var speed_factor := 1.0
## Playfield width in px (SPEC §18.1): LevelData.SCREEN_W (960), 1280 (16:9) or 1152 (16:10). Never narrower than 960.
var width := LevelData.SCREEN_W
var rng := RandomNumberGenerator.new()

## Dev / test switches.
var invincible := false
var auto_slots := true           ## false: combat start/refill spawn nothing (tests place enemies)
var allow_enemy_fire := true
var enemy_speed := 62.0          ## px per game second (set from the level tempo)
var osc_amplitude := LevelData.ENEMY_OSC_AMPLITUDE

# --- Public state --------------------------------------------------------------------------------
var events: Array[Dictionary] = []
var state: State = State.INTRO
var intro_time := 0.0            ## real seconds spent in INTRO
var lives := 3
var score_delta := 0             ## points earned in this level (kills + completion bonus)
var flawless := true             ## no life lost in this level
var goal_met := false
var completion_bonus := 0
var extra_life_awarded := false
var result := {}                 ## {"level", "completion_bonus", "extra_life", "flawless"} once COMPLETE
var bonus_result := {}           ## level 13: {"remaining", "factor", "bonus", "extra_life"}

var player_x := LevelData.PLAYER_START_X
var player_alive := true
var respawn_timer := 0.0

var enemies: Array[Enemy] = []
var shots: Array[Shot] = []
var bullets: Array[Bullet] = []
var explosions: Array[Explosion] = []
var slots: Array[Slot] = []
var rank_timers: Array[float] = []   ## levels 1–10: [rank 1] or [rank 1, rank 2]

var total := 0                   ## ORIGINAL enemies of this level
var spawned := 0                 ## originals spawned so far
var destroyed := 0               ## final destructions (children included)
var attempts := 0                ## bonus level: shot attempts left
var salvos_fired := 0
var anim_time := 0.0             ## game seconds since combat start, runs in every state (flap / FX)
var combat_steps := 0            ## sub-steps in which the combat ran (movement, oscillation)
var step_count := 0              ## all game sub-steps since combat start (game clock, rolling window)

## Real seconds of active play (SPEC §9), exact to the sub-step.
var active_time: float:
	get:
		return float(_active_steps) * LevelData.SIM_STEP / speed_factor

var _active_steps := 0
var _acc := 0.0
var _next_id := 1
var _fire: Dictionary
var _rule: int
var _points := 0
var _fire_factor := 0.0


func _init(p_level: int, p_difficulty: int, p_ship_id: int, p_lives: int, rng_seed: int = 0,
		p_width: float = LevelData.SCREEN_W) -> void:
	width = maxf(p_width, LevelData.SCREEN_W)
	player_x = LevelData.player_start_x(width)
	level = clampi(p_level, LevelData.FIRST_LEVEL, LevelData.LAST_LEVEL)
	difficulty = int(ShipData.difficulty(p_difficulty)["id"])
	speed_factor = float(ShipData.difficulty(p_difficulty)["speed_factor"])
	ship_id = int(ShipData.ship(p_ship_id)["id"])
	lives = p_lives
	rng.seed = rng_seed
	var ld := LevelData.level(level)
	total = int(ld["total"])
	_points = int(ld["points"])
	_fire_factor = float(ld["fire"])
	_fire = LevelData.fire(level)
	_rule = LevelData.hit_rule(level)
	enemy_speed = LevelData.enemy_speed(level)
	if is_bonus():
		attempts = LevelData.BONUS_ATTEMPTS
	for lane in LevelData.slot_lanes(level):
		var s := Slot.new()
		s.lane = lane
		slots.append(s)


# --- Queries -------------------------------------------------------------------------------------
func is_bonus() -> bool:
	return level == LevelData.BONUS_LEVEL


func combat_time() -> float:
	return float(combat_steps) * LevelData.SIM_STEP


func hit_rule() -> int:
	return _rule


func ship() -> Dictionary:
	return ShipData.ship(ship_id)


## 0..1 wing-flap phase (2.5 Hz game time; children share the parent's phase).
func flap_phase(e: Enemy) -> float:
	return fposmod(anim_time * LevelData.FLAP_HZ + e.flap_offset, 1.0)


func find_enemy(id: int) -> Enemy:
	for e in enemies:
		if e.id == id:
			return e
	return null


## All alive figures ordered by current y, lowest on screen (largest y) first; ties by id.
## (Display / bot order. Who holds a FIRE rank among tied figures is decided by rank_holder().)
func ranked_enemies() -> Array[Enemy]:
	var arr: Array[Enemy] = enemies.duplicate()
	arr.sort_custom(func(a: Enemy, b: Enemy) -> bool:
		if a.y != b.y:
			return a.y > b.y
		return a.id < b.id)
	return arr


## The figure that holds fire rank r (0 = currently lowest) right now (SPEC §7).
## Figures with exactly the same y are equally low and hold their positions jointly – in play this is a
## split pair (same lane, inherited oscillation phase). Inside such a tie the armed figures take the front
## positions, and among several armed ones the holder is drawn at random each time it is asked (i.e. each
## time a rank timer fires). So a tie can never silence an armed sibling systematically, while a STRICTLY
## higher figure never takes over the right of a lower defenceless one ("no passing").
## May consume one random number (only for a tie of several armed figures).
func rank_holder(r: int) -> Enemy:
	var ranked := ranked_enemies()
	if r < 0 or r >= ranked.size():
		return null
	var y := ranked[r].y
	var lo := r
	while lo > 0 and ranked[lo - 1].y == y:
		lo -= 1
	var hi := r
	while hi + 1 < ranked.size() and ranked[hi + 1].y == y:
		hi += 1
	if lo == hi:
		return ranked[r]
	var armed: Array[Enemy] = []
	var defenceless: Array[Enemy] = []
	for i in range(lo, hi + 1):
		if ranked[i].armed:
			armed.append(ranked[i])
		else:
			defenceless.append(ranked[i])
	var k := r - lo
	if k >= armed.size():
		return defenceless[k - armed.size()]
	if armed.size() == 1:
		return armed[0]
	# Uniformly random order of the armed part: the figure at any one of its positions is uniform.
	return armed[rng.randi_range(0, armed.size() - 1)]


## Horizontal turning limits of an enemy CENTER (SPEC §5): the same for every figure, children included.
## `w` = playfield width (SPEC §18.1): the right limit keeps its 50 px margin to the right screen edge.
static func min_x(_s: float = 1.0, _w: float = LevelData.SCREEN_W) -> float:
	return LevelData.ENEMY_MIN_X


static func max_x(_s: float = 1.0, w: float = LevelData.SCREEN_W) -> float:
	return LevelData.enemy_max_x(w)


func is_finished() -> bool:
	return state == State.COMPLETE or state == State.GAME_OVER


# --- Driving -------------------------------------------------------------------------------------
## Advances the world by REAL seconds. Sub-steps itself (fixed 1/240 game-second steps).
func update(real_dt: float, move_axis: float, fire_held: bool) -> void:
	if is_finished() or real_dt <= 0.0:
		return
	var axis := clampf(move_axis, -1.0, 1.0)
	if state == State.INTRO:
		intro_time += real_dt
		if intro_time < LevelData.INTRO_TIME - EPS:
			return
		real_dt = maxf(intro_time - LevelData.INTRO_TIME, 0.0)
		intro_time = LevelData.INTRO_TIME
		start_combat()
	_acc += real_dt * speed_factor / LevelData.SIM_STEP
	while _acc >= 1.0 - EPS:
		_acc -= 1.0
		step(axis, fire_held)
		if is_finished():
			_acc = 0.0
			return


## Runs n sub-steps (tests).
func run_steps(n: int, move_axis: float = 0.0, fire_held: bool = false) -> void:
	for i in n:
		if is_finished():
			return
		step(move_axis, fire_held)


## Runs for the given GAME seconds (tests).
func run_game_seconds(seconds: float, move_axis: float = 0.0, fire_held: bool = false) -> void:
	run_steps(int(round(seconds / LevelData.SIM_STEP)), move_axis, fire_held)


## Ends the intro and starts the combat: every slot is filled (SPEC §5, §9).
func start_combat() -> void:
	if state != State.INTRO:
		return
	state = State.PLAYING
	events.append({"type": "combat_start"})
	_reset_rank_timers()
	if auto_slots:
		for i in slots.size():
			if spawned < total:
				_spawn_original(i)


## One fixed simulation sub-step of LevelData.SIM_STEP game seconds.
func step(move_axis: float, fire_held: bool) -> void:
	if state == State.INTRO or is_finished():
		return
	var dt := LevelData.SIM_STEP
	step_count += 1
	anim_time += dt
	_update_explosions(dt)
	for e in enemies:
		e.flash = maxf(e.flash - dt, 0.0)
	match state:
		State.PLAYING:
			_active_steps += 1
			_combat_step(dt, clampf(move_axis, -1.0, 1.0), fire_held)
		State.RESPAWN:
			respawn_timer -= dt
			if respawn_timer <= EPS:
				_respawn()
		State.CLEARING:
			_move_player(dt, clampf(move_axis, -1.0, 1.0))
			_move_shots(dt)
			if not enemies.is_empty():
				# Bonus level ended by attempts: the survivors keep flying (harmless, no fire, no refill).
				combat_steps += 1
				_move_enemies(dt)
			if explosions.is_empty():
				_complete()
		State.GAME_OVER_WAIT:
			if not _has_player_explosion():
				state = State.GAME_OVER
				events.append({"type": "game_over"})


func _combat_step(dt: float, axis: float, fire_held: bool) -> void:
	combat_steps += 1
	_move_player(dt, axis)
	_update_refills(dt)
	_move_enemies(dt)
	_move_shots(dt)
	_collide_shots()
	if fire_held and player_alive and shots.is_empty():
		_try_fire()
	_move_bullets(dt)
	_update_enemy_fire(dt)
	_collide_player()
	if state == State.PLAYING:
		_check_goal()


# --- Player --------------------------------------------------------------------------------------
func _move_player(dt: float, axis: float) -> void:
	if not player_alive:
		return
	player_x = clampf(player_x + axis * LevelData.PLAYER_SPEED * dt, LevelData.PLAYER_MIN_X,
		LevelData.player_max_x(width))


## Creates a new salvo (SPEC §4). Caller guarantees that the previous salvo is gone.
func _try_fire() -> void:
	if is_bonus() and attempts <= 0:
		return
	# No new salvo once the level goal is reached – not even in the sub-step of the last kill
	# (held fire would otherwise cost a bonus attempt after the 20th kill, REFERENCE H).
	if goal_met or _goal_condition():
		return
	var sh := ship()
	for off in ShipData.shot_offsets(ship_id):
		var s := Shot.new()
		s.id = _new_id()
		s.offset = off
		s.x = player_x + off
		s.y = LevelData.SALVO_Y
		s.speed = float(sh["speed"])
		s.guided = bool(sh["guided"])
		s.piercing = bool(sh["piercing"])
		shots.append(s)
	salvos_fired += 1
	if is_bonus():
		attempts -= 1
	events.append({"type": "shot_fired", "ship_id": ship_id, "count": int(sh["count"]), "x": player_x})


func _move_shots(dt: float) -> void:
	var i := 0
	while i < shots.size():
		var s := shots[i]
		s.age += dt
		s.y -= s.speed * dt
		if s.guided:
			s.x = player_x + s.offset
		if s.y < LevelData.OWN_PROJECTILE_REMOVE_Y:
			shots.remove_at(i)
		else:
			i += 1


func _collide_player() -> void:
	if not player_alive or invincible:
		return
	for b in bullets:
		if absf(b.x - player_x) < LevelData.PLAYER_HIT_DX and absf(b.y - LevelData.PLAYER_Y) < LevelData.PLAYER_HIT_DY:
			_player_hit()   # one life, no matter how many bullets overlap in this step
			return


func _player_hit() -> void:
	lives -= 1
	flawless = false
	player_alive = false
	shots.clear()
	bullets.clear()
	var ex := Explosion.new()
	ex.id = _new_id()
	ex.kind = "player"
	ex.x = player_x
	ex.y = LevelData.PLAYER_Y
	ex.scale = 1.0
	ex.duration = LevelData.PLAYER_EXPLOSION_TIME
	explosions.append(ex)
	events.append({"type": "player_hit", "x": player_x, "y": LevelData.PLAYER_Y, "lives_left": lives, "explosion": ex.id})
	if lives <= 0:
		lives = 0
		state = State.GAME_OVER_WAIT
	else:
		state = State.RESPAWN
		respawn_timer = LevelData.RESPAWN_DELAY


func _respawn() -> void:
	player_x = LevelData.player_start_x(width)
	player_alive = true
	state = State.PLAYING
	_reset_rank_timers()
	if _per_figure_fire():
		for e in enemies:
			e.fire_timer = _initial_figure_fire_time()
	events.append({"type": "player_respawn", "x": player_x})
	_check_goal()


# --- Enemies -------------------------------------------------------------------------------------
func _new_id() -> int:
	_next_id += 1
	return _next_id - 1


func _lane_y(e: Enemy) -> float:
	return LevelData.LANE_Y[e.lane] + osc_amplitude * sin(e.osc_phase + TAU * LevelData.ENEMY_OSC_HZ * combat_time())


func _spawn_original(slot_idx: int) -> Enemy:
	var sl := slots[slot_idx]
	var e := Enemy.new()
	e.id = _new_id()
	e.group_id = e.id
	e.slot = slot_idx
	e.lane = sl.lane
	e.x = _pick_spawn_x(sl.lane)
	e.dir = _pick_spawn_dir(sl.lane, e.x)
	e.osc_phase = rng.randf() * TAU
	e.flap_offset = rng.randf()
	e.armed = _original_armed(e.lane)
	_init_figure_timers(e)
	e.y = _lane_y(e)
	enemies.append(e)
	sl.alive += 1
	sl.refill = -1.0
	spawned += 1
	events.append({"type": "enemy_spawned", "id": e.id, "x": e.x, "y": e.y, "scale": e.scale, "lane": e.lane})
	return e


## Spawn x of a new original (SPEC §5): uniformly random among all x within the limits that keep
## SPAWN_MIN_DISTANCE to every figure on its own lane AND a free column, i.e. SPAWN_COLUMN_CLEARANCE to every
## figure on the other lanes (children included), so it does not appear hidden behind a lower one.
## If the screen is too crowded for that, both distances are relaxed by the same factor (1.0, 0.9, … 0.0)
## and the first factor that leaves room is used – the best compromise keeps as much of both as possible.
## The free set is computed exactly (no sampling), so exactly one random number is used per spawn.
func _pick_spawn_x(lane: int) -> float:
	var lo := min_x(1.0, width)
	var hi := max_x(1.0, width)
	for k in LevelData.SPAWN_RELAX_STEPS + 1:
		var f := 1.0 - float(k) / float(LevelData.SPAWN_RELAX_STEPS)
		var free := _spawn_free_segments(lane, f, lo, hi)
		var length := 0.0
		for i in range(0, free.size(), 2):
			length += free[i + 1] - free[i]
		if length <= EPS:
			continue
		var r := rng.randf() * length
		for i in range(0, free.size(), 2):
			var seg := free[i + 1] - free[i]
			if r <= seg:
				return free[i] + r
			r -= seg
		return free[free.size() - 1]   # rounding guard
	return rng.randf_range(lo, hi)   # unreachable: factor 0.0 blocks nothing


## The parts of [lo, hi] at least f·SPAWN_MIN_DISTANCE away from every figure on `lane` and at least
## f·SPAWN_COLUMN_CLEARANCE away from every figure on the other lanes, as [a0, b0, a1, b1, …] (ascending).
func _spawn_free_segments(lane: int, f: float, lo: float, hi: float) -> PackedFloat64Array:
	var blocked: Array[PackedFloat64Array] = []
	for e in enemies:
		var r := f * (LevelData.SPAWN_MIN_DISTANCE if e.lane == lane else LevelData.SPAWN_COLUMN_CLEARANCE)
		if r > 0.0:
			blocked.append(PackedFloat64Array([e.x - r, e.x + r]))
	blocked.sort_custom(func(a: PackedFloat64Array, b: PackedFloat64Array) -> bool: return a[0] < b[0])
	var out := PackedFloat64Array()
	var cur := lo
	for iv in blocked:
		if iv[0] > cur and cur < hi:
			out.append(cur)
			out.append(minf(iv[0], hi))
		cur = maxf(cur, iv[1])
	if cur < hi:
		out.append(cur)
		out.append(hi)
	return out


## Start direction of a new original (SPEC §5): if a figure on another lane (children included) is within
## SPAWN_DIR_RANGE, opposite to the CURRENT direction of the nearest such figure, so the two separate instead
## of flying on as a stack; otherwise random. Always uses one random number.
func _pick_spawn_dir(lane: int, x: float) -> float:
	var d := -1.0 if rng.randf() < 0.5 else 1.0
	var nearest := INF
	for e in enemies:
		var dx := absf(e.x - x)
		if e.lane != lane and dx <= LevelData.SPAWN_DIR_RANGE and dx < nearest:
			nearest = dx
			d = -e.dir
	return d


## Places an enemy directly (tests / dev). Pass slot -1 for a figure outside the slot system.
func add_enemy(lane: int, x: float, dir: float = 1.0, scale: float = 1.0, is_child: bool = false, slot: int = -1) -> Enemy:
	var e := Enemy.new()
	e.id = _new_id()
	e.group_id = e.id
	e.lane = lane
	e.x = x
	e.dir = dir
	e.scale = scale
	e.is_child = is_child
	e.slot = slot
	e.age = LevelData.MATERIALIZE_TIME
	e.armed = _original_armed(lane) if not is_child else _child_armed_default(lane)
	_init_figure_timers(e)
	e.y = _lane_y(e)
	enemies.append(e)
	if slot >= 0 and slot < slots.size():
		slots[slot].alive += 1
		slots[slot].refill = -1.0
	return e


## Applies one own-projectile hit to an alive enemy exactly as a fresh projectile would (tests / dev).
func apply_hit(e: Enemy, piercing: bool = false) -> void:
	if e == null or not enemies.has(e):
		return
	var s := Shot.new()
	s.id = _new_id()
	s.piercing = piercing
	_hit_enemy(e, s)


## Places an enemy bullet directly (tests / dev).
func add_bullet(x: float, y: float, vx: float = 0.0, vy: float = LevelData.ENEMY_BULLET_SPEED) -> Bullet:
	var b := Bullet.new()
	b.id = _new_id()
	b.x = x
	b.y = y
	b.vx = vx
	b.vy = vy
	bullets.append(b)
	return b


func _init_figure_timers(e: Enemy) -> void:
	if level >= LevelData.DIR_CHANGE_FROM_LEVEL:
		e.dir_timer = rng.randf_range(LevelData.DIR_CHANGE_MIN, LevelData.DIR_CHANGE_MAX)
	if _per_figure_fire():
		e.fire_timer = _initial_figure_fire_time()


func _move_enemies(dt: float) -> void:
	for e in enemies:
		e.age += dt
		e.turn_age += dt
		e.x += e.dir * enemy_speed * dt
		var lo := min_x(e.scale, width)
		var hi := max_x(e.scale, width)
		if e.x <= lo:
			e.x = lo
			_set_dir(e, 1.0)
		elif e.x >= hi:
			e.x = hi
			_set_dir(e, -1.0)
		if e.dir_timer != INF:
			e.dir_timer -= dt
			if e.dir_timer <= EPS:
				_set_dir(e, -e.dir)
				e.dir_timer = rng.randf_range(LevelData.DIR_CHANGE_MIN, LevelData.DIR_CHANGE_MAX)
		e.y = _lane_y(e)
	if level >= LevelData.DIR_CHANGE_FROM_LEVEL:
		_break_stacks(dt)


func _set_dir(e: Enemy, d: float) -> void:
	if e.dir != d:
		e.dir = d
		e.turn_age = 0.0


## Stack breaking (SPEC §5). All figures of a level fly at the same speed, so a figure flying right above a
## lower one stays hidden behind it until one of them turns – and a non-piercing shot always hits the LOWEST
## overlapping figure (in levels 14–16 often a locked one). A figure counts as covered while a figure on a
## LOWER lane is within |dx| < STACK_OVERLAP_DX and moves the same way. After STACK_COVER_TIME covered game
## seconds in a row the upper figure reverses early – but never sooner than DIR_CHANGE_MIN after its own last
## direction change (limit turn, random change, earlier break), and its random timer then restarts with
## rand(1.2, 3.2): a break only brings the next random change forward, within the 1.2–3.2 s of the rules.
## Only from level 10 on, where the rules allow additional direction changes; it runs with the movement,
## i.e. in game time and not during RESPAWN.
func _break_stacks(dt: float) -> void:
	var covered: Array[bool] = []
	for e in enemies:
		covered.append(is_covered(e))
	for i in enemies.size():
		var e := enemies[i]
		if not covered[i]:
			e.cover_time = 0.0
			continue
		e.cover_time += dt
		if e.cover_time >= LevelData.STACK_COVER_TIME - EPS and e.turn_age >= LevelData.DIR_CHANGE_MIN - EPS:
			_set_dir(e, -e.dir)
			e.cover_time = 0.0
			e.dir_timer = rng.randf_range(LevelData.DIR_CHANGE_MIN, LevelData.DIR_CHANGE_MAX)


## True while a figure on a lower lane overlaps `e` horizontally (|dx| < STACK_OVERLAP_DX) and moves the same way.
func is_covered(e: Enemy) -> bool:
	for o in enemies:
		if o.lane > e.lane and o.dir == e.dir and absf(o.x - e.x) < LevelData.STACK_OVERLAP_DX:
			return true
	return false


func _update_refills(dt: float) -> void:
	for i in slots.size():
		var sl := slots[i]
		if sl.refill < 0.0:
			continue
		sl.refill -= dt
		if sl.refill <= EPS:
			sl.refill = -1.0
			if auto_slots and spawned < total and sl.alive == 0:
				_spawn_original(i)


# --- Own projectiles vs enemies (SPEC §4, §8) ----------------------------------------------------
func _overlapping(s: Shot) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for e in enemies:
		if s.hit_ids.has(e.id):
			continue
		if absf(s.x - e.x) < LevelData.HIT_DX * e.scale and absf(s.y - e.y) < LevelData.HIT_DY * e.scale:
			out.append(e)
	out.sort_custom(func(a: Enemy, b: Enemy) -> bool:
		if a.y != b.y:
			return a.y > b.y
		return a.id < b.id)
	return out


func _collide_shots() -> void:
	var i := 0
	while i < shots.size():
		var s := shots[i]
		var cands := _overlapping(s)
		var consumed := false
		if not cands.is_empty():
			if s.piercing:
				for e in cands:
					if enemies.has(e) and not s.hit_ids.has(e.id):
						_hit_enemy(e, s)
			else:
				_hit_enemy(cands[0], s)   # the LOWEST overlapping enemy
				consumed = true           # non-piercing shots are consumed by every hit, locked ones too
		if consumed:
			shots.remove_at(i)
		else:
			i += 1


func _hit_enemy(e: Enemy, s: Shot) -> void:
	s.hit_ids[e.id] = true
	match _rule:
		LevelData.Hit.SPLIT:
			if e.is_child:
				_destroy(e)
			else:
				_split(e, s)
		LevelData.Hit.COLOR_LOCK:
			_color_hit(e)
		LevelData.Hit.ROLLING:
			_rolling_hit(e)
		_:
			_destroy(e)


func _destroy(e: Enemy) -> void:
	enemies.erase(e)
	destroyed += 1
	score_delta += _points
	var ex := Explosion.new()
	ex.id = _new_id()
	ex.kind = "enemy"
	ex.x = e.x
	ex.y = e.y
	ex.scale = e.scale
	ex.stage = e.stage
	ex.is_child = e.is_child
	ex.duration = LevelData.ENEMY_EXPLOSION_TIME
	explosions.append(ex)
	events.append({"type": "enemy_destroyed", "id": e.id, "x": e.x, "y": e.y, "scale": e.scale,
		"points": _points, "is_child": e.is_child, "stage": e.stage, "explosion": ex.id,
		"group_cleared": not _group_alive(e.group_id)})
	_release_slot(e.slot)


## True while any figure of this group (an original or its children) is still alive.
func _group_alive(group_id: int) -> bool:
	for o in enemies:
		if o.group_id == group_id:
			return true
	return false


func _release_slot(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	var sl := slots[slot_idx]
	sl.alive = maxi(sl.alive - 1, 0)
	if sl.alive == 0 and spawned < total:
		sl.refill = LevelData.REFILL_DELAY


func _split(e: Enemy, s: Shot) -> void:
	var cs := LevelData.child_scale(level)
	var idx := enemies.find(e)
	enemies.remove_at(idx)
	var kids: Array[Enemy] = []
	for k in 2:
		var c := Enemy.new()
		c.id = _new_id()
		c.slot = e.slot
		c.lane = e.lane
		c.scale = cs
		c.is_child = true
		c.parent_id = e.id
		c.group_id = e.group_id
		c.osc_phase = e.osc_phase
		c.flap_offset = e.flap_offset
		c.age = LevelData.MATERIALIZE_TIME
		c.stage = e.stage
		var side := -1.0 if k == 0 else 1.0
		c.dir = side
		c.x = clampf(e.x + side * LevelData.CHILD_SPAWN_OFFSET, min_x(cs, width), max_x(cs, width))
		c.y = e.y
		c.armed = _child_armed_default(e.lane)
		kids.append(c)
	if int(_fire["child_rule"]) == LevelData.ChildRule.ONE_ARMED:
		var pick := rng.randi_range(0, 1)
		kids[0].armed = pick == 0
		kids[1].armed = pick == 1
	for c in kids:
		_init_figure_timers(c)
		s.hit_ids[c.id] = true      # the splitting projectile must not hit the children
	enemies.insert(idx, kids[1])
	enemies.insert(idx, kids[0])
	if e.slot >= 0 and e.slot < slots.size():
		slots[e.slot].alive += 1    # parent (−1) replaced by two children (+2)
	events.append({"type": "enemy_split", "id": e.id, "x": e.x, "y": e.y, "scale": e.scale,
		"children": [kids[0].id, kids[1].id]})


func _color_hit(e: Enemy) -> void:
	match e.stage:
		LevelData.Stage.VIOLET:
			e.stage = LevelData.Stage.YELLOW
			events.append({"type": "enemy_hit_nonlethal", "id": e.id, "x": e.x, "y": e.y, "kind": "color_stage",
				"stage": e.stage, "scale": e.scale})
		LevelData.Stage.YELLOW:
			if _count_stage(LevelData.Stage.VIOLET) == 0:
				e.stage = LevelData.Stage.GREEN
				events.append({"type": "enemy_hit_nonlethal", "id": e.id, "x": e.x, "y": e.y, "kind": "color_stage",
					"stage": e.stage, "scale": e.scale})
			else:
				_locked(e)
		_:
			if _count_stage(LevelData.Stage.GREEN) == enemies.size():
				_destroy(e)
			else:
				_locked(e)


func _locked(e: Enemy) -> void:
	events.append({"type": "locked_hit", "id": e.id, "x": e.x, "y": e.y, "stage": e.stage, "scale": e.scale})


func _count_stage(st: int) -> int:
	var n := 0
	for e in enemies:
		if e.stage == st:
			n += 1
	return n


func _rolling_hit(e: Enemy) -> void:
	# The window runs on GAME time (SPEC §1), respawn pauses included: §3 pauses movement, fire and refill
	# during a respawn, not the rolling window. step_count = game sub-steps since combat start.
	var now := step_count
	var kept: Array[int] = []
	for t in e.hit_steps:
		if now - t <= ROLLING_WINDOW_STEPS:   # keep a hit while now − t ≤ 10.0 game seconds
			kept.append(t)
	kept.append(now)
	e.hit_steps = kept
	if kept.size() >= LevelData.ROLLING_HITS:
		_destroy(e)
	else:
		e.flash = LevelData.HIT_FLASH_TIME
		events.append({"type": "enemy_hit_nonlethal", "id": e.id, "x": e.x, "y": e.y, "kind": "rolling",
			"hits": kept.size(), "scale": e.scale})


# --- Enemy fire (SPEC §7) ------------------------------------------------------------------------
func _per_figure_fire() -> bool:
	return level >= 11 and _fire_factor > 0.0 and int(_fire["count"]) > 0


func _initial_figure_fire_time() -> float:
	return (LevelData.FIRE_INITIAL_RANK1 + rng.randf_range(0.0, 0.8)) / _fire_factor


func _reset_rank_timers() -> void:
	rank_timers.clear()
	if level > 10 or _fire_factor <= 0.0:
		return
	match int(_fire["perm"]):
		LevelData.Perm.RANK1:
			rank_timers.append(LevelData.FIRE_INITIAL_RANK1 / _fire_factor)
		LevelData.Perm.RANK2:
			rank_timers.append(LevelData.FIRE_INITIAL_RANK1 / _fire_factor)
			rank_timers.append(LevelData.FIRE_INITIAL_RANK2 / _fire_factor)


func _next_fire_interval() -> float:
	return rng.randf_range(LevelData.FIRE_INTERVAL_MIN, LevelData.FIRE_INTERVAL_MAX) / _fire_factor


## Whether an ORIGINAL on this lane may fire at all (levels ≥ 11: lane permission).
func _original_armed(lane: int) -> bool:
	if int(_fire["count"]) <= 0 or _fire_factor <= 0.0:
		return false
	match int(_fire["perm"]):
		LevelData.Perm.RANK1, LevelData.Perm.RANK2:
			return true
		LevelData.Perm.LANE_BOTTOM:
			return lane == LevelData.BOTTOM_LANE
		LevelData.Perm.LANES_MID_BOTTOM:
			return lane >= 1
		LevelData.Perm.ALL:
			return true
	return false


## Child arming (SPEC §8). ONE_ARMED is decided randomly at the split.
func _child_armed_default(lane: int) -> bool:
	if not _original_armed(lane):
		return false
	match int(_fire["child_rule"]):
		LevelData.ChildRule.BOTTOM_LANE:
			return lane == LevelData.BOTTOM_LANE
		LevelData.ChildRule.ONE_ARMED:
			return true
	return false


func _update_enemy_fire(dt: float) -> void:
	if _fire_factor <= 0.0 or int(_fire["count"]) <= 0:
		return
	if level <= 10:
		for r in rank_timers.size():
			rank_timers[r] -= dt
			if rank_timers[r] <= EPS:
				rank_timers[r] = _next_fire_interval()
				if not allow_enemy_fire:
					continue
				# The figure holding this rank fires if armed – a defenceless one does NOT pass its right on.
				var holder := rank_holder(r)
				if holder != null and holder.armed:
					_fire_salvo(holder)
	else:
		for e in enemies.duplicate():
			e.fire_timer -= dt
			if e.fire_timer <= EPS:
				e.fire_timer = _next_fire_interval()
				if allow_enemy_fire and e.armed:
					_fire_salvo(e)


func _fire_salvo(e: Enemy) -> void:
	var n := int(_fire["child_count"]) if e.is_child else int(_fire["count"])
	if n <= 0:
		return
	# Salvo width in % of the enemy width (0.55–1.0) – not the playfield width member `width`.
	var salvo_w := float(_fire["width"])
	var vel := LevelData.bullet_velocity(int(_fire["dir"]), player_x, e.x)
	var y0 := e.y + LevelData.ENEMY_BULLET_SPAWN_DY * e.scale
	if bool(_fire["columns"]):
		# Level 10: adjacent columns of two bullets, the second one 18 px above.
		for off in LevelData.salvo_offsets(n >> 1, salvo_w, e.scale):
			_spawn_bullet(e.x + off, y0, vel, e.id)
			_spawn_bullet(e.x + off, y0 - LevelData.LEVEL10_COLUMN_DY, vel, e.id)
	else:
		for off in LevelData.salvo_offsets(n, salvo_w, e.scale):
			_spawn_bullet(e.x + off, y0, vel, e.id)
	events.append({"type": "enemy_fire", "id": e.id, "x": e.x, "y": y0, "count": n, "vx": vel.x, "vy": vel.y})


func _spawn_bullet(x: float, y: float, vel: Vector2, owner: int) -> void:
	var b := add_bullet(x, y, vel.x, vel.y)
	b.owner_id = owner


func _move_bullets(dt: float) -> void:
	var i := 0
	while i < bullets.size():
		var b := bullets[i]
		b.age += dt
		b.x += b.vx * dt
		b.y += b.vy * dt
		if not b.landed and b.y + BULLET_HALF >= LevelData.GROUND_Y:
			b.landed = true
			events.append({"type": "bullet_landed", "x": b.x})
		# Swallowed by the ground once entirely below it; also removed when entirely off-screen sideways (0 / width).
		if b.y - BULLET_HALF > LevelData.GROUND_Y or b.x + BULLET_HALF < 0.0 or b.x - BULLET_HALF > width:
			bullets.remove_at(i)
		else:
			i += 1


# --- Level end -----------------------------------------------------------------------------------
func _goal_condition() -> bool:
	if is_bonus():
		return destroyed >= LevelData.BONUS_TARGET or (attempts <= 0 and shots.is_empty())
	return spawned >= total and enemies.is_empty()


func _check_goal() -> void:
	if not goal_met and _goal_condition():
		goal_met = true
		events.append({"type": "level_goal_met"})
	if goal_met and bullets.is_empty() and state == State.PLAYING:
		state = State.CLEARING
		events.append({"type": "clearing"})
		if explosions.is_empty():
			_complete()


func _complete() -> void:
	if state == State.COMPLETE:
		return
	state = State.COMPLETE
	var reason := ""
	if is_bonus():
		var factor := int(ship()["bonus_factor"])
		completion_bonus = LevelData.bonus_value(attempts, ship_id)
		extra_life_awarded = LevelData.bonus_gives_extra_life(completion_bonus)
		bonus_result = {"remaining": attempts, "factor": factor, "bonus": completion_bonus, "extra_life": extra_life_awarded}
		reason = "bonus"
	else:
		completion_bonus = int(LevelData.level(level)["bonus"])
		extra_life_awarded = flawless and LevelData.flawless_extra_life(level)
		reason = "flawless"
	score_delta += completion_bonus
	if extra_life_awarded:
		lives += 1
		events.append({"type": "extra_life", "reason": reason})
	result = {"level": level, "completion_bonus": completion_bonus, "extra_life": extra_life_awarded, "flawless": flawless}
	events.append({"type": "level_complete", "completion_bonus": completion_bonus, "extra_life": extra_life_awarded,
		"flawless": flawless})


func _update_explosions(dt: float) -> void:
	var i := 0
	while i < explosions.size():
		var ex := explosions[i]
		ex.age += dt
		if ex.age >= ex.duration - EPS:
			explosions.remove_at(i)
		else:
			i += 1


func _has_player_explosion() -> bool:
	for ex in explosions:
		if ex.kind == "player":
			return true
	return false
