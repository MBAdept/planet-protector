extends TestBase
## Shared state of two-player matches and power-up runs (docs/SPEC.md §19): Run's per-player slots, the PLAYERS /
## POWER-UPS settings and the separate power-up highscore lists, LevelData.powerup_of.

var _saved := {}


func _save_settings() -> void:
	_saved = {"path": Settings.settings_path, "hs_path": Settings.highscore_path, "players": Settings.players,
		"powerups": Settings.powerups, "classic": Settings.get("_highscores").duplicate(true),
		"pu": Settings.get("_highscores_pu").duplicate(true)}
	var dir := OS.get_user_data_dir().path_join("test_hotseat_state")
	DirAccess.make_dir_recursive_absolute(dir)
	Settings.settings_path = dir.path_join("settings.cfg")
	Settings.highscore_path = dir.path_join("highscores.json")
	DirAccess.remove_absolute(Settings.settings_path)
	DirAccess.remove_absolute(Settings.highscore_path)


func _restore_settings() -> void:
	Settings.settings_path = _saved["path"]
	Settings.highscore_path = _saved["hs_path"]
	Settings.players = _saved["players"]
	Settings.powerups = _saved["powerups"]
	Settings.set("_highscores", _saved["classic"])
	Settings.set("_highscores_pu", _saved["pu"])


func test_start_new_is_one_player() -> void:
	Run.start_new(1, 4, 3, true)
	check_eq(Run.players, 1)
	check_eq(Run.current, 0)
	check(Run.powerups, "power-ups on")
	check(not Run.is_two_player())
	check_eq(Run.ship_id, 4)
	check_eq(Run.level, 3)
	check_eq(Run.lives, 3)
	check(not Run.out and not Run.won)
	Run.switch_to(1)   # no-op with one player
	check_eq(Run.current, 0)
	check_eq(Run.ship_id, 4)
	Run.start_new(1, 0)
	check(not Run.powerups, "default: power-ups off")


func test_match_slots_swap_per_player_state() -> void:
	Run.start_match(0, [2, 5], [[4, 5], [0]], 1, false)
	check(Run.is_two_player())
	check_eq(Run.current, 0)
	check_eq(Run.ship_id, 2)
	check_eq(Run.lives, 5, "BEGINNER lives")
	check_eq(Run.locked, [4, 5] as Array[int])
	Run.score = 1234
	Run.lives = 2
	Run.active_time = 61.5
	Run.level = 4
	Run.last_level_result = {"level": 3}
	Run.switch_to(1)
	check_eq(Run.current, 1)
	check_eq(Run.ship_id, 5)
	check_eq(Run.score, 0)
	check_eq(Run.lives, 5)
	check_eq(Run.level, 1)
	check_eq(Run.locked, [0] as Array[int])
	check_eq(Run.last_level_result, {})
	check_eq(int(Run.player_get(0, "score")), 1234, "parked P1 score")
	check_eq(int(Run.player_get(1, "score")), 0, "live P2 score")
	Run.score = 77
	Run.out = true
	Run.switch_to(0)
	check_eq(Run.score, 1234)
	check_eq(Run.lives, 2)
	check_near(Run.active_time, 61.5)
	check_eq(Run.level, 4)
	check_eq(Run.last_level_result, {"level": 3})
	check(not Run.out)
	check_eq(int(Run.player_get(1, "score")), 77)
	check(bool(Run.player_get(1, "out")))
	check_eq(Run.player_label(1), "PLAYER 2")


func test_parked_dictionaries_are_copies() -> void:
	Run.start_match(1, [0, 1], [[], []])
	Run.last_level_result = {"level": 1}
	Run.switch_to(1)
	Run.switch_to(0)
	Run.last_level_result["level"] = 9
	Run.switch_to(1)
	Run.switch_to(0)
	check_eq(int(Run.last_level_result["level"]), 9, "live dictionary survives a round trip")


func test_settings_players_and_powerups_persist() -> void:
	_save_settings()
	Settings.set_players(2)
	Settings.set_powerups(true)
	Settings.players = 1
	Settings.powerups = false
	Settings.load_settings()
	check_eq(Settings.players, 2)
	check(Settings.powerups)
	Settings.set_players(7)
	check_eq(Settings.players, 1, "invalid → 1")
	check_eq(Settings.clean_players(2.0), 2)
	check_eq(Settings.clean_players("2"), 1)
	_restore_settings()


func test_powerup_highscores_are_separate_lists() -> void:
	_save_settings()
	Settings.set("_highscores", {0: [], 1: [], 2: [], 3: []})
	Settings.set("_highscores_pu", {0: [], 1: [], 2: [], 3: []})
	check_eq(Settings.insert_highscore(1, {"name": "AAA", "score": 500, "time": 10.0, "level": 2, "ship": 0}), 0)
	check_eq(Settings.insert_highscore(1, {"name": "BBB", "score": 900, "time": 10.0, "level": 3, "ship": 1}, true), 0)
	check_eq(Settings.get_highscores(1).size(), 1)
	check_eq(String(Settings.get_highscores(1)[0]["name"]), "AAA")
	check_eq(String(Settings.get_highscores(1, true)[0]["name"]), "BBB")
	check_eq(Settings.list_key(2, false), "2")
	check_eq(Settings.list_key(2, true), "p2")
	Settings.load_highscores()
	check_eq(String(Settings.get_highscores(1)[0]["name"]), "AAA", "classic list reloads")
	check_eq(String(Settings.get_highscores(1, true)[0]["name"]), "BBB", "power-up list reloads")
	_restore_settings()


func test_old_highscore_file_has_no_powerup_lists() -> void:
	_save_settings()
	var f := FileAccess.open(Settings.highscore_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"0": [{"name": "OLD", "score": 100, "time": 5.0, "level": 1, "ship": 0}],
		"1": [], "2": [], "3": []}))
	f.close()
	Settings.load_highscores()
	check_eq(Settings.get_highscores(0).size(), 1)
	for d in 4:
		check_eq(Settings.get_highscores(d, true).size(), 0, "no power-up entries for %d" % d)
	_restore_settings()


func test_powerup_of_levels() -> void:
	var P := LevelData.PowerUp
	for n in range(1, 21):
		var expected: int = P.NONE
		if n >= 7 and n <= 9:
			expected = P.RAPID_FIRE
		elif n >= 10 and n <= 12:
			expected = P.TWIN
		elif n >= 14 and n <= 16:
			expected = P.SHIELD
		check_eq(LevelData.powerup_of(n), expected, "level %d" % n)
	check_eq(LevelData.powerup_of(LevelData.BONUS_LEVEL), P.NONE, "bonus level")
	check_near(float(LevelData.POWERUP_TIME[P.TWIN]), 15.0)
