extends TestBase
## Two-player hotseat run flow (docs/SPEC.md §19.2): the pure RunFlow decisions of the match setup and the match
## (rounds, TURN screens, arrivals / Mars rules once per round, game overs, victory, match result, name-entry
## order, highlighted ranks), simulated through whole matches; the screen variants' texts and layouts; and the REAL
## Main node driven through a setup, a match and its end (screens finished by hand with fake results and Run values)
## – screen sequence, setup args, Run.current per turn and the highscore entries of both categories.
## Like the other screen tests these run before the SceneTree is live: Main and its screens never enter the tree.
## Settings / highscores are redirected to scratch files and restored afterwards (the player's files stay untouched).

const MainScript := preload("res://scripts/main.gd")
const InterlevelScreen := preload("res://scripts/screens/interlevel_screen.gd")
const GameOverScreen := preload("res://scripts/screens/game_over_screen.gd")
const NameEntryScreen := preload("res://scripts/screens/name_entry_screen.gd")
const HighscoresScreen := preload("res://scripts/screens/highscores_screen.gd")
const MarsRulesScreen := preload("res://scripts/screens/mars_rules_screen.gd")

const STEP := 1.0 / 60.0
const ARRIVALS: Array[int] = [3, 6, 9, 12, 16]


## Game over screen without its sound.
class SilentGameOver extends GameOverScreen:
	func sfx(_sfx_name: String) -> void:
		pass


# --- Helpers ---------------------------------------------------------------------------------------
var _saved := {}
var _screens: Array[Node] = []


## Points Settings at scratch files with empty highscore lists; remembers everything a test may change.
func _settings_begin() -> void:
	_saved = {"path": Settings.settings_path, "hs_path": Settings.highscore_path, "players": Settings.players,
		"powerups": Settings.powerups, "difficulty": Settings.difficulty,
		"classic": Settings.get("_highscores").duplicate(true), "pu": Settings.get("_highscores_pu").duplicate(true)}
	var dir := OS.get_user_data_dir().path_join("test_hotseat_flow")
	DirAccess.make_dir_recursive_absolute(dir)
	Settings.settings_path = dir.path_join("settings.cfg")
	Settings.highscore_path = dir.path_join("highscores.json")
	DirAccess.remove_absolute(Settings.settings_path)
	DirAccess.remove_absolute(Settings.highscore_path)
	Settings.set("_highscores", {0: [], 1: [], 2: [], 3: []})
	Settings.set("_highscores_pu", {0: [], 1: [], 2: [], 3: []})


func _settings_end() -> void:
	DirAccess.remove_absolute(Settings.settings_path)
	DirAccess.remove_absolute(Settings.highscore_path)
	Settings.settings_path = _saved["path"]
	Settings.highscore_path = _saved["hs_path"]
	Settings.players = _saved["players"]
	Settings.powerups = _saved["powerups"]
	Settings.difficulty = _saved["difficulty"]
	Settings.set("_highscores", _saved["classic"])
	Settings.set("_highscores_pu", _saved["pu"])
	Run.start_new(1, 0)
	Run.active = false


func _fonts() -> void:
	if Assets.font_title == null:
		Assets._ready()


func _router_init() -> void:
	if (InputRouter.get("_down") as Dictionary).is_empty():
		InputRouter._ready()
	InputRouter.set_text_mode(false)
	_router_step()


func _router_step() -> void:
	Input.flush_buffered_events()
	InputRouter._process(STEP)


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


## Steps a (not-in-tree) screen and the router together for `seconds`.
func _run(screen: Node, seconds: float) -> void:
	var t := 0.0
	while t < seconds - 1e-6:
		_router_step()
		screen._process(STEP)
		t += STEP


## A Main node outside the tree (like test_attract.gd): _go / _handle_finished are called directly.
func _new_main(args: Dictionary = {}) -> Node:
	_router_init()
	var m: Node = MainScript.new()
	m.set("_args", args)
	return m


func _scr(m: Node) -> String:
	return String(m.get("_screen_name"))


func _args_of(m: Node) -> Dictionary:
	return (m.get("_screen") as Node).get("args") as Dictionary


## Finishes Main's current screen with `result` / `data`, as its `finished` signal would (after the deferred call).
func _finish(m: Node, result: String, data: Dictionary = {}) -> void:
	var s: Node = m.get("_screen")
	_screens.append(s)
	m._handle_finished(result, data, _scr(m), s)


func _free_all(m: Node) -> void:
	_screens.append(m.get("_screen"))
	for s in _screens:
		if is_instance_valid(s):
			s.free()
	_screens.clear()
	m.free()


## A level of the current player ends: score / time as given, lives (0 = game over).
func _end_level(m: Node, score: int, time: float, lives: int = 2) -> void:
	Run.score = score
	Run.active_time = time
	Run.lives = lives
	var n := int(m.get("_level"))
	Run.last_level_result = {"level": n, "completion_bonus": int(LevelData.level(n)["bonus"]), "extra_life": false,
		"flawless": false}
	if n == LevelData.BONUS_LEVEL:
		Run.last_bonus_result = {"remaining": 10, "factor": 200, "bonus": 2000, "extra_life": false}
	_finish(m, "completed" if lives > 0 else "game_over")


