extends RefCounted
## Simple bot for the dev flag "autoplay" (docs/SPEC.md §17.3): moves under the lowest enemy (leading
## the target for unguided shots), keeps firing and sidesteps incoming fireballs. Reads the world only.
## The attract mode (AttractDirector, SPEC §11.1) drives it through demo(): a careful player that never lets a
## fireball touch the ship, shoots only when a salvo is predicted to hit, and finally seeks a fireball.
## Playfield width (SPEC §18.1): every limit comes from the world (w.width), so it plays 960 and 1280 alike; the
## candidate grids keep their density (more candidates on the wider field, exactly the classic ones at 960).

## Candidate positions of decide() over the classic ship range [30, 930] (scaled with the range, _grid_size()).
const CANDIDATES := 48
const CLASSIC_RANGE := LevelData.PLAYER_MAX_X - LevelData.PLAYER_MIN_X
const DANGER_DX := 34.0

# --- Attract mode (demo()) -----------------------------------------------------------------------
## Escape set (_escape_set): time step, horizon (the slowest fireball needs < 4.7 s from the top lane to below
## the ship), the half-width a fireball blocks (hit box 21 plus a margin) and the distance kept from the edges.
const DEMO_ESCAPE_DT := 1.0 / 30.0
const DEMO_ESCAPE_HORIZON := 4.8
const DEMO_ESCAPE_DX := 26.0
const DEMO_ESCAPE_EDGE := 8.0
## Both dodges count a fireball while it is within DEMO_MARGIN_Y of the ship's height band (|dy| < 15).
const DEMO_MARGIN_Y := 4.0
## Fallback dodging (no escape left): candidate positions (a grid, plus the aim point), the fireballs' paths are
## checked DEMO_HORIZON game seconds ahead; a fireball should pass at least DEMO_CLEAR_X away horizontally and must
## not come within the hit box (|dx| < 21) plus DEMO_HIT_MARGIN.
const DEMO_CANDIDATES := 64
const DEMO_HORIZON := 2.0
const DEMO_CLEAR_X := 34.0
const DEMO_HIT_MARGIN := 3.0
## The demo's salvo prediction relies on this part of the hit box (|dx| < 49 · scale).
const DEMO_AIM_DX := 0.75


## Ship x range of the world: [PLAYER_MIN_X, player_max_x(width)].
static func _ship_max(w: GameWorld) -> float:
	return LevelData.player_max_x(w.width)


## Number of grid candidates over the ship's range: `classic` over the classic range, the same density on a wider
## playfield (exactly `classic` at width 960).
static func _grid_size(w: GameWorld, classic: int) -> int:
	return maxi(classic, roundi(float(classic - 1) * (_ship_max(w) - LevelData.PLAYER_MIN_X) / CLASSIC_RANGE) + 1)


## Returns Vector2(move_axis, fire) with fire = 1.0 when the button should be held.
static func decide(w: GameWorld) -> Vector2:
	if w.state != GameWorld.State.PLAYING or not w.player_alive:
		return Vector2.ZERO
	var px := w.player_x
	var sh := w.ship()
	var shot_speed := float(sh["speed"])
	var guided := bool(sh["guided"])
	# Levels 14–16: only figures of the lowest colour stage can be advanced, every other hit is locked.
	var stage := 99
	if w.hit_rule() == LevelData.Hit.COLOR_LOCK:
		for e in w.enemies:
			stage = mini(stage, e.stage)
	var tgt: GameWorld.Enemy = null
	for e in w.enemies:
		if stage != 99 and e.stage != stage:
			continue
		if tgt == null or e.y > tgt.y + 1.0 or (absf(e.y - tgt.y) <= 1.0 and absf(e.x - px) < absf(tgt.x - px)):
			tgt = e
	var target_x := px
	# The ship's own salvo in flight steers with the ship (a TWIN's shots follow the twin, SPEC §19.3).
	var own := _own_shot(w)
	if tgt != null:
		var fly_from := LevelData.SALVO_Y
		if guided and own != null:
			fly_from = own.y
		var t := maxf(fly_from - tgt.y, 0.0) / shot_speed
		target_x = _predict_x(w, tgt, t)
		if guided and own != null:
			target_x -= own.offset
	else:
		target_x = LevelData.player_start_x(w.width)
	# Landing points of incoming fireballs (computed once). A slanted fireball sweeps sideways while it
	# crosses the ship's hit band (|dy| < 15), so its danger zone is wider.
	var threats := PackedVector3Array()   # (x at the player line, time until it gets there, danger half-width)
	for b in w.bullets:
		if b.vy <= 0.0:
			continue
		var t_hit := (LevelData.PLAYER_Y - b.y) / b.vy
		if t_hit < -LevelData.PLAYER_HIT_DY / b.vy or t_hit > 1.2:
			continue
		threats.append(Vector3(b.x + b.vx * maxf(t_hit, 0.0), t_hit,
			DANGER_DX + absf(b.vx) * LevelData.PLAYER_HIT_DY / b.vy))
	# Pick the reachable position with the best trade-off between aiming and danger.
	var best := px
	var best_cost := INF
	var n := _grid_size(w, CANDIDATES)
	for i in n:
		var cand := lerpf(LevelData.PLAYER_MIN_X, _ship_max(w), float(i) / float(n - 1))
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


