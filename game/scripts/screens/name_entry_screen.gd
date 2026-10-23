extends ScreenBase
## Highscore name entry (docs/SPEC.md §13). Editing logic: NameEditor (pure, tested).
## Controller: D-pad / stick (single axis, tie → horizontal) – horizontal moves the cursor, vertical
## changes the character; B deletes the last character; X / Y / Start confirm.
## Keyboard: typing appends, Backspace deletes, Enter confirms, arrow keys behave like the D-pad.
## On confirm: Settings.insert_highscore(difficulty, {name, score, time, level, ship}) →
## finished("done", {"difficulty": d, "rank": r}).
## setup args: {"difficulty", "score", "time", "level", "ship"} (default: from Run),
##             optional "initial_name" (dev / screenshots).

const BOX_W := 72.0
const BOX_H := 88.0
const BOX_GAP := 16.0
const BOX_Y := 334.0

var editor := NameEditor.new()
var _diff := 1
var _score := 0
var _time := 0.0
var _level := 1
var _ship := 0
var _rank := 1
var _flash := {}        # box index → time of last change (for a short highlight)


func _enter() -> void:
	AudioManager.play_title_music()
	_diff = int(args.get("difficulty", Run.difficulty))
	_score = int(args.get("score", Run.score))
	_time = float(args.get("time", Run.active_time))
	_level = int(args.get("level", Run.level))
	_ship = int(args.get("ship", Run.ship_id))
	_rank = 1
	for e in Settings.get_highscores(_diff):
		if int(e["score"]) > _score or (int(e["score"]) == _score and float(e["time"]) < _time):
			_rank += 1
	if args.has("initial_name"):   # dev / screenshots only
		editor = NameEditor.new(String(args["initial_name"]))
	InputRouter.set_text_mode(true)
	InputRouter.text_char.connect(_on_text_char)


func _exit_tree() -> void:
	InputRouter.set_text_mode(false)
	if InputRouter.text_char.is_connected(_on_text_char):
		InputRouter.text_char.disconnect(_on_text_char)


func _on_text_char(ch: String) -> void:
	if is_finished():
		return
	if editor.type_char(ch):
		_flash[editor.text.length() - 1] = time
		sfx("menu_move")


func _tick(_delta: float) -> void:
	var d := InputRouter.menu_direction()
	if d != Vector2i.ZERO:
		var before_text := editor.text
		var before_cursor := editor.cursor
		editor.apply_direction(d)
		if editor.text != before_text:
			_flash[editor.cursor] = time
		if editor.text != before_text or editor.cursor != before_cursor:
			sfx("menu_move")
	if InputRouter.delete_pressed():
		if not editor.text.is_empty():
			editor.delete_last()
			sfx("menu_back")
	if InputRouter.confirm_pressed():
		_confirm()


func _confirm() -> void:
	sfx("menu_confirm")
	var entry := {"name": editor.final_name(), "score": _score, "time": _time, "level": _level, "ship": _ship}
	var rank := Settings.insert_highscore(_diff, entry)
	finish("done", {"difficulty": _diff, "rank": rank})


