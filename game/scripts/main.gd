extends Node
## Screen manager and run flow (docs/SPEC.md §11, §17.1, §17.3, §19.2).
## Every screen is created with `new()`, configured with `setup(args)` before entering the tree and
## reports back through `finished(result, data)`. The flow decisions live in RunFlow (pure, tested).
## Two players (hotseat, SPEC §19.2): START with Settings.players == 2 runs the match setup (ship locks, hand-over,
## reveal, both ship selects – RunFlow.setup_next) and then the match (RunFlow.match_next): Run.switch_to(k) before
## player k's turn, so every screen that reads Run shows the player whose turn it is. At the end of the match every
## player whose score qualifies enters a name (best score first, each checked when it is his/her turn) and the
## highscore list highlights all entries of the match. A one-player run is exactly the classic flow (RunFlow.next).
##
## Dev / test command line (user args after `--`):
##   --level=N --ship=K --difficulty=D       start a run directly at level N (skips menus)
##   --players=2 [--ship2=K2]                (with --level) start a two-player match directly at PLAYER 1's TURN
##                                           screen of level N (ships K / K2, no locks)
##   --powerups                              POWER-UPS on for a direct start (one or two players) and for the fake
##                                           run of --screen (highscores: the power-up lists)
##   --dev [--invincible] [--autoplay]       dev flags for GameScreen (Run.dev_flags)
##   --screen=<name> [--arrival=N] [--name=ABC]  open one screen with fake run data (see RunFlow.SCREENS);
##                                           --name: initial name (name_entry), highlighted row of the fake
##                                           list (highscores), fake BEST line (title) – only without stored scores
##   --screen=<name> --players=2 [--player=k] [--other-out]  the two-player variant with a fake match (interlevel,
##                                           bonus_result, game_over, victory, name_entry, mars_rules, ship_select,
##                                           highscores – two highlighted rows); --player: whose screen (0 / 1);
##                                           --other-out: the other player is out (game over: MATCH OVER, mars rules:
##                                           one ship; without it game_over --player=1 --level=20 shows PLAYER 1
##                                           SAVED EARTH!). ship_lock, handover [--kind=locks|turn], lock_reveal,
##                                           match_result and turn are always two-player screens.
##   --select=<item> [--pending-display=<m>] (with --screen=title) initial menu row / a pending DISPLAY choice
##   --screen=attract                        start a demo run (attract mode) directly
##   --attract-after=<s>                     idle time on the title before the demo starts (default 90)
##   --attract-level=N --attract-seed=S      fixed demo level (1–20 except 13) / random seed (deterministic captures)
##   --screenshot=<abs path.png> [--screenshot-delay=<s>]   save a viewport PNG, then quit (modes 1–4: exactly the
##                                           render size 1920×1080 / 2560×1440 / 1280×800 / 1280×720; mode 0: the
##                                           window, 1280×960)
##   --quit-after=<s>                        quit after s seconds
##   --display=<0..4>                        display mode for this run (Display; not stored, no first-start screen)
##   --first-start                           show the first-start display choice even if one is stored

const GameScreenScript := preload("res://scripts/game/game_screen.gd")
const SCREEN_SCRIPTS := {
	"title": preload("res://scripts/screens/title_screen.gd"),
	"ship_select": preload("res://scripts/screens/ship_select_screen.gd"),
	"interlevel": preload("res://scripts/screens/interlevel_screen.gd"),
	"arrival": preload("res://scripts/screens/arrival_screen.gd"),
	"mars_rules": preload("res://scripts/screens/mars_rules_screen.gd"),
	"bonus_result": preload("res://scripts/screens/bonus_result_screen.gd"),
	"victory": preload("res://scripts/screens/victory_screen.gd"),
	"game_over": preload("res://scripts/screens/game_over_screen.gd"),
	"name_entry": preload("res://scripts/screens/name_entry_screen.gd"),
	"highscores": preload("res://scripts/screens/highscores_screen.gd"),
	"display_select": preload("res://scripts/screens/display_select_screen.gd"),
	"ship_lock": preload("res://scripts/screens/ship_lock_screen.gd"),
	"handover": preload("res://scripts/screens/handover_screen.gd"),
	"lock_reveal": preload("res://scripts/screens/lock_reveal_screen.gd"),
	"match_result": preload("res://scripts/screens/match_result_screen.gd"),
	"turn": preload("res://scripts/screens/handover_screen.gd"),   # the hand-over screen of kind "turn"
}
## Screens of the match setup / of a running match (their results go to RunFlow.setup_next / match_next).
const SETUP_SCREENS: Array[String] = ["ship_lock", "handover", "lock_reveal", "ship_select"]
const MATCH_SCREENS: Array[String] = ["turn", "level", "interlevel", "bonus_result", "game_over", "arrival",
	"mars_rules", "victory", "match_result", "name_entry", "highscores"]