## The oldest projectile of the ship's own salvos in flight (not the TWIN's), or null.
static func _own_shot(w: GameWorld) -> GameWorld.Shot:
	for s in w.shots:
		if not s.twin:
			return s
	return null


## Attract mode (AttractDirector): Vector2(move_axis, fire) like decide(), but played for the camera –
## - it aims at the countable figure whose hit comes soonest, leading it along its known path (_future_x);
## - the trigger is pressed only for a NEW salvo (none in flight), only while allow_fire, and only if that
##   salvo is predicted to land a hit that counts (unguided: _salvo_hits; guided: the target is within steering
##   reach) – a salvo wasted on a miss costs up to 2.5 s;
## - dodging comes first: it only moves within the escape set (_escape_target), i.e. it never goes where a fireball
##   now in the air could still catch it; aiming only chooses within that set (fallback without escape: _danger);
## - seek_hit = true (vulnerable window): no dodging, it steers under the nearest falling fireball.
static func demo(w: GameWorld, allow_fire: bool, seek_hit: bool) -> Vector2:
	if w.state != GameWorld.State.PLAYING or not w.player_alive:
		return Vector2.ZERO
	var px := w.player_x
	var sh := w.ship()
	var speed := float(sh["speed"])
	var guided := bool(sh["guided"])
	var stage := _countable_stage(w)
	var steering := guided and not w.shots.is_empty()
	# Aim: the countable figure whose hit comes soonest. Unguided (or a new guided salvo): stand where a salvo
	# fired now meets it; a guided salvo in flight: steer it onto a figure still above it.
	var target_x := LevelData.player_start_x(w.width)
	var best_t := INF
	var reach := false
	for e in w.enemies:
		if stage >= 0 and e.stage != stage:
			continue
		var from_y := w.shots[0].y if steering else LevelData.SALVO_Y
		if from_y - e.y < -LevelData.HIT_DY * e.scale:
			continue   # already below the guided salvo
		var t := maxf(from_y - e.y, 0.0) / speed
		var x := _future_x(w, e, t)
		if steering:
			x -= w.shots[0].offset
		var move := absf(x - px) / LevelData.PLAYER_SPEED
		var cost := move + t
		if steering and move > t:
			cost += 100.0   # out of steering reach
		if cost < best_t:
			best_t = cost
			target_x = x
			reach = move <= t * 0.8
	var fire := false
	if allow_fire and w.shots.is_empty() and best_t < INF:
		fire = reach if guided else _salvo_hits(w, px, sh, stage)
	if seek_hit:
		return Vector2(_seek_axis(w), 1.0 if fire else 0.0)
	var aim := clampf(target_x, LevelData.PLAYER_MIN_X, _ship_max(w))
	# Dodge: stay inside the escape set – the positions from which the ship can still avoid every fireball in the
	# air (_escape_set) – heading for the aim point. AttractDirector withdraws any salvo that would leave the
	# invincible ship no escape, so the ship is always inside.
	var to := _escape_target(w, aim)
	if not is_nan(to):
		# Full speed if needed to be there one escape step from now (the escape set moves with the fireballs).
		return Vector2(clampf((to - px) / (LevelData.PLAYER_SPEED * DEMO_ESCAPE_DT), -1.0, 1.0), 1.0 if fire else 0.0)
	# Fallback (no escape left): the cheapest position = distance to the aim point + danger (_danger). The
	# candidates are tried in the order of their distance to the aim point (the aim point, then the grid outwards
	# from it), so the search stops as soon as the distance alone costs more than the best position found.
	var threats := _threats(w, DEMO_HORIZON)
	var n := _grid_size(w, DEMO_CANDIDATES)
	var grid := (_ship_max(w) - LevelData.PLAYER_MIN_X) / float(n - 1)
	var lo := clampi(floori((aim - LevelData.PLAYER_MIN_X) / grid), 0, n - 1)
	var hi := lo + 1
	var cand := aim
	var best := aim
	var best_cost := INF
	while true:
		var dist := absf(cand - aim) / 260.0
		if dist >= best_cost:
			break
		var cost := dist + _danger(threats, px, cand)
		if cost < best_cost:
			best_cost = cost
			best = cand
		if lo < 0 and hi >= n:
			break
		var x_lo := LevelData.PLAYER_MIN_X + grid * lo
		var x_hi := LevelData.PLAYER_MIN_X + grid * hi
		if hi >= n or (lo >= 0 and aim - x_lo <= x_hi - aim):
			cand = x_lo
			lo -= 1
		else:
			cand = x_hi
			hi += 1
	return Vector2(clampf((best - px) / 18.0, -1.0, 1.0), 1.0 if fire else 0.0)


