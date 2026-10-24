extends ScreenBase
## Highscore lists (docs/SPEC.md §13): one list at a time with tabs BEGINNER / NORMAL / HARD / EXPERT
## (left/right switches). Columns RANK, NAME, SCORE, LEVEL, TIME, SHIP – every heading uses exactly the
## same anchor x and alignment as its values (numbers right-aligned).
## Confirm / B / Escape → finished("back").
## setup args: {"difficulty": d, "rank": highlighted row (0-based, -1 = none),
##              "preview_entries": Array (dev screenshots only: shown instead of the stored list)}.

const PANEL := Rect2(80, 150, 800, 474)
const HEADER_Y := 196.0
const ROW_Y0 := 242.0
const ROW_H := 38.0
## Column definitions: [heading, anchor x, alignment]. Values use the same anchor and alignment.
## NAME is wide enough for Settings.NAME_MAX (8) of the widest character ("WWWWWWWW", 170 px) and still leaves
## room for a 6-digit SCORE; SHIP ends inside the panel with the longest ship name.
const COLUMNS := [
	["RANK", 148.0, HORIZONTAL_ALIGNMENT_RIGHT],
	["NAME", 178.0, HORIZONTAL_ALIGNMENT_LEFT],
	["SCORE", 474.0, HORIZONTAL_ALIGNMENT_RIGHT],
	["LEVEL", 562.0, HORIZONTAL_ALIGNMENT_RIGHT],
	["TIME", 690.0, HORIZONTAL_ALIGNMENT_RIGHT],
	["SHIP", 722.0, HORIZONTAL_ALIGNMENT_LEFT],
]
## Font sizes: headings (font_body_bold), values (font_title), ship names (font_body_bold).
const HEADING_SIZE := 14
const VALUE_SIZE := 18
const SHIP_SIZE := 16
const TAB_W := 168.0
const TAB_H := 36.0
const TAB_Y := 96.0

var _diff := 1
var _highlight := -1
var _highlight_diff := -1
var _entries: Array = []
var _tab_anim := 0.0


func _enter() -> void:
	AudioManager.play_title_music()
	_diff = clampi(int(args.get("difficulty", Settings.difficulty)), 0, 3)
	_highlight = int(args.get("rank", -1))
	_highlight_diff = _diff
	_tab_anim = _diff
	_load_entries()


func _load_entries() -> void:
	if args.has("preview_entries") and _diff == _highlight_diff:
		_entries = args["preview_entries"]
	else:
		_entries = Settings.get_highscores(_diff)


func _tick(delta: float) -> void:
	_tab_anim = lerpf(_tab_anim, float(_diff), 1.0 - exp(-delta * 16.0))
	var d := InputRouter.menu_direction()
	if d.x != 0:
		_diff = posmod(_diff + d.x, 4)
		_load_entries()
		sfx("menu_move")
	if InputRouter.confirm_pressed() or InputRouter.back_pressed():
		sfx("menu_back")
		finish("back")


## Column anchor/alignment (shared by heading and values) – exposed for tests.
static func column(i: int) -> Array:
	return COLUMNS[i]


## NAME placeholder of an empty row: one dash per possible character (Settings.NAME_MAX).
static func empty_name() -> String:
	return "-".repeat(Settings.NAME_MAX)


func _cell(col: int, baseline: float, s: String, font: Font, size: int, color: Color) -> void:
	var c: Array = COLUMNS[col]
	UiKit.text(self, font, Vector2(float(c[1]), baseline), s, size, color, c[2])


