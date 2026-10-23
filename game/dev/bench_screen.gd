extends Node
## DEV ONLY: measures the per-frame cost of the GameScreen (headless).
const GameScreenScript := preload("res://scripts/game/game_screen.gd")
var _gs: Node
var _n := 0
var _t0 := 0

func _ready() -> void:
	var lvl := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			lvl = int(a.substr(8))
	Run.start_new(1, 3, lvl)
	Run.dev_flags = {"autoplay": true, "invincible": true}
	var t := Time.get_ticks_msec()
	_gs = GameScreenScript.new()
	_gs.setup({"level": lvl})
	add_child(_gs)
	print("setup ms: ", Time.get_ticks_msec() - t)
	_t0 = Time.get_ticks_usec()

func _process(_d: float) -> void:
	_n += 1
	if _n % 60 == 0:
		var now := Time.get_ticks_usec()
		print("frames %d: %.2f ms/frame  state=%d enemies=%d bullets=%d" % [_n, (now - _t0) / 60000.0, _gs.world.state, _gs.world.enemies.size(), _gs.world.bullets.size()])
		_t0 = now
	if _n >= 600:
		get_tree().quit()
