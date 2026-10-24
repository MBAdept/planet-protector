extends TestBase
## Highscore names of up to 8 characters (client request; docs/SPEC.md §13 – originally 5): old highscore files
## with 5-character names, over-long names in a hand-edited file, the name entry storing 8 characters, and the
## layouts with the widest names (name-entry boxes, highscore columns, title BEST line).
## Highscores are redirected to a scratch file (Settings.highscore_path) and the lists are restored afterwards,
## so the player's highscores.json is never touched.

const HighscoresScreen := preload("res://scripts/screens/highscores_screen.gd")
const NameEntryScreen := preload("res://scripts/screens/name_entry_screen.gd")
const TitleScreen := preload("res://scripts/screens/title_screen.gd")

const SCRATCH_JSON := "user://test_highscore_names.json"
## Minimum free space between two neighbouring highscore columns (heading or widest value).
const MIN_GAP := 16.0
## Widest score the layouts must hold: 6 digits – more than a whole run can earn (about 80 000 at most).
const WORST_SCORE := 888888


# --- Helpers -------------------------------------------------------------------------------------
var _saved := {}


## Points Settings at the scratch file (removed first) with empty lists; remembers the real ones.
func _scores_begin() -> void:
	var lists := {}
	for d in 4:
		lists[d] = Settings.get_highscores(d)
	_saved = {"path": Settings.highscore_path, "lists": lists}
	Settings.highscore_path = SCRATCH_JSON
	Settings.set("_highscores", {0: [], 1: [], 2: [], 3: []})
	_remove_scratch()


func _scores_end() -> void:
	_remove_scratch()
	Settings.highscore_path = _saved["path"]
	Settings.set("_highscores", _saved["lists"])


func _remove_scratch() -> void:
	if FileAccess.file_exists(SCRATCH_JSON):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_JSON))