## Plays a whole match through RunFlow.match_next (TURN screens included, from level `start`): out_at[k] = level in
## which player k loses the last life (0 = never); `entries` = the players who enter a name (in this order).
## Returns the screens: "turn:P1:5", "L5:P2", "interlevel:P1:5", "bonus_result:P2", "game_over:P1:7", "arrival:3",
## "mars_rules", "victory", "match_result", "name_entry:P2", "highscores".
func _simulate(out_at: Array, start: int = 1, entries: Array = []) -> Array[String]:
	var seq: Array[String] = []
	var out := [false, false]
	var queue := entries.duplicate()
	var st := RunFlow.match_step("turn", start, 0)
	var last := -1
	var guard := 0
	while String(st["screen"]) != "title" and guard < 500:
		guard += 1
		var scr := String(st["screen"])
		var n := int(st["level"])
		var k := int(st["player"])
		var tag := "P%d" % (k + 1)
		var result := "continue"
		match scr:
			"turn":
				seq.append("turn:%s:%d" % [tag, n])
			"level":
				seq.append("L%d:%s" % [n, tag])
				last = k
				if int(out_at[k]) == n:
					out[k] = true
					result = "game_over"
				else:
					result = "completed"
			"interlevel", "game_over":
				seq.append("%s:%s:%d" % [scr, tag, n])
			"bonus_result", "name_entry":
				seq.append("%s:%s" % [scr, tag])
			"arrival":
				seq.append("arrival:%d" % n)
			_:
				seq.append(scr)
		var entry := -1
		if scr == "match_result" or scr == "name_entry":
			entry = int(queue.pop_front()) if not queue.is_empty() else -1
		st = RunFlow.match_next(scr, result, n, k if k >= 0 else last, out, entry)
	check(guard < 500, "the match ends")
	return seq


## The screens of a level n turn of player k (TURN screen included when `turn`).
func _turn(n: int, k: int, turn: bool = true, game_over: bool = false) -> Array[String]:
	var tag := "P%d" % (k + 1)
	var out: Array[String] = []
	if turn:
		out.append("turn:%s:%d" % [tag, n])
	out.append("L%d:%s" % [n, tag])
	if game_over:
		out.append("game_over:%s:%d" % [tag, n])
	elif n == LevelData.BONUS_LEVEL:
		out.append("bonus_result:%s" % tag)
	else:
		out.append("interlevel:%s:%d" % [tag, n])
	return out


## What follows the end of round n (arrival / Mars rules), nothing for the other rounds.
func _after_round(n: int) -> Array[String]:
	if ARRIVALS.has(n):
		return ["arrival:%d" % n] as Array[String]
	if n == LevelData.BONUS_LEVEL:
		return ["mars_rules"] as Array[String]
	return [] as Array[String]


func _index(seq: Array[String], item: String) -> int:
	return seq.find(item)


# --- RunFlow: setup ------------------------------------------------------------------------------------
func test_setup_sequence_and_back() -> void:
	var seq: Array[String] = []
	var st := RunFlow.setup_next("title", "start", -1)
	var results := {"ship_lock": "done", "handover": "continue", "lock_reveal": "continue", "ship_select": "confirm"}
	while String(st["screen"]) != "turn" and seq.size() < 20:
		seq.append("%s:%d" % [st["screen"], st["player"]])
		st = RunFlow.setup_next(String(st["screen"]), String(results[st["screen"]]), int(st["player"]))
	check_eq(seq, ["ship_lock:0", "handover:1", "ship_lock:1", "lock_reveal:-1", "ship_select:0", "ship_select:1"]
		as Array[String], "locks → hand-over → locks → reveal → ship select × 2")
	check_eq(st, RunFlow.match_step("turn", 1, 0), "then PLAYER 1's TURN screen of level 1")
	for from in ["ship_lock", "ship_select"]:
		for p in [0, 1]:
			check_eq(String(RunFlow.setup_next(from, "back", p)["screen"]), "title", "back on %s (%d) → title" % [from, p])


# --- RunFlow: rounds -----------------------------------------------------------------------------------
func test_next_in_round_and_turn_screen_rule() -> void:
	check_eq(RunFlow.next_in_round(-1, [false, false]), 0, "PLAYER 1 starts a round")
	check_eq(RunFlow.next_in_round(0, [false, false]), 1, "then PLAYER 2")
	check_eq(RunFlow.next_in_round(1, [false, false]), -1, "then the round is over")
	check_eq(RunFlow.next_in_round(-1, [true, false]), 1, "PLAYER 1 out: PLAYER 2 starts")
	check_eq(RunFlow.next_in_round(0, [true, false]), 1, "PLAYER 1 just went out: PLAYER 2 plays the level")
	check_eq(RunFlow.next_in_round(0, [false, true]), -1, "PLAYER 2 out: round over after PLAYER 1")
	check_eq(RunFlow.next_in_round(-1, [true, true]), -1, "nobody left")
	check(not RunFlow.anyone_left([true, true]))
	check(RunFlow.anyone_left([true, false]))
	check(RunFlow.needs_turn_screen(0, -1), "at the start of the match")
	check(RunFlow.needs_turn_screen(1, 0), "on a player change")
	check(not RunFlow.needs_turn_screen(1, 1), "not between two levels of the same player")
	check_eq(RunFlow.turn_or_level(0, 6, 1), RunFlow.match_step("turn", 6, 0))
	check_eq(RunFlow.turn_or_level(0, 6, 0), RunFlow.match_step("level", 6, 0))