## Dev screens (--screen) that only exist in a match, and those with a two-player variant (--players=2).
const DEV_MATCH_ONLY: Array[String] = ["ship_lock", "handover", "lock_reveal", "match_result", "turn"]
const DEV_MATCH_VARIANTS: Array[String] = ["ship_select", "interlevel", "arrival", "bonus_result", "mars_rules",
	"victory", "game_over", "name_entry", "highscores"]

var _screen: Node = null
var _screen_name := ""
var _args := {}
## Level the run is at (for "level": the level currently played / just finished).
var _level := 1
var _shot_path := ""
var _shot_delay := 0.0
var _shot_busy := false
var _clock := 0.0
## The highscore list was opened from the title menu (return there with HIGHSCORES selected).
var _hs_from_title := false

# --- Two-player match (SPEC §19.2) ------------------------------------------------------------------
## The match setup is running (lock / hand-over / reveal / ship select screens) …
var _setup := false
## … with the locks chosen so far ([ids PLAYER 1 may not fly, ids PLAYER 2 may not fly]) and the ships.
var _locks: Array = [[], []]
var _ships: Array = [0, 0]
## A match is running – from the first TURN screen up to the highscores.
var _match := false
## Player the current screen is for (step "player"; −1 = a shared screen).
var _screen_player := -1
## Player of the last level played (TURN screen rule, shared screens; −1 before the first level).
var _last_player := -1
## End of the match: players still to enter a name (entry order) and the entries made so far.
var _entry_queue: Array[int] = []
var _match_entries: Array = []


func _ready() -> void:
	_args = RunFlow.parse_args(OS.get_cmdline_user_args())
	var dev := _args.has("dev")
	Run.dev_flags = {
		"dev": dev,
		"invincible": dev and _args.has("invincible"),
		"autoplay": dev and _args.has("autoplay"),
	}
	# Display mode (--display is read by the Display autoload itself, so dev scenes get it too): the canvas is
	# set up already; the window follows here (not in screenshot runs – their image is the render size anyway).
	Display.apply_canvas()
	if not _args.has("screenshot"):
		Display.apply_window()
	AudioManager.apply_settings()
	if _args.has("screenshot"):
		_take_screenshot_later(String(_args["screenshot"]), RunFlow.arg_float(_args, "screenshot-delay", 1.0))
	if _args.has("quit-after"):
		_quit_later(RunFlow.arg_float(_args, "quit-after", 5.0))
	_start_from_args()


## The first screen: a dev screen (--screen), a direct start (--level, --players=2: a match), else the normal start.
func _start_from_args() -> void:
	if _args.has("screen"):
		_open_dev_screen(String(_args["screen"]))
	elif _args.has("level"):
		var lvl := RunFlow.arg_int(_args, "level", 1, LevelData.FIRST_LEVEL, LevelData.LAST_LEVEL)
		if RunFlow.arg_int(_args, "players", 1, 1, 2) == 2:
			Run.start_match(_arg_difficulty(), [_arg_ship(), _arg_ship2()], [[], []], lvl, _args.has("powerups"))
			_begin_match()
			_go(RunFlow.match_step("turn", lvl, 0))
		else:
			Run.start_new(_arg_difficulty(), _arg_ship(), lvl, _args.has("powerups"))
			_go(RunFlow.step("level", lvl))
	else:
		_go(RunFlow.step(RunFlow.first_screen(Settings.display_chosen, Display.forced_mode >= 0,
			_args.has("first-start"))))


