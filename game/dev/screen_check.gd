extends Node
## DEV ONLY – frame-driven integration check of the real GameScreen in the scene tree (autoplay bot):
##   godot --headless --fixed-fps 60 --path game res://dev/screen_check.tscn
## Scenarios: level completes + Run.last_level_result; bonus level + Run.last_bonus_result; game over;
## respawn with no play time; finished emitted exactly once. Prints PASS/FAIL and exits with 0/1.

const GameScreenScript := preload("res://scripts/game/game_screen.gd")

var _fails: Array[String] = []
var _gs: Node
var _result := ""
var _emits := 0


func _ready() -> void:
	_run_all()


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)
		print("  FAIL ", msg)


func _start(level: int, difficulty: int, ship: int, flags: Dictionary) -> void:
	Run.start_new(difficulty, ship, level)
	Run.dev_flags = flags
	_result = ""
	_emits = 0
	_gs = GameScreenScript.new()
	_gs.setup({"level": level})
	_gs.finished.connect(func(r: String, _d: Dictionary) -> void:
		_result = r
		_emits += 1)
	add_child(_gs)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
		if _result != "":
			return


func _stop() -> void:
	_gs.queue_free()
	await get_tree().process_frame


func _run_all() -> void:
	# 1) Level 1 completes with the bot.
	_start(1, 1, 0, {"autoplay": true, "invincible": true})
	await _frames(60 * 120)
	_check(_result == "completed", "level 1 completed (got '%s')" % _result)
	var r := Run.last_level_result
	_check(r.get("level") == 1 and r.get("completion_bonus") == 100 and r.has("extra_life") and r.has("flawless"),
		"last_level_result %s" % str(r))
	_check(Run.score == 10 * 10 + 100, "score synced (%d)" % Run.score)
	var w: GameWorld = _gs.world
	_check(absf(Run.active_time - w.active_time) < 1e-9 and Run.active_time > 1.0, "time synced")
	await _frames(90)
	_check(_emits == 1, "finished exactly once (%d)" % _emits)
	await _stop()
	print("level 1: score=%d time=%.2f" % [Run.score, Run.active_time])

	# 2) Bonus level.
	_start(13, 1, 2, {"autoplay": true, "invincible": true})
	await _frames(60 * 240)
	_check(_result == "completed", "bonus completed (got '%s')" % _result)
	var b := Run.last_bonus_result
	_check(b.has("remaining") and b.has("factor") and b.has("bonus") and b.has("extra_life"), "bonus keys %s" % str(b))
	_check(int(b.get("factor", 0)) == 300 and int(b.get("bonus", -1)) == int(b.get("remaining", -2)) * 300, "bonus value")
	_check(Run.score == int(b.get("bonus", -1)), "no kill score in the bonus level")
	print("bonus: %s hits=%d" % [str(b), (_gs.world as GameWorld).destroyed])
	await _stop()

	# 3) Game over (EXPERT, one life).
	_start(4, 3, 0, {})
	await _frames(130)
	w = _gs.world
	_check(w.state == GameWorld.State.PLAYING, "playing after intro")
	w.add_bullet(w.player_x, LevelData.PLAYER_Y, 0.0, 0.0)
	await _frames(2)
	_check(Run.lives == 0, "lives synced on hit")
	await _frames(60 * 5)
	_check(_result == "game_over", "game over (got '%s')" % _result)
	await _stop()

	# 4) Respawn: no play time, run continues.
	_start(2, 1, 1, {})
	await _frames(130)
	w = _gs.world
	w.add_bullet(w.player_x, LevelData.PLAYER_Y, 0.0, 0.0)
	await _frames(2)
	_check(Run.lives == 2 and w.state == GameWorld.State.RESPAWN, "respawn state")
	var t := Run.active_time
	await _frames(60)
	_check(absf(Run.active_time - t) < 1e-9, "no play time during respawn")
	await _frames(60)
	_check(w.state == GameWorld.State.PLAYING and _result == "", "respawned")
	await _stop()

	# 5) Bot survival smoke test without invincibility (information only).
	_start(5, 1, 0, {"autoplay": true})
	await _frames(60 * 40)
	print("bot level 5 (40 s, NORMAL): lives=%d result='%s' destroyed=%d" % [Run.lives, _result, (_gs.world as GameWorld).destroyed])
	await _stop()

	print("SCREEN CHECK: ", "PASS" if _fails.is_empty() else "FAIL (%d)" % _fails.size())
	get_tree().quit(0 if _fails.is_empty() else 1)