# --- Drawing -------------------------------------------------------------------------------------
func _draw() -> void:
	draw_title("HIGHSCORES", 58, 36)
	_draw_tabs()
	UiKit.panel(self, PANEL, 0.6)
	for i in COLUMNS.size():
		_cell(i, HEADER_Y, COLUMNS[i][0], Assets.font_body_bold, HEADING_SIZE, UiKit.COLOR_HILITE)
	UiKit.divider(self, Vector2(CX, HEADER_Y + 14), PANEL.size.x - 60, Color(UiKit.COLOR_HILITE, 0.4), 1.5)
	for r in Settings.LIST_SIZE:
		var by := ROW_Y0 + r * ROW_H + 8.0
		var cy := by - 7.0
		var hl := r == _highlight and _diff == _highlight_diff
		if hl:
			var pulse := 0.5 + 0.5 * sin(time * 4.0)
			UiKit.panel_ex(self, Rect2(PANEL.position.x + 14, cy - ROW_H * 0.5 + 2, PANEL.size.x - 28, ROW_H - 4),
				Color(UiKit.COLOR_GOLD, 0.12 + 0.06 * pulse), Color(UiKit.COLOR_GOLD, 0.55 + 0.35 * pulse), 8, 1,
				Color(UiKit.COLOR_GOLD, 0.25), 10)
		elif r % 2 == 1:
			draw_rect(Rect2(PANEL.position.x + 14, cy - ROW_H * 0.5 + 2, PANEL.size.x - 28, ROW_H - 4),
				Color(1, 1, 1, 0.025))
		var rank_col := UiKit.COLOR_GOLD if r == 0 else (UiKit.COLOR_TEXT if r < 3 else UiKit.COLOR_DIM)
		if r < _entries.size():
			var e: Dictionary = _entries[r]
			var tc := UiKit.COLOR_GOLD.lerp(Color.WHITE, 0.3) if hl else UiKit.COLOR_TEXT
			var ship: Dictionary = ShipData.ship(int(e.get("ship", 0)))
			_cell(0, by, "%d." % (r + 1), Assets.font_title, VALUE_SIZE, rank_col if not hl else tc)
			_cell(1, by, String(e.get("name", "")), Assets.font_title, VALUE_SIZE, tc)
			_cell(2, by, Fmt.score(int(e.get("score", 0))), Assets.font_title, VALUE_SIZE,
				UiKit.COLOR_GOLD if not hl else tc)
			_cell(3, by, str(int(e.get("level", 1))), Assets.font_title, VALUE_SIZE, tc)
			_cell(4, by, Fmt.time(float(e.get("time", 0.0))), Assets.font_title, VALUE_SIZE, tc)
			_cell(5, by, String(ship["name"]), Assets.font_body_bold, SHIP_SIZE,
				Color(ship["accent"]).lerp(Color.WHITE, 0.45))
		else:
			_cell(0, by, "%d." % (r + 1), Assets.font_title, VALUE_SIZE, Color(UiKit.COLOR_FAINT, 0.6))
			_cell(1, by, empty_name(), Assets.font_title, VALUE_SIZE, Color(UiKit.COLOR_FAINT, 0.35))
			_cell(2, by, "0", Assets.font_title, VALUE_SIZE, Color(UiKit.COLOR_FAINT, 0.35))
	if _entries.is_empty():
		UiKit.text(self, Assets.font_body, Vector2(CX, PANEL.end.y - 20), "No entries yet – be the first!", 16,
			UiKit.COLOR_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.hint_bar(self, Vector2(CX, 680), [
		[["LR"], "Difficulty"], [["ENTER", "ESC", "pad:B"], "Back"],
	], 14)


func _draw_tabs() -> void:
	var total := TAB_W * 4
	var x0 := CX - total * 0.5
	var bar := Rect2(x0 - 4, TAB_Y - TAB_H * 0.5 - 4, total + 8, TAB_H + 8)
	UiKit.panel_ex(self, bar, Color(UiKit.COLOR_PANEL, 0.7), Color(UiKit.COLOR_BORDER, 0.25), int(bar.size.y * 0.5), 1)
	# Sliding highlight
	var hx := x0 + _tab_anim * TAB_W
	UiKit.panel_ex(self, Rect2(hx + 2, TAB_Y - TAB_H * 0.5, TAB_W - 4, TAB_H), Color(UiKit.COLOR_ACCENT, 0.22),
		Color(UiKit.COLOR_ACCENT, 0.85), int(TAB_H * 0.5), 1, Color(UiKit.COLOR_ACCENT, 0.25), 10)
	for i in 4:
		var c := Vector2(x0 + (i + 0.5) * TAB_W, TAB_Y)
		var active := i == _diff
		UiKit.text(self, Assets.font_title, Vector2(c.x, UiKit.baseline_for(Assets.font_title, 15, c.y)),
			String(ShipData.difficulty(i)["name"]), 15, UiKit.COLOR_TEXT if active else UiKit.COLOR_DIM,
			HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.triangle(self, Vector2(x0 - 24, TAB_Y), Vector2.LEFT, 13, Color(UiKit.COLOR_HILITE, 0.8))
	UiKit.triangle(self, Vector2(x0 + total + 24, TAB_Y), Vector2.RIGHT, 13, Color(UiKit.COLOR_HILITE, 0.8))