## True while the ship can still avoid every fireball in the air (attract mode, see _escape_target).
static func can_escape(w: GameWorld) -> bool:
	return not w.player_alive or not is_nan(_escape_target(w, w.player_x))


## Where the ship should head to stay clear of every fireball in the air while it approaches `aim`: the point of
## the escape set one step ahead (_escape_set) that it can reach within that step and that is closest to `aim`
## (DEMO_ESCAPE_EDGE inside the ends of its range). NAN if there is none (no escape).
static func _escape_target(w: GameWorld, aim: float) -> float:
	var s1 := _escape_set(w)
	var px := w.player_x
	var reach := LevelData.PLAYER_SPEED * DEMO_ESCAPE_DT
	var best := NAN
	var best_d := INF
	for i in range(0, s1.size(), 2):
		if s1[i + 1] < px - reach or s1[i] > px + reach:
			continue
		var lo := s1[i] + DEMO_ESCAPE_EDGE
		var hi := s1[i + 1] - DEMO_ESCAPE_EDGE
		if lo > hi:
			lo = (s1[i] + s1[i + 1]) * 0.5
			hi = lo
		var x := clampf(aim, lo, hi)
		if absf(x - aim) < best_d:
			best_d = absf(x - aim)
			best = x
	return best


## The escape set S1 (interval list [a0, b0, a1, b1, …]): the ship positions one step of DEMO_ESCAPE_DT from now
## from which it can avoid every fireball now in the air, and which it can reach from where it is without a
## fireball touching it. Computed backwards over DEMO_ESCAPE_HORIZON (longer than any fireball needs to reach the
## ship) in steps of DEMO_ESCAPE_DT: B_k = the x ranges the fireballs sweep (± DEMO_ESCAPE_DX) while they cross
## the ship's height band in step k; S_K = the whole range, S_k = dilate(S_{k+1} \ B_k, speed·dt) \ B_k; the
## result is S_1 \ B_0. A blocked range is wider than one step of the ship, so it cannot be jumped.
static func _escape_set(w: GameWorld) -> PackedFloat64Array:
	var dt := DEMO_ESCAPE_DT
	var steps := ceili(DEMO_ESCAPE_HORIZON / dt)
	var blocked: Array[PackedFloat64Array] = []
	blocked.resize(steps)
	# The fireballs of a salvo fly side by side (same height and velocity, < 2·DEMO_ESCAPE_DX apart, in order):
	# one row [x_first, x_last] each.
	var rows := PackedFloat64Array()   # x_first, x_last, y, vx, vy per row
	for b in w.bullets:
		if b.vy <= 0.0:
			continue
		var n := rows.size()
		if n > 0 and b.y == rows[n - 3] and b.vx == rows[n - 2] and b.vy == rows[n - 1] \
				and b.x >= rows[n - 5] and b.x - rows[n - 4] < 2.0 * DEMO_ESCAPE_DX:
			rows[n - 4] = maxf(rows[n - 4], b.x)
		else:
			rows.append_array([b.x, b.x, b.y, b.vx, b.vy])
	var band := LevelData.PLAYER_HIT_DY + DEMO_MARGIN_Y
	for r in range(0, rows.size(), 5):
		var vx := rows[r + 3]
		var vy := rows[r + 4]
		var t0 := maxf((LevelData.PLAYER_Y - band - rows[r + 2]) / vy, 0.0)
		var t1 := (LevelData.PLAYER_Y + band - rows[r + 2]) / vy
		if t1 <= 0.0 or t0 >= DEMO_ESCAPE_HORIZON:
			continue
		for k in range(int(t0 / dt), mini(int(t1 / dt), steps - 1) + 1):
			# The row sweeps sideways during the step.
			var da := vx * maxf(t0, k * dt)
			var db := vx * minf(t1, (k + 1) * dt)
			blocked[k].append(rows[r] + minf(da, db) - DEMO_ESCAPE_DX)
			blocked[k].append(rows[r + 1] + maxf(da, db) + DEMO_ESCAPE_DX)
	var x_max := _ship_max(w)
	var s := PackedFloat64Array([LevelData.PLAYER_MIN_X, x_max])
	for k in range(steps - 1, -1, -1):
		if not blocked[k].is_empty():
			s = _subtract(s, blocked[k])
		if k == 0 or s.is_empty():
			break
		s = _dilate(s, LevelData.PLAYER_SPEED * dt, x_max)
		if not blocked[k].is_empty():
			s = _subtract(s, blocked[k])
	return s


