extends Node
## DEV ONLY (excluded from export via export filter "dev/*").
## Starts a level directly with the real GameScreen and saves viewport screenshots.
## Run deterministic captures with --fixed-fps so every frame advances exactly 1/60 s:
##   xvfb-run -a -s "-screen 0 1280x960x24" godot --rendering-driver opengl3 --audio-driver Dummy --fixed-fps 60 \
##     --path game res://dev/capture.tscn -- --level=7 --ship=0 --difficulty=1 --autoplay --invincible \
##     --out=/abs/path/prefix --at=3.0,6.5 [--when=split --delay=0.15] [--seed=3] [--quit-after=20] [--pause-at=4]
## --hit-at=T forces a player hit at T seconds.
## --display=<0..4>: display mode (SPEC §18): 0 classic 4:3 (screenshot = window size), 1 / 2 / 4 the 16:9 modes and 3 the
## 16:10 Steam Deck mode (1152 px playfield, screenshot 1280×800); 1 / 2 / 4 have the
## 1280 px wide playfield (screenshot = 1920×1080 / 2560×1440 / 1280×720). Without it the stored mode counts.
## --at: capture times in seconds since start. --when: capture once when a condition first holds
## (split | explosion | bullets | respawn | clearing | stage | flash | materialize | powerup | powerup_warn |
## powerup_used | absorb) plus --delay seconds.
## Power-ups (SPEC §19.3): --powerups turns them on for the run; --powerup-at=T triggers the power-up at T seconds
## (retried until it can; the autoplay bot then leaves the button alone – without --powerup-at it triggers it at
## once). Two players (SPEC §19.2): --players=2 [--player=K] [--ship2=S] starts a match and makes player K (0 / 1)
## current (HUD captions in the player colour); --score applies to that player.

const GameScreenScript := preload("res://scripts/game/game_screen.gd")

var _args := {}
var _times: Array[float] = []
var _t := 0.0
var _screen: Node
var _when := ""
var _when_at := -1.0
var _shot_n := 0
var _quit_after := 30.0
var _pause_at := -1.0
var _hit_at := -1.0
var _powerup_at := -1.0
var _busy := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := a.trim_prefix("--")
		var eq := s.find("=")
		if eq >= 0:
			_args[s.substr(0, eq)] = s.substr(eq + 1)
		else:
			_args[s] = true
	if _args.has("seed"):
		seed(int(_args["seed"]))
	for p in String(_args.get("at", "")).split(",", false):
		_times.append(float(p))
	_times.sort()
	_when = String(_args.get("when", ""))
	_quit_after = float(_args.get("quit-after", 30.0))
	_pause_at = float(_args.get("pause-at", -1.0))
	_hit_at = float(_args.get("hit-at", -1.0))
	_powerup_at = float(_args.get("powerup-at", -1.0))
	_apply_display()
	var diff := int(_args.get("difficulty", 1))
	var ship := int(_args.get("ship", 0))
	var lvl := int(_args.get("level", 1))
	if int(_args.get("players", 1)) == 2:
		Run.start_match(diff, [ship, int(_args.get("ship2", ship))], [[], []], lvl, _args.has("powerups"))
		Run.switch_to(clampi(int(_args.get("player", 0)), 0, 1))
	else:
		Run.start_new(diff, ship, lvl, _args.has("powerups"))
	if _args.has("score"):
		Run.score = int(_args["score"])
	Run.dev_flags = {"invincible": _args.has("invincible"), "autoplay": _args.has("autoplay"),
		"manual_powerup": _powerup_at >= 0.0}
	_start(Run.level)


## --display=<n>: the Display autoload reads the same argument (a forced mode for this run, never stored); it is
## set here as well so the capture does not depend on that, then canvas and window are applied before the
## GameScreen is built (it takes its playfield width from Display at setup).
func _apply_display() -> void:
	if _args.has("display"):
		var m := clampi(int(_args["display"]), 0, Display.Mode.size() - 1)
		if Display.mode() != m:
			Display.set("forced_mode", m)
		if Display.mode() != m:
			push_warning("capture: Display does not support --display=%d here" % m)
		Display.apply()
	print("display mode %d (%s): logical %s" % [Display.mode(), Display.MODE_NAMES[Display.mode()], Display.logical_size()])


func _start(n: int) -> void:
	_screen = GameScreenScript.new()
	_screen.setup({"level": n})
	_screen.finished.connect(_on_finished)
	add_child(_screen)


func _on_finished(result: String, _d: Dictionary) -> void:
	print("finished: ", result, " score=", Run.score, " lives=", Run.lives, " time=", Run.active_time,
		" result=", Run.last_level_result, " bonus=", Run.last_bonus_result)
	if _args.has("chain") and result == "completed" and Run.level < LevelData.LAST_LEVEL:
		_screen.queue_free()
		_start(Run.level + 1)
	else:
		get_tree().quit()


func _process(delta: float) -> void:
	if _busy:
		return
	_t += delta
	if _pause_at >= 0.0 and _t >= _pause_at and _screen and is_instance_valid(_screen) and not _screen.paused:
		_screen._set_paused(true)
	if _hit_at >= 0.0 and _t >= _hit_at and _screen and is_instance_valid(_screen):
		_hit_at = -1.0
		var w: GameWorld = _screen.world
		w.add_bullet(w.player_x, LevelData.PLAYER_Y, 0.0, 0.0)   # forced player hit (dev)
	if _powerup_at >= 0.0 and _t >= _powerup_at and _screen and is_instance_valid(_screen):
		if (_screen.world as GameWorld).activate_powerup():
			_powerup_at = -1.0
			print("power-up triggered at %.2f" % _t)
	if _when != "" and _when_at < 0.0 and _screen and is_instance_valid(_screen) and _check(_screen.world):
		_when_at = _t + float(_args.get("delay", 0.0))
		print("condition '%s' at %.2f" % [_when, _t])
	if _when_at >= 0.0 and _t >= _when_at:
		_when_at = INF
		_capture("when_" + _when)
	elif not _times.is_empty() and _t >= _times[0]:
		var at: float = _times.pop_front()
		_capture("t%05.1f" % at)
	elif _t >= _quit_after:
		get_tree().quit()


func _check(w: GameWorld) -> bool:
	match _when:
		"split":
			for e in w.enemies:
				if e.is_child:
					return true
		"explosion":
			return not w.explosions.is_empty()
		"bullets":
			return w.bullets.size() >= int(_args.get("min", 6))
		"respawn":
			return w.state == GameWorld.State.RESPAWN
		"clearing":
			return w.state == GameWorld.State.CLEARING
		"stage":
			for e in w.enemies:
				if e.stage > 0:
					return true
		"flash":
			for e in w.enemies:
				if e.flash > 0.0:
					return true
		"materialize":
			for e in w.enemies:
				if e.materialize() < 0.6 and e.materialize() > 0.2:
					return true
		"powerup":
			return w.powerup_state == GameWorld.PowerState.ACTIVE
		"powerup_warn":
			return w.powerup_state == GameWorld.PowerState.ACTIVE and w.powerup_left < 2.0
		"powerup_used":
			return w.powerup_state == GameWorld.PowerState.USED
		"absorb":
			return float(_screen._player.shield_flash) > 0.8
	return false


func _capture(tag: String) -> void:
	_busy = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var prefix := String(_args.get("out", "/tmp/capture"))
	var path := "%s_%s.png" % [prefix, tag]
	img.save_png(path)
	print("saved ", path)
	_shot_n += 1
	_busy = false
	if _times.is_empty() and (_when == "" or _when_at == INF) and not _args.has("keep"):
		get_tree().quit()
