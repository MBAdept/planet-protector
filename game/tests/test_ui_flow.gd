extends TestBase
## Run flow (docs/SPEC.md §11), dev argument parsing (§17.3) and screen timing helpers.

const ArrivalScreen := preload("res://scripts/screens/arrival_screen.gd")
const HighscoresScreen := preload("res://scripts/screens/highscores_screen.gd")


func _n(from: String, result: String, level: int = 0, q: bool = false) -> String:
	return RunFlow.next(from, result, level, q)["screen"]


func _lvl(from: String, result: String, level: int = 0, q: bool = false) -> int:
	return int(RunFlow.next(from, result, level, q)["level"])


func test_title_and_ship_select() -> void:
	check_eq(_n("title", "start"), "ship_select")
	check_eq(_n("title", "highscores"), "highscores")
	check_eq(_n("title", "quit"), "quit")
	check_eq(_n("ship_select", "confirm"), "level")
	check_eq(_lvl("ship_select", "confirm"), 1)
	check_eq(_n("ship_select", "back"), "title")
	check_eq(_n("highscores", "back"), "title")


func test_level_completed_goes_to_interlevel_except_bonus() -> void:
	for n in range(1, 21):
		if n == 13:
			check_eq(_n("level", "completed", n), "bonus_result", "level 13")
		else:
			check_eq(_n("level", "completed", n), "interlevel", "level %d" % n)
			check_eq(_lvl("level", "completed", n), n)


func test_interlevel_arrivals_victory_and_next_level() -> void:
	for n in [3, 6, 9, 12, 16]:
		check_eq(_n("interlevel", "continue", n), "arrival", "arrival after %d" % n)
		check_eq(_n("arrival", "continue", n), "level", "level after arrival %d" % n)
		check_eq(_lvl("arrival", "continue", n), n + 1)
	for n in [1, 2, 4, 5, 7, 8, 10, 11, 14, 15, 17, 18, 19]:
		check_eq(_n("interlevel", "continue", n), "level", "after %d" % n)
		check_eq(_lvl("interlevel", "continue", n), n + 1)
	check_eq(_n("interlevel", "continue", 20), "victory")


func test_bonus_level_goes_to_mars_rules_then_level_14() -> void:
	check_eq(_n("bonus_result", "continue", 13), "mars_rules")
	check_eq(_n("mars_rules", "continue", 13), "level")
	check_eq(_lvl("mars_rules", "continue", 13), 14)


func test_end_of_run() -> void:
	check_eq(_n("level", "game_over", 7), "game_over")
	check_eq(_n("game_over", "continue", 7, true), "name_entry")
	check_eq(_n("game_over", "continue", 7, false), "highscores")
	check_eq(_n("victory", "continue", 20, true), "name_entry")
	check_eq(_n("victory", "continue", 20, false), "highscores")
	check_eq(_n("name_entry", "done", 20), "highscores")
	check_eq(_n("highscores", "back"), "title")


func test_pause_quit_returns_to_title_without_entry() -> void:
	check_eq(_n("level", "quit", 5, true), "title")


func test_full_run_sequence() -> void:
	# Simulate a complete successful run and record the visited screens.
	var seq: Array[String] = []
	var st := RunFlow.next("title", "start", 0)
	seq.append(st["screen"])
	st = RunFlow.next("ship_select", "confirm", 0)
	var guard := 0
	while st["screen"] != "title" and guard < 200:
		guard += 1
		var scr: String = st["screen"]
		var lvl := int(st["level"])
		seq.append(scr if scr != "level" else "L%d" % lvl)
		match scr:
			"level":
				st = RunFlow.next("level", "completed", lvl)
			"name_entry":
				st = RunFlow.next(scr, "done", lvl, true)
			"highscores":
				st = RunFlow.next(scr, "back", lvl, true)
			_:
				st = RunFlow.next(scr, "continue", lvl, true)
	var expected: Array[String] = ["ship_select",
		"L1", "interlevel", "L2", "interlevel", "L3", "interlevel", "arrival",
		"L4", "interlevel", "L5", "interlevel", "L6", "interlevel", "arrival",
		"L7", "interlevel", "L8", "interlevel", "L9", "interlevel", "arrival",
		"L10", "interlevel", "L11", "interlevel", "L12", "interlevel", "arrival",
		"L13", "bonus_result", "mars_rules",
		"L14", "interlevel", "L15", "interlevel", "L16", "interlevel", "arrival",
		"L17", "interlevel", "L18", "interlevel", "L19", "interlevel", "L20", "interlevel",
		"victory", "name_entry", "highscores"]
	check_eq(seq, expected, "full run")