func test_after_round() -> void:
	check_eq(String(RunFlow.after_round(7, [true, true], 1)["screen"]), "match_result", "nobody left")
	check_eq(String(RunFlow.after_round(20, [true, true], 1)["screen"]), "match_result", "both out in level 20")
	check_eq(String(RunFlow.after_round(20, [false, true], 1)["screen"]), "victory", "someone completed level 20")
	check_eq(String(RunFlow.after_round(13, [false, false], 1)["screen"]), "mars_rules")
	for n in ARRIVALS:
		check_eq(RunFlow.after_round(n, [false, false], 1), RunFlow.match_step("arrival", n, -1), "arrival %d" % n)
	check_eq(RunFlow.after_round(4, [false, false], 1), RunFlow.match_step("turn", 5, 0), "next round: PLAYER 1")
	check_eq(RunFlow.after_round(4, [false, true], 1), RunFlow.match_step("turn", 5, 0), "PLAYER 2 just went out")
	check_eq(RunFlow.after_round(4, [false, true], 0), RunFlow.match_step("level", 5, 0), "PLAYER 1 alone")
	check_eq(RunFlow.after_round(4, [true, false], 1), RunFlow.match_step("level", 5, 1), "PLAYER 2 alone")
	check_eq(RunFlow.match_next("arrival", "continue", 3, 1, [false, false]), RunFlow.match_step("turn", 4, 0))
	check_eq(RunFlow.match_next("arrival", "continue", 3, 0, [false, true]), RunFlow.match_step("level", 4, 0))
	check_eq(RunFlow.match_next("mars_rules", "continue", 13, 1, [false, false]), RunFlow.match_step("turn", 14, 0))
	check_eq(RunFlow.match_next("level", "quit", 9, 1, [false, false])["screen"], "title", "pause quit → title")
	check_eq(RunFlow.match_next("victory", "continue", 20, -1, [false, false])["screen"], "match_result")
	check_eq(RunFlow.match_next("match_result", "continue", 20, -1, [false, false], 1),
		RunFlow.match_step("name_entry", 20, 1))
	check_eq(RunFlow.match_next("name_entry", "done", 20, 1, [false, false], -1)["screen"], "highscores")
	check_eq(RunFlow.match_next("highscores", "back", 20, -1, [false, false])["screen"], "title")


func test_both_survive_whole_match() -> void:
	var expected: Array[String] = []
	for n in range(1, 21):
		expected.append_array(_turn(n, 0))
		expected.append_array(_turn(n, 1))
		expected.append_array(_after_round(n))
	expected.append_array(["victory", "match_result", "name_entry:P1", "name_entry:P2", "highscores"] as Array[String])
	var seq := _simulate([0, 0], 1, [0, 1])
	check_eq(seq, expected, "both survive")
	# Spot checks of the rules behind the sequence.
	check_eq(seq.count("arrival:3"), 1, "the arrival once per round")
	check_eq(_index(seq, "arrival:3"), _index(seq, "interlevel:P2:3") + 1, "… after PLAYER 2's interlevel")
	check_eq(seq.count("mars_rules"), 1, "the Mars rules once")
	check_eq(_index(seq, "mars_rules"), _index(seq, "bonus_result:P2") + 1, "… after both bonus results")
	check_eq(_index(seq, "bonus_result:P1") + 1, _index(seq, "turn:P2:13"), "PLAYER 1's bonus result, then PLAYER 2")
	for n in range(1, 21):
		for k in 2:
			var tag := "P%d" % (k + 1)
			check_eq(_index(seq, "turn:%s:%d" % [tag, n]) + 1, _index(seq, "L%d:%s" % [n, tag]),
				"TURN screen before level %d of %s" % [n, tag])


func test_player_1_out_early_player_2_alone_to_the_end() -> void:
	var expected: Array[String] = []
	expected.append_array(_turn(1, 0))
	expected.append_array(_turn(1, 1))
	expected.append_array(_turn(2, 0, true, true))
	expected.append_array(_turn(2, 1))
	for n in range(3, 21):
		expected.append_array(_turn(n, 1, false))   # alone: no TURN screens any more
		expected.append_array(_after_round(n))
	expected.append_array(["victory", "match_result", "name_entry:P2", "highscores"] as Array[String])
	check_eq(_simulate([2, 0], 1, [1]), expected, "PLAYER 1 out in level 2")


func test_player_2_out_arrivals_still_once_per_round_after_player_1() -> void:
	# Out in level 5: round 5 ends with PLAYER 2's game over, PLAYER 1 continues (TURN once, then none).
	var seq := _simulate([0, 5], 1)
	var i := _index(seq, "game_over:P2:5")
	check(i > 0, "PLAYER 2's game over in level 5")
	check_eq(seq.slice(i - 3, i + 8), ["interlevel:P1:5", "turn:P2:5", "L5:P2", "game_over:P2:5", "turn:P1:6",
		"L6:P1", "interlevel:P1:6", "arrival:6", "L7:P1", "interlevel:P1:7", "L8:P1"] as Array[String])
	for n in ARRIVALS:
		check_eq(seq.count("arrival:%d" % n), 1, "arrival %d once" % n)
	check_eq(seq.count("mars_rules"), 1)
	check_eq(_index(seq, "mars_rules"), _index(seq, "bonus_result:P1") + 1, "Mars rules right after PLAYER 1's bonus")
	check_eq(seq.count("turn:P2:6"), 0, "PLAYER 2 is skipped")
	# Out in an arrival level: the arrival follows PLAYER 2's game over.
	var seq3 := _simulate([0, 3], 1)
	var j := _index(seq3, "game_over:P2:3")
	check_eq(seq3.slice(j, j + 5), ["game_over:P2:3", "arrival:3", "turn:P1:4", "L4:P1", "interlevel:P1:4"]
		as Array[String])
	check_eq(seq3.count("arrival:3"), 1)


func test_both_out_in_the_same_round() -> void:
	var expected: Array[String] = []
	for n in range(1, 7):
		expected.append_array(_turn(n, 0))
		expected.append_array(_turn(n, 1))
		expected.append_array(_after_round(n))
	expected.append_array(_turn(7, 0, true, true))
	expected.append_array(_turn(7, 1, true, true))
	expected.append_array(["match_result", "name_entry:P2", "highscores"] as Array[String])
	check_eq(_simulate([7, 7], 1, [1]), expected, "both out in level 7: no victory")
	check_eq(_simulate([7, 7], 1, []).slice(-2), ["match_result", "highscores"] as Array[String], "no entries")


