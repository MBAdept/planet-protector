extends RefCounted
## Simple bot for the dev flag "autoplay" (docs/SPEC.md §17.3): moves under the lowest enemy (leading
## the target for unguided shots), keeps firing and sidesteps incoming fireballs. Reads the world only.

const CANDIDATES := 48
const DANGER_DX := 34.0


## Returns Vector2(move_axis, fire) with fire = 1.0 when the button should be held.
static func decide(w: GameWorld) -> Vector2:
	if w.state != GameWorld.State.PLAYING or not w.player_alive:
		return Vector2.ZERO
	var px := w.player_x
	var sh := w.ship()
	var shot_speed := float(sh["speed"])
	var guided := bool(sh["guided"])
	var tgt: GameWorld.Enemy = null
	for e in w.enemies:
		if tgt == null or e.y > tgt.y + 1.0 or (absf(e.y - tgt.y) <= 1.0 and absf(e.x - px) < absf(tgt.x - px)):
			tgt = e
	var target_x := px
	if tgt != null:
		var fly_from := LevelData.SALVO_Y
		if guided and not w.shots.is_empty():
			fly_from = w.shots[0].y
		var t := maxf(fly_from - tgt.y, 0.0) / shot_speed
		target_x = _predict_x(w, tgt, t)
		if guided and not w.shots.is_empty():
			target_x -= w.shots[0].offset
	else:
		target_x = LevelData.PLAYER_START_X
	# Landing points of incoming fireballs (computed once).
	var threats := PackedVector2Array()   # (x at the player line, time until it gets there)
	for b in w.bullets:
		if b.vy <= 0.0:
			continue
		var t_hit := (LevelData.PLAYER_Y - b.y) / b.vy
		if t_hit < -0.06 or t_hit > 1.2:
			continue
		threats.append(Vector2(b.x + b.vx * maxf(t_hit, 0.0), t_hit))
	# Pick the reachable position with the best trade-off between aiming and danger.
	var best := px
	var best_cost := INF
	for i in CANDIDATES:
		var cand := lerpf(LevelData.PLAYER_MIN_X, LevelData.PLAYER_MAX_X, float(i) / float(CANDIDATES - 1))
		var cost := absf(cand - target_x) / 260.0 + _risk(threats, px, cand) * 5.0
		if cost < best_cost:
			best_cost = cost
			best = cand
	var here := absf(px - target_x) / 260.0 + _risk(threats, px, px) * 5.0
	if here <= best_cost + 0.02:
		best = px if absf(px - target_x) < 3.0 else best
	var axis := clampf((best - px) / 18.0, -1.0, 1.0)
	var fire := true
	if w.is_bonus():
		# Do not waste attempts: only shoot when the predicted intercept is inside the hit box.
		fire = tgt != null and w.shots.is_empty() and absf(target_x - px) < LevelData.HIT_DX * tgt.scale * 0.6
	return Vector2(axis, 1.0 if fire else 0.0)


static func _predict_x(w: GameWorld, e: GameWorld.Enemy, t: float) -> float:
	var x := e.x
	var dir := e.dir
	var remaining := t * w.enemy_speed
	var lo := GameWorld.min_x(e.scale)
	var hi := GameWorld.max_x(e.scale)
	for i in 4:
		var limit := hi if dir > 0.0 else lo
		var dist := absf(limit - x)
		if remaining <= dist:
			return x + dir * remaining
		remaining -= dist
		x = limit
		dir = -dir
	return x


## Danger of standing at `cand` (and of travelling there from `px`) for the next ≈ 1.2 game seconds.
static func _risk(threats: PackedVector2Array, px: float, cand: float) -> float:
	var travel := absf(cand - px) / LevelData.PLAYER_SPEED
	var lo := minf(px, cand) - 18.0
	var hi := maxf(px, cand) + 18.0
	var risk := 0.0
	for th in threats:
		var d := absf(th.x - cand)
		if d < DANGER_DX:
			risk += (1.0 - d / DANGER_DX) * (2.0 if th.y < travel + 0.25 else 1.0) * (1.6 - th.y)
		# Crossing a fireball's landing spot on the way there is dangerous too.
		if th.y < travel and th.x > lo and th.x < hi:
			if absf(absf(th.x - px) / LevelData.PLAYER_SPEED - th.y) < 0.18:
				risk += 1.5
	return risk
