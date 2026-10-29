extends ScreenBase
## Game over (docs/SPEC.md §11): GAME OVER, score, level reached, play time. Confirm →
## finished("continue") (Main then opens the name entry if the score qualifies, else the highscores).
## setup args: {"level": n, "qualifies": bool}.
## Two players (SPEC §19.2): {"player": k, "other_status": "plays_on" | "won" | "out"} (the other player still has
## levels to play / has completed level 20 / is out as well) – a "PLAYER k" label in the player colour above GAME OVER
## and, instead of NEW HIGHSCORE (the name entries come at the end of the match), "PLAYER j PLAYS ON" or
## "PLAYER j SAVED EARTH!" in j's colour, or "MATCH OVER" when both are out.

const CONFIRM_DELAY := 1.0
## Baselines of the two-player label above GAME OVER and of the line under the panel.
const PLAYER_LABEL_Y := 124.0
const STATUS_Y := 580.0

var _n := 1
var _qualifies := false
var _player := -1
var _other_status := ""


func _enter() -> void:
	AudioManager.stop_music()
	sfx("game_over")
	_n = int(args.get("level", Run.level))
	_qualifies = bool(args.get("qualifies", false))
	_player = int(args.get("player", -1))
	_other_status = String(args.get("other_status", "out"))
	if _player >= 0:
		_qualifies = false   # a match enters its names at the end (match result)


## Line under the panel in a match: what the other player (1 − player) does now.
static func status_text(player: int, other_status: String) -> String:
	match other_status:
		"plays_on":
			return "%s PLAYS ON" % Run.player_label(1 - player)
		"won":
			return "%s SAVED EARTH!" % Run.player_label(1 - player)
	return "MATCH OVER"


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
	if _player >= 0:
		UiKit.text_spaced(self, Assets.font_title, Vector2(CX, PLAYER_LABEL_Y), Run.player_label(_player), 22, 7.0,
			Color(UiKit.player_color(_player), a), HORIZONTAL_ALIGNMENT_CENTER)
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
		UiKit.text_glow(self, Assets.font_title, Vector2(CX, STATUS_Y), "NEW HIGHSCORE!", 26,
			Color(UiKit.COLOR_GOLD, qa), UiKit.COLOR_ACCENT, HORIZONTAL_ALIGNMENT_CENTER, qa)
	elif _player >= 0:
		var sa := ramp(0.9, 0.4) * (0.8 + 0.2 * sin(time * 3.0))
		var sc := UiKit.COLOR_DIM if _other_status == "out" else UiKit.player_color(1 - _player)
		UiKit.text_glow(self, Assets.font_title, Vector2(CX, STATUS_Y), status_text(_player, _other_status), 26,
			Color(sc, sa), sc, HORIZONTAL_ALIGNMENT_CENTER, 0.8 * sa)
	draw_continue_hint("Continue", CONFIRM_DELAY)