# --- Flow ----------------------------------------------------------------------------------------
func _go(st: Dictionary, extra: Dictionary = {}) -> void:
	var screen_name: String = st["screen"]
	var lvl := int(st.get("level", 0))
	if lvl > 0:
		_level = lvl
	_screen_player = int(st.get("player", -1))
	match screen_name:
		"quit":
			Run.active = false
			get_tree().quit()
		"level":
			if _match:
				_turn_to(_screen_player)
				_last_player = _screen_player
			_start_level(_level)
		"display_select":
			Run.active = false
			_open("display_select", extra)
		"title":
			Run.active = false
			_end_match()
			if _args.has("attract-after"):
				extra = _merge({"attract_after": RunFlow.arg_float(_args, "attract-after", AttractDirector.IDLE_TIME)}, extra)
			_open("title", extra)
		"attract":
			_start_attract()
		"ship_select":
			if _setup:
				_open("ship_select", _merge({"ship": int(_ships[_screen_player]), "player": _screen_player,
					"locked": (_locks[_screen_player] as Array).duplicate()}, extra))
			else:   # the ship of the last run (after a match: PLAYER 1's)
				_open("ship_select", _merge({"ship": int(Run.player_get(0, "ship_id"))}, extra))
		"turn":
			_turn_to(_screen_player)
			_open("turn", _merge({"kind": "turn", "player": _screen_player, "level": _level}, extra))
		"interlevel", "arrival", "bonus_result", "mars_rules":
			_open(screen_name, _merge(_match_args(screen_name) if _match else {"level": _level}, extra))
		"victory", "game_over":
			if _match:
				if screen_name == "victory" or not RunFlow.anyone_left(_out()):
					Run.active = false
				_open(screen_name, _merge(_match_args(screen_name), extra))
			else:
				Run.active = false
				_open(screen_name, _merge({"level": _level,
					"qualifies": _run_qualifies()}, extra))
		"name_entry":
			if _match:
				_open("name_entry", _merge(_match_args(screen_name), extra))
			else:
				_open("name_entry", _merge({"difficulty": Run.difficulty, "score": Run.score, "time": Run.active_time,
					"level": Run.level, "ship": Run.ship_id, "powerups": Run.powerups}, extra))
		"highscores":
			var hs := {"difficulty": Settings.difficulty, "powerups": Settings.powerups}
			if _match:
				hs = {"difficulty": Run.difficulty, "powerups": Run.powerups,
					"ranks": RunFlow.entry_ranks(Settings.get_highscores(Run.difficulty, Run.powerups), _match_entries)}
			_open("highscores", _merge(hs, extra))
		"match_result":
			Run.active = false
			_open("match_result", extra)
		"ship_lock":
			_open("ship_lock", _merge({"player": _screen_player, "locked": []}, extra))
		"handover":
			_open("handover", _merge({"kind": "locks", "player": _screen_player}, extra))
		"lock_reveal":
			_open("lock_reveal", _merge({"locked": _locks.duplicate(true)}, extra))
		_:
			push_warning("Main: unknown screen '%s'" % screen_name)
			_open("title")


func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	out.merge(b, true)
	return out


func _run_qualifies() -> bool:
	return RunFlow.entry_qualifies(Run.score, Settings.qualifies(Run.difficulty, Run.score, Run.active_time,
		Run.powerups))


func _open(screen_name: String, screen_args: Dictionary = {}) -> void:
	var script: GDScript = SCREEN_SCRIPTS[screen_name]
	var s: Node = script.new()
	s.setup(screen_args)
	s.finished.connect(_on_screen_finished.bind(screen_name, s))
	_show(s, screen_name)


func _start_level(n: int) -> void:
	Run.level = n
	Run.active = true
	var gs: Node = GameScreenScript.new()
	gs.setup({"level": n})
	gs.finished.connect(_on_screen_finished.bind("level", gs))
	_show(gs, "level")


