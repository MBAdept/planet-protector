extends TestBase
## Two players (hotseat) + power-ups, menu side (client request, forum round; docs/SPEC.md §11, §19.2, §19.3):
## the title rows PLAYERS / POWER-UPS (binary, no auto-repeat, persisted, explanation line, BEST line per category,
## the 11-row layout in every display mode), the ship select with locked ships (refused, never the start
## selection), and the new screens SHIP LOCK (toggling, max 3 + refusal, DONE sorted, back), HAND-OVER (both kinds,
## confirm delay, keys, music, no lock information), LOCK REVEAL (exactly the locks, one clink per stamp) and
## MATCH RESULT (winner / draw), plus their layout on every canvas (960 / 1152 / 1280 × 720, label sizes of modes 3/4).
## Like the other screen tests these run before the SceneTree is live: screens are driven by hand (_ready /
## _process), the InputRouter is stepped manually, every pressed key is released again. Settings and highscores go
## to scratch files and every touched value is restored; display modes are forced and restored.

const TitleScreen := preload("res://scripts/screens/title_screen.gd")
const ShipSelect := preload("res://scripts/screens/ship_select_screen.gd")
const ShipLock := preload("res://scripts/screens/ship_lock_screen.gd")
const Handover := preload("res://scripts/screens/handover_screen.gd")
const LockReveal := preload("res://scripts/screens/lock_reveal_screen.gd")
const MatchResult := preload("res://scripts/screens/match_result_screen.gd")

const STEP := 1.0 / 60.0
const SCRATCH_DIR := "test_hotseat_screens"


# --- Spies: record sounds and finished() instead of playing / switching ----------------------------
class SpyTitle extends TitleScreen:
	var sfx_calls: Array[String] = []
	var results: Array = []

	func sfx(n: String) -> void:
		sfx_calls.append(n)

	func finish(result: String, data: Dictionary = {}) -> void:
		results.append([result, data])
		super(result, data)


class SpySelect extends ShipSelect:
	var sfx_calls: Array[String] = []
	var results: Array = []

	func sfx(n: String) -> void:
		sfx_calls.append(n)

	func finish(result: String, data: Dictionary = {}) -> void:
		results.append([result, data])
		super(result, data)


class SpyLock extends ShipLock:
	var sfx_calls: Array[String] = []
	var results: Array = []

	func sfx(n: String) -> void:
		sfx_calls.append(n)

	func finish(result: String, data: Dictionary = {}) -> void:
		results.append([result, data])
		super(result, data)


class SpyHandover extends Handover:
	var sfx_calls: Array[String] = []
	var results: Array = []

	func sfx(n: String) -> void:
		sfx_calls.append(n)

	func finish(result: String, data: Dictionary = {}) -> void:
		results.append([result, data])
		super(result, data)


class SpyReveal extends LockReveal:
	var sfx_calls: Array[String] = []
	var results: Array = []

	func sfx(n: String) -> void:
		sfx_calls.append(n)

	func finish(result: String, data: Dictionary = {}) -> void:
		results.append([result, data])
		super(result, data)


class SpyResult extends MatchResult:
	var sfx_calls: Array[String] = []
	var results: Array = []

	func sfx(n: String) -> void:
		sfx_calls.append(n)

	func finish(result: String, data: Dictionary = {}) -> void:
		results.append([result, data])
		super(result, data)


## No joypad exists headless: the InputRouter autoload gets a subclass that reads a fake button table (as in
## test_volume.gd / test_display.gd).
class FakePadRouter extends "res://scripts/autoload/input_router.gd":
	var pad := {}

	func _joy(button: JoyButton) -> bool:
		return bool(pad.get(button, false))

	func _left_sticks() -> Dictionary:
		return {}


# --- Helpers -------------------------------------------------------------------------------------
var _saved := {}
var _orig_router: Script