func test_out_in_level_20_while_the_other_wins() -> void:
	var seq := _simulate([0, 20], 19, [0])
	check_eq(seq.slice(-10, -1), ["turn:P1:20", "L20:P1", "interlevel:P1:20", "turn:P2:20", "L20:P2", "game_over:P2:20",
		"victory", "match_result", "name_entry:P1"] as Array[String])
	var seq2 := _simulate([20, 0], 19, [])
	check_eq(seq2.slice(-9, -1), ["turn:P1:20", "L20:P1", "game_over:P1:20", "turn:P2:20", "L20:P2", "interlevel:P2:20",
		"victory", "match_result"] as Array[String])
	check_eq(_simulate([20, 20], 19).slice(-3), ["game_over:P2:20", "match_result", "highscores"] as Array[String],
		"both out in level 20: no victory")


func test_bonus_level_per_player_mars_rules_once() -> void:
	var seq := _simulate([0, 0], 12)
	check_eq(seq.slice(0, 15), ["turn:P1:12", "L12:P1", "interlevel:P1:12", "turn:P2:12", "L12:P2",
		"interlevel:P2:12", "arrival:12", "turn:P1:13", "L13:P1", "bonus_result:P1", "turn:P2:13", "L13:P2",
		"bonus_result:P2", "mars_rules", "turn:P1:14"] as Array[String])
	# Alone in the bonus round (PLAYER 1 out in level 11): no TURN screens, the Mars rules once.
	var alone := _simulate([11, 0], 11)
	var i := _index(alone, "L13:P2")
	check_eq(alone.slice(i - 1, i + 5), ["arrival:12", "L13:P2", "bonus_result:P2", "mars_rules", "L14:P2",
		"interlevel:P2:14"] as Array[String])


func test_entry_order_by_score_then_time_then_player_1() -> void:
	check_eq(RunFlow.entry_order([100, 900], [5.0, 9.0]), [1, 0] as Array[int], "better score first")
	check_eq(RunFlow.entry_order([900, 100], [9.0, 5.0]), [0, 1] as Array[int])
	check_eq(RunFlow.entry_order([500, 500], [9.0, 5.0]), [1, 0] as Array[int], "equal score: shorter time first")
	check_eq(RunFlow.entry_order([500, 500], [5.0, 5.0]), [0, 1] as Array[int], "all equal: PLAYER 1 first")


func test_entry_ranks_recomputed_after_all_inserts() -> void:
	var e1 := {"name": "ACE", "score": 500, "time": 50.0, "level": 4, "ship": 1}
	var e2 := {"name": "ACE", "score": 500, "time": 50.0, "level": 4, "ship": 1}   # identical twin entry
	var other := {"name": "BOB", "score": 900, "time": 10.0, "level": 9, "ship": 0}
	check_eq(RunFlow.entry_ranks([other, e1, e2], [e1, e2]), [1, 2] as Array[int], "each row counts once")
	check_eq(RunFlow.entry_ranks([e1, other], [e1]), [0] as Array[int])
	check_eq(RunFlow.entry_ranks([other], [e1]), [] as Array[int], "pushed out of the list: no highlight")
	var changed := e1.duplicate()
	changed["time"] = 50.1
	check_eq(RunFlow.entry_ranks([changed], [e1]), [] as Array[int], "all fields must be equal")


# --- Screens -----------------------------------------------------------------------------------------
func test_interlevel_next_line_and_confirm_sound_follow_the_real_next_screen() -> void:
	check_eq(InterlevelScreen.progress_line(5, 1), "Next: PLAYER 2 – LEVEL 5")
	check_eq(InterlevelScreen.progress_line(5, -1), LevelData.progress_text(5))
	for n in ARRIVALS:
		var after_p1 := String(RunFlow.match_next("interlevel", "continue", n, 0, [false, false])["screen"])
		var after_p2 := String(RunFlow.match_next("interlevel", "continue", n, 1, [false, false])["screen"])
		check_eq(after_p1, "turn")
		check_eq(InterlevelScreen.confirm_sound(n, after_p1), "menu_confirm", "PLAYER 1's interlevel %d: TURN next" % n)
		check_eq(InterlevelScreen.confirm_sound(n, after_p2), "", "PLAYER 2's interlevel %d: the silent arrival next" % n)
		check_eq(InterlevelScreen.confirm_sound(n), "", "one player: unchanged")
	check_eq(InterlevelScreen.confirm_sound(4, "level"), "menu_confirm")


## The "Next: PLAYER 2 – LEVEL n" line stays clear of the planet like the progress texts (test_ui_screens.gd).
func test_interlevel_next_line_clear_of_the_planet() -> void:
	_fonts()
	var radius := InterlevelScreen.PLANET_D * 0.5
	for n in range(1, LevelData.LAST_LEVEL + 1):
		for rows in [4, 5]:
			var r := UiKit.text_backing_rect(Assets.font_title, Vector2(ScreenBase.CX, InterlevelScreen.progress_baseline(rows)),
				InterlevelScreen.progress_line(n, 1), InterlevelScreen.PROGRESS_SIZE, HORIZONTAL_ALIGNMENT_CENTER,
				Vector2(4, 4))
			var p := InterlevelScreen.PLANET_POS
			var gap := p.distance_to(Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))) - radius
			check(gap >= 12.0, "level %d (%d rows): next line %.0f px from the planet limb" % [n, rows, gap])