func test_entry_qualifies() -> void:
	check(not RunFlow.entry_qualifies(0, true), "zero score never enters the list")
	check(RunFlow.entry_qualifies(10, true))
	check(not RunFlow.entry_qualifies(5000, false))


func test_parse_args() -> void:
	var a := RunFlow.parse_args(PackedStringArray(["--level=3", "--dev", "--screen=arrival", "--screenshot=/tmp/x.png",
		"--screenshot-delay=2.5", "--autoplay"]))
	check_eq(a["level"], "3")
	check_eq(a["dev"], true)
	check_eq(a["screen"], "arrival")
	check_eq(a["screenshot"], "/tmp/x.png")
	check_eq(a["autoplay"], true)
	check_eq(RunFlow.arg_int(a, "level", 1, 1, 20), 3)
	check_eq(RunFlow.arg_int({"level": "99"}, "level", 1, 1, 20), 20, "clamped")
	check_eq(RunFlow.arg_int({"level": "abc"}, "level", 4, 1, 20), 4, "invalid → default")
	check_eq(RunFlow.arg_int({}, "ship", 2, 0, 5), 2, "missing → default")
	check_near(RunFlow.arg_float(a, "screenshot-delay", 1.0), 2.5)
	check_near(RunFlow.arg_float({}, "screenshot-delay", 1.0), 1.0)


func test_arrival_timeline() -> void:
	# 0–3 s: only stars (fast stream), no message, no planet.
	check_eq(ArrivalScreen.message_alpha(0.0), 0.0)
	check_eq(ArrivalScreen.message_alpha(2.99), 0.0)
	check(ArrivalScreen.stream_speed(1.0) > 600.0, "fast stream right → left in the first 3 s")
	check_eq(ArrivalScreen.planet_diameter(3.0), 0.0)
	# 3–6 s: message fades in.
	check(ArrivalScreen.message_alpha(4.5) > 0.2 and ArrivalScreen.message_alpha(4.5) < 0.8, "fading in")
	check_near(ArrivalScreen.message_alpha(6.0), 1.0)
	check_eq(ArrivalScreen.message_offset(5.9), 0.0, "message does not move before 6 s")
	# 6–7 s: slides out to the left, gone at 7 s.
	check(ArrivalScreen.message_offset(6.5) < 0.0, "slides to the left")
	check(ArrivalScreen.message_offset(7.0) <= -960.0, "off-screen at 7 s")
	check_eq(ArrivalScreen.message_alpha(7.0), 0.0)
	# 7–12 s: planet appears small and zooms in for 5 s.
	check_eq(ArrivalScreen.planet_diameter(6.99), 0.0)
	check(ArrivalScreen.planet_diameter(7.0) > 0.0 and ArrivalScreen.planet_diameter(7.0) < 30.0, "small at 7 s")
	var prev := 0.0
	for i in 51:
		var d: float = ArrivalScreen.planet_diameter(7.0 + i * 0.1)
		check(d >= prev, "zoom is monotonic")
		prev = d
	check_near(ArrivalScreen.planet_diameter(12.0), ArrivalScreen.PLANET_D1, 0.01)
	check_near(ArrivalScreen.planet_diameter(15.0), ArrivalScreen.PLANET_D1, 0.01)
	check(ArrivalScreen.stream_speed(9.0) < 60.0, "stars drift slowly while the planet zooms")


func test_arrival_texts_are_exact() -> void:
	check_eq(LevelData.ARRIVAL_AFTER[3]["text"], "Neptun has been secured - approaching Uranus")
	check_eq(LevelData.ARRIVAL_AFTER[16]["text"], "Mars has been secured - protect EARTH!")


func test_highscore_columns_aligned() -> void:
	# Headings and values share anchor + alignment; numbers right-aligned, texts left-aligned.
	var right := ["RANK", "SCORE", "LEVEL", "TIME"]
	var names: Array[String] = []
	var last_x := -1.0
	for i in HighscoresScreen.COLUMNS.size():
		var c: Array = HighscoresScreen.column(i)
		names.append(c[0])
		check_eq(int(c[2]), int(HORIZONTAL_ALIGNMENT_RIGHT if right.has(c[0]) else HORIZONTAL_ALIGNMENT_LEFT),
			"alignment of %s" % c[0])
		check(float(c[1]) > last_x, "columns ordered left → right")
		last_x = float(c[1])
	check_eq(names, ["RANK", "NAME", "SCORE", "LEVEL", "TIME", "SHIP"] as Array[String])


func test_name_editor_respects_settings_limits() -> void:
	check_eq(NameEditor.max_len(), 5)
	check_eq(NameEditor.chars(), "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
