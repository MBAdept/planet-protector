class_name AttractDirector
extends RefCounted
## Attract mode / demo run (docs/SPEC.md §11.1) – the choreography as a PURE class, unit-tested headless.
## After IDLE_TIME seconds without input on the title screen Main opens the GameScreen in attract mode: a random
## level (never the bonus level 13 – nobody fires there, the ship could not be hit) with a random ship on NORMAL
## (speed factor 1.0) and ONE life. The director decides what the autopilot does and when the scene ends:
##
##   0 … t_vulnerable        the ship is invincible; it aims, fires until it has landed `hits_wanted` (3–6)
##                           hits on enemies – only salvos predicted to hit, none after the last of those hits –
##                           and dodges inside its escape set (Autopilot.demo). An enemy salvo that would leave it
##                           no escape is withdrawn at once, so no fireball ever passes through the invincible ship.
##   t_vulnerable … t_die    vulnerable: no more dodging, it steers under the nearest falling fireball.
##   t_die − FORCE_LEAD      still alive: a fireball appears right above the ship, which holds still – it is
##                           hit right at t_die, in the first sub-step after it (a failsafe fireball ON the ship
##                           follows FAILSAFE_DELAY after t_die, never needed).
##   hit + HIT_TO_END        player explosion (1.3 s) + END_PAUSE → the demo is over (back to the title).
##
## D = rand(15, 40) real seconds (screen start → title), t_die = D − HIT_TO_END,
## t_vulnerable = max(DURATION_MIN − HIT_TO_END, t_die − VULNERABLE_WINDOW). So the hit lies in [13.1, t_die]
## (+ one sub-step) and the demo ends at min(hit + HIT_TO_END, D) within [15, D] ⊂ [15, 40] s (play() cuts its
## slices exactly at these marks).
## The level can never be completed: the smallest one needs 10 kills, the demo fires no salvo once it has landed
## its (at most 6) hits – only the salvo still in flight may add the few figures it touches.
##
## Time is the screen's real time; on NORMAL it equals game time (explosion lengths, fireball speed).
## Playfield width (SPEC §18.1): the demo world has the width of the run's display mode (make_world(width)); the
## choreography is the same at 960 and 1280 (the autopilot takes every limit from the world).

const Autopilot := preload("res://scripts/game/autopilot.gd")

## Real seconds without any player input on the title screen until the demo starts.
const IDLE_TIME := 90.0
## A stick counts as player input beyond this deflection.
const STICK_THRESHOLD := 0.5
const STICK_AXES: Array[JoyAxis] = [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]

const DIFFICULTY := 1                ## NORMAL, speed factor 1.0 – regardless of the settings
const LIVES := 1
const DURATION_MIN := 15.0
const DURATION_MAX := 40.0
const HITS_MIN := 3
const HITS_MAX := 6
const VULNERABLE_WINDOW := 3.0
const END_PAUSE := 0.6               ## after the player explosion (like GameScreen.GAME_OVER_DELAY)
const HIT_TO_END := LevelData.PLAYER_EXPLOSION_TIME + END_PAUSE
## The rescue fireball is placed this long before t_die (visible for a few frames before it hits); the failsafe
## fireball (never needed) this long after t_die.
const FORCE_LEAD := 0.1
const FAILSAFE_DELAY := 2.0 * LevelData.SIM_STEP
## The autopilot re-decides at least this often (like GameScreen.AUTOPLAY_SLICE).
const BOT_SLICE := 1.0 / 60.0
## World events that count as a hit on an enemy: split, destruction, colour-stage change, non-lethal Earth
## hit. A locked hit changes nothing and does not count.
const HIT_EVENTS: Array[String] = ["enemy_split", "enemy_destroyed", "enemy_hit_nonlethal"]
const MARK_EPS := 1e-6

# --- Script of this demo (fixed at construction) -------------------------------------------------
var level := 1
var ship_id := 0
var hits_wanted := HITS_MIN
var duration := DURATION_MIN         ## D: screen start → back to the title (real seconds)
var t_die := 0.0
var t_vulnerable := 0.0
var world_seed := 0

# --- Progress ------------------------------------------------------------------------------------
var time := 0.0                      ## real seconds since the screen started
var hits := 0                        ## hits landed on enemies
var hit_time := -1.0                 ## when the ship was hit (end of that slice), −1 = not yet
var rescue_placed := false
var failsafe_placed := false
var salvos_withdrawn := 0            ## enemy salvos withdrawn because they would have trapped the invincible ship