func test_game_over_status_texts() -> void:
	check_eq(GameOverScreen.status_text(0, "plays_on"), "PLAYER 2 PLAYS ON")
	check_eq(GameOverScreen.status_text(1, "plays_on"), "PLAYER 1 PLAYS ON")
	check_eq(GameOverScreen.status_text(1, "won"), "PLAYER 1 SAVED EARTH!")
	check_eq(GameOverScreen.status_text(0, "out"), "MATCH OVER")
	var g := SilentGameOver.new()
	g.setup({"level": 4, "qualifies": true, "player": 0, "other_status": "plays_on"})
	g._enter()
	check(not g.get("_qualifies"), "a match shows no NEW HIGHSCORE (the entries come at its end)")
	g.free()
	var g1 := SilentGameOver.new()
	g1.setup({"level": 4, "qualifies": true})
	g1._enter()
	check(g1.get("_qualifies"), "one player: unchanged")
	g1.free()
	AudioManager.stop_music()


func test_mars_rules_locked_hits_for_mixed_ships() -> void:
	_fonts()
	var script: GDScript = load("res://scripts/screens/mars_rules_screen.gd")
	var consts := script.get_script_constant_map()
	for ships in [[0, 4], [4, 1], [0], [5], [0, 1], [4, 5], []]:
		var lines: Array = MarsRulesScreen.locked_lines(ships)
		var text := ""
		for line in lines:
			var w := 0.0
			for seg in line:
				text += String(seg[0])
				var plain: bool = seg[1] == consts["C_W"] or seg[1] == consts["C_D"]
				w += UiKit.text_width(Assets.font_body if plain else Assets.font_body_bold, String(seg[0]), 19)
			check(float(consts["TEXT_X"]) + w <= 910.0, "%s: line fits the panel (%.0f)" % [ships, w])
			text += "\n"
		var piercing := 0
		for id in ships:
			piercing += 1 if bool(ShipData.ship(int(id))["piercing"]) else 0
		var low := text.to_lower()
		check_eq(low.contains("wasted"), piercing < ships.size() or ships.is_empty(), "%s: normal shots wasted" % [ships])
		check_eq(low.contains("fly on") or low.contains("flies on"), piercing > 0, "%s: piercing shots fly on" % [ships])
		check_eq(lines.size(), 2 if piercing > 0 and piercing < ships.size() else 1, "%s: line count" % [ships])
	# The screen with mixed ships: rule 4 gets three lines, all inside its panel; the subtitle says "pilots".
	var s := MarsRulesScreen.new()
	s.setup({"level": 13, "ships": [0, 4]})
	s._enter()
	check_eq((s.get("_rules") as Array)[3].size(), 3, "rule 4: arrivals + two locked-hit lines")
	check_eq(int(s.get("_pilots")), 2)
	var row_y: Array = consts["ROW_Y"]
	var top := float(row_y[3])
	var bottom := top + float(consts["ROW_H"]) - 8.0
	var c := (top + bottom) * 0.5
	var lh := 25.0
	var y0 := c + 8.0 - lh
	check(y0 - Assets.font_body.get_ascent(19) > top + 4.0, "first line inside the panel")
	check(y0 + 2.0 * lh + Assets.font_body.get_descent(19) < bottom - 2.0, "third line inside the panel")
	s.free()
	AudioManager.stop_music()


func test_highscores_ranks_and_category_switch() -> void:
	_settings_begin()
	_router_init()
	Settings.insert_highscore(1, {"name": "CLASSIC", "score": 700, "time": 9.0, "level": 3, "ship": 0})
	Settings.insert_highscore(1, {"name": "POWER", "score": 900, "time": 9.0, "level": 4, "ship": 1}, true)
	check_eq(HighscoresScreen.highlight_rows({"ranks": [4, 1, 4, 12, -1]}), [4, 1] as Array[int], "ranks")
	check_eq(HighscoresScreen.highlight_rows({"rank": 3}), [3] as Array[int], "a single rank is still accepted")
	check_eq(HighscoresScreen.highlight_rows({}), [] as Array[int])
	var h := HighscoresScreen.new()
	h.setup({"difficulty": 1, "powerups": true, "ranks": [0, 2]})
	h._ready()
	check(h.get("_powerups"), "opens the requested category")
	check_eq(String((h.get("_entries") as Array)[0]["name"]), "POWER")
	check_eq(h.get("_highlights"), [0, 2] as Array[int])
	_run(h, 0.1)
	_key(KEY_DOWN, true)
	_run(h, 1.0)   # held: switches once, no auto-repeat flicker
	check(not h.get("_powerups"), "down → CLASSIC")
	check_eq(String((h.get("_entries") as Array)[0]["name"]), "CLASSIC")
	_key(KEY_DOWN, false)
	_run(h, 0.1)
	_key(KEY_UP, true)
	_run(h, 0.1)
	_key(KEY_UP, false)
	_run(h, 0.1)
	check(h.get("_powerups"), "up → POWER-UPS again")
	check_eq(int(h.get("_diff")), 1, "the difficulty stays")
	h.free()
	var h2 := HighscoresScreen.new()
	h2.setup({"difficulty": 2})
	Settings.powerups = true
	h2._ready()
	check(h2.get("_powerups"), "default: the category of Settings.powerups (title → highscores)")
	h2.free()
	_settings_end()