func _write_scratch(data: Dictionary) -> void:
	var f := FileAccess.open(SCRATCH_JSON, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  ", false, true))
	f.close()


func _names(diff: int) -> Array[String]:
	var out: Array[String] = []
	for e in Settings.get_highscores(diff):
		out.append(String(e["name"]))
	return out


func _fonts() -> void:
	if Assets.font_title == null:
		Assets._ready()


## The widest single character of `chars` in that font and size.
func _widest_char(font: Font, chars: String, size: int) -> String:
	var best := chars[0]
	for c in chars:
		if UiKit.text_width(font, c, size) > UiKit.text_width(font, best, size):
			best = c
	return best


# --- Stored names --------------------------------------------------------------------------------
func test_legacy_5_character_entries_load_unchanged() -> void:
	check_eq(Settings.highscore_path, Settings.HIGHSCORE_PATH, "the game uses user://highscores.json")
	_scores_begin()
	# highscores.json as version 1.2 (names of max 5 characters) wrote it.
	var old := {
		"0": [],
		"1": [
			{"name": "ACE", "score": 44017, "time": 1438.7, "level": 18, "ship": 1},
			{"name": "ZED-9", "score": 39808, "time": 1377.4123456789, "level": 16, "ship": 2},
			{"name": "PILOT", "score": 35373, "time": 1316.1, "level": 14, "ship": 3},
		],
		"2": [{"name": "B0B_-", "score": 4017, "time": 948.3, "level": 2, "ship": 5}],
		"3": [{"name": "Q", "score": 120, "time": 61.5, "level": 1, "ship": 0}],
	}
	_write_scratch(old)
	var file_before := FileAccess.get_file_as_string(SCRATCH_JSON)
	Settings.load_highscores()
	for d in 4:
		var expected: Array = old[str(d)]
		check_eq(Settings.get_highscores(d), expected, "list %d loads unchanged" % d)
	check_eq(FileAccess.get_file_as_string(SCRATCH_JSON), file_before, "loading does not rewrite the file")
	# A new 8-character entry joins the old ones; after saving and loading again they are all unchanged.
	var rank := Settings.insert_highscore(1, {"name": "STARDUST", "score": 40000, "time": 1400.0, "level": 17,
		"ship": 0})
	check_eq(rank, 1)
	Settings.load_highscores()
	check_eq(_names(1), ["ACE", "STARDUST", "ZED-9", "PILOT"] as Array[String],
		"old 5-character names next to an 8-character one")
	check_eq(_names(2), ["B0B_-"] as Array[String])
	check_eq(_names(3), ["Q"] as Array[String])
	check_eq(Settings.get_highscores(1)[2], old["1"][1], "old entry unchanged after re-saving (time at full precision)")
	_scores_end()


func test_overlong_names_are_cut_to_8() -> void:
	_scores_begin()
	# A hand-edited file: names longer than 8 (and invalid characters) are cleaned on load.
	_write_scratch({"1": [
		{"name": "SUPERNOVA_RIDER", "score": 900, "time": 10.0, "level": 3, "ship": 0},
		{"name": "stardust99", "score": 800, "time": 10.0, "level": 3, "ship": 0},
		{"name": "COMET-42", "score": 700, "time": 10.0, "level": 3, "ship": 0},
		{"name": "a b c d e f g h i j", "score": 600, "time": 10.0, "level": 3, "ship": 0},
		{"name": "!?#", "score": 500, "time": 10.0, "level": 3, "ship": 0},
	]})
	Settings.load_highscores()
	check_eq(_names(1), ["SUPERNOV", "STARDUST", "COMET-42", "ABCDEFGH", "PILOT"] as Array[String])
	# Same rule for entries inserted directly.
	Settings.insert_highscore(0, {"name": "VERYLONGNAME", "score": 50, "time": 5.0, "level": 1, "ship": 0})
	check_eq(_names(0), ["VERYLONG"] as Array[String])
	check_eq(Settings.sanitize_name("ABCDEFGHIJ"), "ABCDEFGH")
	check_eq(Settings.sanitize_name("abcdefgh"), "ABCDEFGH", "exactly 8 is kept")
	_scores_end()


func test_name_entry_stores_8_characters() -> void:
	_scores_begin()
	var n := NameEntryScreen.new()
	n.setup({"difficulty": 2, "score": 1234, "time": 100.0, "level": 4, "ship": 1})
	n._ready()
	for ch in "WWWWMMMMX":   # keyboard typing: the 9th character is ignored
		n._on_text_char(ch)
	check_eq(n.editor.text, "WWWWMMMM")
	check_eq(n.editor.cursor, 7)
	var res := [""]
	n.finished.connect(func(r: String, _d: Dictionary) -> void: res[0] = r)
	n._confirm()
	check_eq(res[0], "done")
	check_eq(_names(2), ["WWWWMMMM"] as Array[String], "all 8 characters are stored")
	Settings.load_highscores()
	check_eq(_names(2), ["WWWWMMMM"] as Array[String], "and survive saving / loading")
	n._exit_tree()
	n.free()
	_scores_end()


# --- Layouts with the widest names ---------------------------------------------------------------
func test_highscore_columns_do_not_overlap_with_8_wide_characters() -> void:
	_fonts()
	var vf: Font = Assets.font_title
	var hf: Font = Assets.font_body_bold
	var vs := HighscoresScreen.VALUE_SIZE
	var widest := _widest_char(vf, Settings.NAME_CHARS, vs)
	var ships: Array = []
	for i in ShipData.SHIPS.size():
		ships.append(String(ShipData.ship(i)["name"]))
	# Widest values of every column (same order as COLUMNS).
	var values := [
		["%d." % Settings.LIST_SIZE],
		["WWWWWWWW", "MMMMMMMM", widest.repeat(Settings.NAME_MAX), HighscoresScreen.empty_name()],
		[Fmt.score(WORST_SCORE)],
		[str(LevelData.LAST_LEVEL)],
		[Fmt.time(5999.9)],
		ships,
	]
	var spans: Array[Vector2] = []
	for i in HighscoresScreen.COLUMNS.size():
		var c: Array = HighscoresScreen.column(i)
		var x := float(c[1])
		var align: HorizontalAlignment = c[2]
		var lo := UiKit.aligned_x(hf, c[0], HighscoresScreen.HEADING_SIZE, x, align)
		var hi := lo + UiKit.text_width(hf, c[0], HighscoresScreen.HEADING_SIZE)
		var font := hf if c[0] == "SHIP" else vf
		var size := HighscoresScreen.SHIP_SIZE if c[0] == "SHIP" else vs
		for v: String in values[i]:
			var l := UiKit.aligned_x(font, v, size, x, align)
			lo = minf(lo, l)
			hi = maxf(hi, l + UiKit.text_width(font, v, size))
		spans.append(Vector2(lo, hi))
	check(UiKit.text_width(vf, "WWWWWWWW", vs) > UiKit.text_width(vf, "WWWWW", vs) + 50.0, "8 W are much wider than 5")
	for i in range(1, spans.size()):
		var a: String = HighscoresScreen.column(i - 1)[0]
		var b: String = HighscoresScreen.column(i)[0]
		check(spans[i - 1].y + MIN_GAP <= spans[i].x, "%s (to %.0f) clear of %s (from %.0f)" % [a, spans[i - 1].y,
			b, spans[i].x])
	# Everything inside the row band of the panel.
	var band := Vector2(HighscoresScreen.PANEL.position.x + 14.0, HighscoresScreen.PANEL.end.x - 14.0)
	check(spans[0].x >= band.x, "RANK starts inside the panel (%.0f >= %.0f)" % [spans[0].x, band.x])
	check(spans[spans.size() - 1].y <= band.y, "SHIP ends inside the panel (%.0f <= %.0f)" % [
		spans[spans.size() - 1].y, band.y])


func test_empty_row_placeholder_has_one_dash_per_character() -> void:
	check_eq(HighscoresScreen.empty_name(), "--------", "8 dashes (was 5 with the old limit)")
	check_eq(HighscoresScreen.empty_name().length(), Settings.NAME_MAX)


func test_name_entry_shows_8_boxes_that_fit() -> void:
	_fonts()
	var n := NameEditor.max_len()
	check_eq(n, 8)
	var first: Rect2 = NameEntryScreen.box_rect(0)
	var last: Rect2 = NameEntryScreen.box_rect(n - 1)
	check_near((first.position.x + last.end.x) * 0.5, ScreenBase.CX, 0.01, "row of boxes centred")
	check(first.position.x >= 120.0 and last.end.x <= ScreenBase.W - 120.0,
		"8 boxes fit at 960 × 720 with wide margins (%.0f – %.0f)" % [first.position.x, last.end.x])
	for i in range(1, n):
		var gap := NameEntryScreen.box_rect(i).position.x - NameEntryScreen.box_rect(i - 1).end.x
		check(gap >= 8.0, "gap between box %d and %d (%.0f)" % [i - 1, i, gap])
	var font: Font = Assets.font_title_heavy
	var widest := _widest_char(font, Settings.NAME_CHARS, NameEntryScreen.GLYPH_SIZE)
	var gw := UiKit.text_width(font, widest, NameEntryScreen.GLYPH_SIZE)
	check(gw + 16.0 <= NameEntryScreen.BOX_W, "widest character %s (%.0f px) leaves 8 px on each side of a %.0f px box" % [
		widest, gw, NameEntryScreen.BOX_W])
	check(Settings.DEFAULT_NAME.length() <= n, "the PILOT placeholder fits the boxes")


func test_title_best_line_fits_8_characters() -> void:
	_fonts()
	var font: Font = Assets.font_title
	for name in ["WWWWWWWW", "MMMMMMMM"]:
		var s := TitleScreen.best_text({"name": name, "score": WORST_SCORE})
		check_eq(s, "%s  %d" % [name, WORST_SCORE])
		var left := TitleScreen.BEST_X - UiKit.text_width(font, s, TitleScreen.BEST_SIZE)
		check(left > ScreenBase.CX + 100.0, "BEST line '%s' stays in the top-right corner (from x %.0f)" % [s, left])
	check(TitleScreen.BEST_X <= ScreenBase.W - 16.0, "right margin")
