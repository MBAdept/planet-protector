extends TestBase
## Review of the attract mode (docs/SPEC.md §11.1): failing tests for the defects found in the review.
## Every demo is simulated headless exactly like test_attract.gd (director + real GameWorld, 60 fps frames),
## but the world events are checked in EVENT ORDER, not per frame. The fixed seeds were found with the
## current game_world.gd (fair spawning / stack breaking of the parallel package).

const STEP := 1.0 / 60.0


## Plays a whole demo. Returns per-demo facts:
##   "salvos_after_n": shot_fired events that come AFTER the N-th counted hit in event order (same frame included)
##   "through": ids of enemy fireballs that overlapped the hit box of the alive, still invincible ship
func _play(d: AttractDirector) -> Dictionary:
	var w := d.make_world()
	var hits := 0
	var salvos_after_n := 0
	var through := {}
	var guard := 0
	while not d.is_over() and guard < int(AttractDirector.DURATION_MAX * 60.0) + 120:
		guard += 1
		w.events.clear()
		d.play(w, STEP)
		for ev in w.events:
			var ty := String(ev["type"])
			if AttractDirector.HIT_EVENTS.has(ty):
				hits += 1
			elif ty == "shot_fired" and hits >= d.hits_wanted:
				salvos_after_n += 1
		if w.player_alive and w.invincible:
			for b in w.bullets:
				if absf(b.x - w.player_x) < LevelData.PLAYER_HIT_DX and absf(b.y - LevelData.PLAYER_Y) < LevelData.PLAYER_HIT_DY:
					through[b.id] = true
	return {"salvos_after_n": salvos_after_n, "through": through.size(), "hits": hits}


## SPEC §11.1 / build spec 5: "it stops firing after N hits". The director decides the trigger once per 1/60 s
## slice and holds it for the whole slice; GameWorld re-fires the instant the last shot of a salvo is gone, so
## when the N-th hit consumes the last shot a NEW salvo leaves in the same sub-step (and may add up to two more
## hits: 9 hits with N = 6 for seed 403869). test_attract.gd misses it because it compares the hit count at the
## START of the frame. Ship 0 (one non-piercing shot) hits this every time.
func test_no_salvo_after_the_nth_hit_in_event_order() -> void:
	for s in [7919, 39595, 403869]:
		var d := AttractDirector.new(s)
		var r := _play(d)
		check_eq(int(r["salvos_after_n"]), 0, "seed %d (level %d, ship %d, N=%d, hits %d): salvos fired after the N-th hit"
			% [s, d.level, d.ship_id, d.hits_wanted, int(r["hits"])])
	for lvl in [1, 5, 9]:
		var d := AttractDirector.new(1000 + lvl, lvl)
		d.ship_id = 0   # INTERCEPTOR: single non-piercing shot – the N-th hit always empties the salvo
		var r := _play(d)
		check_eq(int(r["salvos_after_n"]), 0, "level %d, ship 0, N=%d: salvos fired after the N-th hit" % [lvl, d.hits_wanted])


## Client request: the ship "lands a few hits" before it is hit itself (build spec 5: N = 3…6). With the slow
## piercing BLASTER (ship 4: one salvo per ≈ 1.9 s) on the fast levels 12 / 15 some demos land only 1–2 hits
## before the vulnerable window, and the ship is hit anyway.
func test_demo_lands_at_least_three_hits_before_the_ship_is_hit() -> void:
	for s in [4712822, 23145126, 348436]:
		var d := AttractDirector.new(s)
		_play(d)
		check(d.hit_time >= 0.0, "seed %d: the ship is hit" % s)
		check(d.hits >= AttractDirector.HITS_MIN, "seed %d (level %d, ship %d, N=%d): only %d hit(s) landed before the ship was hit"
			% [s, d.level, d.ship_id, d.hits_wanted, d.hits])


## The ship is invincible before the vulnerable window only so that the timing holds – a viewer must not see
## an enemy fireball fly through the ship without effect (in the real game that touch is a death). In ≈ 18 %
## of the demos (56 of 300 simulated) at least one fireball crosses the hit box of the invincible ship.
func test_no_fireball_passes_through_the_invincible_ship() -> void:
	for s in [39595, 95028, 293003, 451383]:
		var d := AttractDirector.new(s)
		var r := _play(d)
		check_eq(int(r["through"]), 0, "seed %d (level %d, ship %d): fireballs through the invincible ship" % [s, d.level, d.ship_id])