## Like test_audit_flow.gd for A / D: W or S still held from the name entry (the last letter typed) must not
## switch the category away from the list that holds the new entry.
func test_letter_held_from_name_entry_does_not_switch_category() -> void:
	_settings_begin()
	for letter: Key in [KEY_W, KEY_S]:
		_router_init()
		var n := NameEntryScreen.new()
		n.setup({"difficulty": 1, "score": 5, "time": 1.0, "level": 1, "ship": 0, "powerups": true})
		n._ready()
		_key(letter, true)
		n._on_text_char(OS.get_keycode_string(letter))
		_run(n, STEP * 3)
		n._exit_tree()
		n.free()
		var h := HighscoresScreen.new()
		h.setup({"difficulty": 1, "powerups": true, "rank": 0})
		h._ready()
		InputRouter.require_release()
		_run(h, 0.3)
		check(h.get("_powerups"), "%s held from the name entry keeps the POWER-UPS list" % OS.get_keycode_string(letter))
		_key(letter, false)
		_run(h, STEP * 3)
		h.free()
	InputRouter.set_text_mode(false)
	AudioManager.stop_music()
	_settings_end()


func test_name_entry_power_up_category_and_entry_data() -> void:
	_settings_begin()
	check_eq(NameEntryScreen.rank_text(3, 1, false), "RANK 3  ·  NORMAL", "classic: unchanged")
	check_eq(NameEntryScreen.rank_text(1, 3, true), "RANK 1  ·  EXPERT  ·  POWER-UPS")
	Settings.insert_highscore(2, {"name": "TOP", "score": 9000, "time": 5.0, "level": 9, "ship": 0}, true)
	var n := NameEntryScreen.new()
	n.setup({"difficulty": 2, "score": 1234, "time": 100.5, "level": 7, "ship": 3, "powerups": true, "player": 1})
	n._ready()
	check_eq(int(n.get("_rank")), 2, "rank within the power-up list")
	for ch in "KIRA":
		n._on_text_char(ch)
	var got := {}
	n.finished.connect(func(_r: String, d: Dictionary) -> void: got.merge(d))
	n._confirm()
	check_eq(int(got["rank"]), 1)
	check(bool(got["powerups"]))
	check_eq(got["entry"], {"name": "KIRA", "score": 1234, "time": 100.5, "level": 7, "ship": 3})
	check_eq(Settings.get_highscores(2).size(), 0, "classic list untouched")
	check_eq(Settings.get_highscores(2, true)[1], got["entry"], "stored in the power-up list exactly as reported")
	n._exit_tree()
	n.free()
	AudioManager.stop_music()
	_settings_end()


# --- Main ----------------------------------------------------------------------------------------------
func test_main_setup_then_turns_skips_and_pause_quit() -> void:
	_settings_begin()
	Settings.players = 2
	Settings.difficulty = 2
	Settings.powerups = false
	Run.start_new(1, 5)   # the last run flew ship 5: both ship selects start there
	var m := _new_main()
	m._go(RunFlow.step("title"))
	_finish(m, "start")
	check_eq(_scr(m), "ship_lock")
	check_eq(_args_of(m), {"player": 0, "locked": []}, "PLAYER 1 locks first")
	_finish(m, "done", {"locked": [5, 1]})
	check_eq(_scr(m), "handover")
	check_eq(_args_of(m), {"kind": "locks", "player": 1}, "hand-over to PLAYER 2 (no lock information)")
	_finish(m, "continue")
	check_eq(_scr(m), "ship_lock")
	check_eq(_args_of(m), {"player": 1, "locked": []}, "PLAYER 2 locks")
	_finish(m, "done", {"locked": [0]})
	check_eq(_scr(m), "lock_reveal")
	check_eq(_args_of(m), {"locked": [[0], [1, 5]]}, "[ids PLAYER 1 may not fly, ids PLAYER 2 may not fly]")
	_finish(m, "continue")
	check_eq(_scr(m), "ship_select")
	check_eq(_args_of(m), {"ship": 5, "player": 0, "locked": [0]})
	_finish(m, "confirm", {"ship": 2})
	check_eq(_scr(m), "ship_select")
	check_eq(_args_of(m), {"ship": 5, "player": 1, "locked": [1, 5]})
	_finish(m, "confirm", {"ship": 3})
	# The match starts at PLAYER 1's TURN screen.
	check_eq(_scr(m), "turn")
	check_eq(_args_of(m), {"kind": "turn", "player": 0, "level": 1})
	check(Run.is_two_player())
	check_eq(Run.difficulty, 2)
	check(not Run.powerups)
	check_eq(Run.current, 0)
	check_eq(Run.ship_id, 2)
	check_eq(Run.locked, [0] as Array[int])
	check_eq(int(Run.player_get(1, "ship_id")), 3)
	check_eq(Run.player_get(1, "locked"), [1, 5] as Array[int])
	_finish(m, "continue")
	check_eq(_scr(m), "level")
	check_eq(int(m.get("_screen").get("level")), 1)
	check_eq(Run.current, 0, "PLAYER 1 plays level 1")
	_end_level(m, 300, 50.0)
	check_eq(_scr(m), "interlevel")
	check_eq(_args_of(m), {"level": 1, "player": 0, "next_player": 1, "next_screen": "turn"})
	_finish(m, "continue")
	check_eq(_scr(m), "turn")
	check_eq(_args_of(m), {"kind": "turn", "player": 1, "level": 1})
	check_eq(Run.current, 1, "switched to PLAYER 2 at the TURN screen")
	check_eq(Run.score, 0)
	check_eq(Run.ship_id, 3)
	_finish(m, "continue")
	check_eq(Run.current, 1, "PLAYER 2 plays level 1")
	_end_level(m, 120, 40.0, 0)
	check_eq(_scr(m), "game_over")
	check_eq(_args_of(m), {"level": 1, "qualifies": false, "player": 1, "other_status": "plays_on"})
	check(Run.out, "PLAYER 2 is out")
	check(Run.active, "the match goes on")
	_finish(m, "continue")
	check_eq(_scr(m), "turn", "a TURN screen after the switch back to PLAYER 1")
	check_eq(_args_of(m), {"kind": "turn", "player": 0, "level": 2})
	check_eq(Run.current, 0)
	check_eq(Run.score, 300, "PLAYER 1's state is back")
	_finish(m, "continue")
	_end_level(m, 600, 90.0)
	check_eq(_args_of(m), {"level": 2, "player": 0, "next_player": -1, "next_screen": "level"},
		"PLAYER 2 is out: the usual progress line")
	_finish(m, "continue")
	check_eq(_scr(m), "level", "PLAYER 1 alone: no TURN screen")
	check_eq(int(m.get("_level")), 3)
	_end_level(m, 900, 130.0)
	check_eq(String(_args_of(m)["next_screen"]), "arrival")
	_finish(m, "continue")
	check_eq(_scr(m), "arrival")
	check_eq(_args_of(m), {"level": 3})
	_finish(m, "continue")
	check_eq(_scr(m), "level")
	check_eq(int(m.get("_level")), 4)
	_finish(m, "quit")   # pause → quit
	check_eq(_scr(m), "title", "pause quit → title")
	check(not m.get("_match"), "the match is over")
	check(not Run.active)
	check_eq(Settings.get_highscores(2).size(), 0, "no entries for an aborted match")
	_free_all(m)
	_settings_end()