# --- Drawing -------------------------------------------------------------------------------------
func _draw() -> void:
	draw_title("NEW HIGHSCORE!", 104, 42, UiKit.COLOR_GOLD, UiKit.COLOR_ACCENT)
	UiKit.text_spaced(self, Assets.font_title, Vector2(CX, 146), "RANK %d  ·  %s" % [_rank,
		ShipData.difficulty(_diff)["name"]], 16, 4.0, UiKit.COLOR_HILITE, HORIZONTAL_ALIGNMENT_CENTER)
	# Run summary
	var sy := 214.0
	_summary(CX - 220, sy, "SCORE", Fmt.score(_score), UiKit.COLOR_GOLD)
	_summary(CX, sy, "TIME", Fmt.time(_time), UiKit.COLOR_TEXT)
	_summary(CX + 220, sy, "LEVEL", str(_level), UiKit.COLOR_TEXT)
	UiKit.text(self, Assets.font_body, Vector2(CX, 300), "ENTER YOUR NAME", 18, UiKit.COLOR_DIM,
		HORIZONTAL_ALIGNMENT_CENTER)
	_draw_boxes()
	# Help
	UiKit.hint_bar(self, Vector2(CX, 520), [
		[["A-Z", "0-9"], "Type"], [["BKSP"], "Delete"], [["ENTER"], "Confirm"],
	], 15)
	UiKit.hint_bar(self, Vector2(CX, 560), [
		[["UD"], "Letter"], [["LR"], "Move"], [["pad:B"], "Delete"], [["pad:X", "pad:Y", "pad:START"], "Confirm"],
	], 15)
	UiKit.text(self, Assets.font_body, Vector2(CX, 618), "Characters: A–Z  0–9  _  -   ·   Empty name = PILOT", 14,
		UiKit.COLOR_FAINT, HORIZONTAL_ALIGNMENT_CENTER)


func _summary(x: float, baseline: float, label: String, value: String, col: Color) -> void:
	UiKit.text(self, Assets.font_body, Vector2(x, baseline - 34), label, 14, UiKit.COLOR_FAINT, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.text(self, Assets.font_title, Vector2(x, baseline), value, 28, col, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_boxes() -> void:
	var n := NameEditor.max_len()
	var total := n * BOX_W + (n - 1) * BOX_GAP
	var x0 := CX - total * 0.5
	var font := Assets.font_title_heavy
	var text := editor.text
	var pulse := 0.5 + 0.5 * sin(time * 5.0)
	for i in n:
		var r := Rect2(x0 + i * (BOX_W + BOX_GAP), BOX_Y, BOX_W, BOX_H)
		var is_cursor := i == editor.cursor
		var filled := i < text.length()
		if is_cursor:
			UiKit.panel_ex(self, r, Color(UiKit.COLOR_HILITE, 0.12 + 0.06 * pulse), Color(UiKit.COLOR_HILITE,
				0.75 + 0.25 * pulse), 10, 2, Color(UiKit.COLOR_HILITE, 0.3), 16)
			UiKit.triangle(self, Vector2(r.get_center().x, r.position.y - 13), Vector2.UP, 12,
				Color(UiKit.COLOR_HILITE, 0.8))
			UiKit.triangle(self, Vector2(r.get_center().x, r.end.y + 13), Vector2.DOWN, 12,
				Color(UiKit.COLOR_HILITE, 0.8))
		elif filled:
			UiKit.panel_ex(self, r, Color(UiKit.COLOR_PANEL, 0.75), Color(UiKit.COLOR_BORDER, 0.45), 10, 1)
		else:
			UiKit.panel_ex(self, r, Color(UiKit.COLOR_PANEL, 0.45), Color(UiKit.COLOR_BORDER, 0.16), 10, 1)
		var cx := r.get_center().x
		var by := UiKit.baseline_for(font, 46, r.get_center().y)
		if filled:
			var fl := 1.0 - clampf((time - float(_flash.get(i, -10.0))) / 0.25, 0.0, 1.0)
			var col := UiKit.COLOR_TEXT.lerp(UiKit.COLOR_GOLD, fl)
			UiKit.text(self, font, Vector2(cx, by), text[i], 46, col, HORIZONTAL_ALIGNMENT_CENTER)
		elif text.is_empty():
			# Placeholder: an empty name is stored as PILOT.
			UiKit.text(self, font, Vector2(cx, by), Settings.DEFAULT_NAME[i], 46, Color(UiKit.COLOR_FAINT, 0.28),
				HORIZONTAL_ALIGNMENT_CENTER)
		if is_cursor and not filled:
			var blink := 1.0 if fmod(time, 1.0) < 0.6 else 0.15
			draw_rect(Rect2(cx - 18, r.end.y - 18, 36, 4), Color(UiKit.COLOR_HILITE, blink))