## Attract mode (SPEC §11.1): a demo run of the GameScreen. It never touches Run – Run.active stays false.
func _start_attract() -> void:
	var gs: Node = GameScreenScript.new()
	gs.setup({"attract": {"seed": RunFlow.arg_int(_args, "attract-seed", randi() & 0x7fffffff, 0, 0x7fffffff),
		"level": RunFlow.arg_int(_args, "attract-level", 0, 0, LevelData.LAST_LEVEL)}})
	gs.finished.connect(_on_screen_finished.bind("attract", gs))
	_show(gs, "attract")


func _show(screen: Node, screen_name: String) -> void:
	if _screen:
		if _screen.get_parent() == self:
			remove_child(_screen)
		_screen.queue_free()
	_screen = screen
	_screen_name = screen_name
	add_child(screen)
	InputRouter.require_release()


func _on_screen_finished(result: String, data: Dictionary, from: String, emitter: Node) -> void:
	# Switch screens at the end of the frame, never in the middle of the emitting screen's callback.
	_handle_finished.call_deferred(result, data, from, emitter)


func _handle_finished(result: String, data: Dictionary, from: String, emitter: Node) -> void:
	if emitter != _screen:
		return   # stale signal from a screen that has already been replaced
	if from == "level":
		if result == "game_over":
			Run.out = true
		elif result == "completed" and _level >= LevelData.LAST_LEVEL:
			Run.won = true
	if _setup and SETUP_SCREENS.has(from):
		_handle_setup(result, data, from)
		return
	if _match and MATCH_SCREENS.has(from):
		_handle_match(result, data, from)
		return
	var end_of_run := from == "victory" or from == "game_over"
	var nxt := RunFlow.next(from, result, _level, _run_qualifies() if end_of_run else false)
	match from:
		"title":
			_hs_from_title = result == "highscores"
			if _hs_from_title:
				_go(nxt, {"difficulty": Settings.difficulty, "powerups": Settings.powerups})
				return
			if result == "display":
				_go(nxt, {"select": "display"})   # the title again, on the new canvas
				return
			if result == "start" and Settings.players == 2:
				_begin_setup()
				_go(RunFlow.setup_next(from, result, -1))
				return
		"ship_select":
			if result == "confirm":
				Run.start_new(Settings.difficulty, int(data.get("ship", 0)), LevelData.FIRST_LEVEL, Settings.powerups)
				_level = LevelData.FIRST_LEVEL
				nxt = RunFlow.next(from, result, _level)
		"victory", "game_over":
			_hs_from_title = false
			_go(nxt, {"difficulty": Run.difficulty, "powerups": Run.powerups})
			return
		"name_entry":
			_go(nxt, {"difficulty": int(data.get("difficulty", Run.difficulty)), "rank": int(data.get("rank", -1)),
				"powerups": Run.powerups})
			return
		"highscores":
			_go(nxt, {"select": "highscores" if _hs_from_title else "start"})
			_hs_from_title = false
			return
	_go(nxt)


# --- Two-player match (SPEC §19.2) ------------------------------------------------------------------
## The setup starts (title START with two players): no locks yet, the ships of the last run preselected.
func _begin_setup() -> void:
	_setup = true
	_match = false
	_locks = [[], []]
	for k in 2:
		_ships[k] = int(Run.player_get(k, "ship_id")) if Run.is_two_player() else Run.ship_id


## The match starts (Run.start_match has been called): PLAYER 1's TURN screen of the first level comes next.
func _begin_match() -> void:
	_setup = false
	_match = true
	_last_player = -1
	_entry_queue.clear()
	_match_entries.clear()


## Back on the title: setup / match are over (aborted or finished). Run keeps the last match (ship preselection).
func _end_match() -> void:
	_setup = false
	_match = false
	_screen_player = -1
	_last_player = -1
	_entry_queue.clear()
	_match_entries.clear()


## Makes player k current (Run's per-player fields show his/her state).
func _turn_to(k: int) -> void:
	if k >= 0:
		Run.switch_to(k)


## [PLAYER 1 out, PLAYER 2 out].
func _out() -> Array:
	return [bool(Run.player_get(0, "out")), bool(Run.player_get(1, "out"))]