## Everything random comes from `rng_seed`. p_level: a valid demo level (1–20 except 13) overrides the random
## choice (dev --attract-level); the random sequence is the same either way.
func _init(rng_seed: int = 0, p_level: int = 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var lvl := pick_level(rng)
	level = p_level if is_demo_level(p_level) else lvl
	ship_id = rng.randi_range(0, ShipData.SHIPS.size() - 1)
	hits_wanted = rng.randi_range(HITS_MIN, HITS_MAX)
	set_duration(rng.randf_range(DURATION_MIN, DURATION_MAX))
	world_seed = rng.randi()


## A level a demo may show: any level except the bonus level.
static func is_demo_level(n: int) -> bool:
	return n >= LevelData.FIRST_LEVEL and n <= LevelData.LAST_LEVEL and n != LevelData.BONUS_LEVEL


## Uniformly one of the 19 demo levels.
static func pick_level(rng: RandomNumberGenerator) -> int:
	var n := rng.randi_range(LevelData.FIRST_LEVEL, LevelData.LAST_LEVEL - 1)
	return n + 1 if n >= LevelData.BONUS_LEVEL else n


## Sets D (clamped to [DURATION_MIN, DURATION_MAX]) and the marks derived from it.
func set_duration(d: float) -> void:
	duration = clampf(d, DURATION_MIN, DURATION_MAX)
	t_die = duration - HIT_TO_END
	t_vulnerable = maxf(DURATION_MIN - HIT_TO_END, t_die - VULNERABLE_WINDOW)


## The demo world: NORMAL, one life, invincible until t_vulnerable; `width` = playfield width (960, 1280 or 1152).
func make_world(width: float = LevelData.SCREEN_W) -> GameWorld:
	var w := GameWorld.new(level, DIFFICULTY, ship_id, LIVES, world_seed, width)
	w.invincible = true
	return w


# --- Driving -------------------------------------------------------------------------------------
## Plays `dt` real seconds of the demo on `w`: the autopilot re-decides every BOT_SLICE, and every mark of the
## script (vulnerable, rescue fireball, failsafe, end) ends a slice exactly. Stops at the end of the demo.
## The world's events stay in w.events for the caller (GameScreen turns them into FX).
## A salvo leaves only in a slice of ONE world sub-step that starts without a shot in flight (control() presses
## the trigger only then): no shot can hit anything in that sub-step before the world reads the trigger (it
## collides before it fires), so the hit count the decision saw (< hits_wanted) is still the count when the salvo
## leaves – never a salvo after the N-th hit, not even in the sub-step of that hit.
func play(w: GameWorld, dt: float) -> void:
	var left := dt
	while left > 1e-9 and not is_over():
		var slice := minf(minf(left, BOT_SLICE), time_to_next_mark())
		var input := control(w)
		var fire := input.y > 0.5
		if fire:
			slice = minf(slice, LevelData.SIM_STEP / w.speed_factor)
		var first := w.events.size()
		# Fireballs are only ever appended (ids ascending), so the last one has the highest id.
		var last_bullet := w.bullets[w.bullets.size() - 1].id if not w.bullets.is_empty() else -1
		w.update(slice, input.x, fire)
		if w.invincible:
			_withdraw_hopeless_salvos(w, first, last_bullet)
		advance(slice, w, first)
		left -= slice


## Input for the next slice (call before w.update): lifts the invincibility at t_vulnerable, places the rescue
## fireball and asks the autopilot (Autopilot.demo: fire only while fewer than hits_wanted hits have landed,
## only for a new salvo – none in flight – and only when it is predicted to hit). Returns Vector2(move_axis, fire).
func control(w: GameWorld) -> Vector2:
	w.invincible = time < t_vulnerable - MARK_EPS
	if hit_time >= 0.0 or not w.player_alive or w.state != GameWorld.State.PLAYING:
		return Vector2.ZERO
	if time >= t_die + FAILSAFE_DELAY - MARK_EPS:
		if not failsafe_placed:
			failsafe_placed = true
			w.add_bullet(w.player_x, LevelData.PLAYER_Y - LevelData.PLAYER_HIT_DY * 0.5)   # hits in the next sub-step
		return Vector2.ZERO
	if time >= t_die - FORCE_LEAD - MARK_EPS:
		if not rescue_placed:
			rescue_placed = true
			# Enters the hit box (|dy| < 15) right after t_die, when the ship is vulnerable for sure (with D = 15 the
			# window is the single instant t_die = 13.1); the ship holds still under it.
			var y := LevelData.PLAYER_Y - LevelData.PLAYER_HIT_DY - 0.25 - LevelData.ENEMY_BULLET_SPEED * FORCE_LEAD
			w.add_bullet(w.player_x, y)
		return Vector2.ZERO
	return Autopilot.demo(w, hits < hits_wanted, not w.invincible)


## While the ship is invincible no fireball may pass through it: a salvo fired in the last slice (events from
## `first_event` on, bullets with an id above `last_bullet`) that would leave the ship no escape
## (Autopilot.can_escape) is withdrawn at once – its fireballs and its event are removed before anything is
## drawn, as if that figure had not fired. Salvos are checked one by one in the order they were fired.
func _withdraw_hopeless_salvos(w: GameWorld, first_event: int, last_bullet: int) -> void:
	if not w.player_alive:
		return
	var fired: Array[int] = []        # event indices
	var salvos := {}                  # owner id → its new fireballs
	for i in range(first_event, w.events.size()):
		if String(w.events[i]["type"]) == "enemy_fire":
			fired.append(i)
			salvos[int(w.events[i]["id"])] = [] as Array[GameWorld.Bullet]
	if fired.is_empty():
		return
	for b in w.bullets:
		if b.id > last_bullet and salvos.has(b.owner_id):
			(salvos[b.owner_id] as Array[GameWorld.Bullet]).append(b)
	for owner: int in salvos:
		for b: GameWorld.Bullet in salvos[owner]:
			w.bullets.erase(b)
	var dropped: Array[int] = []
	for i in fired:
		var salvo: Array[GameWorld.Bullet] = salvos[int(w.events[i]["id"])]
		w.bullets.append_array(salvo)
		if not Autopilot.can_escape(w):
			for b in salvo:
				w.bullets.erase(b)
			dropped.append(i)
			salvos_withdrawn += 1
		salvo.clear()   # a second event of the same figure (never happens) finds nothing left to add
	for j in range(dropped.size() - 1, -1, -1):
		w.events.remove_at(dropped[j])


## Bookkeeping after w.update(dt, …): counts the hits on enemies among the new events (from index
## `first_event` on) and notes when the ship was hit.
func advance(dt: float, w: GameWorld, first_event: int) -> void:
	for i in range(first_event, w.events.size()):
		if HIT_EVENTS.has(String(w.events[i]["type"])):
			hits += 1
	time += dt
	if hit_time < 0.0 and not w.player_alive:
		hit_time = time


## When the demo ends: HIT_TO_END after the hit, never later than D.
func end_time() -> float:
	return minf(hit_time + HIT_TO_END, duration) if hit_time >= 0.0 else duration


func is_over() -> bool:
	return time >= end_time() - MARK_EPS


func is_vulnerable() -> bool:
	return time >= t_vulnerable - MARK_EPS


## Real seconds until the next mark of the script (INF if none is left).
func time_to_next_mark() -> float:
	var next := INF
	for m: float in [t_vulnerable, t_die - FORCE_LEAD, t_die + FAILSAFE_DELAY, end_time()]:
		if m - time > MARK_EPS:
			next = minf(next, m - time)
	return next


# --- Player input (title idle timer, leaving the demo) -------------------------------------------
## True for an input event of the player: a key (also its auto-repeat), a mouse button, a joypad button
## (D-pad included) or a stick deflected beyond STICK_THRESHOLD. Mouse motion and triggers do not count.
static func is_player_input(event: InputEvent) -> bool:
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		return event.is_pressed()
	if event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		return STICK_AXES.has(m.axis) and absf(m.axis_value) > STICK_THRESHOLD
	return false


## True while the player holds anything: a key, a mouse or joypad button, or a stick beyond STICK_THRESHOLD
## (polled each frame, so a hold that began before the screen counts as well).
static func input_held() -> bool:
	if Input.is_anything_pressed():
		return true
	for id in Input.get_connected_joypads():
		for ax in STICK_AXES:
			if absf(Input.get_joy_axis(id, ax)) > STICK_THRESHOLD:
				return true
	return false
