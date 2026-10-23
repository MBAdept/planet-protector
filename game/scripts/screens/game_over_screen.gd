extends ScreenBase
## Game over (docs/SPEC.md §11): GAME OVER, score, level reached, play time. Confirm →
## finished("continue") (Main then opens the name entry if the score qualifies, else the highscores).
## setup args: {"level": n, "qualifies": bool}.

const CONFIRM_DELAY := 1.0

var _n := 1
var _qualifies := false


func _enter() -> void:
	AudioManager.stop_music()
	sfx("game_over")
	_n = int(args.get("level", Run.level))
	_qualifies = bool(args.get("qualifies", false))


func _star_velocity() -> Vector2:
	return Vector2(-4, 1)


func _tick(_delta: float) -> void:
	if time >= CONFIRM_DELAY and InputRouter.confirm_pressed():
		sfx("menu_confirm")
		finish("continue")


func _draw() -> void:
	var a := ramp(0.0, 0.7)
	var pulse := 0.85 + 0.15 * sin(time * 2.2)
	UiKit.glow_spot(self, Vector2(CX, 190), Vector2(420, 120), Color(1.0, 0.15, 0.05, 0.12 * a * pulse))
	var s := 1.0 + 0.08 * (1.0 - ramp(0.0, 0.8))
	draw_set_transform(Vector2(CX, 190), 0.0, Vector2(s, s))
	UiKit.text_glow(self, Assets.font_title_heavy, Vector2(0, 28), "GAME OVER", 76, Color(1.0, 0.42, 0.32, a),
		Color(1.0, 0.18, 0.08), HORIZONTAL_ALIGNMENT_CENTER, 1.3 * a * pulse)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var pa := ramp(0.35, 0.5)
	var panel := Rect2(CX - 250, 278, 500, 246)
	UiKit.panel(self, panel, 0.62 * pa)
	var lx := panel.position.x + 36
	var rx := panel.end.x - 36
	var rows := [
		["SCORE", Fmt.score(Run.score), UiKit.COLOR_GOLD],
		["LEVEL REACHED", "%d  ·  %s" % [_n, LevelData.level(_n)["name"]], UiKit.COLOR_TEXT],
		["PLAY TIME", Fmt.time(Run.active_time), UiKit.COLOR_TEXT],
		["DIFFICULTY", Run.difficulty_name(), UiKit.COLOR_ACCENT],
		["SHIP", String(ShipData.ship(Run.ship_id)["name"]), Color(ShipData.ship(Run.ship_id)["accent"]).lightened(0.3)],
	]
	for i in rows.size():
		var ra := ramp(0.45 + i * 0.07, 0.3)
		var by := panel.position.y + 46 + i * 44
		var row: Array = rows[i]
		UiKit.stat_row(self, lx, rx, by, row[0], row[1], 21 if i == 0 else 19, Color(UiKit.COLOR_DIM, ra),
			Color(row[2], ra))
		if i < rows.size() - 1:
			UiKit.divider(self, Vector2(CX, by + 17), 430, Color(UiKit.COLOR_BORDER, 0.15 * ra), 1.0)
	if _qualifies:
		var qa := ramp(0.9, 0.4) * (0.75 + 0.25 * sin(time * 4.0))
		UiKit.text_glow(self, Assets.font_title, Vector2(CX, 580), "NEW HIGHSCORE!", 26, Color(UiKit.COLOR_GOLD, qa),
			UiKit.COLOR_ACCENT, HORIZONTAL_ALIGNMENT_CENTER, qa)
	draw_continue_hint("Continue", CONFIRM_DELAY)