func _handle_setup(result: String, data: Dictionary, from: String) -> void:
	var p := _screen_player
	match from:
		"ship_lock":
			if result == "done":
				# Player p locked ships for the OTHER player.
				var ids: Array = []
				for id in data.get("locked", []):
					ids.append(int(id))
				ids.sort()
				_locks[1 - p] = ids
		"ship_select":
			if result == "confirm":
				_ships[p] = int(data.get("ship", 0))
	var nxt := RunFlow.setup_next(from, result, p)
	if from == "ship_select" and result == "confirm" and p == 1:
		Run.start_match(Settings.difficulty, _ships.duplicate(), _locks.duplicate(true), LevelData.FIRST_LEVEL,
			Settings.powerups)
		_begin_match()
	_go(nxt)


func _handle_match(result: String, data: Dictionary, from: String) -> void:
	var p := _screen_player if _screen_player >= 0 else _last_player
	match from:
		"match_result":
			_entry_queue = RunFlow.entry_order([Run.player_get(0, "score"), Run.player_get(1, "score")],
				[Run.player_get(0, "active_time"), Run.player_get(1, "active_time")])
		"name_entry":
			if data.has("entry"):
				_match_entries.append(data["entry"])
	var entry := _next_entry() if from == "match_result" or from == "name_entry" else -1
	_go(RunFlow.match_next(from, result, _level, p, _out(), entry))


## The next player of the entry queue whose score enters the list NOW (after the better ones were inserted),
## or −1. Players who do not qualify are skipped.
func _next_entry() -> int:
	while not _entry_queue.is_empty():
		var k: int = _entry_queue.pop_front()
		var score := int(Run.player_get(k, "score"))
		var time := float(Run.player_get(k, "active_time"))
		if RunFlow.entry_qualifies(score, Settings.qualifies(Run.difficulty, score, time, Run.powerups)):
			return k
	return -1


## setup args of a match screen (the current step: _level, _screen_player).
func _match_args(screen_name: String) -> Dictionary:
	var k := _screen_player
	var n := _level
	var out := _out()
	match screen_name:
		"interlevel":
			return {"level": n, "player": k, "next_player": RunFlow.next_in_round(k, out),
				"next_screen": String(RunFlow.match_next("interlevel", "continue", n, k, out)["screen"])}
		"bonus_result":
			return {"level": n, "player": k, "next_player": RunFlow.next_in_round(k, out)}
		"game_over":
			var other := 1 - k
			var status := "out" if bool(out[other]) else ("won" if bool(Run.player_get(other, "won")) else "plays_on")
			return {"level": n, "qualifies": false, "player": k, "other_status": status,
				"next_screen": String(RunFlow.match_next("game_over", "continue", n, k, out)["screen"])}
		"mars_rules":
			var ships: Array = []
			for j in 2:
				if not bool(out[j]):
					ships.append(int(Run.player_get(j, "ship_id")))
			return {"level": n, "ships": ships}
		"victory":
			return {"level": n, "match": true}
		"name_entry":
			return {"player": k, "difficulty": Run.difficulty, "score": int(Run.player_get(k, "score")),
				"time": float(Run.player_get(k, "active_time")), "level": int(Run.player_get(k, "level")),
				"ship": int(Run.player_get(k, "ship_id")), "powerups": Run.powerups}
	return {"level": n}


# --- Dev helpers ---------------------------------------------------------------------------------
func _arg_difficulty() -> int:
	return RunFlow.arg_int(_args, "difficulty", Settings.difficulty, 0, 3)


func _arg_ship() -> int:
	return RunFlow.arg_int(_args, "ship", 0, 0, ShipData.SHIPS.size() - 1)


## --ship2: PLAYER 2's ship of a direct two-player start (default: the same as --ship).
func _arg_ship2() -> int:
	return RunFlow.arg_int(_args, "ship2", _arg_ship(), 0, ShipData.SHIPS.size() - 1)


