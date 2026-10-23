extends SceneTree
## DEV ONLY: rough cost of the simulation and the autopilot.
const Autopilot := preload("res://scripts/game/autopilot.gd")

func _initialize() -> void:
	for lvl in [1, 17, 20]:
		var w := GameWorld.new(lvl, 1, 3, 3, 5)
		w.invincible = true
		var t0 := Time.get_ticks_usec()
		var t_bot := 0
		for i in 1800:
			var b0 := Time.get_ticks_usec()
			var d: Vector2 = Autopilot.decide(w)
			t_bot += Time.get_ticks_usec() - b0
			w.update(1.0 / 60.0, d.x, d.y > 0.5)
			w.events.clear()
		var total := Time.get_ticks_usec() - t0
		print("level %d: %.3f ms/frame total, bot %.3f ms/frame, enemies %d bullets %d destroyed %d" % [lvl, total / 1800000.0, t_bot / 1800000.0, w.enemies.size(), w.bullets.size(), w.destroyed])
	quit()