## Settings and highscores → scratch files; remembers every value the tests touch.
func _settings_begin() -> void:
	_saved = {"path": Settings.settings_path, "hs_path": Settings.highscore_path, "players": Settings.players,
		"powerups": Settings.powerups, "difficulty": Settings.difficulty,
		"classic": Settings.get("_highscores").duplicate(true), "pu": Settings.get("_highscores_pu").duplicate(true)}
	var dir := OS.get_user_data_dir().path_join(SCRATCH_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	Settings.settings_path = dir.path_join("settings.cfg")
	Settings.highscore_path = dir.path_join("highscores.json")
	DirAccess.remove_absolute(Settings.settings_path)
	DirAccess.remove_absolute(Settings.highscore_path)


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


func _stored(section: String, key: String) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(Settings.settings_path) != OK:
		return null
	return cfg.get_value(section, key, null)


func _fonts() -> void:
	if Assets.font_title == null:
		Assets._ready()


func _force(m: int) -> int:
	var before := Display.forced_mode
	Display.forced_mode = m
	Display.apply_canvas()
	return before


func _restore(before: int) -> void:
	Display.forced_mode = before
	Display.apply_canvas()


func _router_init() -> void:
	if (InputRouter.get("_down") as Dictionary).is_empty():
		InputRouter._ready()
	InputRouter.set_text_mode(false)
	_router_step()


func _router_step(dt: float = STEP) -> void:
	Input.flush_buffered_events()
	InputRouter._process(dt)


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


## Press (one frame) and release (two frames) of a key while the screen runs.
func _tap(screen: Node, code: Key, times: int = 1) -> void:
	for i in times:
		_key(code, true)
		_run(screen, STEP)
		_key(code, false)
		_run(screen, STEP * 2)


func _swap_in() -> void:
	_orig_router = InputRouter.get_script()
	InputRouter.set_script(FakePadRouter)
	InputRouter._ready()
	InputRouter.set_text_mode(false)
	InputRouter._process(STEP)


func _swap_out() -> void:
	InputRouter.set_script(_orig_router)
	InputRouter._ready()
	InputRouter._process(STEP)


func _pad_tap(screen: Node, button: JoyButton) -> void:
	InputRouter.pad[button] = true
	_run(screen, STEP)
	InputRouter.pad[button] = false
	_run(screen, STEP * 2)


func _open(screen: Node, args: Dictionary) -> Node:
	screen.setup(args)
	screen._ready()
	_run(screen, 0.1)
	return screen


## A match with fixed scores etc. (state of player k: fields → values).
func _match(level: int, powerups: bool, p0: Dictionary = {}, p1: Dictionary = {}) -> void:
	Run.start_match(1, [0, 3], [[4, 5], [0]], level, powerups)
	for k in 2:
		Run.switch_to(k)
		var d: Dictionary = p0 if k == 0 else p1
		for key: String in d:
			Run.set(key, d[key])
	Run.switch_to(0)


func _end_match() -> void:
	Run.start_new(1, 0)
	Run.active = false


# --- SHIP LOCK -----------------------------------------------------------------------------------
func test_ship_lock_toggle_limit_and_done() -> void:
	_router_init()
	var s: SpyLock = _open(SpyLock.new(), {"player": 0}) as SpyLock
	check(AudioManager.is_title_music_playing(), "title music on the setup screens")
	check_eq([s.player, s.target(), s.selected()], [0, 1, 0], "PLAYER 1 locks for PLAYER 2, cursor on the first ship")
	check_eq(s.title_text(), "PLAYER 1 LOCKS")
	check_eq(s.warning_text(), "PLAYER 2 – LOOK AWAY!")
	_tap(s, KEY_ENTER)
	check_eq(s.locked, [0] as Array[int], "Enter locks the selected ship")
	check_eq(s.sfx_calls.back(), "locked_hit", "the lock clinks")
	_tap(s, KEY_DOWN, 5)
	check_eq(s.selected(), 5, "down 5×")
	_tap(s, KEY_ENTER)
	_tap(s, KEY_UP)
	_tap(s, KEY_SPACE)
	check_eq(s.locked, [0, 5, 4] as Array[int], "Space locks too")
	_tap(s, KEY_UP)
	s.sfx_calls.clear()
	_tap(s, KEY_ENTER)
	check_eq(s.locked, [0, 5, 4] as Array[int], "a 4th lock is refused")
	check_eq(s.sfx_calls, ["menu_back"] as Array[String], "refused with the back sound")
	check(s.time - float(s.get("_refused_at")) < 0.1, "the refusal message starts")
	check(s.results.is_empty(), "no finish")
	_tap(s, KEY_DOWN, 2)
	_tap(s, KEY_ENTER)
	check_eq(s.locked, [0, 4] as Array[int], "Enter on a locked ship unlocks it")
	check_eq(s.sfx_calls.back(), "menu_move", "unlock: soft blip")
	_tap(s, KEY_UP, 2)
	_tap(s, KEY_ENTER)
	check_eq(s.locked, [0, 4, 3] as Array[int], "now a third one fits again")
	_tap(s, KEY_DOWN, 3)
	check_eq(s.selected(), ShipLock.done_row(), "DONE after the six ships")
	_tap(s, KEY_ENTER)
	check_eq(s.results.size(), 1, "finished once")
	if s.results.size() == 1:
		check_eq(s.results[0][0], "done")
		check_eq(s.results[0][1], {"locked": [0, 3, 4] as Array[int]}, "DONE reports the locks sorted")
	check_eq(s.locked, [0, 4, 3] as Array[int], "the screen's own list is untouched")
	s.free()
	# Up from the first ship wraps to DONE; DONE with no locks reports an empty list.
	var s2: SpyLock = _open(SpyLock.new(), {"player": 1}) as SpyLock
	_tap(s2, KEY_UP)
	check_eq(s2.selected(), ShipLock.done_row(), "up wraps to DONE")
	_tap(s2, KEY_ENTER)
	check_eq(s2.results, [["done", {"locked": [] as Array[int]}]], "no locks")
	s2.free()


func test_ship_lock_initial_locks_back_and_controller() -> void:
	_router_init()
	var s: SpyLock = _open(SpyLock.new(), {"player": 1, "locked": [3, 3, 9, -1, 1, 0, 5]}) as SpyLock
	check_eq(s.locked, [3, 1, 0] as Array[int], "initial locks: valid, unique, at most 3")
	check_eq(s.result_locks(), [0, 1, 3] as Array[int])
	check_eq([s.title_text(), s.warning_text()], ["PLAYER 2 LOCKS", "PLAYER 1 – LOOK AWAY!"])
	_tap(s, KEY_ESCAPE)
	check_eq(s.results, [["back", {}]], "Escape → back (setup aborted)")
	s.free()
	_swap_in()
	var p: SpyLock = _open(SpyLock.new(), {"player": 0}) as SpyLock
	_pad_tap(p, JOY_BUTTON_A)
	check_eq(p.locked, [0] as Array[int], "A locks")
	_pad_tap(p, JOY_BUTTON_X)
	check_eq(p.locked, [] as Array[int], "X unlocks")
	_pad_tap(p, JOY_BUTTON_Y)
	_pad_tap(p, JOY_BUTTON_START)
	check_eq(p.locked, [] as Array[int], "Y locks, Start unlocks")
	check(p.results.is_empty(), "no finish yet")
	_pad_tap(p, JOY_BUTTON_B)
	check_eq(p.results, [["back", {}]], "B → back")
	p.free()
	_swap_out()


# --- SHIP SELECT ---------------------------------------------------------------------------------
func test_ship_select_refuses_locked_ships() -> void:
	check_eq(ShipSelect.initial_selection(0, [0]), 1, "requested ship locked → first free")
	check_eq(ShipSelect.initial_selection(2, [0, 1, 2]), 3)
	check_eq(ShipSelect.initial_selection(4, [4, 5]), 0)
	check_eq(ShipSelect.initial_selection(5, []), 5, "free → as requested")
	check_eq(ShipSelect.initial_selection(9, []), 5, "clamped")
	_router_init()
	var s: SpySelect = _open(SpySelect.new(), {"player": 0, "locked": [4, 5], "ship": 4}) as SpySelect
	check_eq(s.selected(), 0, "starts on the first free ship")
	var previews: Array = s.get("_previews")
	var flags: Array[bool] = []
	for p: Control in previews:
		flags.append(bool(p.get("locked")))
	check_eq(flags, [false, false, false, false, true, true] as Array[bool], "locked previews stand still")
	check_eq(String(previews[4].get("lock_text")), "LOCKED BY PLAYER 2")
	_tap(s, KEY_RIGHT, 4)
	check_eq(s.selected(), 4, "the cursor may rest on a locked ship")
	s.sfx_calls.clear()
	_tap(s, KEY_ENTER)
	_tap(s, KEY_SPACE)
	check(s.results.is_empty(), "confirm on a locked ship is refused")
	check_eq(s.sfx_calls, ["menu_back", "menu_back"] as Array[String], "refused with the back sound")
	check_eq(ShipSelect.locked_line_text(0), "Locked by PLAYER 2 – choose a free ship")
	_tap(s, KEY_LEFT)
	_tap(s, KEY_ENTER)
	check_eq(s.results, [["confirm", {"ship": 3}]], "a free ship is confirmed")
	s.free()
	# PLAYER 2 with ship 0 locked; the one-player screen has no locks at all.
	var s2: SpySelect = _open(SpySelect.new(), {"player": 1, "locked": [0]}) as SpySelect
	check_eq(s2.selected(), 1, "PLAYER 2: ship 0 locked → FIGHTER")
	check_eq(ShipSelect.player_title(1), "PLAYER 2  –  CHOOSE YOUR SHIP")
	s2.free()
	var s3: SpySelect = _open(SpySelect.new(), {"ship": 2}) as SpySelect
	check_eq([s3.player, s3.locked.size(), s3.selected()], [-1, 0, 2], "one player: classic screen")
	_tap(s3, KEY_ENTER)
	check_eq(s3.results, [["confirm", {"ship": 2}]])
	s3.free()


func test_ship_select_two_player_header_fits_every_mode() -> void:
	_fonts()
	for m in Display.MODE_COUNT:
		var before := _force(m)
		var ox := Display.center_offset()
		var rx := ScreenBase.W + ox - 24.0   # right edge of the DIFFICULTY caption
		var cap_w := 0.0
		for d in 4:
			cap_w = maxf(cap_w, UiKit.text_width(Assets.font_title, String(ShipData.difficulty(d)["name"]), 15))
		cap_w = maxf(cap_w, UiKit.text_width(Assets.font_body, "DIFFICULTY", UiKit.label_size(12)))
		for k in 2:
			var size := ShipSelect.title_size(k)
			var w := UiKit.text_width(Assets.font_title_heavy, ShipSelect.player_title(k), size)
			check(size >= 28, "mode %d: header size %d" % [m, size])
			check(ScreenBase.CX + w * 0.5 + 16.0 < rx - cap_w, "mode %d: PLAYER %d header (to %.0f) clear of DIFFICULTY (%.0f)" % [
				m, k + 1, ScreenBase.CX + w * 0.5, rx - cap_w])
			var lw := UiKit.text_width(Assets.font_body_bold, ShipSelect.locked_line_text(k), 17) + 24.0
			check(lw < ScreenBase.W - 120.0, "mode %d: locked line fits" % m)
			var cw := UiKit.text_width(Assets.font_body_bold, ShipSelect.lock_caption(k), UiKit.label_size(12))
			check(cw < ShipSelect.TILE_W - 24.0 - 16.0, "mode %d: LOCKED BY caption inside the preview" % m)
		_restore(before)


# --- TITLE ---------------------------------------------------------------------------------------
func test_title_players_and_powerups_rows() -> void:
	_settings_begin()
	_router_init()
	Settings.players = 1
	Settings.powerups = false
	check_eq(TitleScreen.ITEMS.slice(0, 4), ["start", "difficulty", "players", "powerups"] as Array[String],
		"PLAYERS and POWER-UPS directly under DIFFICULTY")
	check_eq([TitleScreen.LABELS["players"], TitleScreen.LABELS["powerups"]], ["PLAYERS", "POWER-UPS"])
	var t: SpyTitle = _open(SpyTitle.new(), {"select": "players"}) as SpyTitle
	check_eq(t._value("players"), "1")
	_tap(t, KEY_RIGHT)
	check_eq([Settings.players, _stored("game", "players")], [2, 2], "Right → 2 players, stored")
	check_eq(t._value("players"), "2")
	_tap(t, KEY_LEFT)
	check_eq([Settings.players, _stored("game", "players")], [1, 1], "Left flips back")
	_tap(t, KEY_ENTER)
	check_eq(Settings.players, 2, "Enter flips")
	_tap(t, KEY_SPACE)
	check_eq(Settings.players, 1, "Space flips")
	_tap(t, KEY_DOWN)
	_tap(t, KEY_RIGHT)
	check_eq([Settings.powerups, _stored("game", "powerups")], [true, true], "POWER-UPS ON, stored")
	check_eq(t._value("powerups"), "ON")
	_tap(t, KEY_ENTER)
	check_eq([Settings.powerups, _stored("game", "powerups")], [false, false], "Enter → OFF")
	check(t.sfx_calls.size() == 7 and t.sfx_calls.count("menu_move") == 7, "menu blip per change / move: %s" % [
		t.sfx_calls])
	check(t.results.is_empty(), "the rows never leave the title")
	# START still only says "start" – Main branches on Settings.players.
	Settings.set_players(2)
	_tap(t, KEY_UP, 3)
	_tap(t, KEY_ENTER)
	check_eq(t.results, [["start", {}]], "START GAME → finished(start)")
	check_eq(Settings.players, 2, "start does not change PLAYERS")
	t.free()
	_settings_end()


## Holding Left/Right on a binary row flips it once (like MUSIC / SOUND EFFECTS), never with the auto-repeat.
func test_title_binary_rows_flip_once_per_press() -> void:
	for item in ["players", "powerups"]:
		check(TitleScreen.accepts_step(item, false), "%s reacts to a fresh step" % item)
		check(not TitleScreen.accepts_step(item, true), "%s ignores auto-repeat steps" % item)
	_settings_begin()
	_router_init()
	Settings.players = 1
	Settings.powerups = false
	for item in ["players", "powerups"]:
		var t: SpyTitle = _open(SpyTitle.new(), {"select": item}) as SpyTitle
		var flips := 0
		var last: Variant = Settings.players if item == "players" else Settings.powerups
		_key(KEY_RIGHT, true)
		var tt := 0.0
		while tt < 1.5:
			_router_step()
			t._process(STEP)
			tt += STEP
			var now: Variant = Settings.players if item == "players" else Settings.powerups
			if now != last:
				flips += 1
				last = now
		_key(KEY_RIGHT, false)
		_run(t, STEP * 3)
		check_eq(flips, 1, "%s: held Right for 1.5 s flips exactly once" % item)
		t.free()
	_settings_end()


func test_title_info_line_and_best_per_category() -> void:
	_settings_begin()
	_router_init()
	Settings.difficulty = 1
	Settings.players = 1
	Settings.powerups = false
	Settings.set("_highscores", {0: [], 1: [], 2: [], 3: []})
	Settings.set("_highscores_pu", {0: [], 1: [], 2: [], 3: []})
	Settings.insert_highscore(1, {"name": "CLASSIC", "score": 500, "time": 100.0, "level": 4, "ship": 0}, false)
	Settings.insert_highscore(1, {"name": "BOOSTED", "score": 900, "time": 90.0, "level": 7, "ship": 2}, true)
	var t: SpyTitle = _open(SpyTitle.new(), {"select": "powerups"}) as SpyTitle
	check_eq(String(t.get("_best").get("name", "")), "CLASSIC", "classic list while POWER-UPS is OFF")
	check_eq(TitleScreen.best_caption(1, false), "BEST · NORMAL", "classic caption unchanged")
	check_eq(t.info_line_text("powerups"), TitleScreen.POWERUPS_INFO[false])
	_tap(t, KEY_RIGHT)
	check_eq(String(t.get("_best").get("name", "")), "BOOSTED", "power-up list while ON")
	check_eq(TitleScreen.best_caption(1, true), "BEST · NORMAL · POWER-UPS")
	check_eq(t.info_line_text("powerups"), TitleScreen.POWERUPS_INFO[true])
	_tap(t, KEY_UP, 2)
	_tap(t, KEY_RIGHT)
	check(t.get("_best").is_empty(), "HARD · POWER-UPS: no entry → no BEST line")
	_tap(t, KEY_LEFT)
	check_eq(String(t.get("_best").get("name", "")), "BOOSTED", "back to NORMAL")
	check_eq(t.info_line_text("players"), TitleScreen.PLAYERS_INFO[1])
	Settings.set_players(2)
	check_eq(t.info_line_text("players"), TitleScreen.PLAYERS_INFO[2])
	check_eq(t.info_line_text("display"), t.display_line_text(false), "DISPLAY keeps its line")
	for item in ["start", "difficulty", "music", "music_volume", "sfx", "sfx_volume", "highscores", "quit"]:
		check_eq(t.info_line_text(item), "", "no line under %s" % item)
	t.free()
	_settings_end()


## Layout of the 11 rows in every display mode: logo below the BEST line, tagline above the panel, the explanation
## line between panel and hints, the two hint rows apart and on the canvas; every row and every line fits.
func test_title_layout_fits_every_mode() -> void:
	_fonts()
	var font := Assets.font_title
	var logo := Assets.logo_texture()
	var logo_h := TitleScreen.LOGO_W * float(logo.get_height()) / float(logo.get_width()) if logo else 120.0
	# First row of the logo image with solid letters (alpha > 0.5; the glow above them is faint). Read from the PNG
	# itself (the headless renderer keeps no texture data).
	var letters_top := 0.0
	var img := Image.load_from_file(ProjectSettings.globalize_path(Assets.SPRITES + "ui/logo.png"))
	check(img != null and not img.is_empty(), "logo.png readable")
	if logo and img and not img.is_empty():
		var found := false
		for y in img.get_height():
			for x in range(0, img.get_width(), 4):
				if img.get_pixel(x, y).a > 0.5:
					letters_top = float(y) / img.get_height() * logo_h
					found = true
					break
			if found:
				break
	var logo_top := TitleScreen.LOGO_Y - 3.0 - logo_h * 0.5   # highest float position
	check(logo_top + letters_top > 56.0 + 2.0, "logo letters (%.1f) below the BEST value (baseline 56)" % [
		logo_top + letters_top])
	var panel := TitleScreen.menu_panel_rect()
	var tagline := TitleScreen.LOGO_Y + 3.0 + logo_h * 0.5 + 22.0
	check(tagline + 8.0 < panel.position.y, "tagline (%.0f) above the panel (%.0f)" % [tagline, panel.position.y])
	check(panel.end.y + 10.0 < TitleScreen.INFO_LINE_Y - 16.0, "explanation line below the panel")
	var hint1_top := TitleScreen.HINT_Y - 14 * 1.55 * 0.5
	var hint1_bottom := TitleScreen.HINT_Y + 14 * 1.55 * 0.5
	var hint2_top := TitleScreen.HINT_Y + TitleScreen.HINT_STEP - 13 * 1.55 * 0.5
	var hint2_bottom := TitleScreen.HINT_Y + TitleScreen.HINT_STEP + 13 * 1.55 * 0.5
	check(TitleScreen.INFO_LINE_Y + 6.0 < hint1_top, "explanation line above the hints")
	check(hint1_bottom + 4.0 < hint2_top, "hint rows apart")
	check(hint2_bottom + 10.0 < ScreenBase.H, "second hint row on the canvas (%.0f)" % hint2_bottom)
	check(TitleScreen.MENU_STEP >= UiKit.menu_row_rect(Vector2.ZERO, TitleScreen.MENU_W, TitleScreen.MENU_FONT).size.y * 0.5
		+ TitleScreen.MENU_FONT * 0.5 + 4.0, "the selection pill stays clear of the neighbouring labels")
	check(UiKit.menu_row_rect(Vector2(0, TitleScreen.MENU_Y), TitleScreen.MENU_W, TitleScreen.MENU_FONT).position.y
		> panel.position.y + 3.0, "first selection pill inside the panel")
	# PLAYERS / POWER-UPS rows: label, value and pointers fit.
	var row := UiKit.menu_row_rect(Vector2(TitleScreen.CX, 300.0), TitleScreen.MENU_W, TitleScreen.MENU_FONT)
	for item in ["players", "powerups"]:
		var label_end := row.position.x + 30.0 + UiKit.text_width(font, TitleScreen.LABELS[item], TitleScreen.MENU_FONT)
		var vw := UiKit.text_width(font, "OFF", TitleScreen.MENU_FONT)
		check(label_end + 12.0 < row.end.x - 30.0 - 18.0 - vw - 14.0 - 6.0, "%s row fits" % item)
	var worst_best := TitleScreen.best_text({"name": "WWWWWWWW", "score": 999999})
	for m in Display.MODE_COUNT:
		var before := _force(m)
		var t := SpyTitle.new()
		t.setup({"select": "players"})
		t._ready()
		var left := t.left_x()
		check(panel.position.x - 30.0 > left and panel.end.x + 30.0 < t.right_x(), "mode %d: panel on the canvas" % m)
		var lines: Array[String] = []
		lines.append_array(TitleScreen.PLAYERS_INFO.values())
		lines.append_array(TitleScreen.POWERUPS_INFO.values())
		for s in lines:
			var w := UiKit.text_width(Assets.font_body, s, 15)
			check(w < ScreenBase.W - 80.0, "mode %d: line fits (%.0f): %s" % [m, w, s])
		for d in 4:
			var cap := TitleScreen.best_caption(d, true)
			var cw := UiKit.text_width(Assets.font_body, cap, UiKit.label_size(13))
			check(TitleScreen.BEST_X + t.ox - cw > left + 16.0, "mode %d: BEST caption on the canvas: %s" % [m, cap])
		var bw := UiKit.text_width(font, worst_best, TitleScreen.BEST_SIZE)
		check(TitleScreen.BEST_X + t.ox - bw > left + 16.0, "mode %d: BEST value on the canvas" % m)
		for items: Array in [[[["UD"], "Select"], [["LR"], "Change"], [["ENTER", "pad:A"], "Confirm"]],
				[[["pad:BACK"], "Highscores"], [["ESC"], "Quit"], [["F11"], "Fullscreen"]]]:
			check(UiKit.hint_bar_width(items, 14) < ScreenBase.W - 80.0, "mode %d: hint row fits" % m)
		t.free()
		_restore(before)
	AudioManager.stop_music()


# --- HAND-OVER -----------------------------------------------------------------------------------
func test_handover_confirm_delay_keys_and_music() -> void:
	_router_init()
	_match(5, false)
	var h: SpyHandover = _open(SpyHandover.new(), {"kind": "locks", "player": 1}) as SpyHandover
	check(AudioManager.is_title_music_playing(), "locks hand-over: title music (setup)")
	check_eq([h.player, h.other()], [1, 0])
	_run(h, 0.3)
	_tap(h, KEY_ENTER)
	check(h.results.is_empty(), "confirm ignored before %.1f s" % Handover.CONFIRM_DELAY)
	_run(h, 0.4)
	_tap(h, KEY_ESCAPE)
	check(h.results.is_empty(), "Escape does nothing")
	_tap(h, KEY_SPACE)
	check_eq(h.results, [["continue", {}]], "Space confirms on the setup hand-over")
	h.free()
	var t: SpyHandover = _open(SpyHandover.new(), {"kind": "turn", "player": 1, "level": 5}) as SpyHandover
	check(not AudioManager.is_title_music_playing(), "turn screen: silent between two levels")
	check_eq([t.player, t.level], [1, 5])
	_tap(t, KEY_ENTER)
	check(t.results.is_empty(), "confirm ignored at once")
	_run(t, Handover.CONFIRM_DELAY)
	_tap(t, KEY_SPACE)
	_tap(t, KEY_ESCAPE)
	check(t.results.is_empty(), "turn screen: Space (fire) and Escape do nothing")
	_tap(t, KEY_ENTER)
	check_eq(t.results, [["continue", {}]], "Enter → continue")
	check_eq(t.sfx_calls, ["menu_confirm"] as Array[String])
	t.free()
	# Controller: B is ignored, A is fire on the turn screen, X / Start confirm.
	_swap_in()
	var c: SpyHandover = _open(SpyHandover.new(), {"kind": "turn", "player": 0, "level": 2}) as SpyHandover
	_run(c, Handover.CONFIRM_DELAY)
	_pad_tap(c, JOY_BUTTON_B)
	_pad_tap(c, JOY_BUTTON_A)
	check(c.results.is_empty(), "B / A do nothing")
	_pad_tap(c, JOY_BUTTON_X)
	check_eq(c.results.size(), 1, "X confirms")
	c.free()
	var c2: SpyHandover = _open(SpyHandover.new(), {"kind": "locks", "player": 0}) as SpyHandover
	_run(c2, Handover.CONFIRM_DELAY)
	_pad_tap(c2, JOY_BUTTON_B)
	check(c2.results.is_empty(), "B does nothing on the setup hand-over")
	_pad_tap(c2, JOY_BUTTON_A)
	check_eq(c2.results.size(), 1, "A confirms on the setup hand-over (like ship lock / select)")
	c2.free()
	_swap_out()
	_end_match()
	AudioManager.stop_music()


## Hidden information: the hand-over between the two lock screens can not show a lock – its code never reads one
## (no "locked" setup arg, no Run.locked, no player_get(…, "locked")).
func test_handover_shows_no_lock_information() -> void:
	var src := (Handover as GDScript).source_code
	for line in src.split("\n"):
		var code := line.strip_edges()
		if code.begins_with("#"):
			continue
		var cut := code.find("#")
		if cut >= 0:
			code = code.substr(0, cut)
		check(not code.contains("locked"), "hand-over code touches lock data: %s" % line)
	for ship: Dictionary in ShipData.SHIPS:
		check(not Handover.LOCKS_NOTE.contains(String(ship["name"])), "note names no ship")


func test_handover_turn_texts_and_powerup() -> void:
	check_eq(Handover.level_line(7), "LEVEL 7  –  SATURN 1")
	check_eq(Handover.level_line(13), "LEVEL 13  –  BONUS ROUND")
	check_eq(Handover.level_line(20), "LEVEL 20  –  EARTH – FINAL BATTLE")
	check_eq([Handover.status_text(true, false), Handover.status_text(false, true), Handover.status_text(false, false)],
		["GAME OVER", "EARTH SAVED", ""])
	var expect := {1: LevelData.PowerUp.NONE, 6: LevelData.PowerUp.NONE, 7: LevelData.PowerUp.RAPID_FIRE,
		9: LevelData.PowerUp.RAPID_FIRE, 10: LevelData.PowerUp.TWIN, 12: LevelData.PowerUp.TWIN,
		13: LevelData.PowerUp.NONE, 14: LevelData.PowerUp.SHIELD, 16: LevelData.PowerUp.SHIELD, 17: LevelData.PowerUp.NONE,
		20: LevelData.PowerUp.NONE}
	for pu in [true, false]:
		_match(1, pu)
		for n: int in expect:
			var h := Handover.new()
			h.setup({"kind": "turn", "player": 1, "level": n})
			h._ready()
			check_eq(h.powerup(), expect[n] if pu else LevelData.PowerUp.NONE, "level %d, power-ups %s" % [n, pu])
			h.free()
	_end_match()
	AudioManager.stop_music()


# --- LOCK REVEAL ---------------------------------------------------------------------------------
func test_lock_reveal_shows_exactly_the_locks() -> void:
	_router_init()
	var r: SpyReveal = _open(SpyReveal.new(), {"locked": [[5, 3, 4], []]}) as SpyReveal
	check_eq(r.locks[0], [3, 4, 5] as Array[int], "PLAYER 1 may not fly 3, 4, 5")
	check_eq(r.locks[1], [] as Array[int], "PLAYER 2: no locks")
	check(AudioManager.is_title_music_playing(), "title music")
	check_eq(r.stamp_count(), 3)
	check_eq(LockReveal.panel_title(0), "PLAYER 1 MAY NOT FLY")
	_tap(r, KEY_ENTER)
	check(r.results.is_empty(), "confirm ignored before %.1f s" % LockReveal.CONFIRM_DELAY)
	_run(r, 1.0)
	check_eq(r.sfx_calls.count("locked_hit"), 3, "one clink per landing lock")
	check(LockReveal.stamp_time(r.stamp_count() - 1) + LockReveal.STAMP_TIME <= LockReveal.CONFIRM_DELAY + 1e-6,
		"every lock has landed before confirm is possible")
	_tap(r, KEY_SPACE)
	check_eq(r.results, [["continue", {}]], "confirm → continue")
	r.free()
	var r2: SpyReveal = _open(SpyReveal.new(), {"locked": [[1], [0, 2]]}) as SpyReveal
	_run(r2, 1.0)
	check_eq(r2.sfx_calls.count("locked_hit"), 2, "both players' i-th locks land together")
	r2.free()
	var r3: SpyReveal = _open(SpyReveal.new(), {"locked": [[], []]}) as SpyReveal
	_run(r3, 1.0)
	check_eq(r3.sfx_calls.count("locked_hit"), 0, "no locks, no clink")
	r3.free()
	AudioManager.stop_music()


# --- MATCH RESULT --------------------------------------------------------------------------------
func test_match_result_winner_and_draw() -> void:
	check_eq([MatchResult.winner(100, 50), MatchResult.winner(50, 100), MatchResult.winner(70, 70)], [0, 1, -1])
	check_eq(MatchResult.winner(0, 0), -1, "0 : 0 is a draw")
	check_eq([MatchResult.banner_text(0), MatchResult.banner_text(1), MatchResult.banner_text(-1)],
		["PLAYER 1 WINS!", "PLAYER 2 WINS!", "DRAW!"])
	check_eq([MatchResult.status_text(true, false), MatchResult.status_text(false, true)], ["GAME OVER", "EARTH SAVED"])
	check_eq(MatchResult.level_text(13), "13 – BONUS ROUND")
	check_eq(MatchResult.level_text(14), "14 – MARS 1")
	_router_init()
	_match(1, true, {"score": 4800, "level": 20, "won": true}, {"score": 5120, "level": 17, "out": true})
	var m: SpyResult = _open(SpyResult.new(), {}) as SpyResult
	check_eq(m.match_winner(), 1, "PLAYER 2 wins by score (even though PLAYER 1 saved Earth)")
	check(not AudioManager.is_title_music_playing(), "silent end screen")
	_tap(m, KEY_ENTER)
	_run(m, 0.6)
	check(m.results.is_empty(), "confirm ignored before %.1f s" % MatchResult.CONFIRM_DELAY)
	check(m.sfx_calls.count("bonus_tick") > 3, "the scores count up")
	_run(m, 0.4)
	check_eq(m.sfx_calls.count("level_complete"), 1, "winner fanfare once")
	_tap(m, KEY_SPACE)
	check(m.results.is_empty(), "Space (fire) does not confirm the end screen")
	_tap(m, KEY_ENTER)
	check_eq(m.results, [["continue", {}]], "Enter → continue")
	m.free()
	_match(1, false, {"score": 3000}, {"score": 3000})
	var d: SpyResult = _open(SpyResult.new(), {}) as SpyResult
	check_eq(d.match_winner(), -1, "equal scores → draw")
	d.free()
	Run.switch_to(1)
	Run.score = 2999
	check_eq(MatchResult.winner(int(Run.player_get(0, "score")), int(Run.player_get(1, "score"))), 0, "parked score read")
	_end_match()


# --- Layout of the new screens on every canvas ----------------------------------------------------
func test_new_screens_stay_on_the_canvas() -> void:
	_fonts()
	for m in Display.MODE_COUNT:
		var before := _force(m)
		var ox := Display.center_offset()
		var canvas := Rect2(-ox + 4.0, 4.0, ScreenBase.W + ox * 2.0 - 8.0, ScreenBase.H - 8.0)
		var hint_top := ScreenBase.CONTINUE_HINT_Y - ScreenBase.CONTINUE_HINT_SIZE * 2.45 * 0.5
		# SHIP LOCK: rows (with the pointers), DONE row, warning banner, stat line clear of the LOCKED tag.
		for i in ShipData.SHIPS.size():
			var r := ShipLock.row_rect(i)
			check(canvas.encloses(r.grow_individual(30.0, 0.0, 30.0, 0.0)), "mode %d: lock row %d on the canvas" % [m, i])
			if i > 0:
				check(r.position.y > ShipLock.row_rect(i - 1).end.y + 4.0, "lock rows apart")
			var name_w := UiKit.text_width(Assets.font_title, String(ShipData.ship(i)["name"]), ShipLock.NAME_SIZE)
			check(ShipLock.TEXT_X + name_w + 12.0 < ShipLock.ROW_W - ShipLock.STATUS_W, "mode %d: name %d clear of LOCKED" % [m, i])
		var last := ShipLock.row_rect(ShipData.SHIPS.size() - 1)
		var done := ShipLock.done_rect()
		check(last.end.y + 12.0 < done.position.y, "DONE below the list")
		check(done.end.y + 8.0 < ShipLock.MSG_Y - 17.0 * 0.72, "message (capitals) below DONE")
		check(ShipLock.MSG_Y + 6.0 < ShipLock.HINT_Y - 14 * 1.55 * 0.5, "message above the hints")
		check(ShipLock.stat_line_end() + 14.0 < ShipLock.ROW_W - ShipLock.STATUS_W,
			"mode %d: stat line (to %.0f) clear of the LOCKED tag (%.0f)" % [m, ShipLock.stat_line_end(),
			ShipLock.ROW_W - ShipLock.STATUS_W])
		var tag_w := 28.0 + UiKit.text_width(Assets.font_title, "LOCKED", 16)
		check(tag_w + 4.0 < ShipLock.STATUS_W, "LOCKED tag inside its area")
		var count_w := UiKit.text_width(Assets.font_title, "3 / 3 LOCKED", 17) + 20.0 + 2 * 22.0 + 8.0
		check(34.0 + UiKit.text_width(Assets.font_title, "DONE", ShipLock.DONE_SIZE) + 20.0 + count_w + 34.0
			< ShipLock.DONE_W, "DONE row content fits")
		for k in 2:
			var warn := UiKit.look_away_rect(Vector2(ScreenBase.CX, ShipLock.WARN_Y), "PLAYER %d – LOOK AWAY!" % (k + 1),
				ShipLock.WARN_SIZE)
			check(warn.position.y > ShipLock.SUB_Y + 4.0 and warn.end.y < ShipLock.LIST_Y - 6.0, "warning between header and list")
			check(canvas.encloses(warn), "warning on the canvas")
		check(UiKit.text_width(Assets.font_body_bold, ShipLock.refusal_text(), 17) < ScreenBase.W - 80.0, "refusal fits")
		# HAND-OVER: both kinds.
		check(UiKit.text_width(Assets.font_body, Handover.LOCKS_NOTE, 17) < ScreenBase.W - 80.0, "note fits")
		var hw := UiKit.look_away_rect(Vector2(ScreenBase.CX, Handover.WARN_Y), "PLAYER 2 – LOOK AWAY!", 22)
		check(canvas.encloses(hw) and hw.end.y < hint_top - 20.0, "hand-over warning above the hint")
		check(Handover.PASS_NAME_Y + 10.0 < hw.position.y, "name above the warning")
		check(canvas.encloses(Handover.PANEL), "turn panel on the canvas")
		for planet: String in LevelData.PLANETS:
			var ph := Handover.planet_image_h(planet)   # rings included; it sinks 12 px into place
			check(Handover.PLANET_Y - 12.0 - ph * 0.5 > 8.0, "%s on the canvas" % planet)
			check(Handover.PLANET_Y + ph * 0.5 + 4.0 < Handover.LEVEL_Y - 18.0 * 0.72,
				"%s (to %.0f) above the level line" % [planet, Handover.PLANET_Y + ph * 0.5])
			check(Handover.planet_size(planet) >= 110.0, "%s not too small" % planet)
		for n in range(LevelData.FIRST_LEVEL, LevelData.LAST_LEVEL + 1):
			var lw := UiKit.spaced_width(Assets.font_title, Handover.level_line(n), 18, 3.0)
			check(lw < ScreenBase.W - 80.0, "mode %d: level line %d fits (%.0f)" % [m, n, lw])
		check(Handover.READY_SPACED_Y + 8.0 < Handover.PANEL.position.y, "GET READY above the panel")
		check(Handover.PANEL.end.y + 14.0 < Handover.OTHER_Y - 16.0, "other player below the panel")
		for pu: int in LevelData.POWERUP_NAMES:
			var pr := Handover.powerup_rect(String(LevelData.POWERUP_NAMES[pu]))
			check(canvas.encloses(pr) and pr.size.x < ScreenBase.W - 80.0, "mode %d: power-up line fits" % m)
			check(pr.position.y > Handover.OTHER_Y + 6.0 and pr.end.y < hint_top - 6.0, "power-up line between other and hint")
		# LOCK REVEAL: panels, three rows above the strip, strip inside the panel.
		for k in 2:
			var p := LockReveal.panel_rect(k)
			check(canvas.encloses(p), "mode %d: reveal panel %d on the canvas" % [m, k])
			check(p.end.y < hint_top - 12.0, "reveal panel above the hint")
			var row := LockReveal.lock_row_rect(p, 2)
			check(row.end.y + 12.0 < p.position.y + LockReveal.STRIP_Y - 20.0, "third lock row above the strip")
			check(LockReveal.lock_row_rect(p, 0).position.y > p.position.y + 96.0 + 4.0, "first row below the divider")
			check(LockReveal.STRIP_STEP * (ShipData.SHIPS.size() - 1) + 46.0 < LockReveal.PANEL_W - 20.0, "strip inside")
			check(LockReveal.STRIP_Y + 44.0 + 10.0 < LockReveal.PANEL_H, "strip caption inside the panel")
			for id in ShipData.SHIPS.size():
				var nw := UiKit.text_width(Assets.font_title, String(ShipData.ship(id)["name"]), 18)
				check(100.0 + nw + 12.0 < row.size.x - 30.0 - 16.0, "ship name %d clear of the padlock" % id)
		check(LockReveal.panel_rect(0).end.x + 20.0 <= LockReveal.panel_rect(1).position.x, "reveal panels apart")
		# MATCH RESULT: panels, badge, banner.
		for k in 2:
			var p := MatchResult.panel_rect(k)
			check(canvas.encloses(p), "mode %d: result panel %d on the canvas" % [m, k])
			check(p.end.y < hint_top - 12.0, "result panel above the hint")
			check(MatchResult.badge_rect(p).position.y > MatchResult.BANNER_Y + 6.0, "badge below the banner")
			check(MatchResult.badge_rect(p).size.x < MatchResult.PANEL_W - 40.0, "badge fits")
		var bw := UiKit.text_width(Assets.font_title_heavy, "PLAYER 2 WINS!", MatchResult.BANNER_SIZE)
		check(bw < ScreenBase.W - 80.0, "banner fits")
		for n in range(LevelData.FIRST_LEVEL, LevelData.LAST_LEVEL + 1):
			var room := MatchResult.PANEL_W - 60.0 - UiKit.text_width(Assets.font_body, "LEVEL", 16) - 16.0
			check(UiKit.fit_size(Assets.font_title, MatchResult.level_text(n), 16, room) >= 13, "level %d readable" % n)
		_restore(before)