## Opens a single screen with plausible fake run data (for screenshots / visual checks).
func _open_dev_screen(screen_name: String) -> void:
	if screen_name == "attract":
		AudioManager.play_title_music()   # a demo runs on the title music (normally it is already playing)
		_go(RunFlow.step("attract"))
		return
	if not SCREEN_SCRIPTS.has(screen_name):
		push_warning("Main: unknown --screen=%s, valid: %s, attract" % [screen_name, ", ".join(RunFlow.SCREENS)])
		_go(RunFlow.step("title"))
		return
	var diff := _arg_difficulty()
	var ship := _arg_ship()
	var lvl := RunFlow.arg_int(_args, "level", 5, LevelData.FIRST_LEVEL, LevelData.LAST_LEVEL)
	match screen_name:
		"arrival":
			lvl = RunFlow.arg_int(_args, "arrival", 3, 1, LevelData.LAST_LEVEL)
			if not LevelData.ARRIVAL_AFTER.has(lvl):
				lvl = 3
		"bonus_result":
			lvl = LevelData.BONUS_LEVEL
		"mars_rules":
			lvl = LevelData.BONUS_LEVEL
		"victory":
			lvl = LevelData.LAST_LEVEL
	Run.start_new(diff, ship, lvl, _args.has("powerups"))
	_fake_player(lvl, 0)
	_level = lvl
	if DEV_MATCH_ONLY.has(screen_name) or (DEV_MATCH_VARIANTS.has(screen_name) and
			RunFlow.arg_int(_args, "players", 1, 1, 2) == 2):
		_open_dev_match_screen(screen_name, diff, ship, lvl)
		return
	match screen_name:
		"display_select":
			Run.active = false
			_go(RunFlow.step(screen_name))
			return
		"title", "ship_select":
			Run.active = false
			Run.score = 0
			var extra := {}
			if screen_name == "title" and _args.has("name") and Settings.get_highscores(Settings.difficulty).is_empty():
				extra["preview_best"] = {"name": _arg_name(), "score": 48000}
			if screen_name == "title" and _args.has("select"):
				extra["select"] = String(_args["select"])
			if screen_name == "title" and _args.has("pending-display"):
				extra["display_pending"] = RunFlow.arg_int(_args, "pending-display", 0, 0, Display.MODE_COUNT - 1)
			_go(RunFlow.step(screen_name), extra)
		"highscores":
			var pu := _args.has("powerups")
			var extra := {"difficulty": diff, "powerups": pu}
			if Settings.get_highscores(diff, pu).is_empty():
				extra["preview_entries"] = _fake_highscores()
				extra["rank"] = 2
			_go(RunFlow.step("highscores"), extra)
		"name_entry":
			_go(RunFlow.step(screen_name, lvl), {"initial_name": String(_args.get("name", ""))})
		_:
			_go(RunFlow.step(screen_name, lvl))


## Plausible fake state of player k at level lvl (score, play time, lives, last level / bonus result).
func _fake_player(lvl: int, k: int) -> void:
	Run.score = 1000 + lvl * 1234 if k == 0 else 800 + lvl * 1111
	Run.active_time = 41.7 * lvl + 12.3 if k == 0 else 44.2 * lvl + 3.1
	Run.lives = 2 if k == 0 else 1
	var lr: Dictionary = LevelData.level(lvl)
	Run.last_level_result = {"level": lvl, "completion_bonus": int(lr["bonus"]),
		"extra_life": LevelData.flawless_extra_life(lvl), "flawless": true}
	var remaining := 37 if k == 0 else 18
	var factor := int(ShipData.ship(Run.ship_id)["bonus_factor"])
	var bonus := LevelData.bonus_value(remaining, Run.ship_id)
	Run.last_bonus_result = {"remaining": remaining, "factor": factor, "bonus": bonus,
		"extra_life": LevelData.bonus_gives_extra_life(bonus)}