func test_main_back_on_setup_screens_returns_to_the_title() -> void:
	_settings_begin()
	Settings.players = 2
	for steps in [0, 4, 5]:   # back on PLAYER 1's lock screen / PLAYER 1's / PLAYER 2's ship select
		var m := _new_main()
		m._go(RunFlow.step("title"))
		_finish(m, "start")
		var results := {"ship_lock": "done", "handover": "continue", "lock_reveal": "continue", "ship_select": "confirm"}
		for i in steps:
			_finish(m, String(results[_scr(m)]), {"locked": [], "ship": 1})
		var on := _scr(m)
		_finish(m, "back")
		check_eq(_scr(m), "title", "back on %s (step %d) → title" % [on, steps])
		check(not m.get("_setup"), "setup aborted")
		_free_all(m)
	_settings_end()


func test_main_one_player_flow_with_power_ups() -> void:
	_settings_begin()
	Settings.players = 1
	Settings.difficulty = 0
	Settings.powerups = true
	var m := _new_main()
	m._go(RunFlow.step("title"))
	_finish(m, "start")
	check_eq(_scr(m), "ship_select")
	check_eq(_args_of(m), {"ship": Run.ship_id}, "one player: the classic ship select args")
	_finish(m, "confirm", {"ship": 1})
	check_eq(_scr(m), "level", "no TURN screen")
	check(not Run.is_two_player())
	check(Run.powerups, "the run takes POWER-UPS from the title")
	_end_level(m, 2500, 77.0)
	check_eq(_args_of(m), {"level": 1}, "one-player interlevel args unchanged")
	_finish(m, "continue")
	_end_level(m, 2600, 99.0, 0)
	check_eq(_scr(m), "game_over")
	check_eq(_args_of(m), {"level": 2, "qualifies": true})
	_finish(m, "continue")
	check_eq(_scr(m), "name_entry")
	check_eq(_args_of(m), {"difficulty": 0, "score": 2600, "time": 99.0, "level": 2, "ship": 1, "powerups": true})
	var ne: Node = m.get("_screen")
	ne._ready()
	for c in ne.finished.get_connections():
		ne.finished.disconnect(c["callable"])
	var got := {}
	ne.finished.connect(func(_r: String, d: Dictionary) -> void: got.merge(d))
	ne._confirm()
	ne._exit_tree()
	_finish(m, "done", got)
	check_eq(_scr(m), "highscores")
	check_eq(_args_of(m), {"difficulty": 0, "rank": 0, "powerups": true})
	check_eq(Settings.get_highscores(0, true).size(), 1, "entered into the power-up list")
	check_eq(Settings.get_highscores(0).size(), 0, "classic list untouched")
	_finish(m, "back")
	check_eq(_scr(m), "title")
	check_eq(_args_of(m), {"select": "start"})
	# Title → HIGHSCORES opens the category of Settings.powerups.
	_finish(m, "highscores")
	check_eq(_args_of(m), {"difficulty": 0, "powerups": true})
	_free_all(m)
	InputRouter.set_text_mode(false)
	AudioManager.stop_music()
	_settings_end()