## Interval list `s` without the ranges in `cut` ([c0, e0, c1, e1, …], unsorted, may overlap).
static func _subtract(s: PackedFloat64Array, cut: PackedFloat64Array) -> PackedFloat64Array:
	var cur := s
	for j in range(0, cut.size(), 2):
		var c := cut[j]
		var e := cut[j + 1]
		var out := PackedFloat64Array()
		for i in range(0, cur.size(), 2):
			var a := cur[i]
			var b := cur[i + 1]
			if e <= a or c >= b:
				out.append(a)
				out.append(b)
				continue
			if a < c:
				out.append(a)
				out.append(c)
			if e < b:
				out.append(e)
				out.append(b)
		cur = out
		if cur.is_empty():
			break
	return cur


## Interval list `s` (sorted) widened by `d` on both sides, clipped to the ship's range [PLAYER_MIN_X, x_max],
## overlaps merged.
static func _dilate(s: PackedFloat64Array, d: float, x_max: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for i in range(0, s.size(), 2):
		var a := maxf(s[i] - d, LevelData.PLAYER_MIN_X)
		var b := minf(s[i + 1] + d, x_max)
		if not out.is_empty() and a <= out[out.size() - 1]:
			out[out.size() - 1] = maxf(out[out.size() - 1], b)
		else:
			out.append(a)
			out.append(b)
	return out


## Levels 14–16: only figures of the lowest colour stage can be advanced, every other hit is locked (−1: any).
static func _countable_stage(w: GameWorld) -> int:
	if w.hit_rule() != LevelData.Hit.COLOR_LOCK or w.enemies.is_empty():
		return -1
	var stage := 99
	for e in w.enemies:
		stage = mini(stage, e.stage)
	return stage


## Where `e` will be in `t` game seconds: its course with the limit turns AND its pending random direction
## change (dir_timer, levels ≥ 10); later random changes and early stack-breaking turns are unknown.
static func _future_x(w: GameWorld, e: GameWorld.Enemy, t: float) -> float:
	var x := e.x
	var dir := e.dir
	var left := t
	var turn := e.dir_timer
	var lo := GameWorld.min_x(e.scale, w.width)
	var hi := GameWorld.max_x(e.scale, w.width)
	var v := maxf(w.enemy_speed, 1e-6)
	for i in 8:
		var wall := absf((hi if dir > 0.0 else lo) - x) / v
		var seg := minf(left, minf(wall, turn))
		x = clampf(x + dir * seg * v, lo, hi)
		left -= seg
		if left <= 1e-9:
			break
		if turn <= wall:
			turn = INF   # the next random change comes 1.2–3.2 s later (unknown)
		else:
			turn -= seg
		dir = -dir
	return x


## Lane height of `e` in `t` game seconds (GameWorld._lane_y, the oscillation runs on the combat clock).
static func _future_y(w: GameWorld, e: GameWorld.Enemy, t: float) -> float:
	return LevelData.LANE_Y[e.lane] + w.osc_amplitude * sin(e.osc_phase
		+ TAU * LevelData.ENEMY_OSC_HZ * (w.combat_time() + t))


## True if an unguided salvo fired now from `px` will land a hit that counts. Each projectile leaves in the next
## sub-step and flies up at its speed; it passes a figure's (oscillating) height at a time found by two
## refinements, and it hits if the figure's predicted x is then close enough (checked across the overlap). A
## non-piercing projectile is used up by the FIRST figure it touches (a locked one too), a piercing one flies on.
static func _salvo_hits(w: GameWorld, px: float, sh: Dictionary, stage: int) -> bool:
	var speed := float(sh["speed"])
	var piercing := bool(sh["piercing"])
	var lag := LevelData.SIM_STEP
	for off in ShipData.shot_offsets(w.ship_id):
		var x := px + off
		var first_t := INF
		var first_counts := false
		for e in w.enemies:
			var t := lag + maxf(LevelData.SALVO_Y - e.y, 0.0) / speed
			for k in 2:
				t = lag + maxf(LevelData.SALVO_Y - _future_y(w, e, t), 0.0) / speed
			var half := LevelData.HIT_DY * e.scale / speed * 0.8
			var reach := LevelData.HIT_DX * e.scale * DEMO_AIM_DX
			if absf(x - _future_x(w, e, t)) >= reach and absf(x - _future_x(w, e, t - half)) >= reach \
					and absf(x - _future_x(w, e, t + half)) >= reach:
				continue
			var counts := stage < 0 or e.stage == stage
			if piercing and counts:
				return true
			if t < first_t:
				first_t = t
				first_counts = counts
		if first_counts:
			return true
	return false


## The fireballs that cross the ship's height band (plus DEMO_MARGIN_Y) within `horizon` game seconds:
## [x, vx, t_in, t_out] per fireball.
static func _threats(w: GameWorld, horizon: float) -> PackedFloat64Array:
	var band := LevelData.PLAYER_HIT_DY + DEMO_MARGIN_Y
	var out := PackedFloat64Array()
	for b in w.bullets:
		if b.vy <= 0.0:
			continue
		var t0 := maxf((LevelData.PLAYER_Y - band - b.y) / b.vy, 0.0)
		var t1 := minf((LevelData.PLAYER_Y + band - b.y) / b.vy, horizon)
		if t0 < t1:
			out.append_array([b.x, b.vx, t0, t1])
	return out


## Danger of the plan "fly from `px` to `cand` at full speed, then stay there" against the `threats`:
## 0 if every fireball keeps DEMO_CLEAR_X away (horizontally, while it crosses the ship's height); 0–100 for a
## closer pass (the closer, the worse); 1000–1200 if one would touch the hit box plus DEMO_HIT_MARGIN (the
## sooner, the worse – a late one may still be dodged later).
static func _danger(threats: PackedFloat64Array, px: float, cand: float) -> float:
	var s := signf(cand - px)
	var arrive := absf(cand - px) / LevelData.PLAYER_SPEED
	var hard := LevelData.PLAYER_HIT_DX + DEMO_HIT_MARGIN
	var clear := INF
	var touch := INF
	for i in range(0, threats.size(), 4):
		var t0 := threats[i + 2]
		var t1 := threats[i + 3]
		# dx(t) = fireball x − ship x is linear while the ship flies and while it stays.
		if t0 < arrive:
			var d0 := threats[i] - px
			var k := threats[i + 1] - s * LevelData.PLAYER_SPEED
			var v := minf(t1, arrive)
			clear = minf(clear, _min_abs(d0, k, t0, v))
			touch = minf(touch, _enter(d0, k, t0, v, hard))
		if t1 > arrive:
			var d0 := threats[i] - cand
			var u := maxf(t0, arrive)
			clear = minf(clear, _min_abs(d0, threats[i + 1], u, t1))
			touch = minf(touch, _enter(d0, threats[i + 1], u, t1, hard))
	if touch < INF:
		return 1000.0 + (DEMO_HORIZON - touch) * 100.0
	if clear < DEMO_CLEAR_X:
		return 100.0 * (DEMO_CLEAR_X - clear) / (DEMO_CLEAR_X - hard)
	return 0.0


## min |d0 + k·t| over t in [u, v].
static func _min_abs(d0: float, k: float, u: float, v: float) -> float:
	var du := d0 + k * u
	var dv := d0 + k * v
	return 0.0 if du * dv <= 0.0 else minf(absf(du), absf(dv))


## Earliest t in [u, v] with |d0 + k·t| < r, INF if there is none.
static func _enter(d0: float, k: float, u: float, v: float, r: float) -> float:
	var du := d0 + k * u
	if absf(du) < r:
		return u
	if (du > 0.0 and k >= 0.0) or (du < 0.0 and k <= 0.0):
		return INF
	var t := ((r if du > 0.0 else -r) - d0) / k
	return t if t <= v else INF


## Attract mode: axis towards the point where the nearest falling fireball crosses the player line – the first
## one to arrive among those the ship can still get under, else the closest one. Without any fireball it waits
## under the lowest enemy, whose next salvo comes down there.
static func _seek_axis(w: GameWorld) -> float:
	var px := w.player_x
	var target := px
	var best := INF
	for b in w.bullets:
		if b.vy <= 0.0:
			continue
		var t := (LevelData.PLAYER_Y - b.y) / b.vy
		if t < -LevelData.PLAYER_HIT_DY / b.vy:
			continue   # already below the ship
		var x := b.x + b.vx * maxf(t, 0.0)
		if x < LevelData.PLAYER_MIN_X - LevelData.PLAYER_HIT_DX or x > _ship_max(w) + LevelData.PLAYER_HIT_DX:
			continue   # lands where the ship cannot be
		var reach := maxf(absf(x - px) - LevelData.PLAYER_HIT_DX * 0.5, 0.0) / LevelData.PLAYER_SPEED
		var cost := maxf(t, 0.0) if reach <= maxf(t, 0.0) else 100.0 + absf(x - px)
		if cost < best:
			best = cost
			target = x
	if best == INF:
		var low: GameWorld.Enemy = null
		for e in w.enemies:
			if low == null or e.y > low.y:
				low = e
		if low != null:
			target = low.x
	return clampf((target - px) / 18.0, -1.0, 1.0)


static func _predict_x(w: GameWorld, e: GameWorld.Enemy, t: float) -> float:
	var x := e.x
	var dir := e.dir
	var remaining := t * w.enemy_speed
	var lo := GameWorld.min_x(e.scale, w.width)
	var hi := GameWorld.max_x(e.scale, w.width)
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
static func _risk(threats: PackedVector3Array, px: float, cand: float) -> float:
	var travel := absf(cand - px) / LevelData.PLAYER_SPEED
	var lo := minf(px, cand) - 18.0
	var hi := maxf(px, cand) + 18.0
	var risk := 0.0
	for th in threats:
		var d := absf(th.x - cand)
		if d < th.z:
			risk += (1.0 - d / th.z) * (2.0 if th.y < travel + 0.25 else 1.0) * (1.6 - th.y)
		# Crossing a fireball's landing spot on the way there is dangerous too.
		if th.y < travel and th.x > lo and th.x < hi:
			if absf(absf(th.x - px) / LevelData.PLAYER_SPEED - th.y) < 0.18:
				risk += 1.5
	return risk