## Two-player dev screens (SPEC §19.2): a fake match – PLAYER 1 may not fly ships 4 / 5, PLAYER 2 not ship 0; PLAYER 2
## flies --ship2 (default: --ship + 3). --player=k: whose screen; --other-out: the other player has lost his/her
## last life. The screen gets exactly the args the real flow gives it (and continues the match when confirmed).
func _open_dev_match_screen(screen_name: String, diff: int, ship: int, lvl: int) -> void:
	var p := RunFlow.arg_int(_args, "player", 0, 0, 1)
	var other_out := _args.has("other-out")
	var ship2 := RunFlow.arg_int(_args, "ship2", posmod(ship + 3, ShipData.SHIPS.size()), 0, ShipData.SHIPS.size() - 1)
	var locks := [[4, 5], [0]]
	Run.start_match(diff, [ship, ship2], locks, lvl, _args.has("powerups"))
	for k in 2:
		Run.switch_to(k)
		_fake_player(lvl, k)
		Run.won = screen_name == "victory"
	if other_out:
		Run.switch_to(1 - p)
		Run.out = true
		Run.lives = 0
		Run.level = maxi(lvl - 2, LevelData.FIRST_LEVEL)
		Run.won = false
	if screen_name == "game_over" and p == 1 and lvl == LevelData.LAST_LEVEL and not other_out:
		Run.switch_to(0)
		Run.won = true   # PLAYER 1 has completed level 20 before: "PLAYER 1 SAVED EARTH!"
	Run.switch_to(p)
	if screen_name == "game_over":
		Run.out = true
		Run.lives = 0
	_locks = locks
	_ships = [ship, ship2]
	_level = lvl
	match screen_name:
		"ship_lock", "lock_reveal", "ship_select":
			Run.active = false
			_setup = true
			_go(RunFlow.match_step(screen_name, 0, p if screen_name != "lock_reveal" else -1))
			return
		"handover":
			if String(_args.get("kind", "turn")) == "locks":
				Run.active = false
				_setup = true
				_go(RunFlow.match_step("handover", 0, 1))
				return
			screen_name = "turn"
		"highscores":
			_match = true
			var pu := _args.has("powerups")
			var extra := {"difficulty": diff, "powerups": pu, "ranks": [1, 4]}
			if Settings.get_highscores(diff, pu).is_empty():
				extra["preview_entries"] = _fake_highscores()
			_go(RunFlow.match_step("highscores", lvl, -1), extra)
			return
	_match = true
	_last_player = p
	var extra := {}
	if screen_name == "name_entry":
		extra["initial_name"] = String(_args.get("name", ""))
	var shared := ["arrival", "mars_rules", "victory", "match_result"].has(screen_name)
	_go(RunFlow.match_step(screen_name, lvl, -1 if shared else p), extra)


## --name as it would be stored (upper case, valid characters, max Settings.NAME_MAX).
func _arg_name() -> String:
	return Settings.sanitize_name(String(_args.get("name", "")))


## Fake top 10 with names of 2–8 characters; --name replaces the highlighted row (index 2).
func _fake_highscores() -> Array:
	var names := ["STARDUST", "ACE", "ZED-9", "PILOT", "KIRA", "MAX_", "COMET-42", "IO", "VEGA", "B0B"]
	if _args.has("name"):
		names[2] = _arg_name()
	var out: Array = []
	for i in 10:
		out.append({"name": names[i], "score": 48000 - i * 3870 - (i * i) * 113,
			"time": 1500.0 - i * 61.3, "level": 20 - i * 2, "ship": i % 6})
	return out


func _take_screenshot_later(path: String, delay: float) -> void:
	_shot_path = path
	_shot_delay = maxf(delay, 0.0)


## Screenshot delay is measured with the same process deltas the screens see (so a delay of 5 s
## shows a screen at its own time 5 s even if the first frames were slow, e.g. under llvmpipe).
func _process(delta: float) -> void:
	if _shot_path == "":
		return
	_clock += delta
	if _clock >= _shot_delay and not _shot_busy:
		_shot_busy = true
		_capture.call_deferred()


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		DirAccess.make_dir_recursive_absolute(_shot_path.get_base_dir())
		var err := img.save_png(_shot_path)
		var st: Variant = _screen.get("time") if _screen else null
		print("Screenshot saved: %s (%s)%s" % [_shot_path, error_string(err),
			"" if st == null else " at screen time %.2f s" % float(st)])
	get_tree().quit()


func _quit_later(seconds: float) -> void:
	await get_tree().create_timer(maxf(seconds, 0.0), true, false, true).timeout
	get_tree().quit()