## The end of a match: victory (one player saved Earth), match result, the name entries in score order – each one
## checked when it is that player's turn – and the highscores with every entry of the match highlighted; in both
## categories (the match's power-up setting decides the lists).
func test_main_match_end_entries_and_highscores() -> void:
	for pu in [false, true]:
		for prefill in [false, true]:
			_settings_begin()
			if prefill:
				# A full list (lowest 1000): PLAYER 1's 1500 qualifies at first, but no longer once PLAYER 2's 5000
				# pushed the 1000 out.
				for i in 10:
					Settings.insert_highscore(1, {"name": "OLD%d" % i, "score": 1000 * (i + 1), "time": 1000.0,
						"level": 5, "ship": 0}, pu)
			var m := _new_main()
			Run.start_match(1, [0, 4], [[], []], 20, pu)
			m._begin_match()
			m._go(RunFlow.match_step("turn", 20, 0))
			_finish(m, "continue")
			_end_level(m, 1500, 900.0)
			check(Run.won, "PLAYER 1 completed level 20")
			check_eq(_args_of(m), {"level": 20, "player": 0, "next_player": 1, "next_screen": "turn"})
			_finish(m, "continue")
			_finish(m, "continue")
			check_eq(Run.current, 1)
			_end_level(m, 5000, 800.0, 0)
			check_eq(_args_of(m), {"level": 20, "qualifies": false, "player": 1, "other_status": "won"},
				"PLAYER 1 saved Earth")
			_finish(m, "continue")
			check_eq(_scr(m), "victory")
			check_eq(_args_of(m), {"level": 20, "match": true})
			_finish(m, "continue")
			check_eq(_scr(m), "match_result")
			_finish(m, "continue")
			check_eq(_scr(m), "name_entry", "the better score enters first")
			check_eq(_args_of(m), {"player": 1, "difficulty": 1, "score": 5000, "time": 800.0, "level": 20, "ship": 4,
				"powerups": pu})
			var ne: Node = m.get("_screen")
			ne._ready()
			for c in ne.finished.get_connections():
				ne.finished.disconnect(c["callable"])
			var got := {}
			ne.finished.connect(func(_r: String, d: Dictionary) -> void: got.merge(d))
			for ch in "PINK":
				ne._on_text_char(ch)
			ne._confirm()
			ne._exit_tree()
			_finish(m, "done", got)
			var list := Settings.get_highscores(1, pu)
			if prefill:
				check_eq(_scr(m), "highscores", "PLAYER 1 no longer qualifies after PLAYER 2's entry (pu=%s)" % pu)
				check_eq(_args_of(m), {"difficulty": 1, "powerups": pu, "ranks": [5]})
			else:
				check_eq(_scr(m), "name_entry", "then PLAYER 1")
				check_eq(_args_of(m), {"player": 0, "difficulty": 1, "score": 1500, "time": 900.0, "level": 20,
					"ship": 0, "powerups": pu})
				var ne2: Node = m.get("_screen")
				ne2._ready()
				for c in ne2.finished.get_connections():
					ne2.finished.disconnect(c["callable"])
				var got2 := {}
				ne2.finished.connect(func(_r: String, d: Dictionary) -> void: got2.merge(d))
				for ch in "CYAN":
					ne2._on_text_char(ch)
				ne2._confirm()
				ne2._exit_tree()
				_finish(m, "done", got2)
				list = Settings.get_highscores(1, pu)
				check_eq(_scr(m), "highscores")
				check_eq(_args_of(m), {"difficulty": 1, "powerups": pu, "ranks": [0, 1]}, "both entries highlighted")
				check_eq(String(list[1]["name"]), "CYAN")
			check_eq(String(list[_args_of(m)["ranks"][0]]["name"]), "PINK")
			check_eq(Settings.get_highscores(1, not pu).size(), 0, "the other category is untouched (pu=%s)" % pu)
			_finish(m, "back")
			check_eq(_scr(m), "title")
			check(not m.get("_match"))
			_free_all(m)
			InputRouter.set_text_mode(false)
			AudioManager.stop_music()
			_settings_end()


func test_main_dev_command_line() -> void:
	_settings_begin()
	var m := _new_main({"level": "7", "players": "2", "ship": "1", "ship2": "4", "powerups": true, "difficulty": "3"})
	m._start_from_args()
	check_eq(_scr(m), "turn", "--players=2 --level=7: PLAYER 1's TURN screen")
	check_eq(_args_of(m), {"kind": "turn", "player": 0, "level": 7})
	check(Run.is_two_player() and Run.powerups)
	check_eq(Run.difficulty, 3)
	check_eq([int(Run.player_get(0, "ship_id")), int(Run.player_get(1, "ship_id"))], [1, 4])
	check_eq([Run.player_get(0, "locked"), Run.player_get(1, "locked")], [[] as Array[int], [] as Array[int]], "no locks")
	_free_all(m)
	var m1 := _new_main({"level": "3", "powerups": true})
	m1._start_from_args()
	check_eq(_scr(m1), "level")
	check(not Run.is_two_player() and Run.powerups, "--powerups for a one-player start")
	_free_all(m1)
	var m0 := _new_main({"level": "3"})
	m0._start_from_args()
	check(not Run.powerups, "classic by default")
	_free_all(m0)
	# Dev screens with a fake match.
	var cases := {
		"interlevel": [{"player": "0"}, {"level": 5, "player": 0, "next_player": 1, "next_screen": "turn"}],
		"bonus_result": [{"player": "1"}, {"level": 13, "player": 1, "next_player": -1}],
		"game_over": [{"player": "1", "other-out": true}, {"level": 5, "qualifies": false, "player": 1,
			"other_status": "out"}],
		"victory": [{}, {"level": 20, "match": true}],
		"mars_rules": [{"ship2": "4"}, {"level": 13, "ships": [0, 4]}],
		"turn": [{"player": "1", "level": "9"}, {"kind": "turn", "player": 1, "level": 9}],
	}
	for scr: String in cases:
		var args: Dictionary = (cases[scr][0] as Dictionary).duplicate()
		args["screen"] = scr
		args["players"] = "2"
		var md := _new_main(args)
		md._start_from_args()
		check_eq(_scr(md), scr, "--screen=%s --players=2" % scr)
		check_eq(_args_of(md), cases[scr][1], "--screen=%s args" % scr)
		check(Run.is_two_player(), "%s: a fake match" % scr)
		_free_all(md)
	var mn := _new_main({"screen": "name_entry", "players": "2", "player": "1", "powerups": true, "name": "AB"})
	mn._start_from_args()
	var na := _args_of(mn)
	check_eq(int(na["player"]), 1)
	check(bool(na["powerups"]))
	check_eq(String(na["initial_name"]), "AB")
	check_eq(int(na["score"]), int(Run.player_get(1, "score")))
	_free_all(mn)
	var mh := _new_main({"screen": "highscores", "powerups": true})
	mh._start_from_args()
	check(bool(_args_of(mh)["powerups"]), "--powerups: the power-up lists")
	_free_all(mh)
	AudioManager.stop_music()
	_settings_end()
