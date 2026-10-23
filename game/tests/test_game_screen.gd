extends TestBase
## GameScreen integration tests (docs/SPEC.md §9, §14, §17.1). Run before the SceneTree is live (see
## run_tests.gd): the screen is driven by hand (_ready / _process) and freed afterwards. The view nodes
## never enter the tree here (their _ready does not run), so the screen runs with its view update stubbed
## out – everything else (input/bot, world, events → audio/FX queues, Run sync, end handling) is real.

const GameScreenScript := preload("res://scripts/game/game_screen.gd")


class LogicOnlyScreen extends GameScreenScript:
	func _update_views(_dt: float, _game_dt: float) -> void:
		pass


func _screen(level: int, flags: Dictionary) -> Node2D:
	if (InputRouter.get("_down") as Dictionary).is_empty():
		InputRouter._ready()
	Run.start_new(1, 0, level)
	Run.dev_flags = flags
	var gs: Node2D = LogicOnlyScreen.new()
	gs.setup({"level": level})
	gs._ready()
	return gs


func _cleanup(gs: Node) -> void:
	gs.free()
	Run.dev_flags = {}
	AudioManager.stop_music()


## SPEC §14: title music plays in ship select and stops for gameplay – the level intro banner is silent,
## the game music starts with the combat.
func test_title_music_stops_when_the_level_starts() -> void:
	AudioManager.play_title_music()
	check(AudioManager.is_title_music_playing())
	var gs := _screen(1, {"invincible": true})
	check(not AudioManager.is_title_music_playing(), "title music stopped at the game screen")
	check(not AudioManager.is_game_music_active(), "no game music during the intro banner")
	var w: GameWorld = gs.get("world")
	var guard := 0
	while w.state == GameWorld.State.INTRO and guard < 200:
		gs._process(1.0 / 60.0)
		guard += 1
	check(not AudioManager.is_title_music_playing())
	check(AudioManager.is_game_music_active(), "game music starts with the combat")
	_cleanup(gs)


## SPEC §1/§9: play time is REAL seconds. Long frames (hitches, slow machines) are simulated and counted in
## full; only a stall beyond GameScreen.MAX_FRAME_DT counts as an interruption.
func test_play_time_counts_long_frames_in_full() -> void:
	var gs := _screen(1, {"invincible": true})
	var w: GameWorld = gs.get("world")
	var guard := 0
	while w.state == GameWorld.State.INTRO and guard < 100:
		gs._process(0.3)
		guard += 1
	check_eq(w.state, GameWorld.State.PLAYING)
	var t0 := Run.active_time
	for i in 10:
		gs._process(0.3)   # ≈ 3 fps
	check_near(Run.active_time - t0, 3.0, 1e-6, "10 frames of 0.3 s = 3.0 s play time")
	var t1 := Run.active_time
	gs._process(3600.0)   # suspend / debugger break
	check_near(Run.active_time - t1, GameScreenScript.MAX_FRAME_DT, 1e-6, "a stall is not play time")
	_cleanup(gs)


## The autoplay bot (dev) re-decides inside long frames, so it keeps working on slow machines.
func test_autoplay_with_long_frames_plays_the_level() -> void:
	var gs := _screen(1, {"autoplay": true, "invincible": true})
	var w: GameWorld = gs.get("world")
	var guard := 0
	while not w.is_finished() and guard < 400:
		gs._process(0.25)
		guard += 1
	check_eq(w.state, GameWorld.State.COMPLETE, "autoplay finishes level 1 with 0.25 s frames")
	check(w.destroyed >= w.total)
	_cleanup(gs)
